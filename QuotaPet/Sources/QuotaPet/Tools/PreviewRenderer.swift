import AppKit
import SwiftUI
import QuotaPetCore

/// QuotaPet --render-previews <dir>：把宠物动画、菜单栏效果和面板渲染成 PNG，
/// 不用真的启动 App 就能检查设计。
@MainActor
enum PreviewRenderer {
    static func renderAll(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(spriteSheet(template: false), to: dir.appendingPathComponent("pet-sheet.png"))
        write(spriteSheet(template: true), to: dir.appendingPathComponent("pet-sheet-mono.png"))
        write(menuBarStrip(), to: dir.appendingPathComponent("menubar.png"))

        let now = Date()
        for (name, snapshot) in sampleSnapshots(now: now) {
            let mood = PetMood.from(snapshot: snapshot)
            for dark in [false, true] {
                let view = OverviewView(snapshot: snapshot, errorMessage: nil, mood: mood,
                                        pet: PetImage(grid: PetSprites.frames(for: mood)[0].portrait), fixedNow: now)
                write(render(view, dark: dark), to: dir.appendingPathComponent("popover-\(name)\(dark ? "-dark" : "").png"))
            }
        }
        // 再用本机真实数据渲染一张，和点开菜单栏看到的一样（宠物停在第一帧）
        if let live = try? ClaudeProvider().snapshot(now: now) {
            let mood = PetMood.from(snapshot: live)
            for dark in [false, true] {
                let view = OverviewView(snapshot: live, errorMessage: nil, mood: mood,
                                        pet: PetImage(grid: PetSprites.frames(for: mood)[0].portrait), fixedNow: now)
                write(render(view, dark: dark), to: dir.appendingPathComponent("popover-live\(dark ? "-dark" : "").png"))
            }
        }
        let settings = SettingsView(settings: AppSettings(), suggestedWeeklyReset: nil,
                                    estimation: EstimationInfo(sessionUSDPerPercent: 0.33, weeklyUSDPerPercent: 2.41,
                                                               learnedIntervals: 86, recordedIntervals: 214,
                                                               learnedUntil: now.addingTimeInterval(-300)),
                                    onBack: {})
        write(renderInWindow(settings, dark: false), to: dir.appendingPathComponent("settings.png"))
        write(renderInWindow(settings, dark: true), to: dir.appendingPathComponent("settings-dark.png"))
        print("预览图已写入 \(dir.path)")
    }

    // MARK: - 宠物动画表：每行一种心情，每列一帧

    static func spriteSheet(template: Bool) -> Data? {
        let moods = PetMood.allCases
        let pixel: CGFloat = 3                                  // 32×32 的头像放大 3 倍
        let cell = CGFloat(PetSprites.iconSize) * pixel + 16
        let labelWidth: CGFloat = 104
        let columns = moods.map { PetSprites.frames(for: $0).count }.max() ?? 1
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
                for (col, frame) in PetSprites.frames(for: mood).enumerated() {
                    let origin = CGPoint(x: labelWidth + CGFloat(col) * cell + 8, y: y + 8)
                    (template ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                    NSRect(x: origin.x - 4, y: origin.y - 4, width: cell - 8, height: cell - 8).fill()
                    PetRenderer.draw(frame.icon, pixel: pixel, origin: origin, template: template, templateColor: .white)
                }
            }
        }
    }

    // MARK: - 模拟菜单栏（2 倍分辨率）：浅色 / 深色 × 彩色 / 单色

    static func menuBarStrip() -> Data? {
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
                    PetRenderer.draw(PetSprites.frames(for: item.0)[0].icon, pixel: 0.5, origin: CGPoint(x: x, y: y + 4),
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
            UsageWindow(id: id, title: title, shortTitle: "", duration: duration, percent: percent, official: official,
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
        return [
            ("calm", snapshot([window("five_hour", "5 小时会话", 5 * 3600, 27.3, official: 24, resetIn: 2 * 3600 + 14 * 60, burn: 6),
                               window("seven_day", "本周额度", week, 25.4, official: 25, resetIn: 4 * 86400 + 19 * 3600, burn: 0.7)])),
            ("busy", snapshot([window("five_hour", "5 小时会话", 5 * 3600, 86.2, official: 80, resetIn: 3 * 3600 + 5 * 60, burn: 42,
                                     other: 14, otherBurn: 8),
                               window("seven_day", "本周额度", week, 38.9, official: 38, resetIn: 4 * 86400 + 19 * 3600, burn: 5)])),
            ("limited", snapshot([window("five_hour", "5 小时会话", 5 * 3600, 100, official: 100, resetIn: 83 * 60, burn: 0),
                                  window("seven_day", "本周额度", week, 47, official: 47, resetIn: 4 * 86400 + 19 * 3600, burn: 0)])),
            ("empty", UsageSnapshot(provider: .claude, windows: [], generatedAt: now,
                                    notes: ["没找到 Claude 桌面端的额度记录。装好并登录 Claude 桌面端后，它每 15 分钟会记一次官方额度。"],
                                    hasData: false)),
        ]
    }

    // MARK: - 工具

    /// 在 y 轴朝下的位图上下文里画图，返回 PNG
    static func bitmap(width: Int, height: Int, scale: CGFloat = 1, draw: () -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = base.cgContext
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func write(_ data: Data?, to url: URL) {
        guard let data else {
            print("渲染失败：\(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
    }
}
