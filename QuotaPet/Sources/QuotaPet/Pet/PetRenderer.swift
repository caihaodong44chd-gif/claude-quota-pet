import AppKit
import QuotaPetCore

/// 把宠物画成 NSImage：每个表情一张图，这里只负责读图
enum PetRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    /// 显示成 picture.points 大小的图
    static func image(_ picture: PetPicture) -> NSImage { image(picture, points: picture.points) }

    /// 显示成 points×points 的图。图片本身是 2 倍图，改一下显示大小就行，不用重画；每张图每个尺寸只读一次盘。
    /// 图没找到时是一块洋红，一眼看得出
    private static func image(_ picture: PetPicture, points: Double) -> NSImage {
        let key = "\(picture.file)@\(points)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let size = NSSize(width: points, height: points)
        let image = picture.url.flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: size, flipped: false) { rect in
            NSColor.magenta.setFill()
            rect.fill()
            return true
        }
        image.size = size
        cache.setObject(image, forKey: key)
        return image
    }

    /// 画到当前（y 轴朝下的）上下文里的 rect 中
    static func draw(_ picture: PetPicture, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.shouldAntialias = true
        image(picture, points: rect.width).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                                hints: [.interpolation: NSImageInterpolation.high.rawValue])
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
}
