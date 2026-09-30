import AppKit
import QuotaPetCore

/// 画精绘宠物：每个表情一张图，这里只负责读图
enum PaintedRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    /// 显示成 points×points 的图。图片本身是 2 倍图，改一下显示大小就行，不用重画；每张图只读一次盘。
    /// 图没找到时是一块洋红，一眼看得出
    static func image(_ picture: PaintedPicture, points: Double) -> NSImage {
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
}
