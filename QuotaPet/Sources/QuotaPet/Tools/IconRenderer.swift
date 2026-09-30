import AppKit
import QuotaPetCore

/// QuotaPet --render-icon <dir>：用宠物的像素画生成 App 图标（.iconset，再用 iconutil 转成 .icns）
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
            let frame = PetSprites.frames(for: .normal)[0]  // 经典款，像素画
            if size >= 128, let portrait = frame.portrait.grid {
                // 大图标：半身像按整数倍放大（像素画保持锐利），贴着底边
                let pixel = (rect.width / CGFloat(PetSprites.portraitSize)).rounded(.down)
                let width = pixel * CGFloat(PetSprites.portraitSize)
                NSGraphicsContext.current?.shouldAntialias = false
                PetRenderer.draw(portrait, pixel: pixel, origin: CGPoint(x: ((size - width) / 2).rounded(), y: rect.maxY - width),
                                 template: false, templateColor: .black)
            } else {
                // 小图标：头像缩放到铺满
                PetRenderer.draw(frame.icon, in: rect, template: false, templateColor: .black)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
