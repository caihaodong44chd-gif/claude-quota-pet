import AppKit
import SwiftUI
import QuotaPetCore

/// QuotaPet --render-previews <dir>：把宠物动画、菜单栏效果和面板渲染成 PNG，
/// 不用真的启动 App 就能检查设计。面板和设置页中英各一套，英文的文件名带 -en。
/// 同时有 Claude 和 Codex 时的样子在 popover-codex*、menubar-codex、settings-codex*。
@MainActor
enum PreviewRenderer {
    static func renderAll(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = AppSettings()  // 它会按设置切换界面语言，所以要在下面固定语言之前建
        L10n.language = .zhHans  // 动画表上的心情名、真实数据那两张用中文
        for style in PetStyle.allCases {
            let suffix = style == .classic ? "" : "-\(style.rawValue)"
            write(spriteSheet(template: false, style: style), to: dir.appendingPathComponent("pet-sheet\(suffix).png"))
            write(spriteSheet(template: true, style: style), to: dir.appendingPathComponent("pet-sheet\(suffix)-mono.png"))
            write(menuBarStrip(style: style), to: dir.appendingPathComponent("menubar\(suffix).png"))
        }
        write(menuBarGlyphStrip(), to: dir.appendingPathComponent("menubar-codex.png"))

        let now = Date()
        // 用本机真实数据渲染一张，和点开菜单栏看到的一样：先看宠物跟着的那家（宠物停在第一帧）
        let live = UsageSnapshot.visible([try? ClaudeProvider().snapshot(now: now), try? CodexProvider().snapshot(now: now)].compactMap { $0 },
                                         hidden: settings.hiddenProviders)
        if let focus = UsageSnapshot.focus(of: live) {
            let mood = PetMood.from(snapshot: focus)
            let style = PetStyle.of(focus.provider, claudeStyle: settings.petStyle, codexStyle: settings.codexPetStyle)
            for dark in [false, true] {
                let view = OverviewView(snapshot: focus, errorMessage: nil, mood: mood,
                                        pet: PetImage(grid: PetSprites.frames(for: mood, style: style)[0].portrait),
                                        tabs: live.count > 1 ? live : [], focus: focus.provider, fixedNow: now)
                write(render(view, dark: dark), to: dir.appendingPathComponent("popover-live\(dark ? "-dark" : "").png"))
            }
        }

        for language in Language.allCases {
            L10n.language = language
            let lang = language == .zhHans ? "" : "-\(language.rawValue)"
            if language != .zhHans {  // 看看各种心情的名字
                write(spriteSheet(template: false, style: .classic), to: dir.appendingPathComponent("pet-sheet\(lang).png"))
            }
            for (name, snapshot) in sampleSnapshots(now: now) {
                let mood = PetMood.from(snapshot: snapshot)
                for dark in [false, true] {
                    let view = OverviewView(snapshot: snapshot, errorMessage: nil, mood: mood,
                                            pet: PetImage(grid: PetSprites.frames(for: mood)[0].portrait), fixedNow: now)
                    write(render(view, dark: dark), to: dir.appendingPathComponent("popover-\(name)\(lang)\(dark ? "-dark" : "").png"))
                }
            }
            // 同时有 Codex：看 Claude（宠物跟着 Claude），和看 Codex（宠物跟着 Codex，换成龙娘）
            for (name, tabs, selected) in codexSamples(now: now) {
                let snapshot = tabs.first { $0.provider == selected }
                let mood = PetMood.from(snapshot: snapshot)
                let style = PetStyle.of(selected, claudeStyle: .classic, codexStyle: .dragon)
                for dark in [false, true] {
                    let view = OverviewView(snapshot: snapshot, errorMessage: nil, mood: mood,
                                            pet: PetImage(grid: PetSprites.frames(for: mood, style: style)[0].portrait),
                                            tabs: tabs, focus: UsageSnapshot.focus(of: tabs)?.provider, fixedNow: now)
                    write(render(view, dark: dark), to: dir.appendingPathComponent("popover-\(name)\(lang)\(dark ? "-dark" : "").png"))
                }
            }
            let estimation = EstimationInfo(sessionUSDPerPercent: 0.33, weeklyUSDPerPercent: 2.41, learnedIntervals: 86,
                                            recordedIntervals: 214, learnedUntil: now.addingTimeInterval(-300))
            // 设置页三个分页：settings（通用）、settings-claude、settings-codex
            for (name, page) in [("", SettingsView.Page.general), ("-claude", .claude), ("-codex", .codex)] {
                let view = SettingsView(settings: settings, suggestedWeeklyReset: nil, estimation: estimation, hasCodex: true,
                                        codexReadingAt: now.addingTimeInterval(-12 * 60), onBack: {}, page: page)
                write(renderInWindow(view, dark: false), to: dir.appendingPathComponent("settings\(name)\(lang).png"))
                if page == .general {
                    write(renderInWindow(view, dark: true), to: dir.appendingPathComponent("settings\(lang)-dark.png"))
                }
            }
        }
        print("预览图已写入 \(dir.path)")
    }

    // MARK: - 宠物动画表：每行一种心情，每列一帧

    static func spriteSheet(template: Bool, style: PetStyle) -> Data? {
        let moods = PetMood.allCases
        let pixel: CGFloat = 3                                  // 32×32 的头像放大 3 倍
        let cell = CGFloat(PetSprites.iconSize) * pixel + 16
        let labelWidth: CGFloat = 104
        let columns = moods.map { PetSprites.frames(for: $0, style: style).count }.max() ?? 1
        let width = labelWidth + CGFloat(columns) * cell + 8
        let height = CGFloat(moods.count) * cell + 8
        let ink: NSColor = template ? .white : NSColor(white: 0.15, alpha: 1)
        return bitmap(width: Int(width), height: Int(height)) {
            (template ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.98, alpha: 1)).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (row, mood) in moods.enumerated() {
                let y = 4 + CGFloat(row) * cell
                ("\(mood.title)\n\(mood.rawValue)" as NSString).draw(
                    at: CGPoint(x: 10, y: y + cell / 2 - 16),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: ink])
                for (col, frame) in PetSprites.frames(for: mood, style: style).enumerated() {
                    let origin = CGPoint(x: labelWidth + CGFloat(col) * cell + 8, y: y + 8)
                    (template ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                    NSRect(x: origin.x - 4, y: origin.y - 4, width: cell - 8, height: cell - 8).fill()
                    PetRenderer.draw(frame.icon, pixel: pixel, origin: origin, template: template, templateColor: .white)
                }
            }
        }
    }

    // MARK: - 模拟菜单栏（2 倍分辨率）：浅色 / 深色 × 彩色 / 单色

    static func menuBarStrip(style: PetStyle) -> Data? {
        let items: [(PetMood, String, NSColor?)] = [
            (.energetic, "27%", nil), (.normal, "63%", nil), (.tired, "82%", .systemOrange),
            (.exhausted, "96%", .systemRed), (.sleeping, "1h23m", nil), (.confused, "", nil),
        ]
        let rows: [(dark: Bool, mono: Bool)] = [(false, false), (false, true), (true, false), (true, true)]
        let barHeight: CGFloat = 24, itemWidth: CGFloat = 78, scale: CGFloat = 2
        let width = CGFloat(items.count) * itemWidth + 16
        return bitmap(width: Int(width * scale), height: Int(barHeight * CGFloat(rows.count) * scale), scale: scale) {
            for (r, row) in rows.enumerated() {
                let y = CGFloat(r) * barHeight
                (row.dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                NSRect(x: 0, y: y, width: width, height: barHeight).fill()
                let ink: NSColor = row.dark ? .white : .black
                for (i, item) in items.enumerated() {
                    let x = 10 + CGFloat(i) * itemWidth
                    NSGraphicsContext.current?.shouldAntialias = false
                    PetRenderer.draw(PetSprites.frames(for: item.0, style: style)[0].icon, pixel: 0.5, origin: CGPoint(x: x, y: y + 4),
                                     template: row.mono, templateColor: ink)
                    NSGraphicsContext.current?.shouldAntialias = true
                    (item.1 as NSString).draw(
                        at: CGPoint(x: x + 19, y: y + 4.5),
                        withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                         .foregroundColor: item.2 ?? ink])
                }
            }
        }
    }

    /// 同时显示两家时的菜单栏：宠物后面跟着那家的小图标。用的是 App 里画菜单栏的同一段代码（MenuBarIcon）
    static func menuBarGlyphStrip() -> Data? {
        let items: [(PetStyle, PetMood, ProviderID, String, NSColor?)] = [
            (.classic, .tired, .claude, "86%", .systemOrange), (.dragon, .exhausted, .codex, "93%", .systemRed),
            (.dragon, .normal, .codex, "55%", nil), (.classic, .energetic, .claude, "27%", nil),
        ]
        let rows: [(dark: Bool, mono: Bool)] = [(false, false), (false, true), (true, false), (true, true)]
        let barHeight: CGFloat = 24, itemWidth: CGFloat = 92, scale: CGFloat = 2
        let width = CGFloat(items.count) * itemWidth + 16
        return bitmap(width: Int(width * scale), height: Int(barHeight * CGFloat(rows.count) * scale), scale: scale) {
            for (r, row) in rows.enumerated() {
                let y = CGFloat(r) * barHeight
                (row.dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                NSRect(x: 0, y: y, width: width, height: barHeight).fill()
                let ink: NSColor = row.dark ? .white : .black
                NSAppearance(named: row.dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                    for (i, item) in items.enumerated() {
                        let x = 10 + CGFloat(i) * itemWidth
                        var image = MenuBarIcon.image(PetSprites.frames(for: item.1, style: item.0)[0].icon, template: row.mono,
                                                      glyph: MenuBarIcon.glyph(for: item.2))
                        if row.mono {  // 模板图画出来是黑的，这里替系统按菜单栏配色着色
                            let template = image
                            image = NSImage(size: template.size, flipped: false) { rect in
                                template.draw(in: rect)
                                ink.set()
                                rect.fill(using: .sourceAtop)
                                return true
                            }
                        }
                        let rect = NSRect(x: x, y: y + (barHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
                        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                        (" " + item.3 as NSString).draw(
                            at: CGPoint(x: rect.maxX, y: y + 4.5),
                            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                             .foregroundColor: item.4 ?? ink])
                    }
                }
            }
        }
    }

    // MARK: - 面板

    static func render<V: View>(_ view: V, dark: Bool) -> Data? {
        let content = view
            .frame(width: 340)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        var data: Data?
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.cgImage {
                data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        return data
    }

    /// 放进一个离屏窗口里渲染，开关、分段控件这些 AppKit 控件也能画出来
    static func renderInWindow<V: View>(_ view: V, dark: Bool) -> Data? {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: 340).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))  // 等 SwiftUI 画完
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    static func sampleSnapshots(now: Date) -> [(String, UsageSnapshot)] {
        func window(_ id: String, _ title: String, _ duration: TimeInterval, _ percent: Double, official: Double,
                    resetIn: TimeInterval, burn: Double, other: Double = 0, otherBurn: Double? = nil) -> UsageWindow {
            UsageWindow(id: id, title: title, duration: duration, percent: percent, official: official,
                        officialAt: now.addingTimeInterval(-9 * 60), startedAt: now.addingTimeInterval(resetIn - duration),
                        resetsAt: now.addingTimeInterval(resetIn), otherPercent: other, burnPerHour: burn, otherBurnPerHour: otherBurn,
                        burnLookback: duration > 86400 ? 86400 : 1800)
        }
        let today = ActivitySummary(
            requests: 262, tokens: 21_400_000, usd: 21.15,
            byFamily: [FamilyUsage(family: "Opus", requests: 174, usd: 14.40), FamilyUsage(family: "Sonnet", requests: 48, usd: 5.78),
                       FamilyUsage(family: "Haiku", requests: 40, usd: 0.97)],
            lastRequestAt: now)
        let week = 7 * 86400.0
        func snapshot(_ windows: [UsageWindow], notes: [String] = []) -> UsageSnapshot {
            UsageSnapshot(provider: .claude, windows: windows, generatedAt: now, officialAt: now.addingTimeInterval(-9 * 60),
                          today: today, notes: notes)
        }
        let session = UsageWindow.sessionTitle, weekly = UsageWindow.weeklyTitle
        return [
            ("calm", snapshot([window("five_hour", session, 5 * 3600, 27.3, official: 24, resetIn: 2 * 3600 + 14 * 60, burn: 6),
                               window("seven_day", weekly, week, 25.4, official: 25, resetIn: 4 * 86400 + 19 * 3600, burn: 0.7)])),
            ("busy", snapshot([window("five_hour", session, 5 * 3600, 86.2, official: 80, resetIn: 3 * 3600 + 5 * 60, burn: 42,
                                     other: 14, otherBurn: 8),
                               window("seven_day", weekly, week, 38.9, official: 38, resetIn: 4 * 86400 + 19 * 3600, burn: 5)])),
            ("limited", snapshot([window("five_hour", session, 5 * 3600, 100, official: 100, resetIn: 83 * 60, burn: 0),
                                  window("seven_day", weekly, week, 47, official: 47, resetIn: 4 * 86400 + 19 * 3600, burn: 0)])),
            ("empty", UsageSnapshot(provider: .claude, windows: [], generatedAt: now, notes: [ClaudeProvider.missingHistoryNote],
                                    hasData: false)),
        ]
    }

    /// Claude + Codex：(文件名, 两家的快照, 正在看哪家)
    static func codexSamples(now: Date) -> [(String, [UsageSnapshot], ProviderID)] {
        let claude = Dictionary(uniqueKeysWithValues: sampleSnapshots(now: now))
        let week = 7 * 86400.0
        func codex(_ percent: Double, agoMinutes: Double, resetIn: TimeInterval, burn: Double) -> UsageSnapshot {
            let window = UsageWindow(id: "seven_day", title: UsageWindow.weeklyTitle, duration: week, percent: percent,
                                     official: percent, officialAt: now.addingTimeInterval(-agoMinutes * 60),
                                     startedAt: now.addingTimeInterval(resetIn - week), resetsAt: now.addingTimeInterval(resetIn),
                                     burnPerHour: burn, burnLookback: 86400)
            return UsageSnapshot(provider: .codex, windows: [window], generatedAt: now, officialAt: window.officialAt)
        }
        return [
            ("codex", [claude["busy"]!, codex(55, agoMinutes: 12, resetIn: 2 * 86400 + 5 * 3600, burn: 0.6)], .claude),
            ("codex-tab", [claude["calm"]!, codex(93, agoMinutes: 4, resetIn: 86400 + 3 * 3600, burn: 3.8)], .codex),
        ]
    }

    // MARK: - 工具

    /// 在 y 轴朝下的位图上下文里画图，返回 PNG
    static func bitmap(width: Int, height: Int, scale: CGFloat = 1, draw: () -> Void) -> Data? {
        PetRenderer.rasterize(width: width, height: height, scale: scale, draw)?.representation(using: .png, properties: [:])
    }

    static func write(_ data: Data?, to url: URL) {
        guard let data else {
            print("渲染失败：\(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
    }
}
