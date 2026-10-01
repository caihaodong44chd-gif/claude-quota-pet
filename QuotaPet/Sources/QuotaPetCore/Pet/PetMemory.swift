import Foundation

/// 宠物记得的事（每家一份）：光看一张快照看不出来、心情和台词又要用的。拿到新快照时更新（updated），只记在内存里
public struct PetMemory: Equatable, Sendable {
    /// 最近一次看到额度恢复：什么时候、哪个窗口
    public struct Recovery: Equatable, Sendable {
        public var at: Date
        public var window: String

        public init(at: Date, window: String) {
            self.at = at
            self.window = window
        }
    }

    /// 最近一次看到的趋势警报（快用完了 / 烧得快）：什么时候看到的、当时那个窗口、预计几点用完
    struct Alarm: Equatable, Sendable {
        var seenAt: Date
        var window: UsageWindow
        var runsOutAt: Date
    }

    public var recovery: Recovery?
    var soon: Alarm?
    var fast: Alarm?

    public init(recovery: Recovery? = nil) {
        self.recovery = recovery
    }

    /// 警报消失后再留这么久。消耗速度一直在变，预计用完的时间正好在门槛附近时警报一会儿有一会儿没有，
    /// 不留一段时间，心情就会跟着来回跳。要比兜底刷新的间隔（一分钟）长
    static let hold: TimeInterval = 180

    /// 拿到这家的新快照后记成什么样。now 是快照的时间
    public func updated(from old: UsageSnapshot?, to new: UsageSnapshot, now: Date) -> PetMemory {
        var next = self
        // 和「额度恢复」提醒同一个标准：从六成以上掉到了 5% 以下
        if let old, let window = new.windows.first(where: { window in
            old.window(window.id).map { UsageAlerts.recovered(from: $0.percent, to: window.percent) } ?? false
        }) {
            next.recovery = Recovery(at: now, window: window.id)
        }
        let seen = PetTrend.alarms(new, now: now)
        next.soon = seen.soon.map { Alarm(seenAt: now, window: $0.window, runsOutAt: $0.at) } ?? kept(soon, in: new, now: now)
        next.fast = seen.fast.map { Alarm(seenAt: now, window: $0.window, runsOutAt: $0.at) } ?? kept(fast, in: new, now: now)
        return next
    }

    /// 这次没再看到的警报还留不留：没过期，那个窗口也没重置（用量没往回掉）、没用完
    private func kept(_ alarm: Alarm?, in snapshot: UsageSnapshot, now: Date) -> Alarm? {
        guard let alarm, held(alarm, now: now) != nil, let window = snapshot.window(alarm.window.id),
              window.percent >= alarm.window.percent - 1, window.percent < 100 else { return nil }
        return alarm
    }

    /// 这个警报现在还算数的话就是它：看到后还没过 hold，当时预计的用完时间也还没到
    func held(_ alarm: Alarm?, now: Date) -> Alarm? {
        alarm.flatMap { now.timeIntervalSince($0.seenAt) < Self.hold && $0.runsOutAt > now ? $0 : nil }
    }
}
