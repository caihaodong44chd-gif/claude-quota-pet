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
    /// Claude 的宠物形象
    @Published var petStyle: PetStyle {
        didSet { defaults.set(petStyle.rawValue, forKey: Keys.petStyle) }
    }
    /// Codex 的宠物形象（和 Claude 各选各的，见 PetStyle.codexChoices）
    @Published var codexPetStyle: PetStyle {
        didSet { defaults.set(codexPetStyle.rawValue, forKey: Keys.codexPetStyle) }
    }
    /// 本机有 Codex 的记录时，在面板、菜单栏上显示它、给它发提醒
    @Published var showCodex: Bool {
        didSet { defaults.set(showCodex, forKey: Keys.showCodex) }
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
    /// 照最近的速度快用完时提前提醒（见 UsageWindow.warningLead）
    @Published var notifyRunningOut: Bool {
        didSet { defaults.set(notifyRunningOut, forKey: Keys.notifyRunningOut) }
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
    /// 界面语言；nil = 跟随系统
    @Published var language: Language? {
        // 在 willSet 里切换：@Published 赋值时就会通知订阅者（早于 didSet），它们要读到新语言
        willSet { L10n.language = newValue ?? .preferred() }
        didSet { defaults.set(language?.rawValue, forKey: Keys.language) }
    }
    /// 开机自启设置失败时系统给的原因（界面上再套一句提示，跟着界面语言走）
    @Published private(set) var launchAtLoginError: String?

    init() {
        defaults.register(defaults: [
            Keys.animatePet: true,
            Keys.monochromePet: false,
            Keys.notificationsEnabled: true,
            Keys.thresholds: [75, 90, 100],
            Keys.notifyRunningOut: true,
            Keys.notifyOnReset: true,
            Keys.liveEstimate: true,
            Keys.autoLearn: true,
            Keys.showCodex: true,
        ])
        menuBarText = MenuBarTextMode(rawValue: defaults.string(forKey: Keys.menuBarText) ?? "") ?? .session
        visibility = MenuBarVisibility(rawValue: defaults.string(forKey: Keys.visibility) ?? "") ?? .withClaude
        // 存的形象不在这家的那一组里（比如以前的版本存的）就用那组的第一款
        petStyle = PetStyle(rawValue: defaults.string(forKey: Keys.petStyle) ?? "").flatMap { PetStyle.claudeChoices.contains($0) ? $0 : nil }
            ?? PetStyle.claudeChoices[0]
        codexPetStyle = PetStyle(rawValue: defaults.string(forKey: Keys.codexPetStyle) ?? "")
            .flatMap { PetStyle.codexChoices.contains($0) ? $0 : nil } ?? PetStyle.codexChoices[0]
        showCodex = defaults.bool(forKey: Keys.showCodex)
        animatePet = defaults.bool(forKey: Keys.animatePet)
        monochromePet = defaults.bool(forKey: Keys.monochromePet)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        thresholds = (defaults.array(forKey: Keys.thresholds) as? [Int]) ?? [75, 90, 100]
        notifyRunningOut = defaults.bool(forKey: Keys.notifyRunningOut)
        notifyOnReset = defaults.bool(forKey: Keys.notifyOnReset)
        liveEstimate = defaults.bool(forKey: Keys.liveEstimate)
        autoLearn = defaults.bool(forKey: Keys.autoLearn)
        weeklyResetAnchor = defaults.object(forKey: Keys.weeklyResetAnchor) as? Date
        language = Language(rawValue: defaults.string(forKey: Keys.language) ?? "")
        L10n.language = language ?? .preferred()  // init 里不会触发 willSet
    }

    /// 用户在设置里关掉、不在面板和菜单栏上显示的几家
    var hiddenProviders: Set<ProviderID> { Self.hiddenProviders(showCodex: showCodex) }

    nonisolated static func hiddenProviders(showCodex: Bool) -> Set<ProviderID> { showCodex ? [] : [.codex] }

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
                launchAtLoginError = error.localizedDescription
            }
        }
    }

    private enum Keys {
        static let menuBarText = "menuBarText"
        static let visibility = "visibility"
        static let petStyle = "petStyle"
        static let codexPetStyle = "codexPetStyle"
        static let showCodex = "showCodex"
        static let animatePet = "animatePet"
        static let monochromePet = "monochromePet"
        static let notificationsEnabled = "notificationsEnabled"
        static let thresholds = "thresholds"
        static let notifyRunningOut = "notifyRunningOut"
        static let notifyOnReset = "notifyOnReset"
        static let liveEstimate = "liveEstimate"
        static let autoLearn = "autoLearn"
        static let weeklyResetAnchor = "weeklyResetAnchor"
        static let language = "language"
    }
}
