"""精绘流水线第 3～5 步：检查原图 → 自动定位 → 导出。GPT 的图存好以后跑这一个就行。

用法：python3 design/painted/pipeline.py classic               检查、定位（配置里还没有位置时）、导出
      python3 design/painted/pipeline.py classic --relocate    重新定位，覆盖配置里已有的位置
      python3 design/painted/pipeline.py shades --dry-run      只检查和定位，打印结果，不写配置、不导出（拿做好的形象验证定位准不准）

整条流水线：make_pack.py（出图包）→ 在 GPT 里出图 → pipeline.py → 在 PetStyle 里把这款标成精绘 → make check、make previews。

定位（写进 design/painted/<形象>.json）：
  face      大多数表情都会变的地方就是眼睛和嘴：各表情和底图的差别取中位数，框出来再放大一圈（眉毛、下巴）
  icon      菜单栏头像：以脸为中心的正方形，边长约为脸宽的 3 倍，偏上一点（多带额头、少带脖子）
  portrait  面板半身像：边长 0.8，水平以脸为中心，从头顶上面一点开始
  patches   tired-wavy 的汗珠（蓝色像素）复制到 tired-wavy、closed-wavy 和 nervous；cry-o 流出脸外的眼泪补到 cry-o
画在 design/out/painted-<形象>-locate.png 上，不准就改配置里的数字（坐标都是原图边长的比例），再跑一次。
"""
import importlib.util, json, os, sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("export_painted", os.path.join(HERE, "export_painted.py"))
ep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ep)

WORK = 128  # 找脸在这个尺寸上算：缩小以后头发的细微差别被抹平，只剩眼睛、嘴这种大块的变化
OUTLINE = "#4A3A36"  # 菜单栏头像描边的默认颜色（深棕）


# MARK: - 检查

def check(src):
    """缺哪张、每张能不能读（背景能不能抠）、尺寸和底图一不一样。返回能用的表情"""
    ok = []
    for face in ep.FACES:
        path = os.path.join(src, face + ".png")
        if not os.path.exists(path):
            print(f"   ✗ 缺 {face}.png")
            continue
        try:
            size = ep.load(path).shape[:2]
        except SystemExit as e:  # load 发现背景不是透明也不是纯绿时会退出
            print(f"   ✗ {face}.png：{e}")
            continue
        ok.append(face)
        if face != ep.FACES[0]:
            base = Image.open(os.path.join(src, ep.FACES[0] + ".png")).size
            if size[::-1] != base:
                print(f"   ⚠ {face}.png 是 {size[1]}×{size[0]}，底图是 {base[0]}×{base[1]}（会缩放对齐，最好一样大）")
    return ok


def report_moves(moves, size):
    """对齐量太大说明 GPT 挪了人物或改了构图：能对齐，但脸的角度可能也变了，要看脸部放大图"""
    for face, (scale, dx, dy) in moves.items():
        if abs(scale - 1) > 0.03 or max(abs(dx), abs(dy)) > 0.03 * size:
            print(f"   ⚠ {face} 和底图偏得比较多（缩放 {scale:.3f}，平移 {dx:+.0f}, {dy:+.0f}），导出后看脸部放大图有没有接缝")


# MARK: - 定位

def small(a):
    """缩到 WORK×WORK 的未预乘 RGBA"""
    return ep.crop(ep.unpremultiply(a), [0, 0, 1], WORK)


def box(mask, low=1, high=99, least=20):
    """mask 里为真的像素的范围（比例坐标），两头各去掉一点离群的；不到 least 个时是 None"""
    ys, xs = np.nonzero(mask)
    if len(xs) < least:
        return None
    h, w = mask.shape
    x0, x1 = np.percentile(xs, [low, high]) / w
    y0, y1 = np.percentile(ys, [low, high]) / h
    return float(x0), float(y0), float(x1), float(y1)


def blue(a):
    """汗珠、眼泪的浅蓝色：蓝比红多很多（灰蓝的眼睛差得少，不算）"""
    return (a[..., 2] - a[..., 0] > 0.2) & (a[..., 2] > 0.6) & (a[..., 3] > 0.5)


def inside(ellipse, x, y):
    cx, cy, rx, ry = ellipse
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def locate(base, aligned):
    b = small(base)
    lum = lambda a: a[..., :3] @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    exprs = {k: small(v) for k, v in aligned.items() if k != ep.FACES[0]}
    if len(exprs) < 3:
        sys.exit("✗ 表情图太少（至少 3 张），定不出脸的位置")

    # 脸：眼睛、嘴在大多数表情里都会变，头发、衣服的零星差别取中位数就没了
    diffs = np.stack([np.abs(lum(e) - lum(b)) * (b[..., 3] > 0.5) for e in exprs.values()])
    found = box(np.median(diffs, axis=0) > 0.1, 0, 100)  # 缩小以后几乎没有零星的点，不用去掉两头
    if found is None:
        sys.exit("✗ 各表情和底图几乎一样，定不出脸的位置")
    x0, y0, x1, y1 = found  # 大致是两只眼睛到嘴
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 + 0.015
    # 放大一圈：上面到眉毛，下面过下巴（嘴不能落在羽化的边上，不然会被淡化一半）
    face = [cx, cy, (x1 - x0) / 2 * 1.15 + 0.015, (y1 - y0) / 2 * 1.2 + 0.045]

    # 菜单栏头像：以脸为中心、偏上一点的正方形
    side = min(round(face[2] * 3.1, 3), 1)
    icon = [cx - side / 2, cy - side * 0.59, side]
    # 面板半身像：边长 0.8，水平以脸为中心；上边从头顶上面一点开始
    head = np.nonzero((b[..., 3] > 0.5).any(axis=1))[0]
    top = head[0] / WORK if len(head) else 0
    portrait = [cx - 0.4, top - 0.02, 0.8]
    clamp = lambda c: [round(float(min(max(c[0], 0), 1 - c[2])), 3), round(float(min(max(c[1], 0), 1 - c[2])), 3), round(float(c[2]), 3)]

    # 小块：汗珠（复制到闭眼那张）、流出脸外的眼泪。它们很小，在原图大小上找
    full = lambda a: ep.unpremultiply(a)
    patches = []
    if "tired-wavy" in aligned:
        sweat = box(blue(full(aligned["tired-wavy"])) & ~blue(full(base)), 0, 100, least=5)
        if sweat:
            sx0, sy0, sx1, sy1 = sweat
            patches.append({"from": "tired-wavy", "onto": ["tired-wavy", "closed-wavy", "nervous"],
                            "region": [(sx0 + sx1) / 2, (sy0 + sy1) / 2, (sx1 - sx0) + 0.01, (sy1 - sy0) + 0.014]})
    if "cry-o" in aligned:
        tears = blue(full(aligned["cry-o"])) & ~blue(full(base))
        ys, xs = np.nonzero(tears)
        size = tears.shape[0]
        outside = ~inside(face, xs / size, ys / size)
        for side in (xs < cx * size, xs >= cx * size):  # 左右两道眼泪各补各的，不要框成一大块
            part = outside & side
            if part.sum() >= 5:
                tx0, tx1 = xs[part].min() / size, xs[part].max() / size
                ty0, ty1 = ys[part].min() / size, ys[part].max() / size
                patches.append({"from": "cry-o", "onto": ["cry-o"],
                                "region": [(tx0 + tx1) / 2, (ty0 + ty1) / 2, (tx1 - tx0) / 2 + 0.02, (ty1 - ty0) / 2 + 0.03]})
    for p in patches:
        p["region"] = [round(float(v), 3) for v in p["region"]]
    return {"face": [round(float(v), 3) for v in face], "portrait": clamp(portrait), "icon": clamp(icon), "patches": patches}


def draw_locate(name, base, found):
    """把定位结果画在底图上：脸（红）、菜单栏头像（蓝）、面板（绿）、小块（橙）"""
    im = ep.to_image(ep.crop(ep.unpremultiply(base), [0, 0, 1], 800))
    canvas = Image.new("RGBA", im.size, (235, 235, 235, 255))
    canvas.alpha_composite(im)
    d = ImageDraw.Draw(canvas)
    S = 800

    def ellipse(e, color):
        cx, cy, rx, ry = e
        d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], outline=color, width=3)

    def square(c, color):
        d.rectangle([c[0] * S, c[1] * S, (c[0] + c[2]) * S, (c[1] + c[2]) * S], outline=color, width=3)

    ellipse(found["face"], (230, 40, 40, 255))
    square(found["icon"], (40, 90, 230, 255))
    square(found["portrait"], (30, 170, 60, 255))
    for p in found["patches"]:
        ellipse(p["region"], (255, 140, 0, 255))
    path = os.path.join(ep.OUT, f"painted-{name}-locate.png")
    os.makedirs(ep.OUT, exist_ok=True)
    canvas.save(path)
    print(f"   定位图：{os.path.relpath(path, ep.REPO)}（红：脸，蓝：菜单栏头像，绿：面板，橙：复制的小块）")


# MARK: -

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    relocate, dry = "--relocate" in sys.argv, "--dry-run" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    name = args[0]
    path = os.path.join(HERE, f"{name}.json")
    with open(path) as f:
        config = json.load(f)
    src = os.path.join(ep.REPO, config["source"])

    print(f"== {name}：检查原图")
    ok = check(src)
    if ep.FACES[0] not in ok:
        sys.exit("✗ 底图不能用，先把底图弄好")

    print(f"== {name}：对齐和定位")
    base, aligned, moves, _ = ep.align_all(src, None, verbose=False)
    report_moves(moves, base.shape[0])
    found = locate(base, aligned)
    draw_locate(name, base, found)
    for key in ("face", "icon", "portrait"):
        note = f"（配置里是 {config[key]}）" if key in config else ""
        print(f"   {key:9s} {found[key]}{note}")
    for p in found["patches"]:
        print(f"   patch     {p['from']} → {', '.join(p['onto'])}：{p['region']}")
    if dry:
        return
    if relocate or "face" not in config:
        config.update(found)
        config.setdefault("outline", OUTLINE)
        with open(path, "w") as f:
            f.write(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
        print(f"   已写入 {os.path.relpath(path, ep.REPO)}")
    else:
        print("   配置里已经有位置，按配置导出（要用上面的结果就加 --relocate）")

    ep.export(name, config, src, trial=False, force=False)
    ep.write_swift()


if __name__ == "__main__":
    main()
