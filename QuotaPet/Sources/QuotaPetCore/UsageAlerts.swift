import Foundation

/// 用量提醒：跨过阈值、照最近的速度快用完了、额度恢复了。每个窗口每个周期，每个阈值和「快用完」各只提醒一次。
/// 进了新的周期（用量掉到 5% 以下，或者重置时间往后跳了半个窗口以上）就重新开始算。
/// 这里只决定发什么、怎么说，发通知和存提醒记录在 App 里（NotificationManager）
public enum UsageAlerts {
    /// 设置里打开了哪些提醒
    public struct Options: Equatable, Sendable {
        /// 用量提醒（总开关）：跨过阈值时提醒
        public var usage: Bool
        public var thresholds: [Int]
        /// 照最近的速度快用完时提前提醒（见 UsageWindow.warningLead），用量提醒关掉时也不发
        public var runningOut: Bool
        /// 额度恢复时提醒
        public var reset: Bool

        public init(usage: Bool, thresholds: [Int], runningOut: Bool, reset: Bool) {
            self.usage = usage
            self.thresholds = thresholds
            self.runningOut = runningOut
            self.reset = reset
        }
    }

    /// 一个窗口的提醒记录（App 存在 UserDefaults 里，重启也不会重复提醒）
    public struct State: Equatable, Sendable {
        /// 上次看到的百分比
        public var last: Double
        /// 这个周期里提醒过的阈值
        public var notified: Set<Int>
        /// 这个周期里已经说过「照这个速度快用完了」：单独提醒过，或者阈值提醒里顺带说了
        public var warned: Bool
        /// 上次看到的重置时间：往后跳了半个窗口以上，说明进了新的周期
        public var cycleEnd: Date?

        public init(last: Double = 0, notified: Set<Int> = [], warned: Bool = false, cycleEnd: Date? = nil) {
            self.last = last
            self.notified = notified
            self.warned = warned
            self.cycleEnd = cycleEnd
        }
    }

    public enum Alert: Equatable, Sendable {
        /// 额度恢复了
        case reset
        /// 跨过了阈值；runsOutAt：照最近的速度会在重置前用完的话，是几点，顺带说一句
        case threshold(Int, runsOutAt: Date?)
        /// 照最近的速度，很快就会在重置前用完
        case runningOut(Date)
    }

    /// 这个窗口的新数据要发哪些提醒，以及更新后的记录
    public static func evaluate(_ window: UsageWindow, state: State, options: Options, now: Date) -> (alerts: [Alert], state: State) {
        var state = state
        var alerts: [Alert] = []
        let percent = window.percent
        // App 没开着时跨过了重置、重新打开时新周期已经用了一些，用量不会掉到 5% 以下，只能看重置时间往后跳了没有。
        // 推算的重置时间会前后挪一点，跳半个窗口以上才算
        var nextCycle = false
        if let old = state.cycleEnd, let end = window.resetsAt { nextCycle = end.timeIntervalSince(old) > window.duration / 2 }
        if percent < 5 || nextCycle {
            if recovered(from: state.last, to: percent), options.reset { alerts.append(.reset) }
            state.notified = []
            state.warned = false
        }
        if let end = window.resetsAt { state.cycleEnd = end }
        let runsOut = window.projectedExhaustion(now: now)
        let soon = runsOut.map { $0.timeIntervalSince(now) <= window.warningLead } ?? false
        if options.usage {
            let crossed = options.thresholds.filter { percent >= Double($0) && !state.notified.contains($0) }
            if let top = crossed.max() {
                alerts.append(.threshold(top, runsOutAt: runsOut))
                state.notified.formUnion(crossed)
                if soon { state.warned = true }  // 这条里已经说了几点用完，不用再单独提醒一次
            }
        }
        if soon, !state.warned, options.usage, options.runningOut, let runsOut {
            alerts.append(.runningOut(runsOut))
            state.warned = true
        }
        state.last = percent
        return (alerts, state)
    }

    /// 额度恢复了：上次看到用了六成以上，现在掉到了 5% 以下（没怎么用就重置的不值得说）
    public static func recovered(from last: Double, to percent: Double) -> Bool { percent < 5 && last >= 60 }

    public static func title(_ alert: Alert, window: UsageWindow, provider: ProviderID) -> String {
        let name = provider.displayName
        switch alert {
        case .reset:
            return tr("\(name) \(window.title)已恢复", "\(name) · \(window.title) has reset")
        case .threshold(let threshold, _):
            return threshold >= 100
                ? tr("\(name) \(window.title)用完了", "\(name) · \(window.title) used up")
                : tr("\(name) \(window.title)已用 \(threshold)%", "\(name) · \(window.title) \(threshold)% used")
        case .runningOut:
            return tr("\(name) \(window.title)快用完了", "\(name) · \(window.title) is running out")
        }
    }

    public static func body(_ alert: Alert, window: UsageWindow, now: Date) -> String {
        switch alert {
        case .reset:
            return tr("满血复活！可以继续干活了 🎉", "Fully recharged, back to work! 🎉")
        case .threshold(let threshold, let runsOut):
            var parts: [String] = []
            if let reset = window.resetsAt {
                let when = Fmt.fromNow(reset.timeIntervalSince(now)), clock = Fmt.clock(reset, now: now)
                parts.append(threshold >= 100
                    ? tr("\(when)恢复（\(clock)）。", "Back \(when) (\(clock)). ")
                    : tr("\(when)重置（\(clock)）。", "Resets \(when) (\(clock)). "))
            }
            if let runsOut {
                let clock = Fmt.clock(runsOut, now: now)
                parts.append(tr("照最近的速度 \(clock) 左右就会用完。", "At the recent pace it runs out around \(clock). "))
            }
            parts.append(threshold >= 100
                ? tr("小家伙睡着了，先去喝杯水吧 ☕️", "Your pet fell asleep. Go grab a drink ☕️")
                : PetMood.from(percent: Double(threshold)).line)
            return parts.joined()
        case .runningOut(let runsOut):
            let clock = Fmt.clock(runsOut, now: now), when = Fmt.fromNow(runsOut.timeIntervalSince(now))
            guard let reset = window.resetsAt else {
                return tr("照最近的速度，\(clock) 左右用完（\(when)）。", "At the recent pace it runs out around \(clock) (\(when)).")
            }
            let early = Fmt.duration(reset.timeIntervalSince(runsOut))
            return tr("照最近的速度，\(clock) 左右用完（\(when)），比重置早 \(early)。",
                      "At the recent pace it runs out around \(clock) (\(when)), \(early) before the reset.")
        }
    }
}
