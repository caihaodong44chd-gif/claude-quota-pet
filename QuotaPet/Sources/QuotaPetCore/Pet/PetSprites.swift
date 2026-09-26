import Foundation

/// 一帧动画：菜单栏头像和面板半身像同一个表情，一起播放
public struct PetFrame: Hashable, Sendable {
    /// 菜单栏头像，32×32（Retina 屏上显示成 16pt，一格一个物理像素）
    public let icon: PixelGrid
    /// 面板里的半身像，64×64
    public let portrait: PixelGrid
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

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: return "经典"
        case .neko: return "猫耳"
        case .youth: return "青春"
        case .witch: return "魔女"
        }
    }

    var art: PetArt.Look {
        switch self {
        case .classic: return PetArt.classic
        case .neko: return PetArt.neko
        case .youth: return PetArt.youth
        case .witch: return PetArt.witch
        }
    }
}

/// 宠物：原创像素角色（参考「Claude 娘」风格），有几款形象可选（PetStyle）。
/// 像素数据在 PetArt.swift（由 design/export_swift.py 生成），这里只负责按心情把五官和小道具叠到底图上。
public enum PetSprites {
    public static let iconSize = 32
    public static let portraitSize = 64

    /// 眼睛：open 平时 / sparkle 星星眼 / happy 笑眯眼 / tired 半睁 / cry >< / closed 闭眼
    /// 嘴：small / open / wavy / o
    /// 小道具：starBig / starSmall / sweatA / sweatB / tearsA / tearsB / zzzA / zzzB / question
    static func makeFrame(_ art: PetArt.Look, _ eyes: String, _ mouth: String, _ extras: [String],
                      _ duration: TimeInterval) -> PetFrame {
        PetFrame(icon: compose(art.icon, eyes: eyes, mouth: mouth, extras: extras),
                 portrait: compose(art.portrait, eyes: eyes, mouth: mouth, extras: extras),
                 duration: duration)
    }

    static func compose(_ art: PetArt.Layers, eyes: String, mouth: String, extras: [String]) -> PixelGrid {
        var grid = PixelGrid(rows: art.base)
        if let patch = art.mouths[mouth] { grid.apply(patch) }  // 头像太小时有的嘴画不出来，没有就不画
        if let patch = art.eyes[eyes] { grid.apply(patch) }
        for name in extras {
            if let patch = art.extras[name] { grid.apply(patch) }
        }
        return grid
    }

    public static func frames(for mood: PetMood, style: PetStyle = .classic) -> [PetFrame] {
        func frame(_ eyes: String, _ mouth: String, _ extras: [String], _ duration: TimeInterval) -> PetFrame {
            makeFrame(style.art, eyes, mouth, extras, duration)
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
}

extension PixelGrid {
    /// 用字符画建一张画布（'.' 是透明）
    public init(rows: [String]) {
        self.init(width: rows.first?.utf8.count ?? 0, height: rows.count)
        stamp(rows, x: 0, y: 0)
    }

    mutating func apply(_ patch: PetArt.Patch) {
        stamp(patch.rows, x: patch.x, y: patch.y)
    }
}
