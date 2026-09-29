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
    /// canFollow：有桌面端可以跟（装了 Claude 桌面端，或者在用 Codex、装了 Codex 桌面端）。
    /// 没有的话「打开时」永远等不到，只用命令行的人就一直看不到宠物，所以按一直显示算；装上以后自动恢复跟着走。
    /// pinned：用户临时把它叫出来了（再次打开 QuotaPet、面板正开着、演示模式）
    public func shouldShow(appRunning: Bool, canFollow: Bool = true, pinned: Bool) -> Bool {
        self == .always || !canFollow || appRunning || pinned
    }

    /// 设置页选项下面的说明，参数同 label(codex:) 和 shouldShow
    public func note(codex: Bool, canFollow: Bool) -> String {
        switch self {
        case .always:
            return tr("一直待在菜单栏里", "Always stays in the menu bar")
        case .withClaude where !canFollow:
            return codex
                ? tr("没装 Claude 或 Codex 桌面端，所以一直显示；装好后会跟着它出现和藏起来",
                     "Neither the Claude nor the Codex desktop app is installed, so the pet always shows; once one is installed, it follows that app")
                : tr("没装 Claude 桌面端，所以一直显示；装好后会跟着它出现和藏起来",
                     "The Claude desktop app isn't installed, so the pet always shows; once it's installed, it follows the app")
        case .withClaude:
            return codex
                ? tr("Claude 和 Codex 都关掉后就藏起来，额度恢复提醒照常发", "Hides when both Claude and Codex quit; reset notifications still arrive")
                : tr("Claude 关掉后就藏起来，额度恢复提醒照常发", "Hides when Claude quits; reset notifications still arrive")
        }
    }
}
