import Foundation

/// 从区间记录里学「多少美元的额度加权花费 ≈ 1% 额度」。
///
/// 换算率 = Σ 权重 × 本机额度加权花费 ÷ Σ 权重 × 官方增量：
/// - 只用本机确实在用（≥ $0.02）、中间没有重置的区间；纯网页端的区间没有本机花费，自动排除。
///   同时在其他端用过、官方涨得明显比本机多的区间，以及旧版本记下的、没有缓存读花费的区间也不用。
/// - 越近的区间权重越大（半衰期 3 小时）：同一个会话里换算率也会慢慢变，要跟得上。
///   回测（usage_lab.py backtest）：半衰期 3 小时比 2 天的误差小，往回跳的次数也少。
///   时间从最近一个区间往前算，隔几天不用也不会把学到的忘掉。
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
                             priorUSD: Double = 2, halfLife: TimeInterval = 3 * 3600) -> Result {
        let usable = intervals.compactMap { interval -> (end: Date, usd: Double, delta: Double)? in
            guard interval.usd >= 0.02, let usd = interval.quotaUSD, let d = delta(interval) else { return nil }
            return (interval.end, usd, d)
        }
        guard let latest = usable.map(\.end).max() else {
            return Result(usdPerPercent: prior, intervals: 0, latest: nil)
        }
        func fit(_ items: [(end: Date, usd: Double, delta: Double)]) -> Double {
            var cost = priorUSD
            var gained = priorUSD / prior
            for item in items {
                let weight = pow(0.5, latest.timeIntervalSince(item.end) / halfLife)
                cost += weight * item.usd
                gained += weight * item.delta
            }
            return gained > 0 ? cost / gained : prior
        }
        // 同时在网页 / 手机上用过的区间，官方涨得比本机花费能解释的多一截（见 OtherUsage），不能拿来学：
        // 先粗算一次，去掉这种区间再算
        let rough = fit(usable)
        let clean = usable.filter { $0.delta - $0.usd / rough <= OtherUsage.threshold(local: $0.usd / rough) }
        let rate = clean.isEmpty ? rough : fit(clean)
        return Result(usdPerPercent: min(max(rate, prior / 10), prior * 10), intervals: clean.count, latest: latest)
    }
}
