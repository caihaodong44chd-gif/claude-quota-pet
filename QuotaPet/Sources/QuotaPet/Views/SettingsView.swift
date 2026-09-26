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
                    Label(tr("返回", "Back"), systemImage: "chevron.left").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text(tr("设置", "Settings")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 1)  // 让标题居中
            }

            SettingsGroup(tr("菜单栏", "Menu Bar")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("什么时候出现", "When to show")).font(.system(size: 12))
                    Picker(tr("什么时候出现", "When to show"), selection: $settings.visibility) {
                        ForEach(MenuBarVisibility.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.visibility == .withClaude
                         ? tr("Claude 关掉后就藏起来，额度恢复提醒照常发", "Hides when Claude quits; reset notifications still arrive")
                         : tr("一直待在菜单栏里", "Always stays in the menu bar"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("宠物旁边显示", "Next to the pet")).font(.system(size: 12))
                    Picker(tr("宠物旁边显示", "Next to the pet"), selection: $settings.menuBarText) {
                        ForEach(MenuBarTextMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("宠物形象", "Pet style")).font(.system(size: 12))
                    // 一行放不下就换行
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8, alignment: .leading)], alignment: .leading,
                              spacing: 8) {
                        ForEach(PetStyle.allCases) { style in
                            StyleOption(style: style, isSelected: settings.petStyle == style) { settings.petStyle = style }
                        }
                    }
                }
                SwitchRow(tr("宠物动画", "Animate pet"), isOn: $settings.animatePet)
                SwitchRow(tr("单色宠物", "Monochrome pet"), subtitle: tr("跟随菜单栏的黑白配色", "Matches the black-and-white menu bar"),
                          isOn: $settings.monochromePet)
            }

            SettingsGroup(tr("提醒", "Notifications")) {
                SwitchRow(tr("用量提醒", "Usage alerts"), isOn: $settings.notificationsEnabled)
                HStack(spacing: 6) {
                    Text(tr("提醒阈值", "Alert at")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    ForEach([50, 75, 90, 100], id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: thresholdBinding(threshold))
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }
                .disabled(!settings.notificationsEnabled)
                SwitchRow(tr("额度恢复时提醒", "Notify when quota resets"), isOn: $settings.notifyOnReset)
            }

            SettingsGroup(tr("实时估算", "Live Estimate")) {
                SwitchRow(tr("用本机日志实时估算", "Estimate from local logs"),
                          subtitle: tr("两次官方读数之间，按 Claude Code 的用量推算（缓存读按半价算）",
                                       "Between official readings, estimate from Claude Code usage (cache reads count at half price)"),
                          isOn: $settings.liveEstimate)
                SwitchRow(tr("自动学习换算率", "Learn the rate automatically"),
                          subtitle: tr("每来一次官方读数就学一次，记录一直存在本机", "Learns from every official reading; records stay on this Mac"),
                          isOn: $settings.autoLearn)
                    .disabled(!settings.liveEstimate)
                if settings.liveEstimate { ratesView }
                SwitchRow(tr("手动指定每周重置时间", "Set weekly reset time manually"),
                          subtitle: tr("推算不准时用，准确时间可以在 Claude 的设置页看到",
                                       "Use this if the estimate is off; Claude's settings page shows the exact time"),
                          isOn: weeklyOverrideBinding)
                if let anchor = settings.weeklyResetAnchor {
                    DatePicker(tr("下次重置", "Next reset"), selection: Binding(get: { anchor }, set: { settings.weeklyResetAnchor = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                        .font(.system(size: 12))
                }
            }

            SettingsGroup(tr("通用", "General")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("语言", "Language")).font(.system(size: 12))
                    Picker(tr("语言", "Language"), selection: $settings.language) {
                        Text(tr("跟随系统", "System")).tag(Language?.none)
                        ForEach(Language.allCases) { Text($0.nativeName).tag(Language?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                SwitchRow(tr("开机自动启动", "Launch at login"),
                          subtitle: tr("开着才能在 Claude 打开时自动出现", "Lets the pet appear when Claude opens"),
                          isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                if let error = settings.launchAtLoginError {
                    Text(tr("设置失败：\(error)（把 App 放进「应用程序」文件夹后再试）",
                            "Couldn't change this: \(error) (move the app into the Applications folder and try again)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
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
                Text(tr("5 小时：每 1% ≈ \(Fmt.usd(session))", "5-hour: 1% ≈ \(Fmt.usd(session))"))
                Text(tr("每周：每 1% ≈ \(Fmt.usd(weekly))", "Weekly: 1% ≈ \(Fmt.usd(weekly))"))
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            Text(learningText)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(tr("在访达中查看记录", "Show records in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([IntervalArchive.defaultURL])
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .disabled(!FileManager.default.fileExists(atPath: IntervalArchive.defaultURL.path))
        }
        .padding(.leading, 2)
    }

    private var learningText: String {
        guard let estimation else { return tr("还没有数据", "No data yet") }
        let recorded = tr("已记录 \(estimation.recordedIntervals) 段（每段约 15 分钟）",
                          "\(plural(estimation.recordedIntervals, "interval")) recorded (about 15 min each).")
        guard settings.autoLearn else {
            return tr("自动学习已关闭，一直用起始值。", "Auto-learning is off, so the starting rate is used. ") + recorded
        }
        guard estimation.learnedIntervals > 0, let until = estimation.learnedUntil else {
            return tr("记录还不够，先用起始值（实测回归的结果）。",
                      "Not enough records yet, so the starting rate (from a measured regression) is used. ") + recorded
        }
        let learned = estimation.learnedIntervals, clock = Fmt.clock(until, now: Date())
        return tr("从 \(learned) 段有 Claude Code 用量的记录里学到，数据截至 \(clock)。",
                  "Learned from \(plural(learned, "interval")) with Claude Code usage, up to \(clock). ") + recorded
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

/// 形象选项：半身像缩略图 + 名字，选中的描一圈强调色
struct StyleOption: View {
    let style: PetStyle
    let isSelected: Bool
    let action: () -> Void

    /// 缩略图只在第一次用到时画一次：先画成位图，再平滑缩到 48pt（0.75pt 一格画不出整像素）
    private static let thumbnails = Dictionary(uniqueKeysWithValues: PetStyle.allCases.map {
        ($0, PetRenderer.bitmap(PetSprites.frames(for: .normal, style: $0)[0].portrait, scale: 2))
    })

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: Self.thumbnails[style] ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text(style.label).font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
