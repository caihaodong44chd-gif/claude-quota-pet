// 自检：swift run QuotaPetChecks
// 命令行工具（CLT）里没有 XCTest / swift-testing，所以用一个小可执行文件代替。
import Foundation
@testable import QuotaPetCore

var passed = 0
var failed = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("✗ 第 \(line) 行：\(message)")
    }
}

func near(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

/// 2026 年 9 月某天的本地时间
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

let hour: TimeInterval = 3600
let fiveHours = 5 * hour
let week = 7 * 86400.0
typealias S = UsageSample

// MARK: - 格式化

check(Fmt.duration(2 * hour + 14 * 60) == "2 小时 14 分", "duration")
check(Fmt.duration(30) == "不到 1 分钟", "duration < 1 分钟")
check(Fmt.duration(3 * 86400 + 4 * hour) == "3 天 4 小时", "duration 天")
check(Fmt.compactDuration(hour + 5 * 60) == "1h05m", "compactDuration")
check(Fmt.compactDuration(20) == "1m", "compactDuration 不到 1 分钟")
check(Fmt.clock(at(25, 15, 5), now: at(25, 12)) == "15:05", "clock 当天")
check(Fmt.clock(at(26, 9), now: at(25, 12)) == "明天 09:00", "clock 明天")
check(Fmt.clock(at(30, 17, 45), now: at(25, 12)) == "周三 17:45", "clock 一周内")
check(Fmt.ago(at(25, 11, 45), now: at(25, 12)) == "15 分钟前", "ago")

// MARK: - 宠物

let palette = Set(PetArt.palette.keys.compactMap(\.asciiValue))
for (name, art, size) in [("头像", PetArt.icon, PetSprites.iconSize), ("半身像", PetArt.portrait, PetSprites.portraitSize)] {
    check(art.base.count == size && art.base.allSatisfy { $0.utf8.count == size }, "\(name)底图 \(size)×\(size)")
    for (kind, patches) in [("眼睛", art.eyes), ("嘴", art.mouths), ("小道具", art.extras)] {
        for (key, patch) in patches {
            let width = patch.rows.first?.utf8.count ?? 0
            check(patch.x >= 0 && patch.y >= 0 && patch.x + width <= size && patch.y + patch.rows.count <= size
                  && patch.rows.allSatisfy { $0.utf8.count == width }, "\(name)的\(kind)「\(key)」要在画布里、每行一样宽")
        }
    }
}
for mood in PetMood.allCases {
    let frames = PetSprites.frames(for: mood)
    check(!frames.isEmpty, "\(mood) 要有动画帧")
    for frame in frames {
        check(frame.duration > 0, "\(mood) 帧时长 > 0")
        check(frame.icon.width == 32 && frame.icon.height == 32 && frame.portrait.width == 64 && frame.portrait.height == 64,
              "\(mood) 头像 32×32、半身像 64×64")
        check((frame.icon.cells + frame.portrait.cells).allSatisfy { $0 == 0 || palette.contains($0) }, "\(mood) 只能用调色板里的颜色")
    }
}
check(PetSprites.frames(for: .energetic)[0] != PetSprites.frames(for: .normal)[0], "不同心情的表情不一样")
check(PetSprites.frames(for: .normal)[0].icon != PixelGrid(rows: PetArt.icon.base), "画上了眼睛")
check(PetMood.from(percent: 10) == .energetic, "< 50% 元气满满")
check(PetMood.from(percent: 50) == .normal, "50% 状态不错")
check(PetMood.from(percent: 80) == .tired, "80% 累了")
check(PetMood.from(percent: 95) == .exhausted, "95% 快撑不住")
check(PetMood.from(percent: 100) == .sleeping, "100% 睡觉")
check(PetMood.from(snapshot: nil) == .loading, "还没数据时在加载")
check(PetMood.from(snapshot: UsageSnapshot(provider: .claude, windows: [], generatedAt: Date(), hasData: false)) == .confused, "没数据时疑惑")

// MARK: - 桌面端读数

let historyJSON = """
{"version": 2, "samples": [
  {"t": 1790325603721, "org": "old", "u": {"fh": 50, "sd": 10}},
  {"t": 1790326504168, "org": "A", "u": {}},
  {"t": 1790327403783, "org": "A", "u": {"fh": 24, "sd": 24}},
  {"t": 1790326000000, "org": "A", "u": {"fh": 23, "sd": 24}}
]}
"""
let parsed = try! ClaudeDesktopHistory.parse(Data(historyJSON.utf8))
check(parsed.count == 2, "跳过空读数和旧组织：\(parsed.count)")
check(parsed.first?.session == 23 && parsed.last?.session == 24, "按时间排序")
check(parsed.last?.weekly == 24, "sd 是每周额度")
check((try? ClaudeDesktopHistory.parse(Data("[]".utf8))) == nil, "格式不对要报错")

// MARK: - Claude Code 日志（规则和 usage_lab.py 一致）

func logLine(_ id: String, _ ts: String, _ model: String, input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite1h: Int = 0) -> String {
    #"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite1h),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":\#(cacheWrite1h)}}}}"#
}

/// Claude Code 被限流时写的 synthetic 消息，resetsAt = 2026-09-25T06:00:00Z
func limitLine(_ id: String, _ ts: String) -> String {
    #"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"\#(id)","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0},"content":[{"type":"text","text":"You've hit your session limit"}]},"quotaLimits":{"status":"rejected","resetsAt":1790316000,"rateLimitType":"five_hour"},"error":"rate_limit","isApiErrorMessage":true}"#
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("quotapet-check-\(UUID().uuidString)")
let project = tmp.appendingPathComponent("-Users-me-demo")
try! FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
let file = project.appendingPathComponent("session.jsonl")
let sonnetLine = logLine("m4", "2026-09-25T02:04:00.000Z", "claude-sonnet-5", output: 10_000)
let content = [
    logLine("m1", "2026-09-25T02:00:00.000Z", "claude-opus-5-5", input: 10, output: 100),
    logLine("m1", "2026-09-25T02:00:05.000Z", "claude-opus-5-5", input: 10, output: 1000, cacheRead: 5000, cacheWrite1h: 2000),
    #"{"type":"user","timestamp":"2026-09-25T02:01:00.000Z","message":{"role":"user","content":"how is my \"usage\""}}"#,
    logLine("m2", "2026-09-25T02:02:00.000Z", "<synthetic>", input: 1, output: 1),
    logLine("m3", "2026-09-25T02:03:00.000Z", "claude-haiku-4-5", input: 1000, output: 2000),
    limitLine("m5", "2026-09-25T02:05:00.000Z"),
    limitLine("m6", "2026-09-25T02:06:00.000Z"),  // 限流中又重试了一次
    #"{"type":"user","timestamp":"2026-09-25T02:07:00.000Z","message":{"role":"user","content":"\"quotaLimits\":{\"status\":\"rejected\"}"}}"#,
    String(sonnetLine.prefix(40)),  // Claude Code 还没写完的半行
].joined(separator: "\n")
try! content.write(to: file, atomically: true, encoding: .utf8)

let scanner = ClaudeTranscriptScanner(root: tmp, retention: 365 * 86400)
var requests = scanner.refresh(now: at(25, 23))
check(requests.count == 2, "按 message.id 去重，跳过 synthetic 和半行：\(requests.count)")
let m1 = requests.first { $0.id == "m1" }
check(m1?.tokens == TokenCounts(input: 10, cacheWrite1h: 2000, cacheRead: 5000, output: 1000), "同一响应各字段取最大值")
// opus：10×4 + 2000×8 + 5000×0.2 + 1000×20 = 37040 / 1e6
check(near(m1?.usd, 0.03704), "opus 成本：\(m1?.usd ?? -1)")
check(near(m1?.cacheReadUSD, 0.001) && near(m1?.quotaUSD, 0.03654), "额度加权花费：缓存读 $0.001 按半价算：\(m1?.quotaUSD ?? -1)")
check(scanner.limitEvents == [ClaudeLimitEvent(time: ClaudeTranscriptScanner.parseDate("2026-09-25T02:05:00.000Z")!, window: "five_hour",
                                               resetsAt: Date(timeIntervalSince1970: 1790316000))],
      "限流消息：重试的去重、留最早那条，用户消息里的同名文字不算：\(scanner.limitEvents)")

let handle = try! FileHandle(forWritingTo: file)
handle.seekToEndOfFile()
handle.write(Data((String(sonnetLine.dropFirst(40)) + "\n").utf8))
try! handle.close()
requests = scanner.refresh(now: at(25, 23))
check(requests.count == 3 && requests.last?.family == .sonnet, "增量读取：半行写完后被读到")
check(near(requests.last?.usd, 0.10), "sonnet 1 万输出 tokens = $0.10")
try? FileManager.default.removeItem(at: tmp)

check(ClaudeRates.starting.usdPerSessionPercent == 0.27 && ClaudeRates.starting.usdPerWeeklyPercent == 2.0,
      "起始换算率：5 小时 $0.27 / 1%，每周 $2.0 / 1%")
/// 下面的估算测试用 $0.117 / 1%，数字好算
let testRate = 0.117

// MARK: - 窗口推算

do {  // 自然到期
    let r1 = WindowInference.infer(samples: [], activity: [at(25, 10), at(25, 10, 30), at(25, 11)], duration: fiveHours, now: at(25, 14))
    check(r1.current == InferredWindow(start: at(25, 10), end: at(25, 15)), "第一次使用开启 5 小时窗口")
    let r2 = WindowInference.infer(samples: [], activity: [at(25, 10)], duration: fiveHours, now: at(25, 15, 30))
    check(r2.current == nil && r2.lastReset == at(25, 15), "5 小时后自然结束")
    let r3 = WindowInference.infer(samples: [], activity: [at(25, 10), at(25, 15, 10)], duration: fiveHours, now: at(25, 16))
    check(r3.current?.start == at(25, 15, 10), "结束后的第一次使用开启新窗口")
}

do {  // 88% → 0%：以读数跳变为准（真实数据 09-25 下午的形状）
    let samples = [S(time: at(25, 10, 16), value: 0), S(time: at(25, 10, 21), value: 6), S(time: at(25, 14, 55), value: 88),
                   S(time: at(25, 15, 10), value: 0), S(time: at(25, 15, 25), value: 6)]
    let activity = [at(25, 10, 19), at(25, 12), at(25, 14, 50), at(25, 15, 12), at(25, 15, 20)]
    let r = WindowInference.infer(samples: samples, activity: activity, duration: fiveHours, now: at(25, 15, 30))
    check(r.current?.start == at(25, 15, 12), "重置后的第一个请求开启新窗口：\(String(describing: r.current))")
    check(r.lastReset.map { $0 > at(25, 14, 55) && $0 <= at(25, 15, 10) } == true, "重置发生在两次读数之间")
}

do {  // 15% → 3%：重置后马上又用了（网页端，没有本机请求）
    let samples = [S(time: at(23, 17, 52), value: 0), S(time: at(23, 18, 10), value: 6), S(time: at(23, 22, 40), value: 15),
                   S(time: at(23, 22, 55), value: 3), S(time: at(23, 23, 10), value: 1)]
    let r = WindowInference.infer(samples: samples, activity: [], duration: fiveHours, now: at(23, 23, 30))
    let start = r.current?.start
    check(start.map { $0 > at(23, 22, 40) && $0 <= at(23, 22, 55) } == true, "新窗口开始于跳变区间：\(String(describing: start))")
    check(!WindowInference.isReset(from: 3, to: 1), "3 → 1 是噪声，不算重置")
    check(WindowInference.isReset(from: 88, to: 0) && WindowInference.isReset(from: 15, to: 3), "明显下跌是重置")
}

do {  // 每周：桌面端最早的读数是 0，说明更早的窗口都结束了
    let samples = [S(time: at(23, 17, 52), value: 0), S(time: at(23, 18, 10), value: 0), S(time: at(23, 19, 40), value: 1)]
    let activity = [at(17, 10), at(20, 9), at(23, 17, 58), at(24, 12)]
    let r = WindowInference.infer(samples: samples, activity: activity, duration: week, now: at(25, 23))
    check(r.current?.start == at(23, 17, 58), "每周窗口从读数为 0 之后的第一次使用开始：\(String(describing: r.current))")
}

do {  // 限流消息给出精确的重置时间：14:00（按第一次使用推的话是 14:15）
    let activity = [at(20, 9, 15), at(20, 11), at(20, 14, 5)]
    let r = WindowInference.infer(samples: [], activity: activity, duration: fiveHours, now: at(20, 14, 10), knownResets: [at(20, 14)])
    check(r.lastReset == at(20, 14) && r.current?.start == at(20, 14, 5), "14:00 重置后，14:05 的使用开启新窗口：\(r)")
    let guess = WindowInference.infer(samples: [], activity: activity, duration: fiveHours, now: at(20, 14, 10))
    check(guess.current?.start == at(20, 9, 15), "没有限流消息时，14:05 还算在旧窗口里")
    // 桌面端读数 100 → 0 只能说明重置在两次读数之间（取中点 13:10），有精确时间就用精确的
    let samples = [S(time: at(20, 12), value: 100), S(time: at(20, 14, 20), value: 0)]
    let r2 = WindowInference.infer(samples: samples, activity: [at(20, 9, 15)], duration: fiveHours, now: at(20, 14, 30),
                                   knownResets: [at(20, 14)])
    check(r2.lastReset == at(20, 14) && r2.current == nil, "读数跳变区间里的精确重置时间：\(r2)")
    // 桌面端关了 12 小时（80 → 3），中间撞了两次限流：14:00 和 19:05 各重置一次（窗口都是从网页上先开始的，比本机第一次请求早）
    let gap = [S(time: at(20, 10), value: 80), S(time: at(20, 22), value: 3)]
    let r3 = WindowInference.infer(samples: gap, activity: [at(20, 9, 30), at(20, 14, 20), at(20, 19, 10)], duration: fiveHours,
                                   now: at(20, 22, 10), knownResets: [at(20, 14), at(20, 19, 5)])
    check(r3.lastReset == at(20, 19, 5) && r3.current?.start == at(20, 19, 10), "一段空档里的两次精确重置都用上：\(r3)")
}

// MARK: - 官方读数 + 实时估算

do {
    let provider = ClaudeProvider(historyURL: URL(fileURLWithPath: "/nonexistent/h.json"),
                                  projectsURL: URL(fileURLWithPath: "/nonexistent/projects"), archiveURL: nil)
    func opus(_ t: Date, usd: Double) -> ClaudeRequest {
        ClaudeRequest(id: UUID().uuidString, time: t, family: .opus, tokens: TokenCounts(output: Int((usd / 20 * 1e6).rounded())))
    }
    let series = [S(time: at(25, 22, 54), value: 0), S(time: at(25, 23, 25), value: 20)]
    let reqs = [opus(at(25, 23, 0), usd: 0.117 * 5), opus(at(25, 23, 30), usd: 0.117 * 3)]
    let percentOf: (ClaudeRequest) -> Double = { $0.usd / testRate }
    let live = provider.buildWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, series: series,
                                    requests: reqs, scale: 1, percentOf: percentOf, resetAnchor: nil, live: true, now: at(25, 23, 40))
    check(near(live.official, 20) && near(live.percent, 23, 1e-3), "官方 20% + 之后本机 3%：\(live.percent)")
    check(live.startedAt == at(25, 23, 0) && live.resetsAt == at(26, 4, 0), "窗口从 23:00 的请求开始")
    let off = provider.buildWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, series: series,
                                   requests: reqs, scale: 1, percentOf: percentOf, resetAnchor: nil, live: false, now: at(25, 23, 40))
    check(near(off.percent, 20), "关掉实时估算时只显示官方读数")

    let heavy = [opus(at(25, 23, 30), usd: 0.117 * 90)]  // 20% + 90% 会冲过 100%
    let capped = provider.buildWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, series: series,
                                      requests: heavy, scale: 1, percentOf: percentOf, resetAnchor: nil, live: true, now: at(25, 23, 40))
    check(near(capped.percent, 99), "估算不能宣布用完：官方没到 100% 时最多 99%：\(capped.percent)")

    // 撞线：14:30 官方 85%，14:45 Claude Code 报告限流，18:00 恢复
    let before = [S(time: at(20, 14, 30), value: 85)]
    let work = [opus(at(20, 14, 35), usd: 0.117 * 5)]
    let hit = ClaudeLimitEvent(time: at(20, 14, 45), window: "five_hour", resetsAt: at(20, 18))
    func limited(_ series: [S], _ reqs: [ClaudeRequest], _ limits: [ClaudeLimitEvent], now: Date) -> UsageWindow {
        provider.buildWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, series: series, requests: reqs,
                             scale: 1, percentOf: percentOf, resetAnchor: nil, limits: limits, live: true, now: now)
    }
    let asleep = limited(before, work, [hit], now: at(20, 14, 50))
    check(near(asleep.percent, 100) && asleep.official == 100 && asleep.officialAt == at(20, 14, 45) && asleep.limitReported,
          "限流消息能宣布用完：\(asleep.percent)")
    check(asleep.startedAt == at(20, 13) && asleep.resetsAt == at(20, 18), "窗口按限流消息里的恢复时间算")
    check(near(limited(before, work, [], now: at(20, 14, 50)).percent, 90, 1e-3), "没有限流消息时还是 85% + 本机 5%")
    let bought = limited(before + [S(time: at(20, 14, 55), value: 60)], work, [hit], now: at(20, 15))
    check(near(bought.percent, 60), "限流之后官方读数明显不到 100（别的账号 / 额度变了）就以官方为准：\(bought.percent)")
    let stale = limited(before + [S(time: at(20, 14, 48), value: 97)], work, [hit], now: at(20, 14, 50))
    check(near(stale.percent, 100) && stale.limitReported, "限流之后的读数只差一点（取整、读得早）还是算用完")
    let confirmed = limited(before + [S(time: at(20, 14, 46), value: 100)], work, [hit], now: at(20, 14, 50))
    check(near(confirmed.percent, 100) && confirmed.officialAt == at(20, 14, 46) && !confirmed.limitReported, "桌面端也读到 100 时用桌面端的读数")
    let other = limited([S(time: at(20, 14, 30), value: 20)], work, [hit], now: at(20, 14, 50))
    check(near(other.percent, 25, 1e-3) && other.resetsAt == at(20, 19, 35), "官方 20% + 本机 5% 离 100 太远：多半是别的账号撞线，不用：\(other.percent)")
    let closed = limited([], work, [hit], now: at(20, 14, 50))
    check(near(closed.percent, 100) && closed.resetsAt == at(20, 18), "这个窗口里没有官方读数时没法核对，相信限流消息")
    let later = limited(before, work + [opus(at(20, 18, 2), usd: 0.117 * 2)], [hit], now: at(20, 18, 10))
    check(later.official == nil && near(later.percent, 2, 1e-3) && later.startedAt == at(20, 18, 2), "恢复之后从新窗口重新算：\(later)")
    let bogus = ClaudeLimitEvent(time: at(20, 14, 45), window: "five_hour", resetsAt: at(20, 20))
    check(near(limited(before, work, [bogus], now: at(20, 14, 50)).percent, 90, 1e-3), "恢复时间比限流晚 5 小时以上的不可信，不用")

    let manual = provider.buildWindow(id: "seven_day", title: "", shortTitle: "", duration: week, series: [], requests: [],
                                      scale: 0.124, percentOf: percentOf, resetAnchor: at(16, 18), live: true, now: at(25, 23))
    check(manual.startedAt == at(23, 18) && manual.resetsAt == at(30, 18), "手动指定的每周重置时间每 7 天循环")
}

do {  // 整条链路：日志里的限流消息经过 snapshot() 分到各自的窗口
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotapet-limits-\(UUID().uuidString)")
    let projects = dir.appendingPathComponent("projects/-Users-me-demo")
    try! FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let iso = ISO8601DateFormatter()
    let history = #"{"version":2,"samples":[{"t":\#(Int(at(20, 14, 30).timeIntervalSince1970 * 1000)),"org":"A","u":{"fh":85,"sd":90}}]}"#
    try! history.write(to: dir.appendingPathComponent("history.json"), atomically: true, encoding: .utf8)
    func limit(_ t: Date, _ type: String, resets: Date) -> String {
        #"{"type":"assistant","timestamp":"\#(iso.string(from: t))","message":{"id":"\#(type)","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}},"quotaLimits":{"status":"rejected","resetsAt":\#(Int(resets.timeIntervalSince1970)),"rateLimitType":"\#(type)"}}"#
    }
    let log = [logLine("w1", iso.string(from: at(20, 14, 35)), "claude-opus-5-5", output: 10_000),
               limit(at(20, 14, 45), "five_hour", resets: at(20, 18)), limit(at(20, 14, 46), "seven_day", resets: at(24, 9))]
    try! (log.joined(separator: "\n") + "\n").write(to: projects.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
    let provider = ClaudeProvider(historyURL: dir.appendingPathComponent("history.json"),
                                  projectsURL: dir.appendingPathComponent("projects"), archiveURL: nil)
    let snap = try! provider.snapshot(now: at(20, 15))
    let session = snap.window("five_hour"), weekly = snap.window("seven_day")
    check(session?.limitReported == true && near(session?.percent, 100) && session?.resetsAt == at(20, 18),
          "5 小时的限流消息进了 5 小时窗口：\(String(describing: session))")
    check(weekly?.limitReported == true && near(weekly?.percent, 100) && weekly?.resetsAt == at(24, 9),
          "每周的限流消息进了每周窗口：\(String(describing: weekly))")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - 其他端用量

do {
    /// 值 pct 个百分点的请求（percentOf = usd × 100）
    func req(_ t: Date, _ pct: Double) -> ClaudeRequest {
        ClaudeRequest(id: UUID().uuidString, time: t, family: .opus, tokens: TokenCounts(output: Int(pct * 500)))
    }
    let percentOf: (ClaudeRequest) -> Double = { $0.usd * 100 }
    let reqs = [req(at(20, 10), 3), req(at(20, 10, 38), 5), req(at(20, 11, 15), 2)]
    let readings = [S(time: at(20, 10, 10), value: 3), S(time: at(20, 10, 25), value: 9), S(time: at(20, 10, 40), value: 15),
                    S(time: at(20, 10, 55), value: 16), S(time: at(20, 11, 10), value: 20), S(time: at(20, 11, 25), value: 30)]
    let segments = OtherUsage.segments(start: at(20, 10), readings: readings, requests: reqs, percentOf: percentOf)
    // 10:10 本机 3 对上；10:25 本机没有请求，+6 全是其他端；10:40 本机 5、官方 6，差 1 是误差；
    // 10:55 +1 紧跟在 10:38 的请求后面，是服务器计数慢；11:10 本机没有请求，+4；11:25 本机 2、官方 10，多出 8
    check(segments.count == 3 && zip(segments, [6.0, 4, 8]).allSatisfy { near($0.percent, $1) } && segments.first?.start == at(20, 10, 10),
          "逐段找出其他端用量：\(segments.map(\.percent))")
    check(near(OtherUsage.burnPerHour(segments, from: at(20, 10, 55), now: at(20, 11, 25), minSpan: 600), 24, 1e-6),
          "其他端每小时：半小时里 4 + 8 = 12")
    check(near(OtherUsage.burnPerHour(segments, from: at(20, 11), now: at(20, 11, 30), minSpan: 600), 21.3333, 1e-3),
          "跨边界的段按时间比例摊，最近一次读数之后看不到的按 0 算：(4 × 2/3 + 8) ÷ 30 分钟")
    let wobble = [S(time: at(20, 10, 10), value: 5), S(time: at(20, 10, 25), value: 3), S(time: at(20, 10, 40), value: 5)]
    let wobbled = OtherUsage.segments(start: at(20, 10), readings: wobble, requests: [], percentOf: percentOf)
    check(wobbled.count == 1 && near(wobbled.first?.percent, 5), "读数往回掉又回来，不算新用量")
    let twin = OtherUsage.segments(start: at(20, 10), readings: [S(time: at(20, 10, 10), value: 3), S(time: at(20, 10, 10), value: 5)],
                                   requests: [], percentOf: percentOf)
    check(twin.count == 1 && OtherUsage.burnPerHour(twin, from: at(20, 10), now: at(20, 10, 30), minSpan: 600).isFinite,
          "同一时刻的两条读数不会产生长度为 0 的段")

    let provider = ClaudeProvider(historyURL: URL(fileURLWithPath: "/nonexistent/h.json"),
                                  projectsURL: URL(fileURLWithPath: "/nonexistent/projects"), archiveURL: nil)
    func window(_ series: [S], live: Bool = true) -> UsageWindow {
        provider.buildWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, series: series,
                             requests: [reqs[0]], scale: 1, percentOf: percentOf, resetAnchor: nil, live: live, now: at(20, 10, 30))
    }
    let zero = [S(time: at(20, 9, 30), value: 0)]  // 窗口开始前读数确实是 0
    let w = window(zero + [S(time: at(20, 10, 10), value: 10), S(time: at(20, 10, 25), value: 16)])
    check(near(w.otherPercent, 13) && near(w.otherBurnPerHour, 26, 1e-6) && near(w.burnPerHour, 26, 1e-6),
          "从 0 算起：10:10 本机 3、官方 10，多 7；10:25 本机没有请求，+6；速度 13 ÷ 30 分钟：\(w.otherPercent) \(w.burnPerHour ?? -1)")
    let midway = window([S(time: at(20, 10, 10), value: 40), S(time: at(20, 10, 25), value: 46)])
    check(near(midway.otherPercent, 6), "开始前没有 0 的读数（记录从窗口中间开始）：第一次读数之前的 40% 不算其他端：\(midway.otherPercent)")
    check(window(zero + Array(readings.prefix(2)), live: false).otherPercent == 0, "关掉实时估算时也不算其他端")
}

// MARK: - 什么时候显示

check(MenuBarVisibility.withClaude.shouldShow(claudeRunning: true, pinned: false), "Claude 开着就显示")
check(!MenuBarVisibility.withClaude.shouldShow(claudeRunning: false, pinned: false), "Claude 关了就藏起来")
check(MenuBarVisibility.withClaude.shouldShow(claudeRunning: false, pinned: true), "用户临时叫出来时显示")
check(MenuBarVisibility.always.shouldShow(claudeRunning: false, pinned: false), "一直显示")

// MARK: - 区间记录 & 学习换算率

do {
    func opus(_ t: Date, usd: Double, effort: String = "max") -> ClaudeRequest {
        ClaudeRequest(id: UUID().uuidString, time: t, family: .opus,
                      tokens: TokenCounts(output: Int((usd / 20 * 1e6).rounded())), effort: effort, thinkingTokens: 100)
    }
    func sample(_ t: Date, _ session: Double, _ weekly: Double) -> PlanUsageSample {
        PlanUsageSample(time: t, org: "A", values: ["fh": session, "sd": weekly])
    }
    let samples = [sample(at(25, 10), 10, 20), sample(at(25, 10, 15), 14, 20), sample(at(25, 10, 30), 20, 21),
                   sample(at(25, 10, 45), 3, 21),  // 5 小时窗口重置了
                   sample(at(25, 13), 5, 22)]      // 桌面端关了一阵，间隔太长
    let reqs = [opus(at(25, 10, 5), usd: 1.2), opus(at(25, 10, 20), usd: 1.8), opus(at(25, 10, 40), usd: 3.0, effort: "high")]
    let intervals = UsageInterval.extract(samples: samples, requests: reqs, now: at(25, 14))
    check(intervals.count == 3, "间隔太长的不算：\(intervals.count)")
    check(near(intervals.first?.usd, 1.2) && intervals.first?.sessionDelta == 4 && intervals.first?.usdByGroup["opus/max"] != nil,
          "区间里的花费、官方增量、按模型/思考程度分的花费")
    check(intervals.last?.sessionDelta == nil && intervals.last?.weeklyDelta == 0, "重置过的区间没有 5 小时增量")
    check(UsageInterval.extract(samples: samples, requests: reqs, now: at(25, 10, 16)).isEmpty, "刚结束 2 分钟内的区间先不记")

    // opus：100 万缓存读 $0.2 + 1 万输出 $0.2 = $0.4，缓存读半价 → 额度加权 $0.3
    let cached = ClaudeRequest(id: "c", time: at(25, 10, 5), family: .opus, tokens: TokenCounts(cacheRead: 1_000_000, output: 10_000))
    let withCache = UsageInterval.extract(samples: Array(samples.prefix(2)), requests: [cached], now: at(25, 14)).first
    check(near(withCache?.usd, 0.4) && near(withCache?.cacheReadUSD, 0.2) && near(withCache?.quotaUSD, 0.3), "区间的额度加权花费：\(String(describing: withCache))")
    var legacy = intervals[0]
    legacy.cacheReadUSD = nil
    check(legacy.quotaUSD == nil && RateLearner.learn([legacy], delta: \.sessionDelta, prior: 0.31).intervals == 0,
          "旧版本记下的区间没有缓存读花费，不参与学习")

    let fit = RateLearner.learn(intervals, delta: \.sessionDelta, prior: 0.31, priorUSD: 0.0001)
    check(near(fit.usdPerPercent, 0.30, 1e-3) && fit.intervals == 2, "换算率 = 本机花费 $3 ÷ 官方增量 10%：\(fit)")
    let cold = RateLearner.learn([], delta: \.sessionDelta, prior: 0.31)
    check(cold.usdPerPercent == 0.31 && cold.intervals == 0, "还没有记录时用起始值")
    var older = intervals[0], newer = intervals[1]
    older.end = at(20, 10); older.usd = 2.0; older.sessionFrom = 0; older.sessionTo = 4   // 5 天前：$0.5 / 1%
    newer.end = at(25, 10); newer.usd = 0.8; newer.sessionFrom = 0; newer.sessionTo = 4   // 最近：$0.2 / 1%
    let recency = RateLearner.learn([older, newer], delta: \.sessionDelta, prior: 0.31, priorUSD: 0.0001)
    check(recency.usdPerPercent < 0.21, "越近的记录权重越大：\(recency.usdPerPercent)")
    older.end = at(25, 4)  // 早 6 小时 = 两个半衰期，权重 1/4：(0.5 + 0.8) ÷ (1 + 4)
    let halfLife = RateLearner.learn([older, newer], delta: \.sessionDelta, prior: 0.31, priorUSD: 0.0001)
    check(near(halfLife.usdPerPercent, 0.26, 1e-4), "半衰期 3 小时：\(halfLife.usdPerPercent)")
    var pure = intervals[0], mixed = intervals[1]
    pure.end = at(25, 10); pure.usd = 3; pure.sessionFrom = 0; pure.sessionTo = 10           // $0.3 / 1%
    mixed.end = at(25, 10, 15); mixed.usd = 0.3; mixed.sessionFrom = 10; mixed.sessionTo = 20 // 本机只够 1%，官方涨了 10%
    let skip = RateLearner.learn([pure, mixed], delta: \.sessionDelta, prior: 0.31, priorUSD: 0.0001)
    check(near(skip.usdPerPercent, 0.3, 1e-3) && skip.intervals == 1, "同时在其他端用过的区间不拿来学：\(skip)")
    // 10 段里有 4 段混用（官方 +15，本机只够 +10）：简单平均会被拉到 $0.25、一段都挑不出来；中位数 + 反复挑能找全
    let crowded = (0..<10).map { i -> UsageInterval in
        var interval = intervals[0]
        interval.end = at(25, 10).addingTimeInterval(Double(i) * 900)
        interval.usd = 3
        interval.sessionFrom = 0
        interval.sessionTo = [1, 4, 6, 8].contains(i) ? 15 : 10
        return interval
    }
    let robust = RateLearner.learn(crowded, delta: \.sessionDelta, prior: 0.31, priorUSD: 0.0001)
    check(near(robust.usdPerPercent, 0.3, 1e-3) && robust.intervals == 6, "混用的区间多的时候也挑得出来：\(robust)")
    let flagged = crowded.filter { OtherUsage.isOther(excess: $0.sessionDelta! - $0.usd / robust.usdPerPercent, local: $0.usd / robust.usdPerPercent) }
    check(flagged.count == 4, "学换算率时挑掉的，正好是按学到的换算率会被面板算成其他端的那几段")
    var stale = intervals[0]
    stale.end = at(22, 10); stale.usd = 3; stale.sessionFrom = 0; stale.sessionTo = 10
    check(RateLearner.learn([stale, pure], delta: \.sessionDelta, prior: 0.31).intervals == 1, "两天以前的区间不再算")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotapet-archive-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("intervals.jsonl")
    let archive = IntervalArchive(url: url)
    check(archive.merge(intervals) == 3 && archive.merge(intervals) == 0, "同一段只记一次")
    let reopened = IntervalArchive(url: url)
    check(reopened.intervals == intervals, "重启后记录能原样读回来")
    check(reopened.merge(intervals) == 0, "重启后也不会重复记录")
    var old = intervals[0], other = intervals[1]
    old.cacheReadUSD = nil
    other.cacheReadUSD = nil
    other.usd += 1  // 本机日志已经对不上了
    let legacyURL = dir.appendingPathComponent("legacy.jsonl")
    IntervalArchive(url: legacyURL).merge([old, other])
    let upgraded = IntervalArchive(url: legacyURL)
    check(upgraded.merge(intervals) == 2, "补全旧记录（1 条）+ 新记录（1 条），对不上的旧记录不动")
    let reread = IntervalArchive(url: legacyURL).intervals
    check(reread.count == 3 && reread[0] == intervals[0] && reread[1].cacheReadUSD == nil, "读回来时以补全后的那行为准")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - 菜单栏文字 & 预测

do {
    let session = UsageWindow(id: "five_hour", title: "", shortTitle: "", duration: fiveHours, percent: 27.4)
    let weekly = UsageWindow(id: "seven_day", title: "", shortTitle: "", duration: week, percent: 81)
    let snap = UsageSnapshot(provider: .claude, windows: [session, weekly], generatedAt: at(25, 12))
    check(MenuBarText.make(snap, mode: .session, now: at(25, 12)).text == "27%", "只显示 5 小时")
    check(MenuBarText.make(snap, mode: .sessionAndWeekly, now: at(25, 12)).text == "27% · 81%", "5 小时 + 每周")
    check(MenuBarText.make(snap, mode: .tightest, now: at(25, 12)).text == "81%", "最紧张的窗口")
    check(MenuBarText.make(snap, mode: .petOnly, now: at(25, 12)).text == "", "只显示宠物")
    var limited = snap
    limited.windows[0].percent = 100
    limited.windows[0].resetsAt = at(25, 13, 23)
    check(MenuBarText.make(limited, mode: .session, now: at(25, 12)).text == "1h23m", "限流时显示恢复倒计时")
    check(PetMood.from(snapshot: limited) == .sleeping, "限流时宠物睡觉")

    let fast = UsageWindow(id: "x", title: "", shortTitle: "", duration: fiveHours, percent: 60, resetsAt: at(25, 16), burnPerHour: 20)
    check(fast.projectedExhaustion(now: at(25, 12)) == at(25, 14), "60% + 20%/小时 → 2 小时后用完")
    let slow = UsageWindow(id: "x", title: "", shortTitle: "", duration: fiveHours, percent: 60, resetsAt: at(25, 13), burnPerHour: 20)
    check(slow.projectedExhaustion(now: at(25, 12)) == nil, "重置前用不完就不预警")
}

print(failed == 0 ? "✓ 全部 \(passed) 项自检通过" : "✗ \(failed) 项失败，\(passed) 项通过")
exit(failed == 0 ? 0 : 1)
