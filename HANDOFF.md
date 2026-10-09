# 交接：验证 Haiku 5.5 价格修正（分支 `claude/vibrant-thompson-ttfr7m`）

你在用户的 Mac 上，仓库根目录是 `claude-quota-pet`。先读一遍仓库里的 `CLAUDE.md`，里面的规则（尤其「隐私」一节）照常遵守。

## 背景

云端那边已经改好、推上去了（提交 `e38e222`），但云端没有 Swift，**Swift 代码还没编译过**。你要做的是在本机编译、跑自检、回测，把结果报给用户。

改了什么：
- `QuotaPet/Sources/QuotaPetCore/Claude/ClaudePricing.swift`：Haiku 的当前价改成 Haiku 5.5（$0.10 / $0.50），Haiku 4.5（$1 / $5）挪进 `olderPrices`。`ModelPrice` 加了 `longPromptAbove` / `longPromptMultiplier`：提示词（输入 + 缓存写 + 缓存读）超过 10 万 token 时，整个请求的价格乘 5。`ClaudePricing.cost` / `cacheReadCost` 通过 `applied(to:)` 选档。
- `QuotaPet/Sources/QuotaPetChecks/main.swift`：补了 Haiku 5.5、Sonnet 5.5 的价格检查，以及分档边界和合并后跨档的检查。
- `usage_lab.py`：同样的规则（`PRICES` 里 Haiku 的元组多了两项，新增 `applied()`）。
- `CLAUDE.md`：在「和 usage_lab.py 要保持一致的地方」里加了分档规则。

## 步骤

### 1. 切到分支

```bash
git status                      # 有没提交的改动就停下来问用户，不要 stash 或丢弃
git fetch origin
git checkout claude/vibrant-thompson-ttfr7m
git pull origin claude/vibrant-thompson-ttfr7m
git log --oneline -3            # 应该能看到 e38e222「Haiku 5.5 按自己的价格算…」
```

### 2. 编译 + 自检（最重要）

```bash
cd QuotaPet
swift build 2>&1 | tail -30
make check 2>&1 | tail -30
```

- 不要加 `-c release`（自检用了 `@testable import`）。
- **都通过**：直接进第 3 步。
- **编译错误或自检失败**：
  - 错误在上面列的三个 Swift 改动里，而且一看就知道怎么修（拼写、类型不匹配、少个参数这种）：修掉，重跑到通过，再把改法告诉用户。
  - 错误在别的文件里，或者你要动价格、阈值、期望值才能让它通过：**不要改**，原样把报错（文件名、行号、错误信息）报给用户。
  - 绝对不要为了通过去删检查、改期望值或者注释掉代码。

### 3. 回测（读的是本机真实数据，只报汇总数字）

先看本机有没有用过 Haiku 5.5（只看文件数量，不看内容）：

```bash
cd ..   # 回到仓库根目录
grep -rl "claude-haiku-5-5" ~/.claude/projects 2>/dev/null | wc -l
```

- 是 0：价格修正对回测没有影响，跳过回测，在报告里写「本机没有 Haiku 5.5 的记录」。
- 不是 0：分别在 main 和这个分支上跑一次，对比结果：

```bash
git checkout main && python3 usage_lab.py backtest
git checkout claude/vibrant-thompson-ttfr7m && python3 usage_lab.py backtest
```

每次只记下「5 小时」「每周」两段里的这几个数：区间数、实时估算的平均差和最大差、「数字往回跳」的次数、「每 1% ≈ $」。**不要**把 `summary`、`calibrate`、`make dump` 的输出或者任何 `.jsonl` 内容贴出来、写进文件或提交。

### 4. 收尾

- 第 2 步有修改的话：先 `git diff` 给用户看，用户同意后再提交，推到 `claude/vibrant-thompson-ttfr7m`。提交时 pre-commit 钩子被拦了就按提示改内容，**不要用 `--no-verify`**。
- 不要合并进 main，也不要开 PR，除非用户明确说要。
- 这份 `HANDOFF.md` 是临时文件，用完后问用户要不要删掉（它在分支上，合并进 main 之前要删）。

## 报告格式（发给用户）

```
分支：claude/vibrant-thompson-ttfr7m @ <提交号>
swift build：通过 / 失败（附报错）
make check：通过 / 失败（附失败的行号和信息）
我做的修改：无 / <改了哪个文件、哪一行、为什么>
本机 Haiku 5.5 记录：<文件数>
回测（main → 分支）：
  5 小时：平均差 x → y，最大 x → y，往回跳 x → y 次，每 1% $x → $y
  每周：  平均差 x → y，最大 x → y，往回跳 x → y 次，每 1% $x → $y
```
