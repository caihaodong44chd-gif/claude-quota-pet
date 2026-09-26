import Foundation

/// 宠物的心情，由最紧张的那个额度窗口决定
public enum PetMood: String, CaseIterable, Sendable {
    case energetic, normal, tired, exhausted, sleeping, confused, loading

    public static func from(percent: Double) -> PetMood {
        switch percent {
        case ..<50: return .energetic
        case ..<75: return .normal
        case ..<90: return .tired
        case ..<100: return .exhausted
        default: return .sleeping
        }
    }

    public static func from(snapshot: UsageSnapshot?) -> PetMood {
        guard let snapshot else { return .loading }
        guard snapshot.hasData, let top = snapshot.tightest else { return .confused }
        return from(percent: top.percent)
    }

    public var title: String {
        switch self {
        case .energetic: return "元气满满"
        case .normal: return "状态不错"
        case .tired: return "有点累了"
        case .exhausted: return "快撑不住"
        case .sleeping: return "睡着了"
        case .confused: return "有点懵"
        case .loading: return "醒过来中"
        }
    }

    /// 宠物说的话
    public var line: String {
        switch self {
        case .energetic: return "额度多着呢，放心用！"
        case .normal: return "用掉一半了，稳着点～"
        case .tired: return "省着点用吧，我在冒汗了…"
        case .exhausted: return "马上就要见底了！！"
        case .sleeping: return "额度用完啦，等我睡醒 zzz"
        case .confused: return "我找不到额度数据…"
        case .loading: return "正在看额度…"
        }
    }
}
