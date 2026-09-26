import Foundation

/// 一款形象的调色板：字符（ASCII）→ 0xRRGGBB。每款形象各有一张，同一个字符（比如头发 H）在不同形象里是不同的颜色
public struct PetPalette: Hashable, Sendable {
    /// 下标是 ASCII 码；没定义的字符是 nil
    private let colors: [UInt32?]

    public init(_ table: [Character: UInt32]) {
        var colors = [UInt32?](repeating: nil, count: 128)
        for (ch, rgb) in table {
            if let ascii = ch.asciiValue { colors[Int(ascii)] = rgb }
        }
        self.colors = colors
    }

    public subscript(code: UInt8) -> UInt32? { code < 128 ? colors[Int(code)] : nil }
}

/// 像素画布。每格存一个调色板字符（ASCII），0 表示透明；颜色查 palette。
public struct PixelGrid: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [UInt8]
    public var palette: PetPalette

    /// palette 必须给：不带调色板的画布画出来全是洋红
    public init(width: Int, height: Int, palette: PetPalette) {
        self.width = width
        self.height = height
        self.palette = palette
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
