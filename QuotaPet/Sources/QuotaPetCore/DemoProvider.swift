import Foundation

/// 演示模式：75 秒一轮，额度从 0 涨到 100%，再睡 15 秒，看看宠物的所有状态。
public final class DemoProvider: UsageProvider, Sendable {
    public let id = ProviderID.claude
    public let pollInterval: TimeInterval = 1
    public var watchPaths: [String] { [] }
    private let started = Date()

    public init() {}

    public func isRelevantChange(path: String) -> Bool { false }

    public func snapshot(now: Date) throws -> UsageSnapshot {
        let t = now.timeIntervalSince(started).truncatingRemainder(dividingBy: 75)
        let session = min(100, t / 60 * 100)
        let weekly = 20 + session * 0.15
        let sessionReset = now.addingTimeInterval(session >= 100 ? 75 - t : 2 * 3600 + 23 * 60)
        let windows = [
            UsageWindow(id: "five_hour", title: UsageWindow.sessionTitle, duration: 5 * 3600, percent: session,
                        official: (session / 5).rounded(.down) * 5, officialAt: now.addingTimeInterval(-240),
                        startedAt: sessionReset.addingTimeInterval(-5 * 3600), resetsAt: sessionReset, burnPerHour: 38),
            UsageWindow(id: "seven_day", title: UsageWindow.weeklyTitle, duration: 7 * 86400, percent: weekly,
                        official: weekly.rounded(.down), officialAt: now.addingTimeInterval(-240),
                        startedAt: now.addingTimeInterval(-3 * 86400), resetsAt: now.addingTimeInterval(4 * 86400 + 5 * 3600),
                        burnPerHour: 4),
        ]
        let today = ActivitySummary(
            requests: 128, tokens: 12_345_678, usd: 18.42,
            byFamily: [FamilyUsage(family: "Opus", requests: 90, usd: 15.1), FamilyUsage(family: "Sonnet", requests: 38, usd: 3.32)],
            lastRequestAt: now)
        return UsageSnapshot(provider: .claude, windows: windows, generatedAt: now, officialAt: now.addingTimeInterval(-240),
                             today: today, notes: [tr("演示模式：数据是假的，75 秒看完宠物的所有状态。",
                                                      "Demo mode: the data is fake. Watch every pet mood in 75 seconds.")])
    }
}

/// 演示模式里的 Codex：本周额度停在 58%。Claude 那边涨过它之前，宠物跟着 Codex（龙娘）
public final class DemoCodexProvider: UsageProvider, Sendable {
    public let id = ProviderID.codex
    public let pollInterval: TimeInterval = 1
    public var watchPaths: [String] { [] }

    public init() {}

    public func isRelevantChange(path: String) -> Bool { false }

    public func snapshot(now: Date) throws -> UsageSnapshot {
        let week = UsageWindow(id: "seven_day", title: UsageWindow.weeklyTitle, duration: 7 * 86400, percent: 58, official: 58,
                               officialAt: now.addingTimeInterval(-600), startedAt: now.addingTimeInterval(-4 * 86400),
                               resetsAt: now.addingTimeInterval(3 * 86400 + 2 * 3600), burnPerHour: 0.8, burnLookback: 86400)
        return UsageSnapshot(provider: .codex, windows: [week], generatedAt: now, officialAt: week.officialAt)
    }
}
