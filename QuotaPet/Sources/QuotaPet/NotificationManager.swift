import AppKit
import Combine
import UserNotifications
import QuotaPetCore

/// 发系统通知：用量跨过阈值、照最近的速度快用完了、额度恢复了。
/// 发什么、怎么说由 UsageAlerts 决定；每个窗口的提醒记录存在 UserDefaults 里，重启 App 也不会重复提醒。
@MainActor
final class NotificationManager {
    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 只有打包成 .app 才能用通知（swift run 直接跑时没有 bundle，会崩）
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    /// 提醒开着时向系统要通知权限（第一次会弹窗问用户）：启动时要一次，之后在设置里重新打开提醒时再要一次。
    /// 用户可能在系统设置里改了权限，每次打开面板（面板窗口变成 key；App 被激活不一定有通知）时重新看一下，被拒绝了设置页要说一声
    func start() {
        guard center != nil else { return }
        Publishers.CombineLatest(settings.$notificationsEnabled, settings.$notifyOnReset)
            .map { $0 || $1 }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.requestAuthorization() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .sink { [weak self] _ in Task { await self?.refreshAuthorization() } }
            .store(in: &cancellables)
    }

    private func requestAuthorization() {
        guard let center else { return }
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    private func refreshAuthorization() async {
        guard let center else { return }
        let denied = await center.notificationSettings().authorizationStatus == .denied
        if settings.notificationsDenied != denied { settings.notificationsDenied = denied }
    }

    func process(old: UsageSnapshot?, new: UsageSnapshot) {
        guard new.hasData else { return }
        let now = new.generatedAt
        let options = UsageAlerts.Options(usage: settings.notificationsEnabled, thresholds: settings.thresholds,
                                          runningOut: settings.notifyRunningOut, reset: settings.notifyOnReset)
        // 设置里关掉了这家：记录照常更新（重新打开时不会一下子补发一堆），只是不发通知
        let muted = settings.hiddenProviders.contains(new.provider)
        for window in new.windows {
            let key = "notify.\(new.provider.rawValue).\(window.id)"
            let old = loadState(key)
            let (alerts, state) = UsageAlerts.evaluate(window, state: old, options: options, now: now)
            if !muted {
                for alert in alerts {
                    post(title: UsageAlerts.title(alert, window: window, provider: new.provider),
                         body: UsageAlerts.body(alert, window: window, now: now))
                }
            }
            if state != old { saveState(key, state) }  // 每分钟都会刷新，没变就不写
        }
    }

    private func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - 提醒记录

    private func loadState(_ key: String) -> UsageAlerts.State {
        UsageAlerts.State(last: defaults.double(forKey: key + ".last"),
                          notified: Set((defaults.array(forKey: key + ".notified") as? [Int]) ?? []),
                          warned: defaults.bool(forKey: key + ".warned"),
                          cycleEnd: defaults.object(forKey: key + ".cycle") as? Date)
    }

    private func saveState(_ key: String, _ state: UsageAlerts.State) {
        defaults.set(state.last, forKey: key + ".last")
        defaults.set(Array(state.notified).sorted(), forKey: key + ".notified")
        defaults.set(state.warned, forKey: key + ".warned")
        defaults.set(state.cycleEnd, forKey: key + ".cycle")
    }
}
