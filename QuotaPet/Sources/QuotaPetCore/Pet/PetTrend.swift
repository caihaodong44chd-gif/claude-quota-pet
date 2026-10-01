import Foundation

/// 用了多少（档位）以外，宠物还看这些趋势：刚恢复、快用完了、烧得快、有一阵没用了。
/// 心情（PetMood.from(snapshot:now:recoveredAt:)）和说的话（PetTalk）都从这里取，表情和台词才对得上
struct PetTrend {
    /// 最紧张的窗口，和只看它用了多少时的心情
    let top: UsageWindow
    let level: PetMood
    /// 刚看到额度恢复，恢复的那个窗口还没怎么用，别的窗口也不紧张
    let recovered: Bool
    /// 快用完了：照最近的速度会在重置前用完、已经进了预警时间的窗口里最早的那个（和「快用完」提醒同一个标准，见 UsageWindow.warningLead）
    let soon: (window: UsageWindow, at: Date)?
    /// 烧得快：5 小时这种短窗口照最近的速度撑不到重置。每周额度这种长窗口多数时候都撑不到，不算，它看节奏
    let fast: (window: UsageWindow, at: Date)?
    /// 聊天、网页、手机正在用的窗口
    let elsewhere: UsageWindow?
    /// 多久没在本机用了，不知道时为 nil
    let quiet: TimeInterval?

    /// 看到额度恢复后这么久以内、恢复的窗口用量还在这么多以下，算「刚恢复」
    static let recoveredFor: TimeInterval = 600
    static let recoveredBelow = 20.0
    /// 多久没用算闲着
    static let idleAfter: TimeInterval = 1800

    /// 没有数据时为 nil
    init?(_ snapshot: UsageSnapshot, now: Date, recoveredAt: Date?) {
        guard snapshot.hasData, let top = snapshot.tightest else { return nil }
        self.top = top
        level = PetMood.from(percent: top.percent)
        // 别的窗口还紧张着（比如 5 小时的恢复了，每周的已经八成）就不算。只记了哪家恢复、没记是哪个窗口：
        // 恢复的窗口是从 5% 以下开始的，看用得最少的那个就行
        recovered = top.percent < 75 && snapshot.windows.contains { $0.percent < Self.recoveredBelow }
            && recoveredAt.map { (0..<Self.recoveredFor).contains(now.timeIntervalSince($0)) } ?? false
        let ending = snapshot.windows.compactMap { window in window.projectedExhaustion(now: now).map { (window: window, at: $0) } }
        soon = ending.filter { $0.at.timeIntervalSince(now) <= $0.window.warningLead }.min { $0.at < $1.at }
        fast = ending.filter { $0.window.duration <= 86400 }.min { $0.at < $1.at }
        elsewhere = snapshot.windows.first { window in
            window.duration <= 86400 && window.otherPercent >= 1 && window.otherBurnPerHour.map { window.perUnit($0) >= 1 } ?? false
        }
        quiet = snapshot.lastActiveAt.map { now.timeIntervalSince($0) }
    }

    /// 有一阵没用了，别处也没在用
    var idle: Bool { elsewhere == nil && (quiet ?? 0) >= Self.idleAfter }

    /// 心情 = 档位 + 趋势：快用完了先哭、烧得快先冒汗，不紧张又闲着就歇着。
    /// 只有档位能说「睡着了」：官方读数或限流消息才能宣布用完
    var mood: PetMood {
        if level == .sleeping { return .sleeping }
        if recovered { return .revived }
        if soon != nil || level == .exhausted { return .exhausted }
        if fast != nil || level == .tired { return .tired }
        return idle ? .resting : level
    }
}
