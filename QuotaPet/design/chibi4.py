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
# 可选的形象：发型（hair，默认长直发）、饰品、配色，还可以换眼睛（eyes，见 pet_pixel.EYE_SETS）、
# 嘴（mouth）、腮红大小（blush）。colors 只写和经典款不一样的颜色，
# 皮肤、腮红、眼睛高光（SsPW）不能改，单色模式靠它们挖空脸。draft = 设计稿，export_swift.py 不导出
STYLES = {
    "classic": dict(label="经典", accessory="flower", colors={}),
    "neko": dict(label="猫耳", accessory="ears", colors={
        "H": (228, 222, 238), "h": (252, 250, 255), "d": (190, 180, 210), "e": (160, 148, 184),
        "A": (88, 48, 132), "B": (146, 90, 200), "C": (204, 160, 240), "E": (40, 20, 60),
        "K": (70, 54, 88), "N": (88, 64, 120), "n": (120, 96, 150)}),
    "youth": dict(label="青春", hair="ponytail", accessory="bow", eyes="big", mouth="cat", blush=1.35, colors={
        "H": (186, 118, 72), "h": (232, 172, 118), "d": (146, 86, 48), "e": (116, 64, 32),
        "A": (26, 92, 84), "B": (46, 150, 128), "C": (130, 214, 180), "E": (14, 48, 40),
        "Q": (250, 252, 255), "q": (196, 212, 234), "O": (58, 100, 180), "N": (232, 64, 84), "n": (252, 130, 140)}),
    "witch": dict(label="魔女", accessory="hat", colors={
        "H": (92, 58, 132), "h": (150, 112, 196), "d": (64, 36, 96), "e": (46, 24, 72), "K": (38, 22, 54),
        "A": (130, 78, 8), "B": (222, 160, 28), "C": (255, 226, 110), "E": (58, 28, 0),
        "Q": (62, 44, 92), "q": (40, 26, 62), "O": (242, 164, 60), "N": (30, 22, 46), "n": (78, 58, 110),
        "b": (104, 44, 150), "k": (62, 22, 96)}),
    # Codex 专用（不在 Claude 的形象选项里）：白发龙娘，龙角、尖耳、背后一对小龙翼，发饰和领口是中国结
    "dragon": dict(label="龙娘", hair="wavy", accessory="horns", collar="knot", wings=True, elf=True, colors={
        "H": (230, 228, 244), "h": (255, 255, 255), "d": (188, 184, 220), "e": (148, 142, 190), "K": (66, 60, 100),
        "A": (78, 72, 124), "B": (136, 130, 188), "C": (196, 194, 238), "E": (40, 36, 70),
        "Q": (252, 252, 255), "q": (212, 210, 234), "O": (164, 156, 210), "N": (56, 50, 92), "n": (120, 114, 170),
        "F": (206, 200, 240), "f": (150, 142, 204), "G": (250, 248, 255), "b": (104, 94, 164), "k": (70, 62, 124)}),
}


def palette(style="classic"):
    return {**PAL, **STYLES[style]["colors"]}


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

def draw_character(c, portrait=False, style="classic"):
    st = STYLES[style]
    accessory, hair = st["accessory"], st.get("hair", "long")
    if portrait and st.get("wings"):
        wing(c)
        wing(c, mirror)
    if hair == "ponytail":
        # 高马尾：从头顶右后方甩出来，往右下垂
        tail = (bez((19.0, 1.6), (26.0, -1.0), (31.6, 4.0), (31.2, 12.0)) + bez((31.2, 12.0), (31.0, 18.0), (29.4, 22.0), (27.6, 25.0))
                + bez((27.6, 25.0), (28.0, 20.0), (28.2, 14.0), (26.4, 9.0)) + bez((26.4, 9.0), (25.0, 5.4), (22.0, 4.0), (19.0, 4.2)))
        c.poly(tail, "H")
        c.line([(24.0, 1.4), (28.6, 4.0), (29.8, 11.0)], 0.5, "h")
    # 后面的头发：头顶不要太厚
    c.ellipse(16, 12.6, 12.4, 11.0, "H")
    if accessory == "ears":
        # 猫耳：从头顶两侧竖起来，内侧粉色；耳根被刘海盖住
        ear = [(6.0, 8.2), (5.4, 0.2), (12.6, 3.0)]
        c.poly(ear, "H")
        c.poly(mirror(ear), "H")
        inner = [(6.9, 6.6), (6.6, 2.0), (10.6, 3.6)]
        c.poly(inner, "P")
        c.poly(mirror(inner), "P")
    if accessory == "horns":  # 根部藏在刘海底下，后画的刘海会盖住
        horn(c, portrait)
        horn(c, portrait, mirror)
    if hair == "long":  # 两侧一直垂到画面外
        curtain = [(4.6, 10), (3.4, 17), (2.6, 25), (2.0, 33), (1.6, 42), (2.4, 52), (8.0, 52), (8.4, 42), (8.2, 32), (7.6, 22), (6.8, 13)]
    elif hair == "wavy":  # 长卷发：外缘一路起伏，越往下波浪越大
        ys = [10 + i * 0.5 for i in range(85)]
        base = np.interp(ys, [10, 17, 25, 33, 42, 52], [4.6, 3.4, 2.6, 2.0, 1.6, 2.4])
        curtain = [(x - (0.2 + 0.7 * (y - 10) / 42) * math.sin((y - 12) / 7.5 * 2 * math.pi), y) for x, y in zip(base, ys)]
        curtain += [(8.0, 52), (8.4, 42), (8.2, 32), (7.6, 22), (6.8, 13)]
    else:  # 扎起来了，两边只剩鬓角
        curtain = None
    if curtain:
        c.poly(curtain, "H")
        c.poly(mirror(curtain), "H")
    neck_bottom = 31 if curtain else 27.5
    c.poly([(9.0, 22), (23.0, 22), (23.4, neck_bottom), (8.6, neck_bottom)], "d")   # 脖子后面的头发（暗一点）

    # 身体：奶油色披肩 + 荷叶边立领 + 黑领结 + 花胸针
    c.poly([(9.0, 27.5), (23.0, 27.5), (27.5, 31), (29.5, 40), (29.5, 52), (2.5, 52), (2.5, 40), (4.5, 31)], "Q")
    c.poly([(4.8, 31.2), (9.4, 28.2), (16, 32.2), (22.6, 28.2), (27.2, 31.2), (26.8, 34.5), (16, 37.0), (5.2, 34.5)], "q")
    c.poly([(5.6, 31.6), (9.8, 28.8), (16, 32.0), (22.2, 28.8), (26.4, 31.6), (26.0, 34.0), (16, 36.2), (6.0, 34.0)], "Q")
    c.poly([(13.9, 24.5), (18.1, 24.5), (18.3, 28.6), (13.7, 28.6)], "s")
    if st.get("collar") == "knot":
        # 白色立领，下沿一道滚边，领口挂一个带流苏的中国结
        c.poly([(13.3, 25.9), (18.7, 25.9), (19.4, 29.0), (12.6, 29.0)], "Q")
        c.line([(12.6, 29.0), (19.4, 29.0)], 0.4, "O")
        c.line([(5.6, 31.6), (6.0, 34.0), (16, 36.2), (26.0, 34.0), (26.4, 31.6)], 0.35, "O")
    else:
        for x in (12.8, 14.6, 16.4, 18.2):
            c.ellipse(x + 0.5, 28.2, 1.15, 1.0, "Q")
        c.line([(5.6, 31.6), (6.0, 34.0), (16, 36.2), (26.0, 34.0), (26.4, 31.6)], 0.35, "O")
        c.poly([(16, 29.8), (12.4, 28.6), (12.8, 31.6)], "N")
        c.poly([(16, 29.8), (19.6, 28.6), (19.2, 31.6)], "N")
        flower(c, 16, 29.7, 1.45)
    if accessory == "hat":
        # 魔女的高立领：从肩膀两边竖起来，尖角贴着下巴
        for m in (lambda p: p, mirror):
            c.poly(m([(12.8, 28.2), (6.8, 21.4), (8.6, 28.8), (5.4, 30.6)]), "n")
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
    if st.get("elf"):
        elf_ear(c)
        elf_ear(c, mirror)
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

    if accessory == "flower":
        # 花饰（星芒）+ 黑色蝴蝶结，别在右上角，稍微伸出头的轮廓，小图里也认得出
        c.poly([(26.0, 8.6), (30.4, 7.4), (30.0, 11.6)], "N")
        c.poly([(25.6, 9.2), (26.8, 14.2), (25.2, 13.8)], "N")
        c.poly([(26.4, 9.0), (30.2, 14.0), (28.8, 14.8)], "N")
        c.ellipse(25.2, 6.2, 3.9, 3.9, "K")
        flower(c, 25.2, 6.2, 3.4)
    elif accessory == "bow":
        # 马尾上的大蝴蝶结 + 刘海上两个发夹
        c.poly([(21.0, 2.6), (17.6, 0.2), (17.4, 5.0)], "N")
        c.poly([(21.0, 2.6), (24.6, 0.0), (24.8, 5.0)], "N")
        c.ellipse(21.0, 2.6, 1.0, 1.0, "n")
        c.line([(8.6, 9.6), (11.6, 8.4)], 0.55, "Y")
        c.line([(9.2, 11.0), (12.2, 9.8)], 0.55, "O")
    elif accessory == "hat":
        # 魔女帽：尖顶从头顶往右折下来垂在耳边，宽帽檐压在刘海上，一圈橙色帽带
        c.poly([(10.0, 4.4)] + bez((10.0, 4.4), (11.0, -0.4), (15.0, -2.2), (20.0, -1.8))
               + bez((20.0, -1.8), (26.0, -1.4), (30.6, 2.0), (31.4, 9.4))
               + bez((31.4, 9.4), (29.4, 6.2), (26.4, 3.6), (22.6, 4.4)), "N")
        c.ellipse(16, 5.0, 14.4, 1.5, "N")
        c.poly([(10.4, 3.0), (22.6, 3.0), (22.8, 4.6), (10.2, 4.6)], "O")
        c.ellipse(31.2, 9.6, 0.9, 0.9, "Y")
        # 帽带上的月牙，身边飘着两颗星
        c.ellipse(13.4, 3.8, 1.0, 1.0, "Y")
        c.ellipse(13.9, 3.5, 0.8, 0.8, "O")
        for sx, sy, r in ((33.4, 18.0, 1.3), (-1.6, 24.0, 1.0)):
            c.poly([(sx, sy - r), (sx + 0.3 * r, sy - 0.3 * r), (sx + r, sy), (sx + 0.3 * r, sy + 0.3 * r),
                    (sx, sy + r), (sx - 0.3 * r, sy + 0.3 * r), (sx - r, sy), (sx - 0.3 * r, sy - 0.3 * r)], "Y")
        c.line([(12.0, 1.0), (15.0, -0.8)], 0.5, "n")


def expand(pts, d):
    """把多边形从中心往外放大 d（近似的外扩描边）"""
    cx, cy = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    out = []
    for x, y in pts:
        r = math.hypot(x - cx, y - cy) or 1
        out.append((x + (x - cx) / r * d, y + (y - cy) / r * d))
    return out


def tapered(spine, w0):
    """沿着一条中线画一根从根部 w0 粗、到尖端变细的长条（龙角）；返回（轮廓，下侧那一半）"""
    n = len(spine) - 1
    upper, lower = [], []
    for i, (x, y) in enumerate(spine):
        (ax, ay), (bx, by) = spine[max(i - 1, 0)], spine[min(i + 1, n)]
        length = math.hypot(bx - ax, by - ay) or 1
        nx, ny = (ay - by) / length, (bx - ax) / length
        w = w0 / 2 * (1 - i / n) ** 0.8
        upper.append((x - nx * w, y - ny * w))
        lower.append((x + nx * w, y + ny * w))
    return upper + lower[::-1], spine + lower[::-1], upper, lower


def horn(c, portrait, m=lambda p: p):
    """左边的龙角（m=mirror 画右边）：根部藏在刘海底下，先往外、再往上弯，下侧一半暗一点，几道横棱"""
    if portrait:
        spine = bez((9.4, 6.0), (6.0, 4.6), (2.6, 3.8), (2.0, -0.9), steps=16)
        outline, shade, upper, lower = tapered(spine, 3.6)
    else:
        spine = bez((9.4, 6.0), (6.6, 4.8), (3.6, 3.8), (3.0, 0.2), steps=16)
        outline, shade, upper, lower = tapered(spine, 3.0)
    c.poly(m(outline), "Q")
    c.poly(m(shade), "q")
    for i in (5, 9, 12):
        c.line(m([upper[i], lower[i]]), 0.45, "q")


def wing(c, m=lambda p: p):
    """左边的小龙翼（m=mirror 画右边）：从肩膀后面伸出来，翼尖朝外上方，下缘两段弧形的翼膜，只在半身像上画"""
    wrist, tip = (-0.4, 22.6), (-2.6, 19.6)
    edge = (bez((3.8, 28.4), (2.4, 26.0), (1.0, 24.2), wrist) + [tip]
            + bez(tip, (-1.6, 22.0), (-1.8, 23.8), (-3.2, 25.8))
            + bez((-3.2, 25.8), (-1.8, 26.8), (-1.2, 28.2), (-1.8, 30.2))
            + bez((-1.8, 30.2), (-0.4, 30.4), (1.2, 31.2), (2.8, 32.6)) + [(4.2, 32.0)])
    c.poly(m(edge), "q")
    c.line(m([(3.8, 28.4), (1.6, 25.2), wrist, tip]), 0.6, "e")
    c.line(m([wrist, (-3.2, 25.8)]), 0.42, "e")
    c.line(m([wrist, (-1.8, 30.2)]), 0.42, "e")


def elf_ear(c, m=lambda p: p):
    """尖耳朵：从脸侧伸到头发外面；白发和皮肤颜色太近，先垫一圈描边"""
    ear = [(7.6, 14.2), (1.6, 11.0), (7.4, 18.8)]
    c.poly(m(expand(ear, 0.5)), "K")
    c.poly(m(ear), "S")
    c.poly(m([(7.0, 15.2), (3.8, 12.6), (7.0, 17.6)]), "s")


# 中国结太小，用形状画出来是一团黑：手画像素，缩成像素之后再盖上去。(图案, 左上角 x, y)
KNOTS = {
    "icon": [([".N.", "NFN", ".N.", ".n."], 21, 5),                                   # 右边龙角根上
             ([".NN.", "NFFN", ".NN.", ".nn."], 14, 28)],                              # 立领
    "portrait": [(["..N..", ".NFN.", "NFNFN", ".NFN.", "..N..", "..N..", "..n..", ".nnn.", ".nnn."], 40, 10),
                 (["..NN..", ".NFFN.", "NFNNFN", ".NFFN.", "..NN..", "..NN..", "..nn..", ".nnnn.", ".nnnn."], 29, 47)],
}


def decorate(g, style, portrait):
    """缩成像素、描完边之后再加的手画部件"""
    if STYLES[style]["accessory"] == "horns":
        for rows, x, y in KNOTS["portrait" if portrait else "icon"]:
            stamp(g, rows, x, y)
    return g


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


def mouth(c, kind, style="classic"):
    shape = STYLES[style].get("mouth")
    if kind == "small" and shape == "cat":       # ω
        c.line([(14.9, 22.9), (15.45, 23.5), (16.0, 23.05), (16.55, 23.5), (17.1, 22.9)], 0.42, "M")
    elif kind == "small":
        c.line([(15.25, 23.1), (16.0, 23.45), (16.75, 23.1)], 0.45, "M")
    elif kind == "open":
        c.poly([(14.7, 22.6), (17.3, 22.6), (16.8, 24.3), (15.2, 24.3)], "M")
        c.ellipse(16, 23.8, 0.85, 0.45, "T")
    elif kind == "wavy":
        c.line([(14.8, 23.4), (15.4, 22.95), (16.0, 23.4), (16.6, 22.95), (17.2, 23.4)], 0.4, "M")
    elif kind == "o":
        c.ellipse(16, 23.4, 0.75, 0.85, "M")
        c.ellipse(16, 23.5, 0.35, 0.4, "T")


def draw_face(c, eyes, mouth_kind, k=1.0, half_gap=None, style="classic"):
    """k：眼睛大小；half_gap：两只眼中心到脸中线的距离（眼睛变小时一起收拢）"""
    b = STYLES[style].get("blush", 1.0)
    c.ellipse(10.7, 21.3, 1.5 * b, 0.55 * b, "P")     # 腮红
    c.ellipse(21.3, 21.3, 1.5 * b, 0.55 * b, "P")
    hg = half_gap if half_gap is not None else (EYE_R - EYE_L) / 2
    if eyes != "none":
        eye(c, 16 - hg, EYE_Y, -1, eyes, k)
        eye(c, 16 + hg, EYE_Y, +1, eyes, k)
    mouth(c, mouth_kind, style)

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


def icon(eyes="open", mouth="small", extras=(), eye_rows=None, k=1.08, half_gap=None, style="classic"):
    c = Canvas(32)
    draw_character(c, style=style)
    draw_face(c, eyes, mouth, k=k, half_gap=half_gap, style=style)
    g = decorate(finish(c.grid()), style, False)
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


def portrait(eyes="open", mouth="small", extras=(), k=1.14, half_gap=None, style="classic"):
    c = Canvas(64, -4.0, -1.0, 64 / 40)
    draw_character(c, portrait=True, style=style)
    draw_face(c, eyes, mouth, k=k, half_gap=half_gap, style=style)
    g = decorate(finish(c.grid()), style, True)
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


def to_img(g, px, style="classic"):
    pal = palette(style)
    n = len(g)
    img = Image.new("RGBA", (n * px, n * px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(n):
        for x in range(n):
            if g[y][x] != ".":
                d.rectangle([x * px, y * px, x * px + px - 1, y * px + px - 1], fill=pal[g[y][x]] + (255,))
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
