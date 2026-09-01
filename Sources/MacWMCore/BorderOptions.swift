/// Focus border drawn by the daemon around the focused window.
public struct BorderOptions: Equatable, Sendable, Codable {
    public var enabled: Bool
    public var width: Double
    /// Hex color, `#rrggbb` or `#rrggbbaa`.
    public var color: String

    public init(enabled: Bool = false, width: Double = 3, color: String = "#5e81ac") {
        self.enabled = enabled
        self.width = max(0, width)
        self.color = color
    }

    public static func isValidColor(_ text: String) -> Bool { rgba(text) != nil }

    /// Components in 0...1 for `#rrggbb` or `#rrggbbaa`.
    public static func rgba(_ text: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        let alpha = hasAlpha ? Double(value & 0xff) / 255 : 1
        return (Double((rgb >> 16) & 0xff) / 255, Double((rgb >> 8) & 0xff) / 255, Double(rgb & 0xff) / 255, alpha)
    }
}
