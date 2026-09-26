import SwiftUI
import QuotaPetCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// 打开「手动指定每周重置时间」时的默认值（当前推算出来的时间）
    var suggestedWeeklyReset: Date?
    /// 当前的换算率和学习记录
    var estimation: EstimationInfo?
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text("设置").font(.system(size: 14, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 1)  // 让标题居中
            }

            SettingsGroup("菜单栏") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("什么时候出现").font(.system(size: 12))
                    Picker("什么时候出现", selection: $settings.visibility) {
                        ForEach(MenuBarVisibility.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.visibility == .withClaude ? "Claude 关掉后就藏起来，额度恢复提醒照常发" : "一直待在菜单栏里")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("宠物旁边显示").font(.system(size: 12))
                    Picker("宠物旁边显示", selection: $settings.menuBarText) {
                        ForEach(MenuBarTextMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                SwitchRow("宠物动画", isOn: $settings.animatePet)
                SwitchRow("单色宠物", subtitle: "跟随菜单栏的黑白配色", isOn: $settings.monochromePet)
            }

            SettingsGroup("提醒") {
                SwitchRow("用量提醒", isOn: $settings.notificationsEnabled)
                HStack(spacing: 6) {
                    Text("提醒阈值").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    ForEach([50, 75, 90, 100], id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: thresholdBinding(threshold))
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }
                .disabled(!settings.notificationsEnabled)
                SwitchRow("额度恢复时提醒", isOn: $settings.notifyOnReset)
            }

            SettingsGroup("实时估算") {
                SwitchRow("用本机日志实时估算", subtitle: "两次官方读数之间，按 Claude Code 的用量推算（缓存读按半价算）", isOn: $settings.liveEstimate)
                SwitchRow("自动学习换算率", subtitle: "每来一次官方读数就学一次，记录一直存在本机",
                          isOn: $settings.autoLearn)
                    .disabled(!settings.liveEstimate)
                if settings.liveEstimate { ratesView }
                SwitchRow("手动指定每周重置时间", subtitle: "推算不准时用，准确时间可以在 Claude 的设置页看到",
                          isOn: weeklyOverrideBinding)
                if let anchor = settings.weeklyResetAnchor {
                    DatePicker("下次重置", selection: Binding(get: { anchor }, set: { settings.weeklyResetAnchor = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                        .font(.system(size: 12))
                }
            }

            SettingsGroup("通用") {
                SwitchRow("开机自动启动", subtitle: "开着才能在 Claude 打开时自动出现",
                          isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                if let error = settings.launchAtLoginError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        }
        .padding(14)
    }

    /// 5 小时 每 1% ≈ $0.33 · 每周 每 1% ≈ $2.41，下面一行说明学了多少记录
    private var ratesView: some View {
        let starting = ClaudeRates.starting
        let session = estimation?.sessionUSDPerPercent ?? starting.usdPerSessionPercent
        let weekly = estimation?.weeklyUSDPerPercent ?? starting.usdPerWeeklyPercent
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Text("5 小时：每 1% ≈ \(Fmt.usd(session))")
                Text("每周：每 1% ≈ \(Fmt.usd(weekly))")
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            Text(learningText)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("在访达中查看记录") {
                NSWorkspace.shared.activateFileViewerSelecting([IntervalArchive.defaultURL])
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .disabled(!FileManager.default.fileExists(atPath: IntervalArchive.defaultURL.path))
        }
        .padding(.leading, 2)
    }

    private var learningText: String {
        guard let estimation else { return "还没有数据" }
        let recorded = "已记录 \(estimation.recordedIntervals) 段（每段约 15 分钟）"
        guard settings.autoLearn else { return "自动学习已关闭，一直用起始值。" + recorded }
        guard estimation.learnedIntervals > 0, let until = estimation.learnedUntil else {
            return "记录还不够，先用起始值（实测回归的结果）。" + recorded
        }
        return "从 \(estimation.learnedIntervals) 段有 Claude Code 用量的记录里学到，数据截至 \(Fmt.clock(until, now: Date()))。" + recorded
    }

    private func thresholdBinding(_ threshold: Int) -> Binding<Bool> {
        Binding(get: { settings.thresholds.contains(threshold) },
                set: { on in
                    var set = Set(settings.thresholds)
                    if on { set.insert(threshold) } else { set.remove(threshold) }
                    settings.thresholds = set.sorted()
                })
    }

    private var weeklyOverrideBinding: Binding<Bool> {
        Binding(get: { settings.weeklyResetAnchor != nil },
                set: { on in
                    settings.weeklyResetAnchor = on ? (suggestedWeeklyReset ?? Date().addingTimeInterval(7 * 86400)) : nil
                })
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }
}

struct SwitchRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}
