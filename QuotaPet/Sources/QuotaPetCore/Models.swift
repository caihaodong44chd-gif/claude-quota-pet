import Foundation

/// 额度来源。以后接 ChatGPT/Codex、Cursor、Gemini…就在这里加 case，再实现一个 UsageProvider。
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        }
    }
}

/// 一个额度窗口，比如 Claude 的「5 小时会话」和「本周额度」。
public struct UsageWindow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var duration: TimeInterval
    /// 当前百分比 = 最近一次官方读数 + 之后本机用量的实时估算（可能超过 100）
    public var percent: Double
    /// 最近一次官方读数（整数）和读数时间；读数属于已经重置掉的旧窗口时为 nil
    public var official: Double?
    public var officialAt: Date?
    /// official 是 Claude Code 限流消息报告的「用完了」，不是桌面端的读数
    public var limitReported: Bool
    /// 当前窗口的开始 / 重置时间（推算值）；窗口还没开始时为 nil
    public var startedAt: Date?
    public var resetsAt: Date?
    /// 这个窗口里网页、手机、桌面端聊天等其他端用了多少（已经包含在官方读数里，见 OtherUsage）
    public var otherPercent: Double
    /// 最近一段时间（burnLookback）的消耗速度，百分点 / 小时：本机 Claude Code + 官方读数里看出来的其他端
    public var burnPerHour: Double?
    /// burnPerHour 里其他端的部分
    public var otherBurnPerHour: Double?
    /// 消耗速度按多长时间算：5 小时窗口看最近 30 分钟，每周窗口看最近 24 小时
    public var burnLookback: TimeInterval

    public init(id: String, title: String, duration: TimeInterval, percent: Double,
                official: Double? = nil, officialAt: Date? = nil, limitReported: Bool = false, startedAt: Date? = nil,
                resetsAt: Date? = nil, otherPercent: Double = 0, burnPerHour: Double? = nil, otherBurnPerHour: Double? = nil,
                burnLookback: TimeInterval = 1800) {
        self.id = id
        self.title = title
        self.duration = duration
        self.percent = percent
        self.official = official
        self.officialAt = officialAt
        self.limitReported = limitReported
        self.startedAt = startedAt
        self.resetsAt = resetsAt
        self.otherPercent = otherPercent
        self.burnPerHour = burnPerHour
        self.otherBurnPerHour = otherBurnPerHour
        self.burnLookback = burnLookback
    }

    /// 显示用，限制在 0...100
    public var clampedPercent: Double { min(max(percent, 0), 100) }

    /// 实时估算比官方读数多出来的部分（没有官方读数时，整个百分比都是估算）
    public var estimatedExtra: Double { official.map { max(0, percent - $0) } ?? percent }

    /// 照最近的消耗速度，会在重置之前的什么时候用完；来得及重置就返回 nil
    public func projectedExhaustion(now: Date) -> Date? {
        guard let burn = burnPerHour, burn >= 1, percent < 100 else { return nil }
        let t = now.addingTimeInterval((100 - percent) / burn * 3600)
        if let reset = resetsAt, t >= reset { return nil }
        return t
    }
}

public struct FamilyUsage: Equatable, Sendable {
    public var family: String
    public var requests: Int
    public var usd: Double

    public init(family: String, requests: Int, usd: Double) {
        self.family = family
        self.requests = requests
        self.usd = usd
    }
}

/// 本机 Claude Code 今天的用量（按 API 价格折算）
public struct ActivitySummary: Equatable, Sendable {
    public var requests: Int
    public var tokens: Int
    public var usd: Double
    public var byFamily: [FamilyUsage]
    public var lastRequestAt: Date?

    public init(requests: Int = 0, tokens: Int = 0, usd: Double = 0, byFamily: [FamilyUsage] = [], lastRequestAt: Date? = nil) {
        self.requests = requests
        self.tokens = tokens
        self.usd = usd
        self.byFamily = byFamily
        self.lastRequestAt = lastRequestAt
    }
}

/// 实时估算用的换算率：多少美元 API 用量 ≈ 1% 额度
public struct EstimationInfo: Equatable, Sendable {
    public var sessionUSDPerPercent: Double
    public var weeklyUSDPerPercent: Double
    /// 学习用到的区间数；0 表示记录还不够，在用起始值
    public var learnedIntervals: Int
    /// 一共记录了多少个区间
    public var recordedIntervals: Int
    /// 学到的数据截至什么时候
    public var learnedUntil: Date?

    public init(sessionUSDPerPercent: Double, weeklyUSDPerPercent: Double, learnedIntervals: Int,
                recordedIntervals: Int, learnedUntil: Date?) {
        self.sessionUSDPerPercent = sessionUSDPerPercent
        self.weeklyUSDPerPercent = weeklyUSDPerPercent
        self.learnedIntervals = learnedIntervals
        self.recordedIntervals = recordedIntervals
        self.learnedUntil = learnedUntil
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public var provider: ProviderID
    public var windows: [UsageWindow]
    public var generatedAt: Date
    /// 最近一次官方读数的时间
    public var officialAt: Date?
    public var today: ActivitySummary?
    /// 给用户看的数据说明 / 警告
    public var notes: [String]
    /// 一点数据都没有时为 false（宠物会显示疑惑）
    public var hasData: Bool
    /// 实时估算的换算率（演示模式等没有时为 nil）
    public var estimation: EstimationInfo?

    public init(provider: ProviderID, windows: [UsageWindow], generatedAt: Date, officialAt: Date? = nil,
                today: ActivitySummary? = nil, notes: [String] = [], hasData: Bool = true, estimation: EstimationInfo? = nil) {
        self.provider = provider
        self.windows = windows
        self.generatedAt = generatedAt
        self.officialAt = officialAt
        self.today = today
        self.notes = notes
        self.hasData = hasData
        self.estimation = estimation
    }

    public func window(_ id: String) -> UsageWindow? { windows.first { $0.id == id } }

    /// 最紧张的窗口，宠物的心情跟它走
    public var tightest: UsageWindow? { windows.max { $0.percent < $1.percent } }
}

/// 一个 AI 的额度数据源。
/// snapshot 只会在同一个后台串行队列上调用，实现里可以放心保存增量读取的状态
/// （所以有可变状态的实现可以标 @unchecked Sendable）。
public protocol UsageProvider: AnyObject, Sendable {
    var id: ProviderID { get }
    /// 要监听的目录（FSEvents），里面相关的文件一变就刷新
    var watchPaths: [String] { get }
    /// 没有文件事件时的兜底刷新间隔
    var pollInterval: TimeInterval { get }
    func isRelevantChange(path: String) -> Bool
    func snapshot(now: Date) throws -> UsageSnapshot
}
