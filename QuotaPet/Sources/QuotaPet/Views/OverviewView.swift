import SwiftUI
import QuotaPetCore

/// 面板首页。只接收普通的值，方便 --render-previews 直接渲染成图片。
struct OverviewView<Pet: View>: View {
    var snapshot: UsageSnapshot?
    var errorMessage: String?
    var mood: PetMood
    var pet: Pet
    var onRefresh: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    /// 渲染预览图时固定「现在」
    var fixedNow: Date?

    /// 点刷新后给个反馈：图标转一圈，底部说明刷新了什么
    @State private var refreshSpin = 0.0
    @State private var refreshedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: fixedNow ?? context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let snapshot, snapshot.hasData {
                VStack(spacing: 8) {
                    ForEach(snapshot.windows) { WindowCard(window: $0, now: now) }
                }
                if let today = snapshot.today, today.requests > 0 {
                    TodayCard(today: today)
                }
                NotesView(notes: snapshot.notes)
            } else if let snapshot {
                NotesView(notes: snapshot.notes.isEmpty ? ["还没有任何额度数据。"] : snapshot.notes)
            } else if let errorMessage {
                NotesView(notes: ["读取出错：\(errorMessage)"])
            } else {
                Text("正在读取…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            footer(now: now)
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 12) {
            pet
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Level.mood(mood).opacity(0.13)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snapshot?.provider.displayName ?? "Claude")
                        .font(.system(size: 15, weight: .semibold))
                    Text(mood.title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Level.mood(mood).opacity(0.16)))
                        .foregroundStyle(Level.mood(mood))
                }
                Text(mood.line)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                IconButton(systemName: "arrow.clockwise",
                           help: "重新读取本机数据（官方读数要等 Claude 桌面端下一次记录）",
                           rotation: refreshSpin) {
                    onRefresh()
                    withAnimation(.easeInOut(duration: 0.6)) { refreshSpin += 360 }
                    refreshedAt = Date()
                }
                IconButton(systemName: "gearshape", help: "设置", action: onSettings)
            }
            .task(id: refreshedAt) {
                guard refreshedAt != nil else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                refreshedAt = nil
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if refreshedAt != nil {
                Label("已刷新：本机部分是最新的，\(nextOfficialText(now: now))", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(sourceLine(now: now))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("退出", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func sourceLine(now: Date) -> String {
        guard let snapshot, snapshot.hasData else { return "只读本机文件，不联网、不读登录凭据" }
        guard snapshot.officialAt != nil else {
            return snapshot.windows.contains(where: \.limitReported)
                ? "暂无桌面端的官方读数：「用完了」是 Claude Code 报告的，其余是本机估算" : "暂无官方读数，数值全部是本机估算"
        }
        return "Claude 桌面端每 15 分钟记一次官方读数，\(nextOfficialText(now: now))"
    }

    /// 桌面端很准时地每 15 分钟记一次，下一次 = 上一次 + 15 分钟
    private func nextOfficialText(now: Date) -> String {
        guard let last = snapshot?.officialAt else { return "官方读数暂时没有" }
        let next = last.addingTimeInterval(15 * 60)
        if next > now { return "下次约 \(Fmt.clock(next, now: now))" }
        if now.timeIntervalSince(last) < 45 * 60 { return "下一次随时会到" }
        return "官方读数暂停了（Claude 桌面端没开？）"
    }
}

/// 一个额度窗口：大数字 + 进度条 + 重置时间
struct WindowCard: View {
    var window: UsageWindow
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if window.estimatedExtra >= 0.5 {
                    Text("≈").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(Fmt.percent(window.clampedPercent))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Level.text(window.percent))
                    .contentTransition(.numericText())
            }
            UsageBar(percent: window.clampedPercent, official: window.official, tint: Level.bar(window.percent))
                .padding(.bottom, 1)
            legend
            if window.otherPercent >= 1 {
                Text("其中约 \(Int(window.otherPercent.rounded()))% 是网页、手机等其他端用的")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Text(resetText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            if let exhaustion = window.projectedExhaustion(now: now), let burn = window.burnPerHour {
                Label("照这个速度（每小时 \(Int(burn.rounded()))%\(otherBurnText)），\(Fmt.clock(exhaustion, now: now)) 左右用完",
                      systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let burn = window.burnPerHour, burn >= 1, window.percent < 100 {
                Text("\(lookbackText)：每小时约 \(Int(burn.rounded()))%\(otherBurnText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// 消耗速度里有其他端的部分时，补一句「，其中其他端约 6%」
    private var otherBurnText: String {
        guard let other = window.otherBurnPerHour, other >= 1 else { return "" }
        return "，其中其他端约 \(Int(other.rounded()))%"
    }

    private var lookbackText: String {
        window.burnLookback >= 86400 ? "最近 24 小时" : "最近 \(Int(window.burnLookback / 60)) 分钟"
    }

    /// 进度条的图例：实色 = 官方读数，浅色 = 之后的本机估算
    @ViewBuilder private var legend: some View {
        let tint = Level.bar(window.percent)
        let extra = window.estimatedExtra
        if window.official != nil || extra >= 0.5 {
            HStack(spacing: 12) {
                if let official = window.official, let at = window.officialAt {
                    LegendItem(color: tint, text: window.limitReported
                               ? "Claude Code 报告用完了（\(Fmt.ago(at, now: now))）"
                               : "官方 \(Int(official))%（\(Fmt.ago(at, now: now))）")
                }
                if extra >= 0.5 {
                    LegendItem(color: tint.opacity(0.4),
                               text: "本机估算 \(window.official == nil ? "" : "+")\(Int(extra.rounded()))%")
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        if let reset = window.resetsAt {
            let verb = window.percent >= 100 ? "恢复" : "重置"
            return "约 \(Fmt.duration(reset.timeIntervalSince(now)))后\(verb) · \(Fmt.clock(reset, now: now))"
        }
        return window.percent < 0.5 ? "还没开始计时（下次使用时开始）" : "重置时间未知"
    }
}

/// 图例里的一个小色块 + 文字
struct LegendItem: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 9, height: 7)
            Text(text).lineLimit(1)
        }
    }
}

/// 进度条：实色是官方读数，浅色是之后的本机估算
struct UsageBar: View {
    var percent: Double
    var official: Double?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let estimated = percent / 100
            let confirmed = min(official ?? 0, percent) / 100  // 没有官方读数时整条都是估算
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if estimated > 0 {
                    Capsule().fill(tint.opacity(0.4)).frame(width: max(estimated * width, 7))
                }
                if confirmed > 0 {
                    Capsule().fill(tint).frame(width: max(confirmed * width, 7))
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

struct TodayCard: View {
    var today: ActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天 · 本机 Claude Code")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("≈ \(Fmt.usd(today.usd))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text("\(today.requests) 次请求 · \(Fmt.tokens(today.tokens)) tokens · 按 API 价格折算")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !today.byFamily.isEmpty {
                Text(today.byFamily.map { "\($0.family) \(Fmt.usd($0.usd))" }.joined(separator: "  ·  "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct NotesView: View {
    var notes: [String]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(notes, id: \.self) { note in
                    Label {
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
