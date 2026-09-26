import Foundation

/// 菜单栏上的宠物什么时候出现
public enum MenuBarVisibility: String, CaseIterable, Identifiable, Sendable {
    /// Claude 桌面端打开时出现，关掉后藏起来（官方读数也是桌面端记录的，关掉后就不更新了）
    case withClaude
    case always

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .withClaude: return tr("Claude 打开时", "When Claude is open")
        case .always: return tr("一直显示", "Always")
        }
    }

    /// pinned：用户临时把它叫出来了（再次打开 QuotaPet、面板正开着、演示模式）
    public func shouldShow(claudeRunning: Bool, pinned: Bool) -> Bool {
        self == .always || claudeRunning || pinned
    }
}
