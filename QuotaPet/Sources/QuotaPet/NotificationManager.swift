import Foundation
import UserNotifications
import QuotaPetCore

/// 用量跨过阈值、额度恢复时发系统通知。
/// 每个窗口每个周期、每个阈值只提醒一次；状态存在 UserDefaults 里，重启 App 也不会重复提醒。
@MainActor
final class NotificationManager {
    private let settings: AppSettings
    private let defaults = UserDefaults.standard

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 只有打包成 .app 才能用通知（swift run 直接跑时没有 bundle，会崩）
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    func requestAuthorizationIfNeeded() {
        guard settings.notificationsEnabled || settings.notifyOnReset, let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(old: UsageSnapshot?, new: UsageSnapshot) {
        guard new.hasData else { return }
        let now = new.generatedAt
        for window in new.windows {
            let key = "notify.\(new.provider.rawValue).\(window.id)"
            var state = loadState(key)
            let percent = window.percent

            if percent < 5 {
                if state.last >= 60, settings.notifyOnReset {
                    let name = new.provider.displayName
                    post(title: tr("\(name) \(window.title)已恢复", "\(name) · \(window.title) has reset"),
                         body: tr("满血复活！可以继续干活了 🎉", "Fully recharged, back to work! 🎉"))
                }
                state.notified = []
            }

            if settings.notificationsEnabled {
                let crossed = settings.thresholds.filter { percent >= Double($0) && !state.notified.contains($0) }
                if let top = crossed.max() {
                    post(title: title(for: window, threshold: top, provider: new.provider),
                         body: body(for: window, threshold: top, now: now))
                    state.notified.formUnion(crossed)
                }
            }

            state.last = percent
            saveState(key, state)
        }
    }

    private func title(for window: UsageWindow, threshold: Int, provider: ProviderID) -> String {
        let name = provider.displayName
        return threshold >= 100
            ? tr("\(name) \(window.title)用完了", "\(name) · \(window.title) used up")
            : tr("\(name) \(window.title)已用 \(threshold)%", "\(name) · \(window.title) \(threshold)% used")
    }

    private func body(for window: UsageWindow, threshold: Int, now: Date) -> String {
        var parts: [String] = []
        if let reset = window.resetsAt {
            let when = Fmt.fromNow(reset.timeIntervalSince(now)), clock = Fmt.clock(reset, now: now)
            parts.append(threshold >= 100
                ? tr("\(when)恢复（\(clock)）。", "Back \(when) (\(clock)). ")
                : tr("\(when)重置（\(clock)）。", "Resets \(when) (\(clock)). "))
        }
        parts.append(threshold >= 100
            ? tr("小家伙睡着了，先去喝杯水吧 ☕️", "Your pet fell asleep. Go grab a drink ☕️")
            : PetMood.from(percent: Double(threshold)).line)
        return parts.joined()
    }

    private func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - 状态

    private struct State {
        var last: Double
        var notified: Set<Int>
    }

    private func loadState(_ key: String) -> State {
        State(last: defaults.double(forKey: key + ".last"),
              notified: Set((defaults.array(forKey: key + ".notified") as? [Int]) ?? []))
    }

    private func saveState(_ key: String, _ state: State) {
        defaults.set(state.last, forKey: key + ".last")
        defaults.set(Array(state.notified).sorted(), forKey: key + ".notified")
    }
}
