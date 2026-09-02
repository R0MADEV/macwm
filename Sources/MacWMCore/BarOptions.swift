/// Look and content of macwm-bar: size, colors and which modules go where,
/// in the spirit of waybar's modules-left/center/right.
public struct BarOptions: Equatable, Sendable, Codable {
    public static let knownModules: Set<String> = ["workspaces", "layout", "window", "agents", "vpn", "media", "network", "cpu", "battery", "clock", "settings", "spacer"]
    public static let verticalThickness: Double = 48

    public var height: Double
    public var fontSize: Double
    /// Hex color for the active workspace and highlights.
    public var accent: String
    /// Background opacity over the blurred desktop, 0 to 1.
    public var opacity: Double
    public var hideEmptyWorkspaces: Bool
    public var left: [String]
    public var center: [String]
    public var right: [String]

    public init(
        height: Double = 34,
        fontSize: Double = 11,
        accent: String = "#5e81ac",
        opacity: Double = 0.85,
        hideEmptyWorkspaces: Bool = false,
        left: [String] = ["workspaces", "layout"],
        center: [String] = ["window"],
        right: [String] = ["agents", "network", "cpu", "battery", "clock", "settings"]
    ) {
        self.height = max(20, height)
        self.fontSize = max(8, fontSize)
        self.accent = accent
        self.opacity = min(max(opacity, 0), 1)
        self.hideEmptyWorkspaces = hideEmptyWorkspaces
        self.left = left
        self.center = center
        self.right = right
    }

    public static func isValidModuleList(_ modules: [String]) -> Bool {
        modules.allSatisfy { knownModules.contains($0) }
    }
}
