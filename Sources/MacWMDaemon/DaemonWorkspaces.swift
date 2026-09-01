import MacWMCore

final class DaemonWorkspaces: @unchecked Sendable {
    var value: WorkspaceManager

    init(count: Int = 9, assignments: [WindowKey: Int] = [:], activeWorkspace: Int = 1, trees: [Int: WindowTree] = [:], layouts: [Int: LayoutKind] = [:]) {
        value = WorkspaceManager(count: count, assignments: assignments, activeWorkspace: activeWorkspace, trees: trees, layouts: layouts)
    }
}

/// Frames of windows parked off-screen by workspace switching, keyed by window,
/// so floating and maximized windows return to their previous position.
final class ParkedFrames: @unchecked Sendable {
    var value: [WindowID: Frame] = [:]
}
