import AppKit
import SwiftUI

/// Tack's single-colour glyph (menu bar, notch, pin toolbar): a template image, so macOS and SwiftUI tint it.
enum Glyph {
    static let name = "TackGlyph"

    static func image(size: CGFloat) -> some View {
        Image(name).resizable().frame(width: size, height: size)
    }

    static func menuBarImage() -> NSImage? {
        let image = NSImage(named: name)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        image?.accessibilityDescription = "Tack"
        return image
    }
}
