import Foundation

/// 精绘的一张图：哪款形象的头像还是半身像、哪个表情。图片在 Resources/Pets/<形象>/ 里，
/// 由 design/painted/export_painted.py 从 GPT 出的原图切出来。
/// 汗珠、眼泪直接画在表情图里，不像像素画那样另外叠小道具；也没有单色版。漫画符号叠在精绘的脸上、精绘缩成剪影，都很难看
public struct PaintedPicture: Hashable, Sendable {
    public enum Part: String, Sendable {
        case icon, portrait
    }

    public let style: PetStyle
    public let part: Part
    /// 表情，比如 open-small（PaintedArt.faces）
    public let face: String

    /// Resources/Pets 下的相对路径
    public var file: String { "\(style.rawValue)/\(part.rawValue)-\(face).png" }
    /// 找不到 Resources/Pets 时是 nil
    public var url: URL? { PaintedArt.root?.appendingPathComponent(file) }
}

extension PaintedArt {
    /// 精绘图的文件夹：打包好的 App 在 Contents/Resources/Pets；开发时（swift run、make previews、make check）
    /// 可执行文件在 .build 里，从那儿往上找 QuotaPet/Resources/Pets。不写死路径，发出去的包里才不会带本机路径
    public static let root: URL? = {
        let fm = FileManager.default
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Pets"), fm.fileExists(atPath: url.path) { return url }
        var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            guard let current = dir else { break }
            let url = current.appendingPathComponent("Resources/Pets")
            if fm.fileExists(atPath: url.path) { return url }
            dir = current.deletingLastPathComponent()
        }
        return nil
    }()
}

/// 宠物的一张图：像素画或精绘，加上显示多大
public struct PetPicture: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case pixel(PixelGrid)
        case painted(PaintedPicture)
    }

    public let content: Content
    /// 显示成多大（正方形的边长，pt）
    public let points: Double

    /// 像素画的画布；精绘时是 nil
    public var grid: PixelGrid? {
        if case .pixel(let grid) = content { return grid }
        return nil
    }

    /// 有没有单色版：只有像素画有（单色模式靠挖空皮肤色），精绘开了「单色宠物」也照样画彩色
    public var hasMonochrome: Bool { grid != nil }
}
