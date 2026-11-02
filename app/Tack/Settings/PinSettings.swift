import AppKit

/// Settings › Pins, stored in UserDefaults. The Settings view binds to the keys with @AppStorage;
/// PinManager applies changes to every pin when UserDefaults changes.
enum PinSettings {
    static let showBorderKey = "pins.showBorder"
    /// "#RRGGBB" in sRGB; empty means Tack's accent colour.
    static let borderColorKey = "pins.borderColor"

    static let defaultBorderColor = NSColor(named: "AccentColor") ?? .systemTeal

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showBorderKey: true])
    }

    static var showBorder: Bool { UserDefaults.standard.bool(forKey: showBorderKey) }

    static var borderColor: NSColor {
        color(fromHex: UserDefaults.standard.string(forKey: borderColorKey) ?? "") ?? defaultBorderColor
    }

    static func color(fromHex hex: String) -> NSColor? {
        guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(from color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
