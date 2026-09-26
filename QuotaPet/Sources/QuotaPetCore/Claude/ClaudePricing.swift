import Foundation

public enum ModelFamily: String, CaseIterable, Codable, Sendable {
    case fable, opus, sonnet, haiku

    /// 和 usage_lab.py 的 family() 一样：模型名里包含哪个就算哪个
    public static func of(model: String?) -> ModelFamily? {
        guard let model = model?.lowercased() else { return nil }
        return allCases.first { model.contains($0.rawValue) }
    }

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0
    public var output = 0

    public init(input: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.output = output
    }

    public var total: Int { input + cacheWrite5m + cacheWrite1h + cacheRead + output }

    /// 同一个响应在流式写入时会出现多行，各字段取最大值
    public mutating func formMax(_ other: TokenCounts) {
        input = max(input, other.input)
        cacheWrite5m = max(cacheWrite5m, other.cacheWrite5m)
        cacheWrite1h = max(cacheWrite1h, other.cacheWrite1h)
        cacheRead = max(cacheRead, other.cacheRead)
        output = max(output, other.output)
    }
}

/// 美元 / 百万 tokens
public struct ModelPrice: Sendable {
    public var input: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    public var cacheRead: Double
    public var output: Double
}

public enum ClaudePricing {
    /// 与 usage_lab.py 的 PRICES 保持一致。
    /// 来源：platform.claude.com/docs/en/about-claude/pricing（2026-09）
    public static let prices: [ModelFamily: ModelPrice] = [
        .fable: ModelPrice(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50),
        .opus: ModelPrice(input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20, output: 20),
        .sonnet: ModelPrice(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20, output: 10),
        .haiku: ModelPrice(input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10, output: 5),
    ]

    /// 缓存读在额度里大约只算 API 价格的一半。与 usage_lab.py 的 CACHE_READ_WEIGHT 保持一致。
    /// 长对话里缓存读占的成本很大，按原价算的话，换算率会随上下文变长一路漂高（产品规划第 7 节）。
    public static let cacheReadQuotaWeight = 0.5

    /// API 等价花费（美元）
    public static func cost(_ family: ModelFamily, _ t: TokenCounts) -> Double {
        guard let p = prices[family] else { return 0 }
        let sum = Double(t.input) * p.input
            + Double(t.cacheWrite5m) * p.cacheWrite5m
            + Double(t.cacheWrite1h) * p.cacheWrite1h
            + Double(t.cacheRead) * p.cacheRead
            + Double(t.output) * p.output
        return sum / 1e6
    }

    /// 其中缓存读的部分（美元）
    public static func cacheReadCost(_ family: ModelFamily, _ t: TokenCounts) -> Double {
        Double(t.cacheRead) * (prices[family]?.cacheRead ?? 0) / 1e6
    }

    /// 额度加权花费：API 等价花费，但缓存读打折。实时估算和学习换算率都用它
    public static func quotaCost(_ family: ModelFamily, _ t: TokenCounts) -> Double {
        cost(family, t) - (1 - cacheReadQuotaWeight) * cacheReadCost(family, t)
    }
}

/// 额度加权花费（见 ClaudePricing.quotaCost）↔ 额度百分比的换算率。所有模型用同一个数：实测额度大致和 API 价格成正比。
///
/// 2026-09-25～26 的回归（18 个 15 分钟区间，留一法比较）：一个统一系数比按模型分、按思考程度分、思考 token 单独算都准；
/// 纯 Opus xhigh 和纯 Opus max 都是 $0.349 / 1%，说明思考程度的影响已经体现在思考 token 里（按输出计费）。
/// 唯一要单独算的是缓存读（打折，见 cacheReadQuotaWeight），起始值也是按加权花费算的。
/// 之后 App 会从持续记录的区间里自动学习（RateLearner），这两个数只在记录不够时用。
public struct ClaudeRates: Codable, Equatable, Sendable {
    /// 每 1% 的 5 小时额度 ≈ 多少美元额度加权花费
    public var usdPerSessionPercent: Double
    /// 每 1% 的每周额度 ≈ 多少美元额度加权花费
    public var usdPerWeeklyPercent: Double

    public init(usdPerSessionPercent: Double, usdPerWeeklyPercent: Double) {
        self.usdPerSessionPercent = usdPerSessionPercent
        self.usdPerWeeklyPercent = usdPerWeeklyPercent
    }

    /// 5 小时 $0.27 / 1%，每周 $2.0 / 1%
    public static let starting = ClaudeRates(usdPerSessionPercent: 0.27, usdPerWeeklyPercent: 2.0)
}
