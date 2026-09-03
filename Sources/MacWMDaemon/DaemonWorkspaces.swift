import Dispatch
import MacWMCore

final class DaemonWorkspaces: @unchecked Sendable {
    var value: WorkspaceManager

    init(count: Int = 9, assignments: [WindowKey: Int] = [:], activeWorkspace: Int = 1, trees: [Int: WindowTree] = [:], layouts: [Int: LayoutKind] = [:]) {
        value = WorkspaceManager(count: count, assignments: assignments, activeWorkspace: activeWorkspace, trees: trees, layouts: layouts)
    }
}

/// Uptime of the last workspace switch, shared with the focus handler.
final class LastSwitch: @unchecked Sendable {
    var nanoseconds: UInt64 = 0
    var secondsAgo: Double { Double(DispatchTime.now().uptimeNanoseconds &- nanoseconds) / 1_000_000_000 }
}

/// Frames of windows parked off-screen by workspace switching, keyed by window,
/// so floating and maximized windows return to their previous position.
final class ParkedFrames: @unchecked Sendable {
    var value: [WindowID: Frame] = [:]
}
