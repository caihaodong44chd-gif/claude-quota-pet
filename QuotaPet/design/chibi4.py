"""二次元宠物 v4（竖长眼睛 + 像素风 / 平滑插画风两种渲染）：参考「橙色长发 + 花饰 + 奶油色荷叶边」风格的原创像素角色。
画法：先用平滑形状（多边形、椭圆、贝塞尔）在 8 倍分辨率上画，再按多数投票缩成像素，
然后自动描边、加阴影，最后手工点上眼睛和嘴。这样比一格一格手敲像素好看得多。
用法：python3 design/chibi2.py  → design/out/
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

PAL = {
    "K": (74, 42, 32),     # 描边（深棕，比纯黑柔和）
    "H": (232, 116, 59),   # 头发
    "h": (248, 170, 112),  # 头发高光（天使环）
    "d": (196, 83, 31),    # 头发暗部
    "e": (160, 62, 24),    # 头发最暗
    "S": (255, 233, 219),  # 皮肤
    "s": (246, 205, 184),  # 皮肤阴影
    "P": (247, 160, 140),  # 腮红
    "A": (122, 53, 16),    # 虹膜暗
    "B": (200, 102, 30),   # 虹膜中
    "C": (245, 169, 59),   # 虹膜亮
    "E": (58, 26, 10),     # 瞳孔
    "W": (255, 255, 255),  # 高光
    "w": (255, 252, 248),  # 眼白
    "M": (138, 58, 42),    # 嘴
    "T": (240, 127, 127),  # 舌头
    "N": (43, 34, 34),     # 黑色蝴蝶结
    "n": (86, 72, 70),
    "F": (240, 138, 60),   # 花瓣
    "f": (200, 86, 30),
    "G": (231, 176, 74),   # 金色花心
    "Q": (255, 246, 234),  # 奶油色衣服
    "q": (234, 217, 196),
    "O": (224, 102, 42),   # 橙色点缀
    "X": (124, 200, 248),  # 汗 / 泪
    "Z": (142, 154, 175),
    "Y": (255, 211, 74),   # 星星
    "b": (122, 62, 40),    # 书皮
    "k": (78, 38, 26),     # 书脊
}
KEYS = ["."] + list(PAL)
IDX = {k: i for i, k in enumerate(KEYS)}
SS = 8  # 超采样倍数
PRIORITY = [("W", 0.30), ("K", 0.30), ("E", 0.32), ("M", 0.30), ("T", 0.40), ("Y", 0.30), ("X", 0.30)]


class Canvas:
    """世界坐标 → 像素：px = (x - x0) * scale"""
    def __init__(self, n, x0=0.0, y0=0.0, scale=1.0):
        self.n, self.x0, self.y0, self.scale = n, x0, y0, scale
        self.img = Image.new("L", (n * SS, n * SS), 0)
        self.d = ImageDraw.Draw(self.img)

    def p(self, x, y):
        return ((x - self.x0) * self.scale * SS, (y - self.y0) * self.scale * SS)

    def poly(self, pts, ch):
        self.d.polygon([self.p(*q) for q in pts], fill=IDX[ch])

    def ellipse(self, cx, cy, rx, ry, ch):
        (x0, y0), (x1, y1) = self.p(cx - rx, cy - ry), self.p(cx + rx, cy + ry)
        self.d.ellipse([x0, y0, x1, y1], fill=IDX[ch])

    def arc(self, cx, cy, rx, ry, a0, a1, width, ch):
        (x0, y0), (x1, y1) = self.p(cx - rx, cy - ry), self.p(cx + rx, cy + ry)
        self.d.arc([x0, y0, x1, y1], a0, a1, fill=IDX[ch], width=max(1, int(width * self.scale * SS)))

    def line(self, pts, width, ch):
        self.d.line([self.p(*q) for q in pts], fill=IDX[ch], width=max(1, int(width * self.scale * SS)), joint="curve")

    def grid(self):
        """每个像素取 8×8 采样里最多的颜色；睫毛、高光、瞳孔、嘴占到三成就优先保留"""
        a = np.array(self.img).reshape(self.n, SS, self.n, SS).transpose(0, 2, 1, 3).reshape(self.n, self.n, SS * SS)
        g = [["."] * self.n for _ in range(self.n)]
        for y in range(self.n):
            for x in range(self.n):
                counts = np.bincount(a[y, x], minlength=len(KEYS))
                if counts[0] > SS * SS * 0.62:
                    continue
                counts[0] = 0
                pick = None
                for ch, share in PRIORITY:
                    if counts[IDX[ch]] >= SS * SS * share:
                        pick = ch
                        break
                g[y][x] = pick or KEYS[int(counts.argmax())]
        return g

    def poly_bands(self, pts, bands):
        """在多边形里按横条上色"""
        mask = Image.new("1", self.img.size, 0)
        ImageDraw.Draw(mask).polygon([self.p(*q) for q in pts], fill=1)
        layer = Image.new("L", self.img.size, 0)
        dl = ImageDraw.Draw(layer)
        for top, bottom, ch in bands:
            dl.rectangle([0, self.p(0, top)[1], self.img.size[0], self.p(0, bottom)[1]], fill=IDX[ch])
        self.img.paste(layer, (0, 0), mask)

    def clipped_bands(self, cx, cy, rx, ry, bands):
        """在椭圆里按横条上色（虹膜从上到下由暗变亮）"""
        (x0, y0), (x1, y1) = self.p(cx - rx, cy - ry), self.p(cx + rx, cy + ry)
        mask = Image.new("1", self.img.size, 0)
        ImageDraw.Draw(mask).ellipse([x0, y0, x1, y1], fill=1)
        layer = Image.new("L", self.img.size, 0)
        dl = ImageDraw.Draw(layer)
        for top, bottom, ch in bands:
            dl.rectangle([0, self.p(0, top)[1], self.img.size[0], self.p(0, bottom)[1]], fill=IDX[ch])
        self.img.paste(layer, (0, 0), mask)


def bez(p0, p1, p2, p3, steps=10):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out


def mirror(pts):
    return [(32 - x, y) for x, y in pts]


# ---------------------------------------------------------------- 角色（世界坐标：头像画布 32×32）

def draw_character(c, portrait=False):
    # 后面的长发：头顶不要太厚，两侧一直垂到画面外
    c.ellipse(16, 12.6, 12.4, 11.0, "H")
    left_curtain = [(4.6, 10), (3.4, 17), (2.6, 25), (2.0, 33), (1.6, 42), (2.4, 52), (8.0, 52), (8.4, 42), (8.2, 32), (7.6, 22), (6.8, 13)]
    c.poly(left_curtain, "H")
    c.poly(mirror(left_curtain), "H")
    c.poly([(9.0, 22), (23.0, 22), (23.4, 31), (8.6, 31)], "d")   # 脖子后面的头发（暗一点）

    # 身体：奶油色披肩 + 荷叶边立领 + 黑领结 + 花胸针
    c.poly([(9.0, 27.5), (23.0, 27.5), (27.5, 31), (29.5, 40), (29.5, 52), (2.5, 52), (2.5, 40), (4.5, 31)], "Q")
    c.poly([(4.8, 31.2), (9.4, 28.2), (16, 32.2), (22.6, 28.2), (27.2, 31.2), (26.8, 34.5), (16, 37.0), (5.2, 34.5)], "q")
    c.poly([(5.6, 31.6), (9.8, 28.8), (16, 32.0), (22.2, 28.8), (26.4, 31.6), (26.0, 34.0), (16, 36.2), (6.0, 34.0)], "Q")
    c.poly([(13.9, 24.5), (18.1, 24.5), (18.3, 28.6), (13.7, 28.6)], "s")
    for x in (12.8, 14.6, 16.4, 18.2):
        c.ellipse(x + 0.5, 28.2, 1.15, 1.0, "Q")
    c.line([(5.6, 31.6), (6.0, 34.0), (16, 36.2), (26.0, 34.0), (26.4, 31.6)], 0.35, "O")
    c.poly([(16, 29.8), (12.4, 28.6), (12.8, 31.6)], "N")
    c.poly([(16, 29.8), (19.6, 28.6), (19.2, 31.6)], "N")
    flower(c, 16, 29.7, 1.45)
    if portrait:
        # 抱在胸前的书，封面上有星芒
        c.poly([(2.6, 31.2), (11.6, 29.4), (13.2, 42.0), (4.2, 43.6)], "b")
        c.poly([(2.6, 31.2), (3.6, 31.0), (5.2, 43.4), (4.2, 43.6)], "k")
        c.poly([(11.6, 29.4), (12.6, 29.8), (14.2, 42.2), (13.2, 42.0)], "Q")
        c.line([(4.4, 32.4), (10.6, 31.2), (11.9, 40.8), (5.8, 42.0), (4.4, 32.4)], 0.25, "G")
        flower(c, 8.3, 36.4, 2.0)
        c.ellipse(12.9, 34.2, 1.5, 1.2, "S")
        c.ellipse(12.2, 36.0, 1.2, 0.9, "S")

    # 脸：比例放大（Q 版大脸）
    face = (bez((6.9, 10.5), (6.5, 17.0), (7.8, 21.5), (11.0, 24.4))
            + bez((11.0, 24.4), (12.9, 25.9), (14.7, 26.4), (16.0, 26.4))
            + bez((16.0, 26.4), (17.3, 26.4), (19.1, 25.9), (21.0, 24.4))
            + bez((21.0, 24.4), (24.2, 21.5), (25.5, 17.0), (25.1, 10.5))
            + bez((25.1, 10.5), (25.0, 6.2), (20.5, 4.6), (16.0, 4.6))
            + bez((16.0, 4.6), (11.5, 4.6), (7.0, 6.2), (6.9, 10.5)))
    c.poly(face, "S")
    jaw = (bez((7.0, 15.0), (7.4, 19.5), (8.6, 22.0), (11.0, 24.4)) + bez((11.0, 24.4), (12.9, 25.9), (14.7, 26.4), (16.0, 26.4))
           + bez((16.0, 26.4), (17.3, 26.4), (19.1, 25.9), (21.0, 24.4)) + bez((21.0, 24.4), (23.4, 22.0), (24.6, 19.5), (25.0, 15.0)))
    c.line(jaw, 0.42, "K")

    # 刘海：中分往两边，一缕一缕的尖，中间一缕垂到两眼之间
    bangs = ([(6.2, 9.4), (7.0, 11.4), (8.0, 11.2), (9.2, 14.2), (10.2, 11.6), (12.2, 14.4), (13.6, 11.6),
              (15.6, 15.6), (16.8, 11.8), (18.8, 14.4), (20.0, 11.6), (22.2, 14.2), (23.6, 11.4), (25.2, 11.4), (25.8, 9.4)]
             + bez((25.8, 9.4), (25.6, 3.2), (20.6, 1.4), (16.0, 1.4)) + bez((16.0, 1.4), (11.4, 1.4), (6.4, 3.2), (6.2, 9.4)))
    c.poly([(x, y + 0.75) for x, y in bangs], "s")   # 刘海投在额头上的影子
    c.poly(bangs, "H")
    side = [(6.0, 9.6), (8.3, 11.8), (8.2, 17.5), (7.9, 22.5), (7.2, 26.4), (6.3, 27.6), (5.8, 21.0), (5.5, 14.0)]
    c.poly(side, "H")
    c.poly(mirror(side), "H")
    c.poly(bez((15.3, 2.4), (15.2, 0.4), (17.4, -0.4), (18.6, 0.4)) + bez((18.6, 0.4), (17.2, 0.2), (16.3, 1.0), (16.4, 2.4)), "H")
    c.arc(16, 11.0, 9.0, 7.6, 206, 334, 1.0, "h")
    c.line([(10.4, 4.6), (9.2, 7.4)], 0.6, "h")
    c.line([(21.6, 4.6), (22.8, 7.4)], 0.6, "h")

    # 花饰（星芒）+ 黑色蝴蝶结，别在右上角，稍微伸出头的轮廓，小图里也认得出
    c.poly([(26.0, 8.6), (30.4, 7.4), (30.0, 11.6)], "N")
    c.poly([(25.6, 9.2), (26.8, 14.2), (25.2, 13.8)], "N")
    c.poly([(26.4, 9.0), (30.2, 14.0), (28.8, 14.8)], "N")
    c.ellipse(25.2, 6.2, 3.9, 3.9, "K")
    flower(c, 25.2, 6.2, 3.4)


def flower(c, cx, cy, r):
    """八瓣花：外圈橙色花瓣，内圈深一点，金色花心"""
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        tip = (cx + r * math.cos(a), cy + r * math.sin(a))
        l = (cx + r * 0.42 * math.cos(a - 0.55), cy + r * 0.42 * math.sin(a - 0.55))
        rr = (cx + r * 0.42 * math.cos(a + 0.55), cy + r * 0.42 * math.sin(a + 0.55))
        c.poly([l, tip, rr, (cx, cy)], "F")
    c.ellipse(cx, cy, r * 0.45, r * 0.45, "f")
    c.ellipse(cx, cy, r * 0.3, r * 0.3, "G")



# ---------------------------------------------------------------- 五官（用形状画，两种尺寸共用）

EYE_L, EYE_R, EYE_Y = 12.2, 19.8, 18.2

def eye(c, ex, ey, side, kind, k=1.0):
    """竖长的眼睛。side = -1 左眼（外眼角在左）、+1 右眼。高光两只眼都在左上。"""
    X = lambda dx: ex + side * dx * k            # dx > 0：往外眼角方向
    Y = lambda dy: ey + dy * k
    rx, ry, cy = 1.75 * k, 2.35 * k, Y(0.25)       # 虹膜：竖长椭圆

    def rim(deg, grow=0.22):
        """虹膜边上的点；deg 按外眼角量：180 = 外眼角，270 = 正上方，360 = 内眼角"""
        a = math.radians(deg)
        return (ex + side * -(rx + grow * k) * math.cos(a), cy + (ry + grow * k) * math.sin(a))

    if kind in ("open", "sparkle", "tired"):
        c.clipped_bands(ex, cy, rx, ry, [(Y(-9), Y(-1.0), "A"), (Y(-1.0), Y(0.9), "B"), (Y(0.9), Y(9), "C")])
        c.ellipse(ex, Y(0.3), 0.6 * k, 1.05 * k, "E")                                     # 瞳孔
        if kind == "sparkle":
            hx, hy, r = ex - 0.55 * k, Y(-0.8), 0.95 * k
            c.poly([(hx, hy - r), (hx + 0.28 * r, hy - 0.28 * r), (hx + r, hy), (hx + 0.28 * r, hy + 0.28 * r),
                    (hx, hy + r), (hx - 0.28 * r, hy + 0.28 * r), (hx - r, hy), (hx - 0.28 * r, hy - 0.28 * r)], "W")
        else:
            c.ellipse(ex - 0.6 * k, Y(-0.85), 0.55 * k, 0.62 * k, "W")                    # 大高光（左上）
        c.ellipse(ex + 0.6 * k, Y(1.3), 0.28 * k, 0.28 * k, "W")                           # 小高光（右下）
        if kind == "tired":                                                                # 眼皮盖住上半
            c.poly([(ex - 2.8 * k, Y(-3.4)), (ex + 2.8 * k, Y(-3.4)), (ex + 2.8 * k, Y(-0.2)), (ex - 2.8 * k, Y(-0.2))], "S")
            c.line([rim(185, 0.1), (X(0.8), Y(-0.35)), (X(-0.8), Y(-0.3)), rim(355, 0.1)], 0.55 * k, "K")
        else:
            c.line([rim(d) for d in range(195, 336, 10)], 0.55 * k, "K")                     # 上睫毛：贴着虹膜顶的弧
            c.line([rim(d) for d in range(195, 256, 10)], 0.95 * k, "K")                     # 外眼角那段加粗
            ox, oy = rim(195)
            c.poly([(ox, oy), rim(212), (ox + side * 0.95 * k, oy - 0.45 * k)], "K")        # 眼尾往外上挑
        c.line([rim(d, 0.12) for d in range(120, 161, 10)], 0.3 * k, "A")                  # 下睫毛：外侧一小段
    elif kind == "happy":                                                                  # ^ ^
        c.line([(X(1.9), Y(0.7)), (X(0.0), Y(-0.9)), (X(-1.9), Y(0.7))], 0.65 * k, "K")
    elif kind == "closed":                                                                 # 睡着：向下的弧
        c.line([(X(2.0), Y(0.1)), (X(1.0), Y(0.95)), (X(-1.0), Y(0.95)), (X(-2.0), Y(0.1))], 0.6 * k, "K")
        c.line([(X(2.0), Y(0.1)), (X(2.6), Y(-0.3))], 0.45 * k, "K")
    elif kind == "cry":                                                                    # > <
        c.line([(X(1.9), Y(-1.5)), (X(-1.6), Y(0)), (X(1.9), Y(1.5))], 0.65 * k, "K")


def mouth(c, kind):
    if kind == "small":
        c.line([(15.25, 23.1), (16.0, 23.45), (16.75, 23.1)], 0.45, "M")
    elif kind == "open":
        c.poly([(14.7, 22.6), (17.3, 22.6), (16.8, 24.3), (15.2, 24.3)], "M")
        c.ellipse(16, 23.8, 0.85, 0.45, "T")
    elif kind == "wavy":
        c.line([(14.8, 23.4), (15.4, 22.95), (16.0, 23.4), (16.6, 22.95), (17.2, 23.4)], 0.4, "M")
    elif kind == "o":
        c.ellipse(16, 23.4, 0.75, 0.85, "M")
        c.ellipse(16, 23.5, 0.35, 0.4, "T")


def draw_face(c, eyes, mouth_kind, k=1.0, half_gap=None):
    """k：眼睛大小；half_gap：两只眼中心到脸中线的距离（眼睛变小时一起收拢）"""
    c.ellipse(10.7, 21.3, 1.5, 0.55, "P")     # 腮红
    c.ellipse(21.3, 21.3, 1.5, 0.55, "P")
    hg = half_gap if half_gap is not None else (EYE_R - EYE_L) / 2
    if eyes != "none":
        eye(c, 16 - hg, EYE_Y, -1, eyes, k)
        eye(c, 16 + hg, EYE_Y, +1, eyes, k)
    mouth(c, mouth_kind)

# ---------------------------------------------------------------- 后处理

HAIR = set("Hhde")
SKIN = set("Ss")

def finish(g):
    n = len(g)
    # 描边
    add = [(x, y) for y in range(n) for x in range(n) if g[y][x] == "." and any(
        0 <= x + dx < n and 0 <= y + dy < n and g[y + dy][x + dx] not in ".K" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for x, y in add:
        g[y][x] = "K"
    # 刘海在额头上投下一道阴影
    for y in range(1, n):
        for x in range(n):
            if g[y][x] == "S" and g[y - 1][x] in HAIR:
                g[y][x] = "s"
    return g


def stamp(g, rows, x0, y0, mirror_x=False):
    for dy, row in enumerate(rows):
        row = row[::-1] if mirror_x else row
        for dx, ch in enumerate(row):
            x, y = x0 + dx, y0 + dy
            if ch != "." and 0 <= y < len(g) and 0 <= x < len(g):
                g[y][x] = ch


# 32 像素头像的眼睛（6×7，左眼；右眼镜像）
EYE_TRIALS = {
    "① 原来（方框）": ["KKKKK.", "KWWAAK", "KWAAAK", "KAEEBK", "KBBBCK", "KBCCWK", ".KKKK."],
    "② 粗睫毛、无侧框": ["KKKKKK", "KKAAWK", ".AAAWA", ".AEEBA", ".BBBCB", ".BCCWC", "..KKK."],
    "③ 竖长大眼": [".KKKK.", "KKAAKK", "KWAAAK", "KWAEBK", "KABBBK", "KBCCCK", ".BCWC.", "..KK.."],
    "④ 大高光": ["KKKKK.", "KWWAAK", "KWWEAK", "KAEEBK", "KBBCCK", ".BCCW.", "..KK.."],
}
EYES32 = {
    "open":    ["KKKKK.", "KKAWWA", ".AAWWA", ".AEEBA", ".BBBCB", ".BCCWC", "..KKK."],
    "sparkle": ["KKKKK.", "KKAAWA", ".AAWWW", ".AEEWA", ".BBBCB", ".BCCYC", "..KKK."],
    "happy":   ["......", "......", "..KK..", ".K..K.", "K....K", "......", "......"],
    "tired":   ["......", "......", "......", "KKKKKK", ".AEEBA", ".BBCCB", "..KKK."],
    "cry":     ["......", "KK....", "..KK..", "....KK", "..KK..", "KK....", "......"],
    "closed":  ["......", "......", "......", "K....K", ".KKKK.", "......", "......"],
}
MOUTH32 = {
    "small": ["MM"],
    "smile": ["M..M", ".MM."],
    "open":  ["MMMM", ".TT."],
    "wavy":  [".M.M", "M.M."],
    "o":     [".M.", "M.M", ".M."],
}


def icon(eyes="open", mouth="small", extras=(), eye_rows=None, k=1.08, half_gap=None):
    c = Canvas(32)
    draw_character(c)
    draw_face(c, eyes, mouth, k=k, half_gap=half_gap)
    g = finish(c.grid())
    for e in extras:
        if e == "sweat": stamp(g, [".X", "XX", "XX"], 3, 11)
        if e == "tear": stamp(g, ["X", "X"], 10, 21); stamp(g, ["X", "X"], 21, 21)
        if e == "zzz": stamp(g, ["ZZZ", ".Z.", "ZZZ"], 1, 1)
        if e == "star": stamp(g, [".Y.", "YYY", ".Y."], 1, 2)
    return g


MOODS = [
    ("元气满满 <50%", dict(eyes="sparkle", mouth="open", extras=("star",))),
    ("状态不错 50–75%", dict(eyes="open", mouth="small")),
    ("有点累 75–90%", dict(eyes="tired", mouth="wavy", extras=("sweat",))),
    ("快撑不住 90–100%", dict(eyes="cry", mouth="o", extras=("tear", "sweat"))),
    ("睡着了 100%", dict(eyes="closed", mouth="small", extras=("zzz",))),
]


def portrait(eyes="open", mouth="small", extras=(), k=1.14, half_gap=None):
    c = Canvas(64, -4.0, -1.0, 64 / 40)
    draw_character(c, portrait=True)
    draw_face(c, eyes, mouth, k=k, half_gap=half_gap)
    g = finish(c.grid())
    if "star" in extras:
        stamp(g, ["..Y..", ".YYY.", "YYYYY", ".YYY.", "..Y.."], 3, 5)
    if "tear" in extras:
        stamp(g, ["X", "XX", "XX"], 22, 43); stamp(g, ["X", "XX", "XX"], 41, 43)
    return g


from PIL import ImageFilter

def smooth(draw, n, x0, y0, scale, outline=1.0):
    """同一套形状，不缩成像素：在 8 倍分辨率上画完，描边，再平滑缩小到 n×n"""
    c = Canvas(n, x0, y0, scale)
    draw(c)
    idx = np.array(c.img)
    sil = Image.fromarray(((idx > 0) * 255).astype(np.uint8))
    for _ in range(max(1, round(outline * SS))):
        sil = sil.filter(ImageFilter.MaxFilter(3))
    ring = (np.array(sil) > 0) & (idx == 0)
    idx = idx.copy()
    idx[ring] = IDX["K"]
    lut = np.zeros((256, 4), dtype=np.uint8)
    for ch, i in IDX.items():
        if ch != ".":
            lut[i] = PAL[ch] + (255,)
    return Image.fromarray(lut[idx], "RGBA").resize((n, n), Image.LANCZOS)


def smooth_icon(eyes="open", mouth="small", extras=(), n=32, k=1.08, half_gap=None):
    def draw(c):
        draw_character(c)
        draw_face(c, eyes, mouth, k=k, half_gap=half_gap)
        extras_vec(c, extras, portrait=False)
    return smooth(draw, n, 0, 0, n / 32, outline=0.9 * n / 32)


def smooth_portrait(eyes="open", mouth="small", extras=(), n=128, k=1.14, half_gap=None):
    def draw(c):
        draw_character(c, portrait=True)
        draw_face(c, eyes, mouth, k=k, half_gap=half_gap)
        extras_vec(c, extras, portrait=True)
    return smooth(draw, n, -4.0, -1.0, n / 40, outline=0.8 * n / 64)


def extras_vec(c, extras, portrait):
    for e in extras:
        if e == "star":
            cx, cy, r = (1.2, 3.0, 1.6)
            c.poly([(cx, cy - r), (cx + 0.3 * r, cy - 0.3 * r), (cx + r, cy), (cx + 0.3 * r, cy + 0.3 * r),
                    (cx, cy + r), (cx - 0.3 * r, cy + 0.3 * r), (cx - r, cy), (cx - 0.3 * r, cy - 0.3 * r)], "Y")
        if e == "sweat":
            c.ellipse(3.6, 13.2, 0.9, 1.2, "X"); c.poly([(2.8, 12.8), (3.6, 10.8), (4.4, 12.8)], "X")
        if e == "tear":
            for x in (EYE_L, EYE_R):
                c.ellipse(x, 21.6, 0.55, 0.8, "X")
        if e == "zzz":
            c.line([(0.8, 1.2), (3.2, 1.2), (0.8, 3.6), (3.2, 3.6)], 0.55, "Z")


def to_img(g, px):
    n = len(g)
    img = Image.new("RGBA", (n * px, n * px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(n):
        for x in range(n):
            if g[y][x] != ".":
                d.rectangle([x * px, y * px, x * px + px - 1, y * px + px - 1], fill=PAL[g[y][x]] + (255,))
    return img


def font(size):
    for path in ("/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


MOODS5 = [("状态不错", dict()), ("元气满满", dict(eyes="sparkle", mouth="open", extras=("star",))),
          ("有点累", dict(eyes="tired", mouth="wavy", extras=("sweat",))),
          ("快撑不住", dict(eyes="cry", mouth="o", extras=("tear", "sweat"))),
          ("睡着了", dict(eyes="closed", mouth="small", extras=("zzz",)))]

SIZES = [  # (名字, 半身像眼睛大小, 头像眼睛大小, 两眼半间距)
    ("现在", 1.14, 1.08, 3.8),
    ("小一点", 0.98, 0.98, 3.6),
    ("再小一点", 0.86, 0.9, 3.45),
]

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "out")
    os.makedirs(out, exist_ok=True)
    P, I = 300, 150
    col = P + 40
    W, H = 40 + col * len(SIZES), 60 + P * 2 + I + 200
    sheet = Image.new("RGB", (W, H), (250, 248, 245))
    d = ImageDraw.Draw(sheet)
    for i, (name, kp, ki, hg) in enumerate(SIZES):
        x = 30 + i * col
        d.text((x, 16), name, fill=(40, 40, 40), font=font(30))
        for r, kw in enumerate((dict(), dict(eyes="sparkle", mouth="open", extras=("star",)))):
            y = 64 + r * (P + 16)
            d.rounded_rectangle([x - 6, y - 6, x + P + 6, y + P + 6], 18, fill=(238, 233, 228))
            im = smooth_portrait(n=P, k=kp, half_gap=hg, **kw)
            sheet.paste(im, (x, y), im)
        y = 64 + 2 * (P + 16)
        d.rounded_rectangle([x - 4, y - 4, x + I + 4, y + I + 4], 14, fill=(238, 233, 228))
        im = smooth_icon(n=I, k=ki, half_gap=hg)
        sheet.paste(im, (x, y), im)
        d.text((x + I + 14, y + 8), "菜单栏头像", fill=(110, 110, 110), font=font(18))
        for j, (bg, ink) in enumerate((((236, 236, 236), (20, 20, 20)), ((34, 34, 36), (240, 240, 240)))):
            bx, by = x + I + 14, y + 44 + j * 54
            d.rounded_rectangle([bx, by, bx + 120, by + 46], 8, fill=bg)
            im = smooth_icon(n=32, k=ki, half_gap=hg)
            sheet.paste(im, (bx + 10, by + 7), im)
            d.text((bx + 50, by + 11), "63%", fill=ink, font=font(20))
    sheet.save(os.path.join(out, "eyesize-v16.png"))
    print("ok")
