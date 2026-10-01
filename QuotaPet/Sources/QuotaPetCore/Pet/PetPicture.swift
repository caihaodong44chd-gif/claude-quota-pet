import Foundation

/// 宠物的一张图：哪款形象的头像还是半身像、哪个表情。图片在 Resources/Pets/<形象>/ 里，
/// 由 design/painted/export_painted.py 从 GPT 出的原图切出来。
/// 汗珠、眼泪直接画在表情图里，不另外叠小道具（漫画符号浮在精绘的脸上很突兀）；也没有单色版（缩成剪影很难看）
public struct PetPicture: Hashable, Sendable {
    public enum Part: String, Sendable {
        case icon, portrait
    }

    public let style: PetStyle
    public let part: Part
    /// 表情，比如 open-small（PaintedArt.faces）
    public let face: String

    /// 显示成多大（正方形的边长，pt）；图片是它的 2 倍
    public var points: Double { part == .icon ? PetSprites.iconPoints : PetSprites.portraitPoints }
    /// Resources/Pets 下的相对路径
    public var file: String { "\(style.rawValue)/\(part.rawValue)-\(face).png" }
    /// 找不到 Resources/Pets 时是 nil
    public var url: URL? { PaintedArt.root?.appendingPathComponent(file) }
}

extension PaintedArt {
    /// 宠物图的文件夹：打包好的 App 在 Contents/Resources/Pets；开发时（swift run、make previews、make check）
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
