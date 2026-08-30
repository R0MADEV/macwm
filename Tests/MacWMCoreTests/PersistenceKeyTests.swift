import Testing
@testable import MacWMCore

@Test func restoredPlacementAppliesToMatchingWindow() {
    let key = WindowKey(bundleIdentifier: "com.apple.Terminal", title: "Shell")
    var manager = WorkspaceManager(assignments: [key: 3])
    let window = ManagedWindow(
        id: WindowID(1),
        processID: 10,
        title: "Shell",
        frame: nil,
        bundleIdentifier: "com.apple.Terminal"
    )

    manager.register(window)

    #expect(manager.workspace(for: window.id) == 3)
}
