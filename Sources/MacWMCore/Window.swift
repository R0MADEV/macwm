public struct WindowID: Hashable, Sendable, Codable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(processID: UInt32, elementHash: Int) {
        rawValue = UInt64(processID) << 32 | UInt64(truncatingIfNeeded: elementHash)
    }
}

public struct ManagedWindow: Equatable, Sendable {
    public let id: WindowID
    public let processID: UInt32
    public let appName: String
    public let title: String
    public let frame: Frame?
    public let subrole: String
    public let bundleIdentifier: String
    public let windowNumber: UInt32?
    public let isFloating: Bool
    /// Minimized, or owned by an application hidden with Cmd+H. Hidden windows leave the layout.
    public let isHidden: Bool

    public init(
        id: WindowID,
        processID: UInt32,
        appName: String = "",
        title: String,
        frame: Frame? = nil,
        subrole: String = "AXStandardWindow",
        bundleIdentifier: String = "",
        isFloating: Bool = false,
        isHidden: Bool = false,
        windowNumber: UInt32? = nil
    ) {
        self.id = id
        self.processID = processID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.subrole = subrole
        self.bundleIdentifier = bundleIdentifier
        self.windowNumber = windowNumber
        self.isFloating = isFloating
        self.isHidden = isHidden
    }

    /// Only standard windows tile. Dialogs, panels and transient popups such as
    /// Chrome's omnibox dropdown report other subroles and must float.
    public var isTileable: Bool {
        let isStandardWindow = subrole == "AXStandardWindow"
        return isStandardWindow && !isFloating && !isHidden
    }

    public var persistentKey: WindowKey {
        WindowKey(bundleIdentifier: bundleIdentifier, title: title, processID: processID, windowNumber: windowNumber)
    }
}

public struct WindowStore: Sendable {
    private var values: [WindowID: ManagedWindow] = [:]
    private var focusedID: WindowID?

    public init() {}

    public var windows: [ManagedWindow] {
        values.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var persistedFloating: [WindowKey: Bool] {
        Dictionary(uniqueKeysWithValues: windows.filter { $0.isFloating }.map { ($0.persistentKey, true) })
    }

    public var focusedWindow: ManagedWindow? {
        guard let focusedID else { return nil }
        return values[focusedID]
    }

    public func window(in direction: Direction, among candidateIDs: Set<WindowID>? = nil) -> ManagedWindow? {
        guard let focusedWindow, let focusedFrame = focusedWindow.frame else { return nil }
        let focusedCenter = center(of: focusedFrame)

        return windows
            .filter { candidate in
                let isCandidate = candidateIDs?.contains(candidate.id) ?? true
                guard candidate.id != focusedWindow.id, isCandidate, let frame = candidate.frame else { return false }
                return isInDirection(center(of: frame), from: focusedCenter, direction: direction)
            }
            .min { lhs, rhs in
                guard let lhsFrame = lhs.frame, let rhsFrame = rhs.frame else { return false }
                return score(center(of: lhsFrame), from: focusedCenter, direction: direction)
                    < score(center(of: rhsFrame), from: focusedCenter, direction: direction)
            }
    }

    public mutating func upsert(_ window: ManagedWindow) {
        values[window.id] = merged(window, preservingFloatingStateFrom: values[window.id])
    }

    public mutating func updateFrame(_ frame: Frame, for id: WindowID) {
        guard let window = values[id] else { return }
        values[id] = ManagedWindow(
            id: window.id,
            processID: window.processID,
            appName: window.appName,
            title: window.title,
            frame: frame,
            subrole: window.subrole,
            bundleIdentifier: window.bundleIdentifier,
            isFloating: window.isFloating,
            isHidden: window.isHidden,
            windowNumber: window.windowNumber
        )
    }

    public mutating func setFloating(_ floating: Bool, for id: WindowID) {
        guard let window = values[id] else { return }
        values[id] = ManagedWindow(
            id: window.id,
            processID: window.processID,
            appName: window.appName,
            title: window.title,
            frame: window.frame,
            subrole: window.subrole,
            bundleIdentifier: window.bundleIdentifier,
            isFloating: floating,
            isHidden: window.isHidden,
            windowNumber: window.windowNumber
        )
    }

    public mutating func replace(windows: [ManagedWindow], forProcessID processID: UInt32) {
        let previousWindows = values
        values = values.filter { $0.value.processID != processID }
        for window in windows {
            values[window.id] = merged(window, preservingFloatingStateFrom: previousWindows[window.id])
        }
        if let focusedID, values[focusedID] == nil {
            self.focusedID = nil
        }
    }

    public mutating func replaceAll(_ windows: [ManagedWindow]) {
        let previousFocusedID = focusedID
        let previousWindows = values
        values = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, merged($0, preservingFloatingStateFrom: previousWindows[$0.id])) })
        focusedID = previousFocusedID.flatMap { values[$0] == nil ? nil : $0 }
    }

    public mutating func remove(_ id: WindowID) {
        values.removeValue(forKey: id)
        guard focusedID == id else { return }
        focusedID = nil
    }

    public mutating func setFocusedWindow(_ id: WindowID?) {
        guard let id else {
            focusedID = nil
            return
        }
        guard values[id] != nil else { return }
        focusedID = id
    }

    @discardableResult
    public mutating func toggleFocusedFloating() -> ManagedWindow? {
        guard let focusedID, let window = values[focusedID] else { return nil }
        let updated = ManagedWindow(
            id: window.id,
            processID: window.processID,
            appName: window.appName,
            title: window.title,
            frame: window.frame,
            subrole: window.subrole,
            bundleIdentifier: window.bundleIdentifier,
            isFloating: !window.isFloating,
            isHidden: window.isHidden,
            windowNumber: window.windowNumber
        )
        values[focusedID] = updated
        return updated
    }

    private func merged(_ window: ManagedWindow, preservingFloatingStateFrom existing: ManagedWindow?) -> ManagedWindow {
        guard let existing else { return window }
        return ManagedWindow(
            id: window.id,
            processID: window.processID,
            appName: window.appName,
            title: window.title,
            frame: window.frame,
            subrole: window.subrole,
            bundleIdentifier: window.bundleIdentifier,
            isFloating: existing.isFloating,
            isHidden: window.isHidden,
            windowNumber: window.windowNumber
        )
    }

    private func center(of frame: Frame) -> (x: Double, y: Double) {
        (frame.x + frame.width / 2, frame.y + frame.height / 2)
    }

    private func isInDirection(
        _ candidate: (x: Double, y: Double),
        from origin: (x: Double, y: Double),
        direction: Direction
    ) -> Bool {
        switch direction {
        case .left: return candidate.x < origin.x
        case .right: return candidate.x > origin.x
        case .up: return candidate.y < origin.y
        case .down: return candidate.y > origin.y
        }
    }

    private func score(
        _ candidate: (x: Double, y: Double),
        from origin: (x: Double, y: Double),
        direction: Direction
    ) -> Double {
        let primary: Double
        let secondary: Double

        switch direction {
        case .left, .right:
            primary = abs(candidate.x - origin.x)
            secondary = abs(candidate.y - origin.y)
        case .up, .down:
            primary = abs(candidate.y - origin.y)
            secondary = abs(candidate.x - origin.x)
        }

        return primary + secondary * 0.5
    }
}
