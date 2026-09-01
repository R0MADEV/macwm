import Foundation

/// JSON-friendly view of the daemon state for `query` commands and the
/// events socket, so external bars and scripts never parse the text status.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public let id: UInt64
    public let app: String
    public let bundleIdentifier: String
    public let title: String
    public let workspace: Int
    public let floating: Bool
    public let hidden: Bool
    public let focused: Bool
    public let frame: Frame?
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public let id: Int
    public let active: Bool
    public let windows: Int

    public init(id: Int, active: Bool, windows: Int) {
        self.id = id
        self.active = active
        self.windows = windows
    }
}

public struct StateSnapshot: Codable, Equatable, Sendable {
    public let workspace: Int
    public let layout: String
    public let mode: String
    public let focused: WindowSnapshot?
    public let workspaces: [WorkspaceSnapshot]
    public let windows: [WindowSnapshot]

    public init(store: WindowStore, workspaces manager: WorkspaceManager, layout: String, mode: String) {
        let focusedID = store.focusedWindow?.id
        windows = store.windows.map { window in
            WindowSnapshot(
                id: window.id.rawValue,
                app: window.appName,
                bundleIdentifier: window.bundleIdentifier,
                title: window.title,
                workspace: manager.workspace(for: window.id),
                floating: window.isFloating,
                hidden: window.isHidden,
                focused: window.id == focusedID,
                frame: window.frame
            )
        }
        workspace = manager.activeWorkspace
        self.layout = layout
        self.mode = mode
        focused = windows.first { $0.focused }
        workspaces = (1...manager.count).map { id in
            WorkspaceSnapshot(id: id, active: id == manager.activeWorkspace, windows: manager.windows(in: id).count)
        }
    }
}

/// One event on the events socket: a full state snapshot after every change.
public struct StateEvent: Codable, Equatable, Sendable {
    public let event: String
    public let state: StateSnapshot

    public init(event: String, state: StateSnapshot) {
        self.event = event
        self.state = state
    }
}

public enum StateJSON {
    /// Single line, sorted keys, so shell scripts can grep it and diffs stay stable.
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
