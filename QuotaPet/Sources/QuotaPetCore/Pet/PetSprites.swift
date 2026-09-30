import Foundation

/// 一帧动画：菜单栏头像和面板半身像同一个表情，一起播放
public struct PetFrame: Hashable, Sendable {
    /// 菜单栏头像：像素画 32×32 显示成 16pt（Retina 屏上一格一个物理像素），精绘显示成 22pt
    public let icon: PetPicture
    /// 面板里的半身像，显示成 96pt：像素画 64×64，精绘是 192×192 的图
    public let portrait: PetPicture
    public let duration: TimeInterval
}

/// 宠物的形象：表情、动画都一样，只是发色、饰品不同
public enum PetStyle: String, CaseIterable, Identifiable, Sendable {
    /// 橙色长发，别着星芒花饰和黑色蝴蝶结
    case classic
    /// 银紫色长发，猫耳
    case neko
    /// 栗色高马尾、大眼睛、水手服，马尾上系红蝴蝶结
    case youth
    /// 紫色长发、金色眼睛，魔女帽和高立领披肩
    case witch
    // 下面三款是 Codex 的形象
    /// 白发龙娘：弯龙角、尖耳，鬓角和立领上是红色中国结
    case dragon
    /// 墨色长发盘两个丸子头、金步摇，粉色襦裙配红色交领
    case hanfu
    /// 薄荷绿长发、头戴耳机，深灰连帽衫
    case geek
    /// 精绘（不是像素画）：淡金色大波浪长发，墨镜推在头顶，白背心配黑色飞行员夹克
    case shades

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: return tr("经典", "Classic")
        case .neko: return tr("猫耳", "Cat ears")
        case .youth: return tr("青春", "Youthful")
        case .witch: return tr("魔女", "Witch")
        case .dragon: return tr("龙娘", "Dragon girl")
        case .hanfu: return tr("汉服", "Hanfu")
        case .geek: return tr("极客", "Geek")
        case .shades: return tr("墨镜", "Shades")
        }
    }

    /// 这款形象怎么画：像素画（PetArt.swift）或精绘（Resources/Pets/<rawValue>/ 里的图，见 PaintedPicture）
    enum Art {
        case pixel(PetArt.Look)
        case painted
    }

    /// 精绘（不是像素画）的形象
    public var isPainted: Bool {
        if case .painted = art { return true }
        return false
    }

    var art: Art {
        switch self {
        case .classic: return .pixel(PetArt.classic)
        case .neko: return .pixel(PetArt.neko)
        case .youth: return .pixel(PetArt.youth)
        case .witch: return .pixel(PetArt.witch)
        case .dragon: return .pixel(PetArt.dragon)
        case .hanfu: return .pixel(PetArt.hanfu)
        case .geek: return .pixel(PetArt.geek)
        case .shades: return .painted
        }
    }

    /// 两家各有一组形象，互不重叠，两家的宠物一眼就能分开
    public static let claudeChoices: [PetStyle] = [.classic, .neko, .youth, .witch, .shades]
    public static let codexChoices: [PetStyle] = [.dragon, .hanfu, .geek]

    /// 这家 AI 的宠物：各用设置里给它选的形象；选的不在它那一组里（比如设置被改坏了）就用那组的第一款
    public static func of(_ provider: ProviderID, claudeStyle: PetStyle, codexStyle: PetStyle) -> PetStyle {
        switch provider {
        case .claude: return claudeChoices.contains(claudeStyle) ? claudeStyle : claudeChoices[0]
        case .codex: return codexChoices.contains(codexStyle) ? codexStyle : codexChoices[0]
        }
    }
}

/// 宠物：原创角色（参考「Claude 娘」风格），两家各有几款形象可选（PetStyle）。
/// 像素画的数据在 PetArt.swift（由 design/export_swift.py 生成），这里按心情把五官和小道具叠到底图上；
/// 精绘的每个表情是一整张图（Resources/Pets），这里只按心情选用哪张。
public enum PetSprites {
    /// 像素画的格数
    public static let iconSize = 32
    public static let portraitSize = 64
    /// 显示多大（pt）：像素头像一格半个点；精绘头像大一些，细节才看得清（菜单栏最高也就 22pt 左右）。
    /// 精绘图是这个尺寸的 2 倍（design/painted/export_painted.py 的 ICON、PORTRAIT），自检会核对
    public static let pixelIconPoints = 16.0
    public static let paintedIconPoints = 22.0
    public static let portraitPoints = 96.0

    /// 像素画的一帧。眼睛：open 平时 / sparkle 星星眼 / happy 笑眯眼 / tired 半睁 / cry >< / closed 闭眼
    /// 嘴：small / open / wavy / o
    /// 小道具：starBig / starSmall / sweatA / sweatB / tearsA / tearsB / zzzA / zzzB / question
    static func makeFrame(_ art: PetArt.Look, _ eyes: String, _ mouth: String, _ extras: [String],
                          _ duration: TimeInterval) -> PetFrame {
        let icon = compose(art.icon, palette: art.palette, eyes: eyes, mouth: mouth, extras: extras)
        let portrait = compose(art.portrait, palette: art.palette, eyes: eyes, mouth: mouth, extras: extras)
        return PetFrame(icon: PetPicture(content: .pixel(icon), points: pixelIconPoints),
                        portrait: PetPicture(content: .pixel(portrait), points: portraitPoints), duration: duration)
    }

    static func compose(_ art: PetArt.Layers, palette: PetPalette, eyes: String, mouth: String, extras: [String]) -> PixelGrid {
        var grid = PixelGrid(rows: art.base, palette: palette)
        if let patch = art.mouths[mouth] { grid.apply(patch) }  // 头像太小时有的嘴画不出来，没有就不画
        if let patch = art.eyes[eyes] { grid.apply(patch) }
        for name in extras {
            if let patch = art.extras[name] { grid.apply(patch) }
        }
        return grid
    }

    public static func frames(for mood: PetMood, style: PetStyle = .classic) -> [PetFrame] {
        switch style.art {
        case .pixel(let art): return pixelFrames(for: mood, art)
        case .painted: return paintedFrames(for: mood, style)
        }
    }

    static func pixelFrames(for mood: PetMood, _ art: PetArt.Look) -> [PetFrame] {
        func frame(_ eyes: String, _ mouth: String, _ extras: [String], _ duration: TimeInterval) -> PetFrame {
            makeFrame(art, eyes, mouth, extras, duration)
        }
        switch mood {
        case .energetic:  // 星星眼，头顶的星星一闪一闪，偶尔笑眯眼
            return [
                frame("sparkle", "open", ["starBig"], 0.55),
                frame("sparkle", "open", ["starSmall"], 0.45),
                frame("sparkle", "open", ["starBig"], 0.55),
                frame("happy", "open", ["starSmall"], 0.5),
                frame("sparkle", "open", [], 1.2),
                frame("closed", "open", [], 0.12),
            ]
        case .normal:  // 安静地看着你，隔一会儿眨两下眼
            return [
                frame("open", "small", [], 2.6),
                frame("closed", "small", [], 0.12),
                frame("open", "small", [], 0.22),
                frame("closed", "small", [], 0.12),
                frame("open", "small", [], 2.0),
            ]
        case .tired:  // 眼皮耷拉，汗珠往下滑，偶尔打个盹
            return [
                frame("tired", "wavy", ["sweatA"], 0.7),
                frame("tired", "wavy", ["sweatB"], 0.7),
                frame("closed", "wavy", ["sweatB"], 0.45),
                frame("tired", "wavy", [], 1.1),
            ]
        case .exhausted:  // >_< 眼泪往下掉
            return [
                frame("cry", "o", ["tearsA", "sweatA"], 0.5),
                frame("cry", "o", ["tearsB", "sweatB"], 0.5),
            ]
        case .sleeping:  // 额度用完：睡着了，Z 往上飘
            return [
                frame("closed", "small", ["zzzA"], 1.1),
                frame("closed", "small", ["zzzB"], 1.1),
            ]
        case .confused:  // 没数据：冒问号
            return [
                frame("open", "small", ["question"], 1.0),
                frame("open", "small", [], 0.6),
            ]
        case .loading:
            return [
                frame("open", "small", [], 0.9),
                frame("closed", "small", [], 0.12),
            ]
        }
    }

    /// 精绘：汗珠、眼泪在表情图里，睡着、疑惑是单独的表情，所以帧数和像素画不一样
    static func paintedFrames(for mood: PetMood, _ style: PetStyle) -> [PetFrame] {
        func frame(_ face: String, _ duration: TimeInterval) -> PetFrame {
            func picture(_ part: PaintedPicture.Part, _ points: Double) -> PetPicture {
                PetPicture(content: .painted(PaintedPicture(style: style, part: part, face: face)), points: points)
            }
            return PetFrame(icon: picture(.icon, paintedIconPoints), portrait: picture(.portrait, portraitPoints), duration: duration)
        }
        switch mood {
        case .energetic:  // 星星眼，偶尔笑眯眼、眨一下眼
            return [frame("sparkle-open", 1.6), frame("happy-open", 0.6), frame("sparkle-open", 1.2), frame("closed-open", 0.12)]
        case .normal:  // 和像素画一样：安静地看着你，隔一会儿眨两下眼
            return [frame("open-small", 2.6), frame("closed-small", 0.12), frame("open-small", 0.22),
                    frame("closed-small", 0.12), frame("open-small", 2.0)]
        case .tired:  // 太阳穴冒汗、眼皮耷拉，偶尔闭一下眼（两张的汗珠是同一颗）
            return [frame("tired-wavy", 2.4), frame("closed-wavy", 0.5)]
        case .exhausted:  // > < 流眼泪
            return [frame("cry-o", 1)]
        case .sleeping:
            return [frame("sleep", 1)]
        case .confused:
            return [frame("puzzled", 1)]
        case .loading:
            return [frame("open-small", 0.9), frame("closed-small", 0.12)]
        }
    }
}

extension PixelGrid {
    /// 用字符画建一张画布（'.' 是透明）
    public init(rows: [String], palette: PetPalette) {
        self.init(width: rows.first?.utf8.count ?? 0, height: rows.count, palette: palette)
        stamp(rows, x: 0, y: 0)
    }

    mutating func apply(_ patch: PetArt.Patch) {
        stamp(patch.rows, x: patch.x, y: patch.y)
    }
}
