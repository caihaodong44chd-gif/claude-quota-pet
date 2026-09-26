import Combine
import Foundation
import ServiceManagement
import QuotaPetCore

/// 用户设置，存在 UserDefaults 里
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var menuBarText: MenuBarTextMode {
        didSet { defaults.set(menuBarText.rawValue, forKey: Keys.menuBarText) }
    }
    /// 什么时候出现在菜单栏：Claude 打开时 / 一直
    @Published var visibility: MenuBarVisibility {
        didSet { defaults.set(visibility.rawValue, forKey: Keys.visibility) }
    }
    @Published var animatePet: Bool {
        didSet { defaults.set(animatePet, forKey: Keys.animatePet) }
    }
    @Published var monochromePet: Bool {
        didSet { defaults.set(monochromePet, forKey: Keys.monochromePet) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    /// 用量提醒的阈值（百分比）
    @Published var thresholds: [Int] {
        didSet { defaults.set(thresholds, forKey: Keys.thresholds) }
    }
    @Published var notifyOnReset: Bool {
        didSet { defaults.set(notifyOnReset, forKey: Keys.notifyOnReset) }
    }
    /// 用本机 Claude Code 日志估算两次官方读数之间的用量
    @Published var liveEstimate: Bool {
        didSet { defaults.set(liveEstimate, forKey: Keys.liveEstimate) }
    }
    /// 从持续记录的区间里自动学习换算率
    @Published var autoLearn: Bool {
        didSet { defaults.set(autoLearn, forKey: Keys.autoLearn) }
    }
    /// 手动指定的每周重置时间；nil = 自动推算
    @Published var weeklyResetAnchor: Date? {
        didSet { defaults.set(weeklyResetAnchor, forKey: Keys.weeklyResetAnchor) }
    }
    @Published private(set) var launchAtLoginError: String?

    init() {
        defaults.register(defaults: [
            Keys.animatePet: true,
            Keys.monochromePet: false,
            Keys.notificationsEnabled: true,
            Keys.thresholds: [75, 90, 100],
            Keys.notifyOnReset: true,
            Keys.liveEstimate: true,
            Keys.autoLearn: true,
        ])
        menuBarText = MenuBarTextMode(rawValue: defaults.string(forKey: Keys.menuBarText) ?? "") ?? .session
        visibility = MenuBarVisibility(rawValue: defaults.string(forKey: Keys.visibility) ?? "") ?? .withClaude
        animatePet = defaults.bool(forKey: Keys.animatePet)
        monochromePet = defaults.bool(forKey: Keys.monochromePet)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        thresholds = (defaults.array(forKey: Keys.thresholds) as? [Int]) ?? [75, 90, 100]
        notifyOnReset = defaults.bool(forKey: Keys.notifyOnReset)
        liveEstimate = defaults.bool(forKey: Keys.liveEstimate)
        autoLearn = defaults.bool(forKey: Keys.autoLearn)
        weeklyResetAnchor = defaults.object(forKey: Keys.weeklyResetAnchor) as? Date
    }

    var providerConfig: ClaudeProvider.Config {
        Self.providerConfig(liveEstimate: liveEstimate, autoLearn: autoLearn, weeklyResetAnchor: weeklyResetAnchor)
    }

    nonisolated static func providerConfig(liveEstimate: Bool, autoLearn: Bool, weeklyResetAnchor: Date?) -> ClaudeProvider.Config {
        var config = ClaudeProvider.Config()
        config.liveEstimate = liveEstimate
        config.autoLearn = autoLearn
        config.weeklyResetAnchor = weeklyResetAnchor
        return config
    }

    /// 开机自启（SMAppService，macOS 13+）
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = "设置失败：\(error.localizedDescription)（把 App 放进「应用程序」文件夹后再试）"
            }
        }
    }

    private enum Keys {
        static let menuBarText = "menuBarText"
        static let visibility = "visibility"
        static let animatePet = "animatePet"
        static let monochromePet = "monochromePet"
        static let notificationsEnabled = "notificationsEnabled"
        static let thresholds = "thresholds"
        static let notifyOnReset = "notifyOnReset"
        static let liveEstimate = "liveEstimate"
        static let autoLearn = "autoLearn"
        static let weeklyResetAnchor = "weeklyResetAnchor"
    }
}
