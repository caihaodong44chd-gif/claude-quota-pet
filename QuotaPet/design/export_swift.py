"""把定稿的像素宠物导出成 Swift 数据：Sources/QuotaPetCore/Pet/PetArt.swift

每款形象（chibi4.STYLES）各一套：底图（不带五官）+ 可以叠上去的补丁（眼睛、嘴、小道具）。补丁是拿「底图」和「画上某个部件后的图」逐像素比出来的，
所以 App 里组合出来的画面和 design/pet_pixel.py 出的预览图完全一样。
每款形象各带一张调色板：同一个字符（比如头发 H）在不同形象里是不同的颜色，所以形象再多也不会不够用。
用法：python3 design/export_swift.py
"""
import importlib.util, os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pet_pixel", os.path.join(HERE, "pet_pixel.py"))
pp = importlib.util.module_from_spec(spec); spec.loader.exec_module(pp)
c4 = pp.c4
OUT = os.path.join(HERE, "..", "Sources", "QuotaPetCore", "Pet", "PetArt.swift")

# 小道具：(字符画, x, y)；一个小道具可以由好几块组成（比如两边的眼泪）
EXTRAS = {
    "icon": {
        "starBig": [([".Y.", "YYY", ".Y."], 1, 2)],
        "starSmall": [(["Y"], 2, 3)],
        "sweatA": [([".X", "XX", "XX"], 3, 11)],
        "sweatB": [([".X", "XX", "XX"], 3, 12)],
        "tearsA": [(["X", "X"], 10, 20), (["X", "X"], 21, 20)],
        "tearsB": [(["X", "X"], 10, 21), (["X", "X"], 21, 21)],
        "zzzA": [(["ZZZZ", "..Z.", ".Z..", "ZZZZ"], 0, 2)],
        "zzzB": [(["ZZZZ", "..Z.", ".Z..", "ZZZZ"], 1, 0)],
        "question": [(["ZZ.", "..Z", ".Z.", "...", ".Z."], 1, 1)],
    },
    "portrait": {
        "starBig": [(["..Y..", ".YYY.", "YYYYY", ".YYY.", "..Y.."], 3, 5)],
        "starSmall": [([".Y.", "YYY", ".Y."], 4, 6)],
        "sweatA": [([".X.", "XXX", "XXX", ".X."], 8, 18)],
        "sweatB": [([".X.", "XXX", "XXX", ".X."], 8, 20)],
        "tearsA": [(["X", "XX", "XX"], 25, 34), (["X", "XX", "XX"], 38, 34)],
        "tearsB": [(["X", "XX", "XX"], 25, 35), (["X", "XX", "XX"], 38, 35)],
        "zzzA": [(["ZZZZ", "..Z.", ".Z..", "ZZZZ"], 3, 5)],
        "zzzB": [(["ZZZZ", "..Z.", ".Z..", "ZZZZ"], 5, 2)],
        "question": [([".ZZ.", "Z..Z", "...Z", "..Z.", ".Z..", "....", ".Z.."], 3, 3)],
    },
}
# 设计稿（draft）不导出
STYLES = {k: v for k, v in c4.STYLES.items() if not v.get("draft")}
# 单色模式靠这几个颜色挖空脸，各款都不能改
FIXED = set("SsPW")
EYES = ["open", "sparkle", "tired", "cry", "closed", "happy"]
MOUTHS = ["small", "open", "wavy", "o"]


def diff_patch(base, g):
    pts = [(x, y) for y in range(len(g)) for x in range(len(g)) if g[y][x] != base[y][x]]
    if not pts:
        return None
    x0, x1 = min(p[0] for p in pts), max(p[0] for p in pts)
    y0, y1 = min(p[1] for p in pts), max(p[1] for p in pts)
    rows = ["".join(g[y][x] if g[y][x] != base[y][x] else "." for x in range(x0, x1 + 1)) for y in range(y0, y1 + 1)]
    return x0, y0, rows


def layers(size, style):
    shapes, faces = {"icon": (c4.icon, pp.icon), "portrait": (c4.portrait, pp.portrait)}[size]
    base = shapes(eyes="none", mouth="none", style=style)
    eyes = {e: diff_patch(base, faces(eyes=e, mouth="none", style=style)) for e in EYES}
    # 32 像素里「小嘴」细到画不出来（定稿的头像平时就没有嘴），空的补丁不导出
    mouths = {m: p for m in MOUTHS if (p := diff_patch(base, shapes(eyes="none", mouth=m, style=style)))}
    extras = {}
    for name, parts in EXTRAS[size].items():
        g = [row[:] for row in base]
        for rows, x, y in parts:
            c4.stamp(g, rows, x, y)
        extras[name] = diff_patch(base, g)
    return ["".join(r) for r in base], eyes, mouths, extras


def used_chars(sizes):
    """一款形象的底图和所有补丁里用到的字符"""
    out = set()
    for base, eyes, mouths, extras in sizes.values():
        out |= set("".join(base))
        for d in (eyes, mouths, extras):
            for _, _, rows in d.values():
                out |= set("".join(rows))
    return sorted(out - {"."})


def swift_rows(rows, indent):
    pad = " " * indent
    return "[\n" + "".join(f'{pad}    "{r}",\n' for r in rows) + pad + "]"


def swift_patches(d, indent):
    pad = " " * indent
    out = "[\n"
    for name, (x, y, rows) in d.items():
        out += f'{pad}    "{name}": Patch(x: {x}, y: {y}, rows: {rows!r}),\n'.replace("'", '"')
    return out + pad + "]"


def swift_layers(layer):
    base, eyes, mouths, extras = layer
    return f"""Layers(
            base: {swift_rows(base, 12)},
            eyes: {swift_patches(eyes, 12)},
            mouths: {swift_patches(mouths, 12)},
            extras: {swift_patches(extras, 12)}
        )"""


def main():
    for style, st in STYLES.items():
        assert not FIXED & st["colors"].keys(), f"{style} 不能改 {''.join(sorted(FIXED))} 的颜色"
    parts = {style: {size: layers(size, style) for size in ("icon", "portrait")} for style in STYLES}

    s = '''// 由 design/export_swift.py 生成，不要手改。
// 想改宠物：改 design/ 里的 Python 原型，python3 design/pet_pixel.py 出预览图，满意了再运行 python3 design/export_swift.py。

/// 宠物的像素数据：每款形象一张调色板、一张不带五官的底图，加上可以叠上去的眼睛、嘴、小道具。
public enum PetArt {
    struct Patch: Sendable {
        let x: Int
        let y: Int
        let rows: [String]
    }

    struct Layers: Sendable {
        let base: [String]
        let eyes: [String: Patch]
        let mouths: [String: Patch]
        let extras: [String: Patch]
    }

    /// 一款形象：自己的调色板 + 菜单栏头像 32×32（显示成 16pt）+ 面板半身像 64×64
    struct Look: Sendable {
        let palette: PetPalette
        let icon: Layers
        let portrait: Layers
    }
'''
    colors = 0
    for style, sizes in parts.items():
        pal = c4.palette(style)
        used = used_chars(sizes)
        colors = max(colors, len(used))
        entries = "".join(f'            "{ch}": 0x{r:02X}{g:02X}{b:02X},\n' for ch in used for (r, g, b) in [pal[ch]])
        s += f'''
    /// {c4.STYLES[style]["label"]}
    static let {style} = Look(
        palette: PetPalette([
{entries}        ]),
        icon: {swift_layers(sizes["icon"])},
        portrait: {swift_layers(sizes["portrait"])}
    )
'''
    s += "}\n"
    with open(OUT, "w") as f:
        f.write(s)
    print("写好了", os.path.normpath(OUT), f"（{len(s) // 1024} KB，{len(parts)} 款形象，每款最多 {colors} 色）")

if __name__ == "__main__":
    main()
