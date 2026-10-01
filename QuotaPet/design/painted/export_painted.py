"""把 GPT 出的宠物图切成 App 用的图片，并生成 Sources/QuotaPetCore/Pet/PaintedArt.swift

用法：python3 design/painted/export_painted.py            导出 design/painted/ 下所有 *.json
      python3 design/painted/export_painted.py shades     只导出一款（生成的 Swift 里仍然列出所有配置）
      python3 design/painted/export_painted.py shades --src <原图目录>   试别的原图：只出对比图
      加 --write：缺表情或用了 --src 时也写进 Resources/Pets（缺的表情先用底图代替）

每款形象一个配置 design/painted/<形象>.json，文件名就是 PetStyle 的 rawValue（比如 shades），坐标都是原图宽高的比例（0~1）：
  source    原图目录，相对仓库根目录。原图和素材只留在本机，要放在不进 git 的地方
  face      [cx, cy, rx, ry]  脸的椭圆：表情图只取这一块盖到底图上
  portrait  [x, y, 边长]      面板半身像的取景
  icon      [x, y, 边长]      菜单栏头像的取景（只要头）
  patches   [{"from": 表情, "region": [cx, cy, rx, ry], "onto": [表情, ...]}]
            脸以外还要取的小块（比如太阳穴上的汗珠、流出脸的眼泪）：从 from 那张取 region 这块，盖到 onto 这几张上。
            一颗汗珠只让 GPT 画一次，别的表情复制同一颗，切换表情时汗珠不会跳
  outline   "#RRGGBB"         菜单栏头像外圈描边的颜色：浅金色头发在浅色菜单栏上会发白
  keepGreen true              人物身上有绿色（薄荷绿的头发、荧光绿的饰品）：按「绿不绿」整张抠会把它们抠掉、变色，
                              改成只认和背景几乎同色的地方，只在背景边上几个像素里算半透明
  appIcon   true              App 图标用这款：另外导出 Resources/AppIcon.png（底图的面板取景，1024×1024），只有一款能写

原图：每个表情一张正方形图，透明背景或纯绿背景（#00FF00），文件名见 FACES，open-small 是底图。
汗珠、眼泪直接让 GPT 画在表情图里，睡着、疑惑也是单独的表情：App 不往图上叠小道具（漫画符号浮在精绘的脸上很突兀）。
GPT 改表情时人物常会挪一点、缩放一点：先避开脸、拿头发和衣服把表情图和底图对齐，再只取脸那一块（椭圆，边缘羽化）盖到底图上，
所以头发、衣服在各个表情里完全一样，切换表情时不会抖。

输出：
  Resources/Pets/<形象>/portrait-<表情>.png    面板半身像，192×192（96pt 的 2 倍）
  Resources/Pets/<形象>/icon-<表情>.png        菜单栏头像，44×44（22pt 的 2 倍），带一圈描边
  （没有单色版：精绘缩成剪影很难看）
  design/out/painted-<形象>.png                对比图：导出完先看这张
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.normpath(os.path.join(HERE, "..", ".."))       # QuotaPet/
REPO = os.path.dirname(PACKAGE)
PETS = os.path.join(PACKAGE, "Resources", "Pets")
SWIFT = os.path.join(PACKAGE, "Sources", "QuotaPetCore", "Pet", "PaintedArt.swift")
OUT = os.path.join(HERE, "..", "out")

# PetSprites.frames / reaction 用到的表情（多数是 眼睛-嘴）；第一个是底图
FACES = ["open-small", "sparkle-open", "happy-open", "closed-open", "closed-small", "tired-wavy", "closed-wavy", "cry-o",
         "sleep", "puzzled", "drowsy", "nervous", "surprised", "pout"]
PORTRAIT = 192  # PetSprites.portraitPoints 的 2 倍（自检会拿导出的图核对）
ICON = 44        # PetSprites.iconPoints 的 2 倍
APP_ICON = 1024  # App 图标（最大 1024 像素）用的半身像
APP_ICON_PATH = os.path.join(PACKAGE, "Resources", "AppIcon.png")


# MARK: - 读图、去背景

def greenness(rgb):
    return rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])


def load(path, keep_green=False):
    """读成 RGBA 的 float 数组（0~1，未预乘）。没有透明背景时按纯绿背景抠图。
    只看上面两个角判断背景：画到胸口时，下面两个角常被人物盖住。
    keep_green：人物身上有绿色（配置里的 keepGreen），见下面"""
    im = Image.open(path)
    rgba = np.asarray(im.convert("RGBA"), dtype=np.float32) / 255
    corners = np.concatenate([rgba[:8, :8].reshape(-1, 4), rgba[:8, -8:].reshape(-1, 4)])
    if corners[:, 3].mean() < 0.5:
        return rgba  # 自带透明背景
    if np.median(greenness(corners)) < 0.4:
        sys.exit(f"✗ {os.path.basename(path)} 的背景既不是透明也不是纯绿，请让 GPT 按说明重出")
    key = np.median(corners[:, :3], axis=0)  # 图上实际的背景绿（GPT 画的不一定正好是 #00FF00）
    rgb = rgba[..., :3]
    alpha = 1 - np.clip((greenness(rgb) - 0.08) / 0.3, 0, 1)
    edge = spill = None  # 只在这些像素里去绿边；None = 整张
    if keep_green:
        # 薄荷绿的头发、荧光绿的饰品也「比红蓝更绿」，按上面那样整张抠会被抠掉一部分、颜色被去绿边改掉。
        # 背景是和 key 几乎同色的大片；只在背景边上几个像素里算半透明（红或蓝够多就不是背景），别处都不透明
        background = np.abs(rgb - key).max(axis=-1) < 0.12
        edge = np.asarray(Image.fromarray(background).filter(ImageFilter.MaxFilter(7))) & ~background
        other = np.maximum(rgb[..., 0], rgb[..., 2])
        soft = np.maximum(alpha, np.clip(other / 0.6, 0, 1))
        # 发丝缝里透出来的背景、溢到头发边上的绿：很绿而且红蓝都少（荧光绿的蓝不少，薄荷绿没这么绿），还按老办法抠
        spill = (greenness(rgb) > 0.25) & (other < 0.45) & ~background & ~edge
        alpha = np.where(background, 0, np.where(edge, soft, np.where(spill, alpha, 1)))
    alpha = alpha.astype(np.float32)[..., None]
    # 边缘像素 = 前景 × 透明度 + 背景绿 × (1 − 透明度)：先减掉背景绿得到预乘的前景，再除回去。
    # 直接把观测色当前景色的话，合成时会再乘一次透明度，半透明的发丝边缘就发暗
    premultiplied = np.clip(np.minimum(rgb - (1 - alpha) * key, alpha), 0, 1)
    color = np.where(alpha > 1e-4, premultiplied / np.maximum(alpha, 1e-4), 0)
    # 残留的绿边：绿不能比红蓝更多。人物身上有绿色时只管背景边上，而且留一点余量（薄荷绿本来就比红蓝绿一些）
    limit = np.maximum(color[..., 0], color[..., 2]) + (0.15 if keep_green else 0)
    if edge is None:
        color[..., 1] = np.minimum(color[..., 1], limit)
    else:
        color[..., 1] = np.where(edge, np.minimum(color[..., 1], limit), color[..., 1])
        color[..., 1] = np.where(spill, np.minimum(color[..., 1], np.maximum(color[..., 0], color[..., 2])), color[..., 1])
    return np.concatenate([color, alpha], axis=-1).astype(np.float32)


def premultiply(a):
    out = a.copy()
    out[..., :3] *= out[..., 3:4]
    return out


def unpremultiply(a):
    out = a.copy()
    alpha = out[..., 3:4]
    out[..., :3] = np.where(alpha > 1e-4, out[..., :3] / np.maximum(alpha, 1e-4), 0)
    return np.clip(out, 0, 1)


def to_image(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def ellipse_mask(size, face, scale=1.0, blur=0.0):
    """脸的椭圆，1 是里面；blur 是羽化半径（原图宽度的比例）"""
    w, h = size
    cx, cy, rx, ry = face
    rx, ry = rx * scale, ry * scale
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([(cx - rx) * w, (cy - ry) * h, (cx + rx) * w, (cy + ry) * h], fill=255)
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur * w))
    return np.asarray(m, dtype=np.float32) / 255


def per_channel(a, op):
    """a 是 高×宽×通道 的浮点数组：每个通道转成 Pillow 的浮点图做 op（缩放、变换），再叠回去"""
    return np.clip(np.stack([np.asarray(op(Image.fromarray(np.ascontiguousarray(a[..., c])))) for c in range(a.shape[2])], axis=-1), 0, 1)


# MARK: - 对齐

def resample(a, scale, dx, dy):
    """以画面中心缩放 scale 倍，再平移 (dx, dy) 像素；a 是 高×宽×通道 的数组（彩色图要先预乘）"""
    h, w = a.shape[:2]
    cx, cy = w / 2, h / 2
    inv = 1 / scale
    data = (inv, 0, cx - (cx + dx) * inv, 0, inv, cy - (cy + dy) * inv)
    return per_channel(a, lambda im: im.transform((w, h), Image.AFFINE, data, resample=Image.BICUBIC))


def luminance(a, work):
    """对齐用：缩到 work×work 的亮度图（背景算黑）"""
    small = np.asarray(to_image(unpremultiply(a)).resize((work, work), Image.LANCZOS), dtype=np.float32) / 255
    return (small[..., :3] @ np.array([0.299, 0.587, 0.114], dtype=np.float32)) * small[..., 3]


def move(lum, scale, dx, dy):
    """亮度图以中心缩放再平移，和 resample 的约定一样"""
    return resample(lum[..., None], scale, dx, dy)[..., 0]


def masked(lum, keep):
    """挖掉脸（表情不同会干扰对齐），再减去均值"""
    lum = lum * keep
    return lum - lum[keep > 0].mean() * keep


def keep_mask(work, face):
    """对齐时挖掉脸（表情不同会干扰对齐）；face 是 None 时整张都用（定位时还不知道脸在哪）"""
    if face is None:
        return np.ones((work, work), dtype=np.float32)
    return 1 - ellipse_mask((work, work), face, scale=1.35)


def align(base, expr, face):
    """找让表情图和底图最吻合的缩放和平移（原图像素）。先在 256 的小图上按缩放逐个试、平移用 FFT 互相关找，再在 512 的图上细调"""
    size = base.shape[0]
    work = 256
    keep = keep_mask(work, face)
    target = np.fft.rfft2(masked(luminance(base, work), keep))
    source = luminance(expr, work)
    best = (-np.inf, 1.0, 0.0, 0.0)
    for scale in np.arange(0.94, 1.0601, 0.01):
        moved = masked(move(source, scale, 0, 0), keep)
        corr = np.fft.irfft2(target * np.conj(np.fft.rfft2(moved)), s=(work, work))
        iy, ix = np.unravel_index(np.argmax(corr), corr.shape)
        score = corr[iy, ix] / (np.linalg.norm(moved) + 1e-6)
        dy = iy if iy < work // 2 else iy - work
        dx = ix if ix < work // 2 else ix - work
        if score > best[0]:
            best = (score, scale, dx * size / work, dy * size / work)
    _, scale, dx, dy = best
    work = 512
    k = size / work
    keep = keep_mask(work, face)
    ref = masked(luminance(base, work), keep)
    source = luminance(expr, work)
    best = (np.inf, scale, dx, dy)
    for s in scale + np.arange(-0.006, 0.0061, 0.003):
        for ddx in np.arange(-3, 4) * k:
            for ddy in np.arange(-3, 4) * k:
                moved = masked(move(source, s, (dx + ddx) / k, (dy + ddy) / k), keep)
                err = np.abs(moved - ref).mean()
                if err < best[0]:
                    best = (err, s, dx + ddx, dy + ddy)
    return best[1:]


def composite(base, expr, face, feather=0.015):
    """把对齐后的表情图里 face 这个椭圆盖到底图上，边缘羽化 feather（原图宽度的比例）。
    先按椭圆周围一圈的平均色把表情图的颜色拉回底图（GPT 改图时整体色调会偏一点）"""
    h, w = base.shape[:2]
    ring = (ellipse_mask((w, h), face, scale=1.3) - ellipse_mask((w, h), face, scale=1.05)) > 0.5
    ring &= (base[..., 3] > 0.99) & (expr[..., 3] > 0.99)
    shifted = expr.copy()
    if ring.sum() > 100:  # 预乘的图：色差按透明度加，透明的地方不能凭空加出颜色
        shifted[..., :3] += (base[ring][:, :3].mean(0) - expr[ring][:, :3].mean(0)) * expr[..., 3:4]
        shifted[..., :3] = np.minimum(shifted[..., :3], shifted[..., 3:4])
    m = ellipse_mask((w, h), face, blur=feather)[..., None]
    return np.clip(base * (1 - m) + shifted * m, 0, 1)


# MARK: - 输出

def crop(a, box, out):
    """按 [x, y, 边长]（比例）取景，缩到 out×out（预乘后缩放，边缘不会发黑）"""
    size = a.shape[0]
    x, y, side = box
    region = (round(x * size), round(y * size), round((x + side) * size), round((y + side) * size))
    return per_channel(a, lambda im: im.crop(region).resize((out, out), Image.LANCZOS))


def blur(a, sigma):
    """高斯模糊（Pillow 的模糊不支持浮点图），先横后竖，边缘按最近的像素延伸"""
    radius = int(sigma * 3 + 0.5)
    kernel = np.exp(-np.arange(-radius, radius + 1) ** 2 / (2 * sigma ** 2))
    kernel /= kernel.sum()
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (radius, radius)
        padded = np.pad(a, pad, mode="edge")
        a = sum(k * np.take(padded, range(i, i + a.shape[axis]), axis=axis) for i, k in enumerate(kernel))
    return a


def sharpen(a, amount=0.35):
    """缩得很小之后稍微锐化一点，五官不糊。a 是预乘的：四个通道各自锐化后颜色可能比透明度还大，要压回去，不然轮廓上会冒白点"""
    out = np.clip(a + (a - blur(a, 0.8)) * amount, 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])
    return out


def outlined(p, color):
    """在头像外面描一圈 1 像素的边：把透明度向外扩一格，用描边色垫在下面（预乘）"""
    alpha = Image.fromarray((p[..., 3] * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    ring = np.asarray(alpha, dtype=np.float32)[..., None] / 255
    under = np.concatenate([np.array(color, dtype=np.float32) * ring, ring], axis=-1)
    return p + under * (1 - p[..., 3:4])


def align_all(src, face, verbose=True, keep_green=False):
    """读底图和已有的表情图，把表情图对齐到底图。face 是 None 时不挖脸对齐（定位时还不知道脸在哪）。
    返回 (底图, {表情: 对齐后的图}, {表情: (缩放, dx, dy)}, 缺的表情)，图都是预乘的"""
    missing = [f for f in FACES if not os.path.exists(os.path.join(src, f + ".png"))]
    if FACES[0] in missing:
        sys.exit(f"✗ 缺底图 {FACES[0]}.png")
    base = premultiply(load(os.path.join(src, FACES[0] + ".png"), keep_green))
    if base.shape[0] != base.shape[1]:
        sys.exit("✗ 底图要是正方形")
    aligned, moves = {FACES[0]: base}, {}
    for key in FACES[1:]:
        if key in missing:
            continue
        expr = premultiply(load(os.path.join(src, key + ".png"), keep_green))
        if expr.shape != base.shape:
            expr = per_channel(expr, lambda im: im.resize(base.shape[1::-1], Image.LANCZOS))
        moves[key] = align(base, expr, face)
        if verbose:
            scale, dx, dy = moves[key]
            print(f"   {key:13s} 对齐：缩放 {scale:.3f}，平移 ({dx:+.0f}, {dy:+.0f}) 像素")
        aligned[key] = resample(expr, *moves[key])
    return base, aligned, moves, missing


def export(name, config, src, trial, force):
    """trial：原图不是配置里的那一套（用了 --src）。缺表情或 trial 时只出对比图，
    免得试一张图就把仓库里已经提交的正式图换掉；force（--write）时照样写进 Resources/Pets"""
    print(f"== {name}（原图：{os.path.relpath(src, REPO) if src.startswith(REPO) else src}）")
    face = config["face"]
    base, aligned, _, missing = align_all(src, face, keep_green=config.get("keepGreen", False))
    if missing:  # 先出底图看效果时，别的表情还没有：先用底图代替
        print(f"   ⚠ 还没有这些表情图，先用底图代替：{', '.join(missing)}")
    color = [int(config["outline"][i:i + 2], 16) / 255 for i in (1, 3, 5)]

    sheet, zooms = [], []
    for key in FACES:
        frame = composite(base, aligned[key], face) if key in aligned and key != FACES[0] else base
        for patch in config.get("patches", []):
            if key in patch["onto"] and patch["from"] in aligned:
                # 小块羽化得窄一些，不然汗珠这么小的东西会被羽化成半透明
                frame = composite(frame, aligned[patch["from"]], patch["region"], feather=0.004)
        sheet.append((key, crop(frame, config["portrait"], PORTRAIT), outlined(sharpen(crop(frame, config["icon"], ICON)), color)))
        zooms.append(face_zoom(frame, face))
    contact_sheet(name, sheet)
    zoom_sheet(name, zooms)

    if (missing or trial) and not force:
        print("   只出了对比图，没动 Resources/Pets（缺表情或用了 --src）；确定要写进 App 就加 --write")
        return
    folder = os.path.join(PETS, name)
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):  # 先清掉上次导出的，表情改名或删掉后不会留下没用的图
        if old.endswith(".png"):
            os.remove(os.path.join(folder, old))
    for key, portrait, icon in sheet:
        to_image(unpremultiply(portrait)).save(os.path.join(folder, f"portrait-{key}.png"), optimize=True)
        to_image(unpremultiply(icon)).save(os.path.join(folder, f"icon-{key}.png"), optimize=True)
    print(f"   已写入 {os.path.relpath(folder, REPO)}/")
    if config.get("appIcon"):  # 大尺寸的 App 图标要高清的半身像，192 的面板图放大会糊；只在打包时用，不进 App 包
        to_image(unpremultiply(crop(base, config["portrait"], APP_ICON))).save(APP_ICON_PATH, optimize=True)
        print(f"   已写入 {os.path.relpath(APP_ICON_PATH, REPO)}")


def face_zoom(frame, face, out=280):
    """脸那一块放大（比脸的椭圆大一圈），看表情盖上去有没有接缝、双下巴线"""
    cx, cy, rx, ry = face
    r = max(rx, ry) * 1.45
    return crop(frame, [cx - r, cy - r, 2 * r], out)


def zoom_sheet(name, zooms):
    """脸部放大对比图：每格一个表情，顺序同 FACES，一行 5 个"""
    size = zooms[0].shape[0]
    columns = 5
    rows = (len(zooms) + columns - 1) // columns
    im = Image.new("RGBA", (columns * size, rows * size), (255, 255, 255, 255))
    for i, zoom in enumerate(zooms):
        im.alpha_composite(to_image(unpremultiply(zoom)), ((i % columns) * size, (i // columns) * size))
    path = os.path.join(OUT, f"painted-{name}-faces.png")
    im.save(path)
    print(f"   脸部放大图：{os.path.relpath(path, REPO)}")


def contact_sheet(name, sheet):
    """对比图：每列一个表情。第一行面板图，下面是头像放大 3 倍和原大，浅色、深色菜单栏上各一次"""
    col = PORTRAIT + 16
    rows = PORTRAIT + (ICON * 3 + 8) * 2 + 40
    im = Image.new("RGBA", (col * len(sheet) + 16, rows), (250, 250, 250, 255))
    for i, (key, portrait, icon) in enumerate(sheet):
        x = 16 + i * col
        im.alpha_composite(to_image(unpremultiply(portrait)), (x, 8))
        y = PORTRAIT + 16
        for bg in [(242, 242, 242, 255), (34, 34, 34, 255)]:
            tile = Image.new("RGBA", (col - 16, ICON * 3 + 8), bg)
            big = to_image(unpremultiply(icon)).resize((ICON * 3, ICON * 3), Image.NEAREST)
            tile.alpha_composite(big, (4, 4))
            tile.alpha_composite(to_image(unpremultiply(icon)), (ICON * 3 + 16, ICON + 4))
            im.alpha_composite(tile, (x, y))
            y += ICON * 3 + 8
        ImageDraw.Draw(im).text((x, rows - 16), key, fill=(40, 40, 40, 255))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"painted-{name}.png")
    im.save(path)
    print(f"   对比图：{os.path.relpath(path, REPO)}")


# MARK: - Swift

def write_swift():
    lines = [
        "// 由 design/painted/export_painted.py 生成，不要手改。",
        "// 想改宠物的图：换 GPT 原图或改 design/painted/<形象>.json，再运行 python3 design/painted/export_painted.py。",
        "",
        "/// 宠物的图在 Resources/Pets/<形象>/ 里（见 PetPicture），这里只记每款都有哪些表情",
        "public enum PaintedArt {",
        f"    static let faces: [String] = [{', '.join(json.dumps(f) for f in FACES)}]",
        "}",
    ]
    with open(SWIFT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"已写入 {os.path.relpath(SWIFT, REPO)}")


def main():
    args = sys.argv[1:]
    force = "--write" in args
    if force:
        args.remove("--write")
    src = None
    if "--src" in args:
        i = args.index("--src")
        src = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    configs = []
    for file in sorted(os.listdir(HERE)):
        if file.endswith(".json"):
            with open(os.path.join(HERE, file)) as f:
                configs.append((file[:-5], json.load(f)))
    for name, config in configs:
        if args and name not in args:
            continue
        if "face" not in config:  # 刚用 make_pack.py 建好、原图还没齐的形象
            print(f"== {name}：还没定好脸的位置和取景，先跳过")
            continue
        export(name, config, src or os.path.join(REPO, config["source"]), trial=src is not None, force=force)
    write_swift()


if __name__ == "__main__":
    main()
