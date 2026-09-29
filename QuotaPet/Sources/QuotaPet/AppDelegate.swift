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
        // 双击后什么都看不到，所以先叫出来，一直显示到退出
        let defaults = UserDefaults.standard
        let firstLaunch = !demo && Self.isFirstLaunch
        if !demo { defaults.set(true, forKey: FirstLaunch.launchedKey) }
        if firstLaunch { defaults.set(true, forKey: FirstLaunch.loginItemPendingKey) }

        settings = AppSettings()
        // 开机自动启动，才能在 Claude 打开时自动出现：make install 时传进来；
        // 下载版等到在「应用程序」文件夹里打开时再开（用户自己在设置里开关过就不管了，见 AppSettings.launchAtLogin）
        if enableLoginItem
            || (defaults.bool(forKey: FirstLaunch.loginItemPendingKey) && FirstLaunch.isInApplicationsFolder(Bundle.main.bundlePath)) {
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
        if firstLaunch { statusController.reveal(untilQuit: true) }
    }

    private static var isFirstLaunch: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return FirstLaunch.isFirst(storedKeys: Array((UserDefaults.standard.persistentDomain(forName: id) ?? [:]).keys))
    }

    /// App 已经在后台运行时又被打开（Spotlight、启动台、双击）：把藏起来的宠物叫出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.reveal()
        return false
    }
}
