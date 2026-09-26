import Foundation

/// Claude 额度：官方读数（桌面端）+ 本机 Claude Code 日志实时估算。不联网、不读凭据。
public final class ClaudeProvider: UsageProvider, @unchecked Sendable {
    public struct Config: Equatable, Sendable {
        /// 用本机日志估算两次官方读数之间的用量
        public var liveEstimate = true
        /// 从持续记录的区间里自动学习换算率；关掉就一直用起始值
        public var autoLearn = true
        /// 用户手动指定的某一次每周重置时间（之后每 7 天一次）；nil 表示自动推算
        public var weeklyResetAnchor: Date?

        public init() {}
    }

    public static let sessionDuration: TimeInterval = 5 * 3600
    public static let weekDuration: TimeInterval = 7 * 86400

    public let id = ProviderID.claude
    public let pollInterval: TimeInterval = 60
    public let historyURL: URL
    public let scanner: ClaudeTranscriptScanner
    /// 区间记录；nil 表示不落盘（自检用）
    public let archive: IntervalArchive?

    /// 最近一次 snapshot 用到的数据，--dump 调试用
    public private(set) var lastRequests: [ClaudeRequest] = []
    public private(set) var lastSamples: [PlanUsageSample] = []

    private let lock = NSLock()
    private var storedConfig = Config()
    private var historyCache: (mtime: Date, samples: [PlanUsageSample])?

    public init(historyURL: URL = ClaudeDesktopHistory.defaultURL, projectsURL: URL = ClaudeTranscriptScanner.defaultRoot,
                archiveURL: URL? = IntervalArchive.defaultURL) {
        self.historyURL = historyURL
        self.scanner = ClaudeTranscriptScanner(root: projectsURL)
        self.archive = archiveURL.map { IntervalArchive(url: $0) }
    }

    /// 可以从任意线程设置
    public var config: Config {
        get { lock.lock(); defer { lock.unlock() }; return storedConfig }
        set { lock.lock(); storedConfig = newValue; lock.unlock() }
    }

    public var watchPaths: [String] {
        // 监听 ~/.claude 而不是 projects：用户第一次用 Claude Code 之前 projects 目录还不存在
        [historyURL.deletingLastPathComponent().path, scanner.root.deletingLastPathComponent().path]
    }

    public func isRelevantChange(path: String) -> Bool {
        path.hasSuffix(".jsonl") || path.hasSuffix(historyURL.lastPathComponent)
    }

    // MARK: - Snapshot

    public func snapshot(now: Date) throws -> UsageSnapshot {
        let cfg = config
        let requests = scanner.refresh(now: now)
        var notes: [String] = []

        let samples: [PlanUsageSample]
        switch loadHistory() {
        case .ok(let s):
            samples = s
            if s.isEmpty { notes.append("Claude 桌面端还没记录到额度，暂时只能用本机日志估算。") }
        case .missing:
            samples = []
            notes.append("没找到 Claude 桌面端的额度记录。装好并登录 Claude 桌面端后，它每 15 分钟会记一次官方额度。")
        case .unreadable(let reason):
            samples = []
            notes.append("Claude 桌面端的额度记录读不了：\(reason)")
        }
        lastRequests = requests
        lastSamples = samples

        // 每来一次官方读数就多一个完整区间：存进记录，再从全部记录里学换算率
        var recorded = UsageInterval.extract(samples: samples, requests: requests, now: now)
        if let archive {
            archive.merge(recorded)
            recorded = archive.intervals
        }
        let starting = ClaudeRates.starting
        let sessionFit = RateLearner.learn(recorded, delta: \.sessionDelta, prior: starting.usdPerSessionPercent)
        let weeklyFit = RateLearner.learn(recorded, delta: \.weeklyDelta, prior: starting.usdPerWeeklyPercent)
        let sessionRate = cfg.autoLearn ? sessionFit.usdPerPercent : starting.usdPerSessionPercent
        let weeklyRate = cfg.autoLearn ? weeklyFit.usdPerPercent : starting.usdPerWeeklyPercent
        let estimation = EstimationInfo(
            sessionUSDPerPercent: sessionRate, weeklyUSDPerPercent: weeklyRate,
            learnedIntervals: cfg.autoLearn ? sessionFit.intervals : 0, recordedIntervals: recorded.count,
            learnedUntil: cfg.autoLearn ? sessionFit.latest : nil)

        let sessionSeries = samples.compactMap { s in s.session.map { UsageSample(time: s.time, value: $0) } }
        let weeklySeries = samples.compactMap { s in s.weekly.map { UsageSample(time: s.time, value: $0) } }
        let session = buildWindow(
            id: "five_hour", title: "5 小时会话", shortTitle: "5h", duration: Self.sessionDuration,
            series: sessionSeries, requests: requests, scale: 1, percentOf: { $0.usd / sessionRate },
            resetAnchor: nil, live: cfg.liveEstimate, now: now)
        let weekly = buildWindow(
            id: "seven_day", title: "本周额度", shortTitle: "周", duration: Self.weekDuration,
            series: weeklySeries, requests: requests, scale: 1, percentOf: { $0.usd / weeklyRate },
            resetAnchor: cfg.weeklyResetAnchor, live: cfg.liveEstimate, now: now)

        let officialAt = samples.last?.time
        if let t = officialAt, now.timeIntervalSince(t) > 45 * 60 {
            notes.append("官方读数停在\(Fmt.ago(t, now: now))（Claude 桌面端没开？），之后的变化是本机估算。")
        }

        return UsageSnapshot(
            provider: .claude, windows: [session, weekly], generatedAt: now, officialAt: officialAt,
            today: todaySummary(requests, now: now), notes: notes,
            hasData: !samples.isEmpty || !requests.isEmpty, estimation: estimation)
    }

    /// 官方读数 + 读数之后的本机用量 = 当前百分比。本机用量 = Σ percentOf(请求) × scale
    func buildWindow(id: String, title: String, shortTitle: String, duration: TimeInterval,
                     series: [UsageSample], requests: [ClaudeRequest], scale: Double,
                     percentOf: (ClaudeRequest) -> Double, resetAnchor: Date?, live: Bool, now: Date) -> UsageWindow {
        var current: InferredWindow?
        var lastReset: Date?
        if let anchor = resetAnchor {
            let periods = (now.timeIntervalSince(anchor) / duration).rounded(.down) + 1
            let end = anchor.addingTimeInterval(periods * duration)
            current = InferredWindow(start: end.addingTimeInterval(-duration), end: end)
            lastReset = current?.start
        } else {
            let inferred = WindowInference.infer(samples: series, activity: requests.map(\.time), duration: duration, now: now)
            current = inferred.current
            lastReset = inferred.lastReset
        }

        func added(after from: Date, including: Bool = false) -> Double {
            guard live else { return 0 }
            var sum = 0.0
            for r in requests where (r.time > from || (including && r.time == from)) && r.time <= now {
                sum += percentOf(r)
            }
            return sum * scale
        }

        var percent = 0.0
        var official: Double?
        var officialAt: Date?
        if let last = series.last, lastReset.map({ $0 <= last.time }) ?? true {
            // 最近的官方读数还属于当前窗口
            official = last.value
            officialAt = last.time
            percent = last.value + added(after: last.time)
        } else if let window = current {
            // 读数之后窗口已经重置过了，只能从窗口开始累计本机用量
            percent = added(after: window.start, including: true)
        }
        // 只有官方读数能宣布「用完了」：估算最多到 99%，免得宠物误睡、误发限流提醒
        if (official ?? 0) < 100 { percent = min(percent, 99) }

        // 5 小时窗口看最近 30 分钟的速度；每周窗口看最近 24 小时，不然一会儿猛用就会误报「几小时后用完」
        let lookback: TimeInterval = duration > 86400 ? 86400 : 1800
        var burn: Double?
        if live {
            let from = max(now.addingTimeInterval(-lookback), current?.start ?? .distantPast)
            burn = added(after: from) * 3600 / max(now.timeIntervalSince(from), lookback / 3)
        }

        return UsageWindow(id: id, title: title, shortTitle: shortTitle, duration: duration, percent: percent,
                           official: official, officialAt: officialAt, startedAt: current?.start,
                           resetsAt: current?.end, burnPerHour: burn, burnLookback: lookback)
    }

    func todaySummary(_ requests: [ClaudeRequest], now: Date) -> ActivitySummary {
        let dayStart = Calendar.current.startOfDay(for: now)
        var summary = ActivitySummary(lastRequestAt: requests.last?.time)
        var byFamily: [ModelFamily: FamilyUsage] = [:]
        for r in requests where r.time >= dayStart && r.time <= now {
            let usd = r.usd
            summary.requests += 1
            summary.tokens += r.tokens.total
            summary.usd += usd
            byFamily[r.family, default: FamilyUsage(family: r.family.displayName, requests: 0, usd: 0)].requests += 1
            byFamily[r.family]?.usd += usd
        }
        summary.byFamily = byFamily.values.sorted { $0.usd > $1.usd }
        return summary
    }

    // MARK: - 桌面端读数

    enum HistoryState {
        case ok([PlanUsageSample])
        case missing
        case unreadable(String)
    }

    private func loadHistory() -> HistoryState {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: historyURL.path) else { return .missing }
        let mtime = attrs[.modificationDate] as? Date ?? .distantPast
        if let cache = historyCache, cache.mtime == mtime { return .ok(cache.samples) }
        do {
            let samples = try ClaudeDesktopHistory.parse(Data(contentsOf: historyURL))
            historyCache = (mtime, samples)
            return .ok(samples)
        } catch {
            // 桌面端正在写文件时可能读到半截，先用上一次的结果
            if let cache = historyCache { return .ok(cache.samples) }
            return .unreadable(error.localizedDescription)
        }
    }
}
