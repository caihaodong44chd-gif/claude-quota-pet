import AppKit
import QuotaPetCore

/// 把像素画渲染成 NSImage
enum PetRenderer {
    /// 按这款形象的调色板查颜色（和 design/ 里的 Python 原型一致）；没定义的字符画成洋红，一眼看得出
    static func color(for code: UInt8, in palette: PetPalette) -> NSColor {
        guard let hex = palette[code] else { return .magenta }
        return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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

    /// 画成固定分辨率的位图，每格 scale×scale 个像素。要缩放显示时用它：
    /// image(...) 是显示时按目标分辨率现画的，缩到一格不是整数个物理像素时，格子之间会露出细缝
    static func bitmap(_ grid: PixelGrid, scale: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: grid.width * scale, height: grid.height * scale))
        let rep = rasterize(width: grid.width * scale, height: grid.height * scale) {
            NSGraphicsContext.current?.shouldAntialias = false
            draw(grid, pixel: CGFloat(scale), origin: .zero, template: false, templateColor: .black)
        }
        if let rep { image.addRepresentation(rep) }
        return image
    }

    /// 在一张 sRGB 位图上画（y 轴朝下，和 draw 的约定一致）；scale：每个点画几个像素
    static func rasterize(width: Int, height: Int, scale: CGFloat = 1, _ body: () -> Void) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = base.cgContext
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 直接画到当前（y 轴朝下的）上下文里
    static func draw(_ grid: PixelGrid, pixel: CGFloat, origin: CGPoint, template: Bool, templateColor: NSColor) {
        var colors = [NSColor?](repeating: nil, count: 128)  // 这张图里用到的颜色，每种只建一次
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let code = grid[x, y]
                if code == 0 || (template && isCutout(code)) { continue }
                if template {
                    templateColor.setFill()
                } else if code < 128 {
                    let fill = colors[Int(code)] ?? color(for: code, in: grid.palette)
                    colors[Int(code)] = fill
                    fill.setFill()
                } else {
                    NSColor.magenta.setFill()
                }
                NSRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel).fill()
            }
        }
    }
}
