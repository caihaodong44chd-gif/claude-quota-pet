import Foundation

/// 一帧动画：菜单栏头像和面板半身像同一个表情，一起播放
public struct PetFrame: Hashable, Sendable {
    /// 菜单栏头像，显示成 22pt
    public let icon: PetPicture
    /// 面板里的半身像，显示成 96pt
    public let portrait: PetPicture
    public let duration: TimeInterval
}

/// 宠物的形象：每款一套表情图（Resources/Pets/<rawValue>/），表情、动画都一样
public enum PetStyle: String, CaseIterable, Identifiable, Sendable {
    /// 橙色长发，右侧橙色花形发饰配黑丝带和金流苏，白色荷叶边立领配橙花胸针和黑领巾
    case classic
    /// 银白色长直发、齐刘海，白色猫耳，紫罗兰色眼睛，深紫颈圈挂小金铃铛，奶油白披肩配深紫蝴蝶结
    case neko
    /// 栗棕色高马尾系红色大蝴蝶结，翠绿色眼睛，刘海别黄蓝两枚发卡，白色水手服配蓝领和红领巾
    case youth
    /// 深紫色长直发、金色眼睛，黑紫色尖顶魔女帽（橙金帽带、帽尖垂金星），高立领披肩配橙色宝石胸针
    case witch
    // 下面三款是 Codex 的形象
    /// 白发龙娘，弯龙角、尖耳，鬓角别白色中国结，白色挂脖立领长裙配荷叶边纱袖
    case dragon
    /// 墨黑长发盘两个丸子头、系红发带，金步摇垂红珠，琥珀色眼睛，淡粉襦裙配白内领和红色交领
    case hanfu
    /// 薄荷绿长发、低马尾，黑色头戴耳机（荧光绿灯环），翠绿色眼睛，黑色连帽卫衣
    case geek
    /// 淡金色大波浪长发，墨镜推在头顶，白背心配黑色飞行员夹克
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

/// 宠物：原创角色，两家各有几款形象可选（PetStyle）。每个表情是一整张图，这里只按心情选用哪张、播多久
public enum PetSprites {
    /// 显示多大（pt）。图片是这个尺寸的 2 倍（design/painted/export_painted.py 的 ICON、PORTRAIT），自检会核对。
    /// 菜单栏最高也就 22pt 左右
    public static let iconPoints = 22.0
    public static let portraitPoints = 96.0

    /// 汗珠、眼泪在表情图里，睡着、疑惑是单独的表情；没开动画时停在第一帧，第一帧要能代表这个心情
    public static func frames(for mood: PetMood, style: PetStyle = .classic) -> [PetFrame] {
        func frame(_ face: String, _ duration: TimeInterval) -> PetFrame { self.frame(style, face, duration) }
        switch mood {
        case .energetic:  // 星星眼，偶尔笑眯眼、眨一下眼
            return [frame("sparkle-open", 1.6), frame("happy-open", 0.6), frame("sparkle-open", 1.2), frame("closed-open", 0.12)]
        case .normal:  // 安静地看着你，隔一会儿眨两下眼
            return [frame("open-small", 2.6), frame("closed-small", 0.12), frame("open-small", 0.22),
                    frame("closed-small", 0.12), frame("open-small", 2.0)]
        case .tired:  // 太阳穴冒汗、眼皮耷拉，偶尔闭一下眼（两张的汗珠是同一颗）
            return [frame("tired-wavy", 2.4), frame("closed-wavy", 0.5)]
        case .exhausted:  // > < 流眼泪
            return [frame("cry-o", 1)]
        case .sleeping:
            return [frame("sleep", 1)]
        case .revived:  // 笑眯眼为主，间或星星眼
            return [frame("happy-open", 0.9), frame("sparkle-open", 0.5), frame("happy-open", 0.7), frame("closed-open", 0.12),
                    frame("sparkle-open", 0.5)]
        case .resting:  // 闭着眼歇着，偶尔睁一下（睡着是另一张：张着嘴、脸红）
            return [frame("closed-small", 3.2), frame("open-small", 1.0), frame("closed-small", 2.6), frame("open-small", 0.3)]
        case .nervous:  // 睁大眼、抿着嘴，偶尔紧张地闭一下眼（汗珠和有点累的是同一颗）
            return [frame("nervous", 2.4), frame("closed-wavy", 0.14)]
        case .confused:
            return [frame("puzzled", 1)]
        case .loading:  // 刚醒，还迷糊着
            return [frame("drowsy", 1.2), frame("closed-small", 0.3)]
        }
    }

    /// 在面板上被戳了一下的反应：播一遍就回到这个心情原来的动画。
    /// 第一帧和平时的第一帧不一样，点了才看得出来；还没算出来（loading）时没有反应。
    /// annoyed：连着戳了很多下（见 PetTalk.poked），心情好的时候会闹别扭
    public static func reaction(for mood: PetMood, style: PetStyle = .classic, annoyed: Bool = false) -> [PetFrame] {
        func frame(_ face: String, _ duration: TimeInterval) -> PetFrame { self.frame(style, face, duration) }
        if annoyed, mood.pouts { return [frame("pout", 1.6)] }
        switch mood {
        case .energetic, .normal: return [frame("surprised", 0.5), frame("happy-open", 0.9)]  // 诶？然后笑
        case .revived: return [frame("surprised", 0.5), frame("sparkle-open", 0.9)]
        case .resting: return [frame("drowsy", 0.9), frame("open-small", 0.5)]                // 迷迷糊糊睁开眼
        case .nervous: return [frame("surprised", 0.9)]                                       // 吓一跳
        case .tired: return [frame("closed-wavy", 0.9)]                                       // 闭眼缓一缓
        case .exhausted: return [frame("tired-wavy", 0.9)]                                    // 抬眼看你一下
        case .sleeping: return [frame("drowsy", 1.4)]                                         // 被叫醒一下，接着睡
        case .confused: return [frame("open-small", 0.8)]
        case .loading: return []
        }
    }

    /// 一帧：这个表情的头像和半身像
    static func frame(_ style: PetStyle, _ face: String, _ duration: TimeInterval) -> PetFrame {
        PetFrame(icon: PetPicture(style: style, part: .icon, face: face),
                 portrait: PetPicture(style: style, part: .portrait, face: face), duration: duration)
    }
}
