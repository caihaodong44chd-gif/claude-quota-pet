"""出图流水线第 1 步：给一款形象生成出图包（提示词 + 参考图），放进本机不进 git 的素材文件夹。

用法：python3 design/painted/make_pack.py classic
      python3 design/painted/make_pack.py --prompt drowsy nervous     只打印这几个表情的提示词（给已经做好的形象补表情，附上它的底图发）

读 design/painted/<形象>.json 里的 character（角色描述）、label（中文名，没写就用文件名）和 source（原图目录），
在 source 的上一级目录里生成：
  提示词.md          底图和各个表情的提示词，按顺序一段段发给 GPT
  参考_画风.png       已经做好的形象（STYLE_REFERENCE）的底图：只参考画风，各款风格才统一
character 里写了 reference（比如 参考_设定.png）时，把那张设定图放进同一个文件夹：发型、发饰、服装以它为准。
再建好 source 目录（GPT出图/），出好的图按提示词里的文件名存进去，接着跑 export_painted.py。
"""
import importlib.util, json, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


ep = module("export_painted", os.path.join(HERE, "export_painted.py"))
STYLE_REFERENCE = "shades"  # 画风以它为准

# 汗珠、眼泪直接画进表情（叠上去的符号和精绘不搭）；要明显，不然缩到菜单栏就看不见了
SWEAT = ("露出皮肤较多的那一侧太阳穴（眉尾外侧、耳朵前面）有一颗明显的汗珠，贴着脸往下滑："
         "浅蓝色，带一圈深一点的蓝色轮廓线，里面有白色高光，大小约为眼睛高度的一半，上尖下圆")
TEARS = ("两只眼睛眼角挂着泪花，各有一道眼泪顺着脸颊流下来：浅蓝色，带一圈深一点的蓝色轮廓线，里面有白色高光，"
         "要明显，不要画成透明的淡淡一层")
# 表情 → 要 GPT 画成什么样。键和 export_painted.FACES 一一对应（底图 open-small 除外）
EXPRESSIONS = {
    "sparkle-open": "眼睛睁大、亮晶晶的，瞳孔里有星形的高光；嘴巴张开，开心地笑。",
    "happy-open": "笑眯眼，眼睛弯成向上的弧线（像 ^ ^）；嘴巴张开，开心地笑。",
    "closed-open": "闭上眼睛，眼睛是向下弯的细线，像在眨眼；嘴巴张开，开心地笑。",
    "closed-small": "闭上眼睛，眼睛是向下弯的细线；嘴小小地抿着，神情平静。",
    "tired-wavy": f"半睁眼，上眼皮耷拉下来盖住一半瞳孔，眉毛微微皱起，眼神疲惫；嘴角歪着，嘴是波浪形，有点为难。{SWEAT}。",
    "closed-wavy": "闭上眼睛，眼睛是向下弯的细线；嘴是波浪形，像在打瞌睡。不要画汗珠（脚本会从上一张复制同一颗过来）。",
    "cry-o": f"眼睛紧紧闭成 > < 的形状，眉毛皱起来；嘴张成小小的 O 形，很着急。{TEARS}。",
    "sleep": "睡着了。眼睛轻轻闭着，眉毛完全放松，嘴巴微微张开一点，脸颊有一点红晕，看起来睡得很香。",
    "puzzled": "有点懵、很疑惑。一边眉毛挑起、另一边微微皱着，眼睛睁着看向画面右上方，嘴抿成一条歪歪的斜线。",
    "drowsy": "刚被叫醒，还迷迷糊糊的。眼睛只睁开一半，眼神发懵、没有焦点，一只眼比另一只睁得更小一点，眉毛放松、微微下垂；"
              "嘴微微张开一条小缝，像还没睡醒。脸颊有一点红晕。",
    "nervous": "紧张、有点慌。眼睛睁大，瞳孔比平时小一点，眉毛向上皱成八字；嘴抿成波浪形、嘴角微微咧开，像在硬撑着笑。"
               "不要画汗珠（之后会另外加上）。",
    "surprised": "被戳了一下，吓了一小跳，有点害羞。眼睛睁得圆圆的，眉毛扬起；嘴张成小小的圆形，像在说「诶？」；脸颊明显泛红。",
    "pout": "有点生气，在闹别扭。眉毛压低、向中间皱起，眼睛半眯着斜看向画面一侧；嘴紧紧抿着、嘴角向下撇，脸颊泛红。"
            "脸的轮廓不要变，不要把腮帮子画鼓。",
}
assert set(EXPRESSIONS) == set(ep.FACES[1:]), "EXPRESSIONS 要和 export_painted.FACES 对上"

BATCH = 7  # 一次让 GPT 出几个表情：再多，后面几张容易走样或者被拼成一张

EDIT_PREFIX = ("在这张图上只改脸部表情，其他全部保持不变：头发、饰品、衣服、姿势、头的角度、构图、人物大小和位置、"
               "绿色背景、画风和光影都不要动，不要移动或缩放人物，头也不要低下、歪或转动。"
               "除了下面写到的，不要画眼泪、汗珠、星星、zzz、问号等符号或文字。")


def base_prompt(c):
    references = ["- 图 1 是同一套桌面宠物里另一个角色的底图，只参考画风、上色、比例和构图，不要参考她的长相、发型和衣服"]
    if c.get("reference"):
        references.append("- 图 2 是这个角色的设定图：发型、发饰、服装和配色以它为准，但只画到胸口，手里不拿东西，画风按图 1")
    newline = "\n"
    return f"""参考图：
{newline.join(references)}

画一张日系动漫风格的角色胸像，用作桌面宠物，和图 1 是同一套、同一种画风。

画风：
- 标准日系动漫立绘风格（类似手游角色立绘），干净的线稿加赛璐璐上色
- 眼睛、鼻子、嘴都用动漫的画法：睫毛不要太浓，嘴唇小而淡，不要写实的五官和浓妆

人物：{c["summary"]}
- 身体比例自然：脖子正常粗细，肩膀窄一点、平一点
- 头稍微向一侧歪一点，身体微微侧向一边，不要完全左右对称
头发：{c["hair"]}
眼睛：{c["eyes"]}
饰品：{c["accessories"]}
服装：{c["outfit"]}
表情：{c["expression"]}

构图：
- 正方形 1024×1024，纯绿色 #00FF00 的纯色背景（不要白色），不要阴影和渐变
- 画到胸口，人物居中；头顶、发饰和两侧的头发不要被画面切掉
- 手不出现在画面里

不要：文字、水印、背景元素；不要画眼泪、汗珠、星星等符号。"""


def batch_prompt(faces=None):
    """几个表情一次发（默认全部）：要 GPT 每个表情出一张单独的图、每张都在底图上改（不然容易拼成九宫格，或者一张接一张地改走样）"""
    items = [f"{i}. {face}：{EXPRESSIONS[face]}" for i, face in enumerate(faces or EXPRESSIONS, start=1)]
    return "\n".join([
        f"以我上传的这张图为底图，生成下面 {len(items)} 个表情，每个表情单独一张图，一共 {len(items)} 张，不要拼成一张。",
        "每张都直接在这张底图上改，不要在上一张生成的图上接着改；每张图注明编号和名字。",
        "",
        "每张的要求都一样：" + EDIT_PREFIX,
        "",
        *items,
    ])


def pack_markdown(name, label, c, source, references):
    lines = [
        f"# 「{label}」精绘出图包",
        "",
        f"出好的图存进 `{source}/`，文件名按每段的标题。满意一张存一张，不用一次出完。",
        "",
        "## 第 1 步：底图 → `open-small.png`",
        "",
        "开一个**新对话**，按顺序上传 " + "、".join(f"`{f}`" for f in references) + "，再粘贴：",
        "",
        "```", base_prompt(c), "```",
        "",
        "检查：头顶、发饰、两侧头发没被切掉；背景是纯绿色。不满意就在同一个对话里让它改。",
        "",
        "## 第 2 步：表情（每次都附上底图 `open-small.png`，在底图上改）",
        "",
    ]
    faces = list(EXPRESSIONS)
    batches = [faces[i:i + BATCH] for i in range(0, len(faces), BATCH)]
    lines += [f"### 分 {len(batches)} 批发（每批都附上底图，粘贴那一段）", "",
              "GPT 可能会拼成一张大图，或者一张接一张地改：出来的不是一张张单独的图、或者越往后越走样时，改用下面一段一段发。", ""]
    for n, batch in enumerate(batches, start=1):
        lines += [f"**第 {n} 批（{len(batch)} 张）**", "", "```", batch_prompt(batch), "```", ""]
    lines += ["### 一段一段发", ""]
    for i, (face, text) in enumerate(EXPRESSIONS.items(), start=1):
        lines += [f"**{i}. `{face}.png`**", "", "```", EDIT_PREFIX, "", f"表情：{text}", "```", ""]
    lines += [
        "和底图对比：人物稍微挪一点、大一点小一点没关系，脚本会对齐，头发、衣服也只用底图的；只有脸的轮廓或五官位置明显变了才重出。",
        "汗珠、眼泪不明显时，在同一个对话里说「汗珠 / 眼泪再明显一点」。",
    ]
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--prompt":
        unknown = [f for f in sys.argv[2:] if f not in EXPRESSIONS]
        if unknown:
            sys.exit(f"✗ 没有这些表情：{', '.join(unknown)}（有：{', '.join(EXPRESSIONS)}）")
        print(batch_prompt(sys.argv[2:]))
        return
    if len(sys.argv) != 2:
        sys.exit("用法：python3 design/painted/make_pack.py <形象>")
    name = sys.argv[1]
    with open(os.path.join(HERE, f"{name}.json")) as f:
        config = json.load(f)
    source = os.path.join(ep.REPO, config["source"])
    folder = os.path.dirname(source)
    os.makedirs(source, exist_ok=True)

    # 画风参考：已经做好的那款的底图
    with open(os.path.join(HERE, f"{STYLE_REFERENCE}.json")) as f:
        style_source = os.path.join(ep.REPO, json.load(f)["source"])
    Image.open(os.path.join(style_source, "open-small.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS) \
        .save(os.path.join(folder, "参考_画风.png"))

    references = ["参考_画风.png"]
    extra = config["character"].get("reference")
    if extra:
        if not os.path.exists(os.path.join(folder, extra)):
            sys.exit(f"✗ 配置里写了设定图 {extra}，但 {os.path.relpath(folder, ep.REPO)}/ 里没有这张图")
        references.append(extra)
    with open(os.path.join(folder, "提示词.md"), "w") as f:
        f.write(pack_markdown(name, config.get("label", name), config["character"], config["source"], references))
    print(f"出图包：{os.path.relpath(folder, ep.REPO)}/（提示词.md、{'、'.join(references)}）")


if __name__ == "__main__":
    main()
