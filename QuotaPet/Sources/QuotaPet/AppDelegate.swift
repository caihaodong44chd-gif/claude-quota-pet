import AppKit
import QuotaPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private let watchBundleID: String
    private let enableLoginItem: Bool
    private var settings: AppSettings!
    private var store: UsageStore!
    private var animator: PetAnimator!
    private var notifier: NotificationManager!
    private var statusController: StatusItemController!

    init(demo: Bool, watchBundleID: String?, enableLoginItem: Bool) {
        self.demo = demo
        self.watchBundleID = watchBundleID ?? ClaudeAppWatcher.claudeBundleID
        self.enableLoginItem = enableLoginItem
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 只保留一个实例（重复打开时直接退出）
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        settings = AppSettings()
        if enableLoginItem {  // make install 时传进来：开机自动启动，才能在 Claude 打开时自动出现
            settings.launchAtLogin = true
        }
        store = UsageStore(provider: demo ? DemoProvider() : ClaudeProvider(), settings: settings)
        animator = PetAnimator(settings: settings)
        notifier = NotificationManager(settings: settings)
        statusController = StatusItemController(store: store, settings: settings, animator: animator,
                                                claudeWatcher: ClaudeAppWatcher(bundleID: watchBundleID),
                                                keepVisible: demo)

        if !demo {  // 演示模式的数据一直在变，不发通知
            notifier.requestAuthorizationIfNeeded()
            store.onUpdate = { [weak self] old, new in self?.notifier.process(old: old, new: new) }
        }
        store.start()
    }

    /// App 已经在后台运行时又被打开（Spotlight、启动台、双击）：把藏起来的宠物叫出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.reveal()
        return false
    }
}
