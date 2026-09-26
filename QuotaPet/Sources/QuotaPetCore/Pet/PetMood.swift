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
        case .energetic: return tr("元气满满", "Energized")
        case .normal: return tr("状态不错", "Doing fine")
        case .tired: return tr("有点累了", "Tired")
        case .exhausted: return tr("快撑不住", "Almost out")
        case .sleeping: return tr("睡着了", "Asleep")
        case .confused: return tr("有点懵", "Confused")
        case .loading: return tr("醒过来中", "Waking up")
        }
    }

    /// 宠物说的话
    public var line: String {
        switch self {
        case .energetic: return tr("额度多着呢，放心用！", "Plenty of quota left, go for it!")
        case .normal: return tr("用掉一半了，稳着点～", "Half gone, pace yourself~")
        case .tired: return tr("省着点用吧，我在冒汗了…", "Easy there, I'm starting to sweat…")
        case .exhausted: return tr("马上就要见底了！！", "We're about to run dry!!")
        case .sleeping: return tr("额度用完啦，等我睡醒 zzz", "All used up, wake me when it's back zzz")
        case .confused: return tr("我找不到额度数据…", "I can't find any usage data…")
        case .loading: return tr("正在看额度…", "Checking your quota…")
        }
    }
}
