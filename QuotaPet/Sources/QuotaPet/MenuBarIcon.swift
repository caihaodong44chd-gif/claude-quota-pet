import AppKit
import QuotaPetCore

/// 菜单栏上的图：宠物头像。同时显示几家时，后面跟一个小图标，看得出数字是哪家的
enum MenuBarIcon {
    /// 每家一个系统自带的通用符号（不用各家的商标）
    static func glyph(for provider: ProviderID) -> String {
        switch provider {
        case .claude: return "asterisk"
        case .codex: return "terminal.fill"
        }
    }

    static func image(_ pet: PixelGrid, template: Bool, glyph: String?) -> NSImage {
        let petImage = PetRenderer.image(pet, pixel: 0.5, template: template)
        let shape = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy)
        guard let glyph, let base = NSImage(systemSymbolName: glyph, accessibilityDescription: nil),
              let symbol = base.withSymbolConfiguration(shape) else { return petImage }
        let gap: CGFloat = 3
        let size = NSSize(width: petImage.size.width + gap + symbol.size.width, height: max(petImage.size.height, symbol.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            petImage.draw(in: NSRect(x: 0, y: (size.height - petImage.size.height) / 2,
                                     width: petImage.size.width, height: petImage.size.height))
            let glyphRect = NSRect(x: petImage.size.width + gap, y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height)
            if template {
                symbol.draw(in: glyphRect)  // 整张是模板图，系统按菜单栏配色着色
            } else {
                // 彩色宠物不是模板图，系统不会替它着色：小图标自己用菜单栏文字的颜色（画的时候才按深浅色取）。
                // labelColor 带一点透明，小图标笔画细，会显得发灰，所以用不透明的
                let ink = (NSColor.labelColor.usingColorSpace(.sRGB) ?? .black).withAlphaComponent(1)
                // 新配置会整个替换掉旧的，所以字号、粗细要和颜色合在一起
                base.withSymbolConfiguration(shape.applying(NSImage.SymbolConfiguration(paletteColors: [ink])))?.draw(in: glyphRect)
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
