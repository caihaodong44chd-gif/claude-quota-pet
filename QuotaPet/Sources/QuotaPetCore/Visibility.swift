import Foundation

/// 菜单栏上的宠物什么时候出现
public enum MenuBarVisibility: String, CaseIterable, Identifiable, Sendable {
    /// Claude 桌面端打开时出现，关掉后藏起来（官方读数也是桌面端记录的，关掉后就不更新了）。
    /// 在用 Codex 时，Codex 桌面端打开也算
    case withClaude
    case always

    public var id: String { rawValue }

    public var label: String { label(codex: false) }

    /// codex：在用 Codex（有它的额度数据），「打开时」也看 Codex 桌面端
    public func label(codex: Bool) -> String {
        switch self {
        case .withClaude: return codex ? tr("Claude/Codex 打开时", "When Claude/Codex is open") : tr("Claude 打开时", "When Claude is open")
        case .always: return tr("一直显示", "Always")
        }
    }

    /// appRunning：Claude（在用 Codex 时还有 Codex）桌面端开着；
    /// pinned：用户临时把它叫出来了（再次打开 QuotaPet、面板正开着、演示模式）
    public func shouldShow(appRunning: Bool, pinned: Bool) -> Bool {
        self == .always || appRunning || pinned
    }
}
