import AppKit
import QuotaPetCore

/// 把像素画渲染成 NSImage
enum PetRenderer {
    /// 按 ASCII 查颜色（调色板来自 PetArt，和 design/ 里的 Python 原型一致）
    private static let colors: [NSColor?] = {
        var table = [NSColor?](repeating: nil, count: 128)
        for (ch, hex) in PetArt.palette {
            guard let ascii = ch.asciiValue else { continue }
            table[Int(ascii)] = NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                                        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return table
    }()

    static func color(for code: UInt8) -> NSColor {
        (code < 128 ? colors[Int(code)] : nil) ?? .magenta
    }

    /// 单色模式下挖空的像素：脸（皮肤、腮红）和眼睛高光。头发、衣服、五官保持实心，剪影里看得出是一张脸
    private static let cutouts = Set("SsPW".utf8)

    static func isCutout(_ code: UInt8) -> Bool { cutouts.contains(code) }

    /// pixel：每个像素画多大（point）。菜单栏头像用 0.5（32 格 = 16pt，Retina 上一格一个物理像素）。
    /// template = 单色模板图，由系统按菜单栏配色着色
    static func image(_ grid: PixelGrid, pixel: CGFloat, template: Bool) -> NSImage {
        let size = NSSize(width: CGFloat(grid.width) * pixel, height: CGFloat(grid.height) * pixel)
        let image = NSImage(size: size, flipped: true) { _ in
            // 一格正好落在整数个物理像素上时关掉抗锯齿，像素边缘才锐利；
            // 外接的 1 倍屏上半个点画不出来，要靠抗锯齿混色，不然会丢像素
            let deviceScale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
            let devicePixels = pixel * deviceScale
            NSGraphicsContext.current?.shouldAntialias = abs(devicePixels - devicePixels.rounded()) > 0.01
            draw(grid, pixel: pixel, origin: .zero, template: template, templateColor: .black)
            return true
        }
        image.isTemplate = template
        return image
    }

    /// 直接画到当前（y 轴朝下的）上下文里
    static func draw(_ grid: PixelGrid, pixel: CGFloat, origin: CGPoint, template: Bool, templateColor: NSColor) {
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let code = grid[x, y]
                if code == 0 || (template && isCutout(code)) { continue }
                (template ? templateColor : color(for: code)).setFill()
                NSRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel).fill()
            }
        }
    }
}
