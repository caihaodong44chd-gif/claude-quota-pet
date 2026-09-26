#!/usr/bin/env python3
"""Claude 订阅额度实验室

把本机 Claude Code 的逐请求 token 记录（~/.claude/projects/**/*.jsonl）
和额度百分比快照（桌面端每 15 分钟一次的 plan-usage-history.json，
加上手动记录的 snapshots.jsonl）按时间对齐，用最小二乘回归估算：

    每 1% 的 5 小时额度 ≈ 多少 API 等价美元 ≈ 多少 tokens（按模型）

只读本机文件，不联网、不读任何凭据。

用法：
    python3 usage_lab.py summary [--hours 24]      各模型 token 用量汇总
    python3 usage_lab.py snap FH SD [--note 文字]   手动记一个额度快照（5小时% 每周%）
    python3 usage_lab.py ratio                       每周%/5小时% 的换算比
    python3 usage_lab.py calibrate --since ISO时间   回归 + 每周额度估算
    python3 usage_lab.py backtest                    按 App 的学习方式逐区间回测实时估算
"""
import argparse
import collections
import datetime as dt
import glob
import json
import os
import sys

HOME = os.path.expanduser("~")
TRANSCRIPT_GLOB = HOME + "/.claude/projects/**/*.jsonl"
HISTORY = HOME + "/Library/Application Support/Claude/plan-usage-history.json"
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "snapshots.jsonl")

# 官方 API 价格，$/百万 tokens：输入, 5分钟缓存写, 1小时缓存写, 缓存读, 输出
# 来源：platform.claude.com/docs/en/about-claude/pricing（2026-09）
PRICES = {
    "fable": (10, 12.5, 20, 0.25, 50),
    "opus": (4, 5, 8, 0.20, 20),
    "sonnet": (2, 2.5, 4, 0.20, 10),
    "haiku": (1, 1.25, 2, 0.10, 5),
}
# 缓存读在额度里大约只算 API 价格的一半（与 ClaudePricing.cacheReadQuotaWeight 一致）
CACHE_READ_WEIGHT = 0.5
# 起始换算率，额度加权美元 / 1%（与 ClaudeRates.starting 一致）
STARTING = {"fh": 0.27, "sd": 2.0}
FIELDS = ("inp", "cw5", "cw1h", "cr", "out")
FIELD_NAMES = {"inp": "输入", "cw5": "缓存写5m", "cw1h": "缓存写1h", "cr": "缓存读", "out": "输出"}


def family(model):
    for f in PRICES:
        if f in (model or ""):
            return f
    return None


def cost(fam, tok):
    p = PRICES[fam]
    return sum(tok[k] * p[i] for i, k in enumerate(FIELDS)) / 1e6


def quota_cost(fam, tok, weight=CACHE_READ_WEIGHT):
    """额度加权花费：缓存读打折，和 App 的实时估算一样"""
    return cost(fam, tok) - (1 - weight) * tok["cr"] * PRICES[fam][3] / 1e6


def parse_ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def fmt_ts(t):
    return dt.datetime.fromtimestamp(t).strftime("%m-%d %H:%M:%S")


def load_requests():
    """每个 API 响应在 jsonl 里会按内容块拆成多行、usage 重复，按 message.id 去重。"""
    reqs = {}
    for path in glob.glob(TRANSCRIPT_GLOB, recursive=True):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                m = d.get("message")
                if not isinstance(m, dict) or not m.get("usage") or "timestamp" not in d:
                    continue
                fam = family(m.get("model"))
                if not fam:  # 例如 <synthetic> 占位消息
                    continue
                u = m["usage"]
                cc = u.get("cache_creation") or {}
                if cc:
                    cw5, cw1h = cc.get("ephemeral_5m_input_tokens") or 0, cc.get("ephemeral_1h_input_tokens") or 0
                else:
                    cw5, cw1h = u.get("cache_creation_input_tokens") or 0, 0
                tok = {"inp": u.get("input_tokens") or 0, "cw5": cw5, "cw1h": cw1h,
                       "cr": u.get("cache_read_input_tokens") or 0, "out": u.get("output_tokens") or 0}
                key = m.get("id") or d.get("requestId") or (path, d.get("uuid"))
                prev = reqs.get(key)
                if prev:  # 同一响应取各字段最大值（流式中途写入的行可能偏小）
                    for k in FIELDS:
                        prev["tok"][k] = max(prev["tok"][k], tok[k])
                    prev["t"] = max(prev["t"], parse_ts(d["timestamp"]))
                else:
                    reqs[key] = {"t": parse_ts(d["timestamp"]), "fam": fam, "tok": tok,
                                 "sub": "/subagents/" in path or bool(d.get("isSidechain"))}
    return sorted(reqs.values(), key=lambda r: r["t"])


def load_snapshots():
    """合并桌面端历史 + 手动快照，返回 [(t秒, fh, sd, 来源)]。"""
    snaps = []
    try:
        with open(HISTORY, encoding="utf-8") as fh:
            for s in json.load(fh).get("samples", []):
                u = s.get("u") or {}
                if "fh" in u and "sd" in u:
                    snaps.append((s["t"] / 1000, u["fh"], u["sd"], "desktop"))
    except (OSError, ValueError):
        pass
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8") as fh:
            for line in fh:
                if line.strip():
                    s = json.loads(line)
                    snaps.append((parse_ts(s["t"]), s["fh"], s["sd"], s.get("note") or "manual"))
    return sorted(snaps)


def bucket(reqs, t0, t1):
    """(t0, t1] 区间内各模型的 token 和 API 等价成本。"""
    tok = collections.defaultdict(lambda: dict.fromkeys(FIELDS, 0))
    n = collections.Counter()
    for r in reqs:
        if t0 < r["t"] <= t1:
            n[r["fam"]] += 1
            for k in FIELDS:
                tok[r["fam"]][k] += r["tok"][k]
    return tok, n


def solve(a, b):
    """高斯消元解 a x = b。"""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        if abs(m[p][c]) < 1e-12:
            raise ValueError("数据不足以区分这些模型（矩阵奇异）")
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * y for x, y in zip(m[r], m[c])]
    return [m[i][n] / m[i][i] for i in range(n)]


def lstsq(rows, ys):
    k = len(rows[0])
    ata = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    aty = [sum(r[i] * y for r, y in zip(rows, ys)) for i in range(k)]
    return solve(ata, aty)


# ---------------------------------------------------------------- 命令

def cmd_summary(args):
    reqs = load_requests()
    t0 = dt.datetime.now().timestamp() - args.hours * 3600
    tok, n = bucket(reqs, t0, float("inf"))
    print(f"最近 {args.hours} 小时，本机 Claude Code 请求（不含网页/手机端）：\n")
    print(f"{'模型':<8}{'请求数':>7}" + "".join(f"{FIELD_NAMES[k]:>11}" for k in FIELDS) + f"{'API等价$':>10}")
    for fam in tok:
        print(f"{fam:<8}{n[fam]:>8}" + "".join(f"{tok[fam][k]:>13,}" for k in FIELDS) + f"{cost(fam, tok[fam]):>11.2f}")


def cmd_snap(args):
    rec = {"t": dt.datetime.now(dt.timezone.utc).isoformat(), "fh": args.fh, "sd": args.sd, "note": args.note}
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print("已记录", rec)


def weekly_ratio(snaps):
    """在 5 小时窗口和每周窗口都没重置的连续段里，累计 Δ周% / Δ5小时%。"""
    dfh = dsd = 0
    seg = [snaps[0]] if snaps else []
    for s in snaps[1:] + [None]:
        if s is None or s[1] < seg[-1][1] or s[2] < seg[-1][2]:
            if len(seg) > 1:
                dfh += seg[-1][1] - seg[0][1]
                dsd += seg[-1][2] - seg[0][2]
            seg = [s] if s else []
        else:
            seg.append(s)
    return (dsd / dfh if dfh else None), dfh, dsd


def cmd_ratio(args):
    r, dfh, dsd = weekly_ratio(load_snapshots())
    if r is None:
        sys.exit("快照不够，无法计算")
    print(f"累计 5小时额度涨了 {dfh}%，同期每周额度涨了 {dsd}%")
    print(f"=> 1% 的 5小时额度 ≈ {r:.3f}% 的每周额度；一个满的 5 小时窗口 ≈ 每周额度的 {100 * r:.1f}%")
    print(f"=> 每周额度 ≈ {1 / r:.1f} 个满的 5 小时窗口")


def cmd_calibrate(args):
    reqs = load_requests()
    since = parse_ts(args.since) if args.since else 0
    until = parse_ts(args.until) if args.until else float("inf")
    snaps = [s for s in load_snapshots() if since <= s[0] <= until and (not args.manual_only or s[3] != "desktop")]
    if len(snaps) < 3:
        sys.exit("区间内快照少于 3 个")
    # 只用同一个 5 小时窗口里的连续快照（遇到重置就截断）
    for i in range(1, len(snaps)):
        if snaps[i][1] < snaps[i - 1][1]:
            snaps = snaps[:i]
            break
    base_t = snaps[0][0]
    # --known opus=0.266：该模型的 $/1% 已知，直接从 y 里扣掉，不参与回归
    known = {k: float(v) for k, v in (kv.split("=") for kv in args.known)}
    fams = sorted({r["fam"] for r in reqs if base_t < r["t"] <= snaps[-1][0]} - set(known))
    rows, ys = [], []
    print(f"{'快照时间':<16}{'5h%':>5}{'周%':>5}  " + "".join(f"{f + '$':>9}" for f in fams) + "   备注")
    for s in snaps:
        tok, _ = bucket(reqs, base_t, s[0])
        x = [quota_cost(f, tok[f]) for f in fams]
        rows.append(x + [1.0])  # 截距吸收起始点的取整误差
        ys.append(s[1] - sum(quota_cost(f, tok[f]) / per for f, per in known.items()))
        print(f"{fmt_ts(s[0]):<16}{s[1]:>5}{s[2]:>5}  " + "".join(f"{v:>9.3f}" for v in x) + f"   {s[3]}")
    coef = lstsq(rows, ys)
    resid = [y - sum(c * v for c, v in zip(coef, r)) for r, y in zip(rows, ys)]
    rms = (sum(e * e for e in resid) / len(resid)) ** 0.5
    ratio, _, _ = weekly_ratio(load_snapshots())
    if args.weekly_ratio:
        ratio = args.weekly_ratio
    tok_all, _ = bucket(reqs, base_t, snaps[-1][0])

    print(f"\n回归残差 RMS = {rms:.2f} 个百分点（百分比是整数，<0.5 算拟合良好）")
    print(f"每周/5小时 换算比 = {ratio:.3f}\n")
    for f, k in zip(fams, coef):
        if k <= 0:
            print(f"{f}: 系数 ≤ 0，数据不足")
            continue
        per_pct = 1 / k                      # 1% 5小时额度 ≈ $
        window = 100 / k                     # 满 5 小时窗口 ≈ $
        week = window / (100 * ratio) * 100  # 满周额度 ≈ $
        p = PRICES[f]
        t = tok_all[f]
        mix_cost = quota_cost(f, t)
        mix_tok = sum(t.values())
        print(f"【{f}】 1% 5小时额度 ≈ ${per_pct:.3f}   满 5 小时窗口 ≈ ${window:.1f}   满周 ≈ ${week:.0f}（缓存读按 {CACHE_READ_WEIGHT:g} 倍算）")
        print(f"   换成纯输出 tokens：5小时 ≈ {window / p[4] * 1e6:,.0f}   每周 ≈ {week / p[4] * 1e6:,.0f}")
        print(f"   换成纯新输入 tokens：5小时 ≈ {window / p[0] * 1e6:,.0f}   每周 ≈ {week / p[0] * 1e6:,.0f}")
        if mix_cost > 0:
            print(f"   按本次实验的实际 token 构成（含缓存）：每周 ≈ {week / mix_cost * mix_tok:,.0f} tokens")
        print()


def cmd_backtest(args):
    """每个 15 分钟区间结束时，用之前的区间学到的换算率估算这段的官方增量，和实际增量比。
    学习方式同 RateLearner：Σ权重×加权花费 ÷ Σ权重×增量，权重按半衰期从最近一个区间往前算，加 $2 的先验。"""
    reqs = load_requests()
    snaps = [s for s in load_snapshots() if s[3] == "desktop"]
    for col, name in ((1, "5 小时"), (2, "每周")):
        prior = STARTING["fh" if col == 1 else "sd"]
        done, errs, stale, down = [], [], [], 0
        for a, b in zip(snaps, snaps[1:]):
            if b[0] - a[0] > 20 * 60 or b[col] < a[col]:  # 桌面端没开 / 窗口重置了
                continue
            tok, _ = bucket(reqs, a[0], b[0])
            if sum(cost(f, t) for f, t in tok.items()) < 0.02:  # 本机没在用
                continue
            usd = sum(quota_cost(f, t, args.cache_weight) for f, t in tok.items())
            spent, gained = 2.0, 2.0 / prior
            for end, u, d in done:
                w = 0.5 ** ((done[-1][0] - end) / (args.half_life * 3600))
                spent, gained = spent + w * u, gained + w * d
            est, actual = usd / (spent / gained), b[col] - a[col]
            errs.append(abs(est - actual))
            stale.append(actual)
            down += actual - est < -1
            done.append((b[0], usd, actual))
        if not done:
            print(f"{name}：没有可用的区间")
            continue
        n = len(errs)
        print(f"{name}：{n} 个区间，缓存读 ×{args.cache_weight:g}，半衰期 {args.half_life:g} 小时")
        print(f"  区间结束时只看上次官方读数：平均差 {sum(stale) / n:.2f} 个百分点")
        print(f"  实时估算：平均差 {sum(errs) / n:.2f}，最大 {max(errs):.1f}；官方读数比估算低 1 点以上（数字往回跳）{down} 次")
        print(f"  全部区间合起来：每 1% ≈ ${sum(u for _, u, _ in done) / max(1, sum(d for _, _, d in done)):.3f}（重新定起始值时用）")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("summary"); s.add_argument("--hours", type=float, default=24); s.set_defaults(fn=cmd_summary)
    s = sub.add_parser("snap"); s.add_argument("fh", type=int); s.add_argument("sd", type=int)
    s.add_argument("--note", default=""); s.set_defaults(fn=cmd_snap)
    s = sub.add_parser("ratio"); s.set_defaults(fn=cmd_ratio)
    s = sub.add_parser("calibrate"); s.add_argument("--since"); s.add_argument("--until")
    s.add_argument("--manual-only", action="store_true", help="只用手动快照（实验时推荐）")
    s.add_argument("--weekly-ratio", type=float, help="手动指定 每周%%/5小时%% 换算比")
    s.add_argument("--known", nargs="*", default=[], metavar="模型=$每1%%",
                   help="已知速率的模型，例如 opus=0.266，其消耗会先从额度变化里扣掉")
    s.set_defaults(fn=cmd_calibrate)
    s = sub.add_parser("backtest"); s.add_argument("--cache-weight", type=float, default=CACHE_READ_WEIGHT)
    s.add_argument("--half-life", type=float, default=3, help="小时"); s.set_defaults(fn=cmd_backtest)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
