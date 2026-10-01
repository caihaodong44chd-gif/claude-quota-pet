import Foundation

/// 宠物的心情：先看最紧张的那个额度窗口用了多少（档位），再看趋势（PetTrend）。某一家现在是什么心情用 PetStatus.of 算
public enum PetMood: String, CaseIterable, Sendable {
    /// 前五个是档位。revived（刚恢复）、resting（歇着）、nervous（烧得快，有点慌）只从趋势来
    case energetic, normal, tired, exhausted, sleeping, revived, resting, nervous, confused, loading

    /// 只看用了多少
    public static func from(percent: Double) -> PetMood {
        switch percent {
        case ..<50: return .energetic
        case ..<75: return .normal
        case ..<90: return .tired
        case ..<100: return .exhausted
        default: return .sleeping
        }
    }

    public var title: String {
        switch self {
        case .energetic: return tr("元气满满", "Energized")
        case .normal: return tr("状态不错", "Doing fine")
        case .tired: return tr("有点累了", "Tired")
        case .exhausted: return tr("快撑不住", "Almost out")
        case .sleeping: return tr("睡着了", "Asleep")
        case .revived: return tr("刚恢复", "Recharged")
        case .resting: return tr("歇着呢", "Resting")
        case .nervous: return tr("有点慌", "Nervous")
        case .confused: return tr("有点懵", "Confused")
        case .loading: return tr("醒过来中", "Waking up")
        }
    }

    /// 连着戳很多下会不会闹别扭：心情好的时候才会，累了、慌了、哭了、睡着了不会
    var pouts: Bool { [.energetic, .normal, .revived, .resting].contains(self) }

    /// 宠物说的话
    public var line: String {
        switch self {
        case .energetic: return tr("额度多着呢，放心用！", "Plenty of quota left, go for it!")
        case .normal: return tr("用掉一半了，稳着点～", "Half gone, pace yourself~")
        case .tired: return tr("省着点用吧，我在冒汗了…", "Easy there, I'm starting to sweat…")
        case .exhausted: return tr("马上就要见底了！！", "We're about to run dry!!")
        case .sleeping: return tr("额度用完啦，等我睡醒 zzz", "All used up, wake me when it's back zzz")
        case .revived: return tr("满血复活！", "Fully recharged!")
        case .resting: return tr("歇着呢？额度都给你留着～", "Taking a break? Your quota's safe with me~")
        case .nervous: return tr("慢点慢点，我快跟不上了", "Slow down, I can barely keep up")
        case .confused: return tr("我找不到额度数据…", "I can't find any usage data…")
        case .loading: return tr("正在看额度…", "Checking your quota…")
        }
    }
}
