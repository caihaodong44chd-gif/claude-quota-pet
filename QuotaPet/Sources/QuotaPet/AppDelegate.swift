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
        self.watchBundleID = watchBundleID ?? AppWatcher.claudeBundleID
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

        // 第一次启动（还没存过任何设置）：下载版不走 make install，Claude 桌面端又没开的话宠物是藏着的，
        // 双击后什么都看不到，所以先叫出来；放进了「应用程序」文件夹的也顺便打开开机自启
        let firstLaunch = !demo && Self.isFirstLaunch
        if !demo { UserDefaults.standard.set(true, forKey: Self.launchedKey) }

        settings = AppSettings()
        // make install 时传进来：开机自动启动，才能在 Claude 打开时自动出现
        if enableLoginItem || (firstLaunch && Bundle.main.bundlePath.contains("/Applications/")) {
            settings.launchAtLogin = true
        }
        store = UsageStore(providers: demo ? [DemoProvider(), DemoCodexProvider()] : [ClaudeProvider(), CodexProvider()],
                           settings: settings)
        animator = PetAnimator(settings: settings, style: settings.petStyle)
        notifier = NotificationManager(settings: settings)
        statusController = StatusItemController(store: store, settings: settings, animator: animator,
                                                headerAnimator: PetAnimator(settings: settings, style: settings.petStyle, isVisible: false),
                                                appWatcher: AppWatcher(claudeBundleID: watchBundleID),
                                                keepVisible: demo)

        if !demo {  // 演示模式的数据一直在变，不发通知
            notifier.start()
            store.onUpdate = { [weak self] old, new in self?.notifier.process(old: old, new: new) }
        }
        store.start()
        if firstLaunch { statusController.reveal() }
    }

    private static let launchedKey = "launchedBefore"

    /// 按设置是不是空的判断，不只看 launchedKey：老版本升级上来的用户没有这个键，但存过别的设置
    private static var isFirstLaunch: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return UserDefaults.standard.persistentDomain(forName: id)?.isEmpty ?? true
    }

    /// App 已经在后台运行时又被打开（Spotlight、启动台、双击）：把藏起来的宠物叫出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.reveal()
        return false
    }
}
