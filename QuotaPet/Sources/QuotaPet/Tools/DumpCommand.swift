import Foundation
import ServiceManagement
import QuotaPetCore

/// QuotaPet --dump：在终端打印当前的额度推算，方便调试、和 usage_lab.py 对账
enum DumpCommand {
    static func run() {
        let provider = ClaudeProvider()
        let now = Date()
        let started = Date()
        let snap: UsageSnapshot
        do {
            snap = try provider.snapshot(now: now)
        } catch {
            print("出错了：\(error.localizedDescription)")
            return
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        print("QuotaPet · Claude 额度（只读本机文件：不联网、不读凭据）")
        print("现在 \(Fmt.clock(now, now: now))，用时 \(ms) ms，读了 \(provider.scanner.trackedFiles) 个日志文件、\(provider.lastRequests.count) 个请求")
        print("")

        print("最近的官方读数（Claude 桌面端）：")
        for s in provider.lastSamples.suffix(6) {
            let fh = s.session.map { Fmt.percent($0) } ?? "-"
            let sd = s.weekly.map { Fmt.percent($0) } ?? "-"
            print("  \(Fmt.clock(s.time, now: now))  5h \(fh.padding(toLength: 5, withPad: " ", startingAt: 0))周 \(sd)")
        }
        print("")

        if !provider.scanner.limitEvents.isEmpty {
            print("最近的限流消息（Claude Code 日志）：")
            for l in provider.scanner.limitEvents.suffix(3) {
                print("  \(Fmt.clock(l.time, now: now))  \(l.window) 用完，\(Fmt.clock(l.resetsAt, now: now)) 恢复")
            }
            print("")
        }

        for w in snap.windows {
            var line = "\(w.title)：\(Fmt.percent(w.percent))"
            if let o = w.official, let t = w.officialAt {
                line += "（官方 \(Fmt.percent(o))，\(Fmt.ago(t, now: now))"
                line += w.estimatedExtra >= 0.05 ? String(format: " + 本机估算 %.1f%%）", w.estimatedExtra) : "）"
            }
            print(line)
            if let start = w.startedAt, let end = w.resetsAt {
                print("  窗口 \(Fmt.clock(start, now: now)) → \(Fmt.clock(end, now: now))，约 \(Fmt.duration(end.timeIntervalSince(now)))后重置")
            } else {
                print("  窗口还没开始（下次使用时开始计时）")
            }
            if let burn = w.burnPerHour, burn > 0 {
                let span = w.burnLookback >= 86400 ? "24 小时" : "\(Int(w.burnLookback / 60)) 分钟"
                print(String(format: "  最近 %@ 消耗速度 %.1f%%/小时", span, burn))
            }
            if let t = w.projectedExhaustion(now: now) {
                print("  ⚠️ 照这个速度 \(Fmt.clock(t, now: now)) 会用完")
            }
        }
        print("")

        if let today = snap.today {
            let families = today.byFamily.map { "\($0.family) \($0.requests) 次 \(Fmt.usd($0.usd))" }.joined(separator: "，")
            print("今天本机 Claude Code：\(today.requests) 次请求，\(Fmt.tokens(today.tokens)) tokens，API 等价 \(Fmt.usd(today.usd))")
            if !families.isEmpty { print("  \(families)") }
        }

        if let e = snap.estimation {
            print(String(format: "换算率：5 小时每 1%% ≈ $%.3f，每周每 1%% ≈ $%.2f（缓存读按半价算）", e.sessionUSDPerPercent, e.weeklyUSDPerPercent))
            let learned = e.learnedIntervals > 0 ? "从 \(e.learnedIntervals) 段有用量的记录里学到" : "记录不够，用起始值"
            print("  \(learned)；一共记录了 \(e.recordedIntervals) 段 → \(IntervalArchive.defaultURL.path)")
        }

        // 和 `python3 usage_lab.py summary --hours 24` 对账
        let dayAgo = now.addingTimeInterval(-86400)
        var last24: [ModelFamily: (Int, Double)] = [:]
        for r in provider.lastRequests where r.time > dayAgo {
            let v = last24[r.family] ?? (0, 0)
            last24[r.family] = (v.0 + 1, v.1 + r.usd)
        }
        let summary = ModelFamily.allCases.compactMap { f in last24[f].map { "\(f.rawValue) \($0.0) 次 \(Fmt.usd($0.1))" } }
        print("最近 24 小时（对账用）：\(summary.joined(separator: "，"))")

        // 只有从 .app 里运行时才看得到开机自启的状态
        if Bundle.main.bundleURL.pathExtension == "app" {
            let status: String
            switch SMAppService.mainApp.status {
            case .enabled: status = "已开启"
            case .requiresApproval: status = "等你在「系统设置 → 通用 → 登录项」里批准"
            case .notRegistered: status = "未开启"
            case .notFound: status = "找不到 App"
            @unknown default: status = "未知"
            }
            print("开机自动启动：\(status)（\(Bundle.main.bundlePath)）")
        }

        if !snap.notes.isEmpty {
            print("")
            snap.notes.forEach { print("· \($0)") }
        }
    }
}
