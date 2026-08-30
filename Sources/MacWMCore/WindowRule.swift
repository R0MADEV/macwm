public struct WindowRule: Equatable, Sendable {
    public let bundleIdentifier: String
    public let title: String?
    public let subrole: String?
    public let float: Bool
    public let workspace: Int?
    public let center: Bool
    public let width: Double?
    public let height: Double?

    public init(bundleIdentifier: String, title: String? = nil, subrole: String? = nil, float: Bool, workspace: Int? = nil, center: Bool = false, width: Double? = nil, height: Double? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.subrole = subrole
        self.float = float
        self.workspace = workspace
        self.center = center
        self.width = width
        self.height = height
    }

    public func matches(bundleIdentifier: String, title: String? = nil, subrole: String? = nil) -> Bool {
        guard self.bundleIdentifier == bundleIdentifier else { return false }
        guard self.title == nil || self.title == title else { return false }
        guard self.subrole == nil || self.subrole == subrole else { return false }
        return true
    }
}
