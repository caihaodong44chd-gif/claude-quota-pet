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
        // 只保留一个实例：已经有一个先启动了（比如另一个位置的副本），就请它把宠物叫出来，自己退出
        if let primary = Self.earlierInstance() {
            Self.revealAndQuit(primary)
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
            settings.setLaunchAtLogin(true, byUser: false)
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
            store.onUpdate = { [weak self] old, new, settingsChanged in
                self?.notifier.process(old: old, new: new, settingsChanged: settingsChanged)
            }
        }
        store.start()
        if firstLaunch { statusController.reveal(untilQuit: true) }
    }

    /// 比自己先启动的另一个 QuotaPet（几个都比自己早就挑最早的）；自己就是最早的时候是 nil
    private static func earlierInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = NSRunningApplication.current
        func key(_ app: NSRunningApplication) -> (launched: Date?, pid: Int32) { (app.launchDate, app.processIdentifier) }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
        guard let first = others.min(by: { FirstLaunch.launchedEarlier(key($0), than: key($1)) }),
              FirstLaunch.launchedEarlier(key(first), than: key(me)) else { return nil }
        return first
    }

    /// 重新打开正在运行的那个：它会收到 applicationShouldHandleReopen，把藏起来的宠物叫出来。之后自己退出
    private static func revealAndQuit(_ primary: NSRunningApplication) {
        guard let url = primary.bundleURL else {
            NSApp.terminate(nil)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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
