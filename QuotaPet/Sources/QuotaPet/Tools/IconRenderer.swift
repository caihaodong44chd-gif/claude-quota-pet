import AppKit
import QuotaPetCore

/// QuotaPet --render-icon <dir>：用经典款的宠物生成 App 图标（.iconset，再用 iconutil 转成 .icns）
@MainActor
enum IconRenderer {
    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let specs: [(Int, String)] = [
            (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
            (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
        ]
        for (pixels, name) in specs {
            PreviewRenderer.write(icon(pixels: pixels), to: dir.appendingPathComponent("icon_\(name).png"))
        }
    }

    /// 大图标用的高清半身像：design/painted/export_painted.py 给配置了 appIcon 的那款导出，只在打包时用
    private static let appIconPortrait = PaintedArt.root.flatMap {
        NSImage(contentsOf: $0.deletingLastPathComponent().appendingPathComponent("AppIcon.png"))
    }

    static func icon(pixels: Int) -> Data? {
        PreviewRenderer.bitmap(width: pixels, height: pixels) {
            let size = CGFloat(pixels)
            let inset = size * 0.1
            let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
            let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
            NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.96, blue: 0.92, alpha: 1),
                       ending: NSColor(srgbRed: 1.0, green: 0.84, blue: 0.75, alpha: 1))?.draw(in: tile, angle: 90)

            NSGraphicsContext.saveGraphicsState()
            tile.addClip()
            let frame = PetSprites.frames(for: .normal)[0]  // 经典款
            if size >= 128, let portrait = appIconPortrait {
                // 大图标：高清半身像铺满，贴着底边（圆角会切掉肩膀两边）
                portrait.draw(in: NSRect(x: rect.minX, y: rect.maxY - rect.width, width: rect.width, height: rect.width),
                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                              hints: [.interpolation: NSImageInterpolation.high.rawValue])
            } else {
                // 小图标：头像缩放到铺满
                PetRenderer.draw(frame.icon, in: rect, template: false, templateColor: .black)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
