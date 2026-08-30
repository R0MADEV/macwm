public struct WindowKey: Hashable, Codable, Sendable {
    public let bundleIdentifier: String
    public let title: String
    public let processID: UInt32?
    public let windowNumber: UInt32?

    public init(bundleIdentifier: String, title: String, processID: UInt32? = nil, windowNumber: UInt32? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.processID = processID
        self.windowNumber = windowNumber
    }
}
