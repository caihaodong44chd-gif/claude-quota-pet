import Foundation

/// 界面上的中文时间 / 数字格式
public enum Fmt {
    /// 2 小时 14 分 / 3 天 4 小时 / 8 分钟 / 不到 1 分钟
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let days = s / 86400, hours = s % 86400 / 3600, minutes = s % 3600 / 60
        if days > 0 { return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天" }
        if hours > 0 { return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时" }
        if minutes > 0 { return "\(minutes) 分钟" }
        return "不到 1 分钟"
    }

    /// 菜单栏用的紧凑写法：3d4h / 2h05m / 8m
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let days = s / 86400, hours = s % 86400 / 3600, minutes = s % 3600 / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        return "\(max(minutes, 1))m"
    }

    /// 15:05 / 明天 09:00 / 周三 17:45 / 昨天 22:10 / 10月2日 17:45
    public static func clock(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: date)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let d = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: d) { return "明天 \(time)" }
        if let d = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: d) { return "昨天 \(time)" }
        if date > now, date.timeIntervalSince(now) < 6 * 86400 {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "\(names[((c.weekday ?? 1) - 1) % 7]) \(time)"
        }
        return "\(c.month ?? 0)月\(c.day ?? 0)日 \(time)"
    }

    /// 刚刚 / 3 分钟前 / 2 小时前 / 3 天前
    public static func ago(_ date: Date, now: Date) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return "\(Int(s / 86400)) 天前"
    }

    public static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    public static func usd(_ v: Double) -> String { String(format: "$%.2f", v) }

    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }
}

/// 菜单栏上宠物旁边显示什么
public enum MenuBarTextMode: String, CaseIterable, Identifiable, Sendable {
    case petOnly, session, sessionAndWeekly, tightest

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .petOnly: return "仅宠物"
        case .session: return "5 小时"
        case .sessionAndWeekly: return "5h + 周"
        case .tightest: return "最紧张"
        }
    }
}

public enum MenuBarText {
    /// 返回要显示的文字，以及文字对应的最高使用率（用来决定要不要标橙 / 标红）。
    /// 被限流时不显示百分比，改成显示多久后恢复。
    public static func make(_ snap: UsageSnapshot?, mode: MenuBarTextMode, now: Date) -> (text: String, level: Double) {
        guard let snap, snap.hasData else { return ("", 0) }
        let limited = snap.windows.filter { $0.percent >= 100 }
        if !limited.isEmpty {
            // 多个窗口都满了，要等最晚恢复的那个
            let resets = limited.compactMap(\.resetsAt)
            if resets.count == limited.count, let latest = resets.max() {
                return (Fmt.compactDuration(latest.timeIntervalSince(now)), 100)
            }
            return ("100%", 100)
        }
        let shown: [UsageWindow]
        switch mode {
        case .petOnly: return ("", 0)
        case .session: shown = [snap.window("five_hour")].compactMap { $0 }
        case .sessionAndWeekly: shown = [snap.window("five_hour"), snap.window("seven_day")].compactMap { $0 }
        case .tightest: shown = [snap.tightest].compactMap { $0 }
        }
        let text = shown.map { Fmt.percent($0.clampedPercent) }.joined(separator: " · ")
        return (text, shown.map(\.percent).max() ?? 0)
    }
}
