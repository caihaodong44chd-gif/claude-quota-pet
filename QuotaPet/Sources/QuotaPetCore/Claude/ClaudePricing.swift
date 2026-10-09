import Foundation

public enum ModelFamily: String, CaseIterable, Codable, Sendable {
    case fable, opus, sonnet, haiku

    /// 和 usage_lab.py 的 family() 一样：模型名里包含哪个就算哪个。Mythos 和 Fable 同一档、同样的价格，算 Fable
    public static func of(model: String?) -> ModelFamily? {
        guard let model = model?.lowercased() else { return nil }
        if model.contains("mythos") { return .fable }
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
    /// 提示词长度：输入 + 缓存写 + 缓存读，按长短分档定价时看它
    public var prompt: Int { input + cacheWrite5m + cacheWrite1h + cacheRead }

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
public struct ModelPrice: Equatable, Sendable {
    public var input: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    public var cacheRead: Double
    public var output: Double
    /// 按提示词长短分两档的模型（Haiku 5.5）：提示词超过这么多 token 时，这个请求的各项价格都乘 longPromptMultiplier
    public var longPromptAbove: Int? = nil
    public var longPromptMultiplier: Double = 1

    /// 这个请求实际用的价格
    public func applied(to t: TokenCounts) -> ModelPrice {
        guard let above = longPromptAbove, t.prompt > above else { return self }
        let k = longPromptMultiplier
        return ModelPrice(input: input * k, cacheWrite5m: cacheWrite5m * k, cacheWrite1h: cacheWrite1h * k, cacheRead: cacheRead * k,
                          output: output * k)
    }
}

public enum ClaudePricing {
    /// 各模型族当前这一代的价格（Fable 5.1、Opus 5.5、Sonnet 5.5、Haiku 5.5），与 usage_lab.py 的 PRICES 保持一致。
    /// 来源：platform.claude.com/docs/en/about-claude/pricing（2026-10）。用 switch 写：加了新的模型族忘了写价格会编译不过
    public static func currentPrice(_ family: ModelFamily) -> ModelPrice {
        switch family {
        case .fable: return ModelPrice(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50)
        case .opus: return ModelPrice(input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20, output: 20)
        case .sonnet: return ModelPrice(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20, output: 10)
        // Haiku 5.5：提示词 10 万 token 以内 $0.10 / $0.50，超过的整个请求 $0.50 / $2.50
        case .haiku: return ModelPrice(input: 0.1, cacheWrite5m: 0.125, cacheWrite1h: 0.2, cacheRead: 0.01, output: 0.5,
                                       longPromptAbove: 100_000, longPromptMultiplier: 5)
        }
    }

    /// 缓存读在额度里大约只算 API 价格的一半。与 usage_lab.py 的 CACHE_READ_WEIGHT 保持一致。
    /// 长对话里缓存读占的成本很大，按原价算的话，换算率会随上下文变长一路漂高（产品规划第 7 节）。
    public static let cacheReadQuotaWeight = 0.5

    /// 同一族里更老、价格不一样的版本：版本号低于 below 的按 price 算，从新到旧排。与 usage_lab.py 的 OLDER_PRICES 保持一致。
    /// 模型名里读不出版本号的（或者是还没收录的新版本）按 currentPrice 算
    static let olderPrices: [ModelFamily: [(below: (Int, Int), price: ModelPrice)]] = [
        // Fable 5、Mythos 5：缓存读 $1（5.1 起是 $0.25）
        .fable: [((5, 1), ModelPrice(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50))],
        .opus: [
            ((5, 5), ModelPrice(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25)),    // Opus 4.5～5
            ((4, 5), ModelPrice(input: 15, cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.5, output: 75)),  // Opus 4、4.1
        ],
        .sonnet: [((5, 0), ModelPrice(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.3, output: 15))],  // Sonnet 4.6 及更早
        .haiku: [
            ((5, 5), ModelPrice(input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10, output: 5)),      // Haiku 4.5
            ((4, 5), ModelPrice(input: 0.8, cacheWrite5m: 1, cacheWrite1h: 1.6, cacheRead: 0.08, output: 4)),    // Haiku 3.5（Bedrock 等还能用）
        ],
    ]

    /// 某个模型的价格：先按族取当前这一代的，模型名里的版本号更老时换成那一代的
    public static func price(model: String?, family: ModelFamily) -> ModelPrice {
        var price = currentPrice(family)
        guard let version = version(of: model, family: family) else { return price }
        for older in olderPrices[family] ?? [] where version < older.below { price = older.price }
        return price
    }

    /// 模型名里的版本号，和 usage_lab.py 的 version() 一样：claude-opus-4-8 → (4, 8)、claude-opus-4-20250514 → (4, 0)、
    /// 老命名 claude-3-7-sonnet → (3, 7)。族名后面（或者前面）紧跟的一两位数字才算，日期那种长数字不算；读不出来是 nil
    static func version(of model: String?, family: ModelFamily) -> (Int, Int)? {
        guard let model = model?.lowercased() else { return nil }
        let parts = model.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
        let names: Set<String> = family == .fable ? ["fable", "mythos"] : [family.rawValue]
        guard let i = parts.firstIndex(where: names.contains) else { return nil }
        func numbers(_ tokens: [String]) -> [Int] {
            var result: [Int] = []
            for token in tokens {
                guard result.count < 2, token.count <= 2, let n = Int(token) else { break }
                result.append(n)
            }
            return result
        }
        let after = numbers(Array(parts[(i + 1)...]))
        let found = after.isEmpty ? Array(numbers(Array(parts[..<i].reversed())).reversed()) : after
        guard let major = found.first else { return nil }
        return (major, found.count > 1 ? found[1] : 0)
    }

    /// API 等价花费（美元）
    public static func cost(_ p: ModelPrice, _ t: TokenCounts) -> Double {
        let p = p.applied(to: t)
        let sum = Double(t.input) * p.input
            + Double(t.cacheWrite5m) * p.cacheWrite5m
            + Double(t.cacheWrite1h) * p.cacheWrite1h
            + Double(t.cacheRead) * p.cacheRead
            + Double(t.output) * p.output
        return sum / 1e6
    }

    /// 其中缓存读的部分（美元）
    public static func cacheReadCost(_ p: ModelPrice, _ t: TokenCounts) -> Double {
        Double(t.cacheRead) * p.applied(to: t).cacheRead / 1e6
    }

    /// 额度加权花费：API 等价花费，但缓存读打折。实时估算和学习换算率都用它
    public static func quotaCost(_ p: ModelPrice, _ t: TokenCounts) -> Double {
        quotaCost(usd: cost(p, t), cacheReadUSD: cacheReadCost(p, t))
    }

    /// 已经知道 API 等价花费和其中缓存读的部分时（比如区间记录）
    public static func quotaCost(usd: Double, cacheReadUSD: Double) -> Double {
        usd - (1 - cacheReadQuotaWeight) * cacheReadUSD
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
