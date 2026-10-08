import AppKit
import Combine
import UserNotifications
import QuotaPetCore

/// 发系统通知：用量跨过阈值、照最近的速度快用完了、额度恢复了。
/// 发什么、怎么说由 UsageAlerts 决定；每个窗口的提醒记录存在 UserDefaults 里，重启 App 也不会重复提醒。
/// 发不出去的提醒（还没问过权限、系统没收下）不记成提醒过，之后还会再发
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []
    /// 系统给的通知权限；nil = 还没查到
    private var authorization: UNAuthorizationStatus?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    /// 只有打包成 .app 才能用通知（swift run 直接跑时没有 bundle，会崩）
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    /// 提醒开着时向系统要通知权限（第一次会弹窗问用户）：启动时要一次，之后在设置里重新打开提醒时再要一次。
    /// 用户可能在系统设置里改了权限，每次打开面板（面板窗口变成 key；App 被激活不一定有通知）时重新看一下，被拒绝了设置页要说一声
    func start() {
        guard let center else { return }
        // 面板开着时 QuotaPet 是前台 App：没有这个代理的话，系统不在前台弹通知
        center.delegate = self
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
        let status = await center.notificationSettings().authorizationStatus
        authorization = status
        let denied = status == .denied
        if settings.notificationsDenied != denied { settings.notificationsDenied = denied }
    }

    /// QuotaPet 在前台（比如面板开着）时也照常弹出来
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// settingsChanged：这次变化是改设置（实时估算、自动学习、每周重置时间）引起的，不是真的用了或恢复了：
    /// 记录照常更新（按新的数字重新算起），不发提醒
    func process(old: UsageSnapshot?, new: UsageSnapshot, settingsChanged: Bool = false) {
        guard new.hasData else { return }
        let now = new.generatedAt
        let options = UsageAlerts.Options(usage: settings.notificationsEnabled, thresholds: settings.thresholds,
                                          runningOut: settings.notifyRunningOut, reset: settings.notifyOnReset)
        // 设置里关掉了这家：记录照常更新（重新打开时不会一下子补发一堆），只是不发通知
        let muted = settings.hiddenProviders.contains(new.provider) || settingsChanged
        for window in new.windows {
            let key = "notify.\(new.provider.rawValue).\(window.id)"
            let old = loadState(key)
            let (alerts, state) = UsageAlerts.evaluate(window, state: old, options: options, now: now)
            if !muted, !alerts.isEmpty {
                // 还没问过权限（第一次启动时弹窗还没点）、还没查到：发了系统也不显示，先不记，等能发了再发
                guard let center, let authorization, authorization != .notDetermined else {
                    if center == nil, state != old { saveState(key, state) }  // 没打包成 .app 时永远发不了，照常记
                    continue
                }
                if authorization != .denied {
                    let posts = alerts.map { (UsageAlerts.title($0, window: window, provider: new.provider),
                                              UsageAlerts.body($0, window: window, now: now)) }
                    post(posts, center: center) { [weak self] delivered in
                        // 系统没收下：退回原来的记录，下次刷新时再发（这期间记录又变了就算了，免得把新记录冲掉）
                        guard let self, !delivered, self.loadState(key) == state else { return }
                        self.saveState(key, old)
                    }
                }
            }
            if state != old { saveState(key, state) }  // 每分钟都会刷新，没变就不写
        }
    }

    /// 发几条通知；done(全都发出去了没有)，在主线程回调
    private func post(_ posts: [(title: String, body: String)], center: UNUserNotificationCenter,
                      done: @escaping @MainActor (Bool) -> Void) {
        let requests = posts.map { post -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = post.title
            content.body = post.body
            content.sound = .default
            return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        }
        Task { @MainActor in
            var delivered = true
            for request in requests {
                do { try await center.add(request) } catch { delivered = false }
            }
            done(delivered)
        }
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
