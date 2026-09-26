import Foundation

/// 像素画布。每格存一个调色板字符（ASCII），0 表示透明。
public struct PixelGrid: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [UInt8]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        cells = Array(repeating: 0, count: width * height)
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { contains(x, y) ? cells[y * width + x] : 0 }
        set { if contains(x, y) { cells[y * width + x] = newValue } }
    }

    private func contains(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// 把一块字符画盖到 (x, y) 上，'.' 是透明的；超出画布的部分会被裁掉
    public mutating func stamp(_ rows: [String], x: Int, y: Int) {
        for (dy, row) in rows.enumerated() {
            for (dx, c) in row.utf8.enumerated() where c != UInt8(ascii: ".") {
                self[x + dx, y + dy] = c
            }
        }
    }

    /// 调试用：转回字符画
    public var rows: [String] {
        (0..<height).map { y in
            String((0..<width).map { x in
                let c = self[x, y]
                return c == 0 ? "." : Character(UnicodeScalar(c))
            })
        }
    }
}
