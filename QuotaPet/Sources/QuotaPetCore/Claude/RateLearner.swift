import Foundation

/// 从区间记录里学「多少美元的 API 用量 ≈ 1% 额度」。
///
/// 换算率 = Σ 权重 × 本机花费 ÷ Σ 权重 × 官方增量：
/// - 只用本机确实在用（≥ $0.02）、中间没有重置的区间；纯网页端的区间没有本机花费，自动排除。
/// - 越近的区间权重越大（半衰期 2 天）。时间从最近一个区间往前算，隔几天不用也不会把学到的忘掉。
/// - 加一点默认值当先验（相当于 $2 的数据），刚开始记录少时不会乱跳。
/// 官方读数是整数，单个区间误差大，但求和时误差会互相抵消。
public enum RateLearner {
    public struct Result: Equatable, Sendable {
        public var usdPerPercent: Double
        /// 用到了多少个区间；0 表示还在用默认值
        public var intervals: Int
        /// 最近一个用到的区间的结束时间
        public var latest: Date?
    }

    public static func learn(_ intervals: [UsageInterval], delta: (UsageInterval) -> Double?, prior: Double,
                             priorUSD: Double = 2, halfLife: TimeInterval = 2 * 86400) -> Result {
        let usable = intervals.compactMap { interval -> (end: Date, usd: Double, delta: Double)? in
            guard interval.usd >= 0.02, let d = delta(interval) else { return nil }
            return (interval.end, interval.usd, d)
        }
        guard let latest = usable.map(\.end).max() else {
            return Result(usdPerPercent: prior, intervals: 0, latest: nil)
        }
        var cost = priorUSD
        var gained = priorUSD / prior
        for item in usable {
            let weight = pow(0.5, latest.timeIntervalSince(item.end) / halfLife)
            cost += weight * item.usd
            gained += weight * item.delta
        }
        let rate = gained > 0 ? cost / gained : prior
        return Result(usdPerPercent: min(max(rate, prior / 10), prior * 10), intervals: usable.count, latest: latest)
    }
}
