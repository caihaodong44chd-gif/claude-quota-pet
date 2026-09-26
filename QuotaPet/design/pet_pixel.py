"""定稿用的像素风宠物：头发、衣服用形状画再转像素（chibi4.py），眼睛手工逐格画（小眼睛）。
用法：python3 design/pet_pixel.py  → design/out/pixel-final.png
"""
import importlib.util, os, sys
from PIL import Image, ImageDraw
spec = importlib.util.spec_from_file_location("c4", os.path.join(os.path.dirname(__file__), "chibi4.py"))
c4 = importlib.util.module_from_spec(spec); spec.loader.exec_module(c4)

# K 睫毛  A 虹膜暗  B 虹膜中  C 虹膜亮  E 瞳孔  W 高光  Y 星星  (左眼, 右眼)；外眼角左右相反，高光都在左上
PORTRAIT_EYES_M = {  # 6×7（折中）
    "open":    ([".KKKK.", "KKAAAK", "AWWEAA", "AWEEBA", "BBEEBB", ".BCCWB", "..CC.."],
                [".KKKK.", "KAAAKK", "AWWEAA", "AWEEBA", "BBEEBB", ".BCCWB", "..CC.."]),
    "sparkle": ([".KKKK.", "KKWAAK", "AWWWEA", "AAWEEB", "BBEEBB", ".BCCWB", "..CC.."],
                [".KKKK.", "KAWAKK", "AWWWEA", "AAWEEB", "BBEEBB", ".BCCWB", "..CC.."]),
    "tired":   (["......", "......", "KKKKKK", "AWEEBA", "BBEEBB", ".BCCWB", "..CC.."],
                ["......", "......", "KKKKKK", "AWEEBA", "BBEEBB", ".BCCWB", "..CC.."]),
    "cry":     (["......", "KK....", "..KK..", "....KK", "..KK..", "KK....", "......"],
                ["......", "....KK", "..KK..", "KK....", "..KK..", "....KK", "......"]),
    "closed":  (["......", "......", "......", "K....K", ".KKKK.", "......", "......"],
                ["......", "......", "......", "K....K", ".KKKK.", "......", "......"]),
    "happy":   (["......", "......", "..KK..", ".K..K.", "K....K", "......", "......"],
                ["......", "......", "..KK..", ".K..K.", "K....K", "......", "......"]),
}
ICON_EYES_M = {  # 4×5（折中）
    "open":    ([".KKK", "KWAA", "AWEA", "BEEB", ".CC."], ["KKK.", "AWAK", "AWEA", "BEEB", ".CC."]),
    "sparkle": ([".KKK", "KWAA", "WWWA", "BWEB", ".CC."], ["KKK.", "AWAK", "WWWA", "BWEB", ".CC."]),
    "tired":   (["....", "KKKK", "AWEA", "BEEB", ".CC."], ["....", "KKKK", "AWEA", "BEEB", ".CC."]),
    "cry":     (["....", "KK..", "..KK", "KK..", "...."], ["....", "..KK", "KK..", "..KK", "...."]),
    "closed":  (["....", "....", "K..K", ".KK.", "...."], ["....", "....", "K..K", ".KK.", "...."]),
    "happy":   (["....", ".KK.", "K..K", "....", "...."], ["....", ".KK.", "K..K", "....", "...."]),
}
PORTRAIT_EYES_L = {"open": ([".KKKKK.", "KKAAAAK", "AWWAEEA", "AWWEEEA", "BBBEEBB", "BBCCCWB", ".CCCCC.", "..CCC.."],
                            [".KKKKK.", "KAAAAKK", "AWWAEEA", "AWWEEEA", "BBBEEBB", "BBCCCWB", ".CCCCC.", "..CCC.."])}
ICON_EYES_L = {"open": ([".KKK.", "KWAAK", "AWEEA", "BEEEB", "BCCWB", ".CC.."], [".KKK.", "KAAWK", "AWEEA", "BEEEB", "BCCWB", "..CC."])}

PORTRAIT_EYES = {  # 5×6（上一版，太小）
    "open":    ([".KKK.", "KKAAK", "AWWEA", "BWEEB", "BCCWB", ".CCC."],
                [".KKK.", "KAAKK", "AWWEA", "BWEEB", "BCCWB", ".CCC."]),
    "sparkle": ([".KKK.", "KKWAK", "AWWWA", "BEWEB", "BCCWB", ".CCC."],
                [".KKK.", "KAWKK", "AWWWA", "BEWEB", "BCCWB", ".CCC."]),
    "tired":   ([".....", ".....", "KKKKK", "BWEEB", "BCCWB", ".CCC."],
                [".....", ".....", "KKKKK", "BWEEB", "BCCWB", ".CCC."]),
    "cry":     (["KK...", "..KK.", "....K", "..KK.", "KK...", "....."],
                ["...KK", ".KK..", "K....", ".KK..", "...KK", "....."]),
    "closed":  ([".....", ".....", "K...K", ".KKK.", ".....", "....."],
                [".....", ".....", "K...K", ".KKK.", ".....", "....."]),
    "happy":   ([".....", "..K..", ".K.K.", "K...K", ".....", "....."],
                [".....", "..K..", ".K.K.", "K...K", ".....", "....."]),
}
ICON_EYES = {  # 4×4（上一版，太小）
    "open":    ([".KK.", "KWAK", "AWEB", ".CC."], [".KK.", "KWAK", "AWEB", ".CC."]),
    "sparkle": ([".KK.", "KWWK", "AWEB", ".CC."], [".KK.", "KWWK", "AWEB", ".CC."]),
    "tired":   (["....", "KKKK", "AWEB", ".CC."], ["....", "KKKK", "AWEB", ".CC."]),
    "cry":     (["KK..", "..KK", "KK..", "...."], ["..KK", "KK..", "..KK", "...."]),
    "closed":  (["....", "K..K", ".KK.", "...."], ["....", "K..K", ".KK.", "...."]),
    "happy":   (["....", ".KK.", "K..K", "...."], ["....", ".KK.", "K..K", "...."]),
}
def _mirror(rows):
    return [r[::-1] for r in rows]


def _pair(left):
    """右眼 = 左眼镜像"""
    return left, _mirror(left)


# 按形象换的眼睛（没写的表情用默认的折中大小）：{名字: (半身像, 头像)}
EYE_SETS = {
    # 御姐：大一号的垂眼，眼皮平平压住虹膜顶，外眼角的睫毛往下垂，看着慵懒
    "sultry": ({
        "open":    _pair([".KKKKKK", "KKAWWEA", "K.AWEEA", "..BEEBB", "..BCCWB", "...CC.."]),
        "sparkle": _pair([".KKKKKK", "KKAWWWA", "K.WWEEA", "..BWEBB", "..BCCWB", "...CC.."]),
        "tired":   _pair([".......", ".KKKKKK", "KKBWEEB", "..BCCWB", "...CC.."]),
    }, {
        "open":    _pair([".KKKK", "KKWEA", "K.AEB", "..CC."]),
        "sparkle": _pair([".KKKK", "KKWWA", "K.WEB", "..CC."]),
        "tired":   _pair([".....", ".KKKK", "KKCWB", "..CC."]),
    }),
    # 学妹：又大又圆的眼睛，高光多
    "big": ({
        "open":    PORTRAIT_EYES_L["open"],
        "sparkle": _pair([".KKKKK.", "KKWAAAK", "AWWWEEA", "AWWEEEA", "BBWEEBB", "BBCCCWB", ".CCCCC.", "..CCC.."]),
    }, {
        "open":    ICON_EYES_L["open"],
        "sparkle": _pair([".KKK.", "KWWAK", "WWWEA", "BWEEB", "BCCWB", ".CC.."]),
    }),
}


def eyes_for(style, portrait):
    custom = EYE_SETS.get(c4.STYLES[style].get("eyes"), ({}, {}))[0 if portrait else 1]
    return {**(PORTRAIT_EYES_M if portrait else ICON_EYES_M), **custom}


MOODS = [  # (名字, 眼睛, 嘴, 小道具)
    ("元气满满", "sparkle", "open", ("star",)),
    ("状态不错", "open", "small", ()),
    ("有点累", "tired", "wavy", ("sweat",)),
    ("快撑不住", "cry", "o", ("tear", "sweat")),
    ("睡着了", "closed", "small", ("zzz",)),
]
HALF_GAP, EYE_Y = 3.5, 18.3


def place(g, eyes, left_center, ey):
    """left_center：左眼中心（像素坐标，可以是小数）；右眼按画布中线镜像，保证左右对称"""
    left, right = eyes
    w, h, n = len(left[0]), len(left), len(g)
    lx = round(left_center - w / 2)
    c4.stamp(g, left, lx, round(ey - h / 2))
    c4.stamp(g, right, n - lx - w, round(ey - h / 2))


def portrait(eyes="open", mouth="small", extras=(), eye_set=None, style="classic"):
    g = c4.portrait(eyes="none", mouth=mouth, style=style)
    x0, y0, sc = -4.0, -1.0, 64 / 40
    left_center, ey = (16 - HALF_GAP - x0) * sc, (EYE_Y - y0) * sc
    lx, rx = round(left_center), 64 - round(left_center)
    place(g, (eye_set or eyes_for(style, True))[eyes], left_center, ey)
    ey = round(ey)
    for e in extras:
        if e == "star": c4.stamp(g, ["..Y..", ".YYY.", "YYYYY", ".YYY.", "..Y.."], 3, 5)
        if e == "sweat": c4.stamp(g, [".X.", "XXX", "XXX", ".X."], 8, 18)
        if e == "tear": c4.stamp(g, ["X", "XX", "XX"], lx - 1, ey + 3); c4.stamp(g, ["X", "XX", "XX"], rx, ey + 3)
        if e == "zzz": c4.stamp(g, ["ZZZZ", "..Z.", ".Z..", "ZZZZ"], 3, 4)
    return g


def icon(eyes="open", mouth="small", extras=(), eye_set=None, style="classic"):
    g = c4.icon(eyes="none", mouth=mouth, style=style)
    place(g, (eye_set or eyes_for(style, False))[eyes], 16 - HALF_GAP, EYE_Y)
    lx, rx, ey = round(16 - HALF_GAP) - 1, round(16 + HALF_GAP), round(EYE_Y)
    for e in extras:
        if e == "star": c4.stamp(g, [".Y.", "YYY", ".Y."], 1, 2)
        if e == "sweat": c4.stamp(g, [".X", "XX", "XX"], 3, 11)
        if e == "tear": c4.stamp(g, ["X", "X"], lx - 1, ey + 2); c4.stamp(g, ["X", "X"], rx + 1, ey + 2)
        if e == "zzz": c4.stamp(g, ["ZZZ", ".Z.", "ZZZ"], 1, 1)
    return g


def styles_sheet(path):
    """几款形象并排：每款一行，半身像 5 个表情 + 菜单栏头像（放大、浅色/深色菜单栏里的原大）"""
    font = c4.font
    PZ, IZ = 3, 4
    col = 64 * PZ + 16
    W = 150 + col * len(MOODS) + 32 * IZ + 150
    row_h = 64 * PZ + 40
    sheet = Image.new("RGB", (W, 70 + row_h * len(c4.STYLES)), (250, 248, 245))
    d = ImageDraw.Draw(sheet)
    for i, (name, *_) in enumerate(MOODS):
        d.text((150 + i * col, 24), name, fill=(90, 90, 90), font=font(20))
    for r, (key, st) in enumerate(c4.STYLES.items()):
        y = 64 + r * row_h
        d.text((24, y + 64 * PZ // 2 - 16), st["label"], fill=(40, 40, 40), font=font(28))
        for i, (name, eyes, mouth, extras) in enumerate(MOODS):
            x = 150 + i * col
            d.rounded_rectangle([x - 4, y - 4, x + 64 * PZ + 4, y + 64 * PZ + 4], 14, fill=(238, 233, 228))
            im = c4.to_img(portrait(eyes, mouth, extras, style=key), PZ, key)
            sheet.paste(im, (x, y), im)
        x = 150 + len(MOODS) * col
        d.rounded_rectangle([x - 4, y - 4, x + 32 * IZ + 4, y + 32 * IZ + 4], 12, fill=(238, 233, 228))
        im = c4.to_img(icon("open", "small", (), style=key), IZ, key)
        sheet.paste(im, (x, y), im)
        for j, (bg, ink) in enumerate((((236, 236, 236), (20, 20, 20)), ((34, 34, 36), (240, 240, 240)))):
            bx, by = x + 32 * IZ + 14, y + 20 + j * 56
            d.rounded_rectangle([bx, by, bx + 84, by + 46], 8, fill=bg)
            s1 = c4.to_img(icon("open", "small", (), style=key), 1, key)
            sheet.paste(s1, (bx + 8, by + 7), s1)
            d.text((bx + 44, by + 11), "63", fill=ink, font=font(19))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)


if __name__ == "__main__" and sys.argv[1:] == ["styles"]:
    styles_sheet(os.path.join(os.path.dirname(__file__), "out", "styles.png"))
    print("ok")
elif __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "out")
    font = c4.font
    PZ, IZ = 4, 5
    col = 64 * PZ + 22
    W = 40 + col * len(MOODS)
    H = 60 + (64 * PZ + 60) * 2 + 32 * IZ + 150
    sheet = Image.new("RGB", (W, H), (250, 248, 245))
    d = ImageDraw.Draw(sheet)
    d.text((30, 14), "眼睛大小对比（平时的表情）", fill=(40, 40, 40), font=font(26))
    sizes = [("上上版：太大", PORTRAIT_EYES_L, ICON_EYES_L), ("折中（这次）", PORTRAIT_EYES_M, ICON_EYES_M),
             ("上一版：太小", PORTRAIT_EYES, ICON_EYES)]
    for i, (name, pset, iset) in enumerate(sizes):
        x = 30 + i * col
        d.rounded_rectangle([x - 6, 60, x + 64 * PZ + 6, 72 + 64 * PZ], 16,
                            fill=(252, 226, 200) if "这次" in name else (238, 233, 228))
        im = c4.to_img(portrait("open", "small", (), pset), PZ)
        sheet.paste(im, (x, 66), im)
        d.text((x, 80 + 64 * PZ), name, fill=(90, 90, 90), font=font(18))
    x = 30 + 3 * col
    for j, (name, pset, iset) in enumerate(sizes):
        im = c4.to_img(icon("open", "small", (), iset), 3)
        d.rounded_rectangle([x - 4 + j * 104, 60, x + 96 + j * 104, 164], 10,
                            fill=(252, 226, 200) if "这次" in name else (238, 233, 228))
        sheet.paste(im, (x + j * 104, 64), im)
        s1 = c4.to_img(icon("open", "small", (), iset), 1)
        d.rounded_rectangle([x + j * 104, 176, x + 92 + j * 104, 222], 8, fill=(34, 34, 36))
        sheet.paste(s1, (x + 8 + j * 104, 183), s1)
        d.text((x + 44 + j * 104, 187), "63", fill=(240, 240, 240), font=font(19))
    d.text((x, 232), "菜单栏头像：大 / 折中 / 小", fill=(90, 90, 90), font=font(18))

    y0 = 60 + 64 * PZ + 70
    d.text((30, y0 - 4), "折中大小 · 全部表情", fill=(40, 40, 40), font=font(26))
    for i, (name, eyes, mouth, extras) in enumerate(MOODS):
        x = 30 + i * col
        d.rounded_rectangle([x - 6, y0 + 40, x + 64 * PZ + 6, y0 + 52 + 64 * PZ], 16, fill=(238, 233, 228))
        im = c4.to_img(portrait(eyes, mouth, extras), PZ)
        sheet.paste(im, (x, y0 + 46), im)
        d.text((x, y0 + 60 + 64 * PZ), name, fill=(90, 90, 90), font=font(18))
    y = y0 + 100 + 64 * PZ
    for i, (name, eyes, mouth, extras) in enumerate(MOODS):
        x = 30 + i * col
        d.rounded_rectangle([x - 4, y, x + 32 * IZ + 4, y + 8 + 32 * IZ], 12, fill=(238, 233, 228))
        im = c4.to_img(icon(eyes, mouth, extras), IZ)
        sheet.paste(im, (x, y + 4), im)
        for j, (bg, ink) in enumerate((((236, 236, 236), (20, 20, 20)), ((34, 34, 36), (240, 240, 240)))):
            bx, by = x + 32 * IZ + 12, y + 10 + j * 56
            d.rounded_rectangle([bx, by, bx + 84, by + 46], 8, fill=bg)
            s1 = c4.to_img(icon(eyes, mouth, extras), 1)
            sheet.paste(s1, (bx + 8, by + 7), s1)
            d.text((bx + 44, by + 11), ["27", "63", "82", "96", "1h"][i], fill=ink, font=font(19))
    sheet.save(os.path.join(out, "pixel-mid.png"))
    g = portrait("open")
    print("半身像（折中）眼睛："); [print("  ", "".join(g[y][16:48])) for y in range(26, 37)]
    g = icon("open")
    print("头像（折中）眼睛："); [print("  ", "".join(g[y][6:26])) for y in range(14, 22)]
