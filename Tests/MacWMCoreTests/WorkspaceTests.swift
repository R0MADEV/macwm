import Testing
@testable import MacWMCore

@Test func windowsStartInWorkspaceOne() {
    var manager = WorkspaceManager()
    manager.register(WindowID(1))

    #expect(manager.workspace(for: WindowID(1)) == 1)
    #expect(manager.windows(in: 1) == [WindowID(1)])
}

@Test func assigningWindowMovesItBetweenWorkspaces() {
    var manager = WorkspaceManager()
    let window = WindowID(1)

    manager.assign(window, to: 3)

    #expect(manager.workspace(for: window) == 3)
    #expect(manager.windows(in: 1).isEmpty)
    #expect(manager.windows(in: 3) == [window])
}

@Test func invalidWorkspaceDoesNotChangeActiveWorkspace() {
    var manager = WorkspaceManager(count: 3)

    manager.activate(9)

    #expect(manager.activeWorkspace == 1)
}

@Test func restoresActiveWorkspaceAndKeepsProcessSpecificKeysDistinct() {
    let first = WindowKey(bundleIdentifier: "com.example.App", title: "Same", processID: 10)
    let second = WindowKey(bundleIdentifier: "com.example.App", title: "Same", processID: 11)
    var manager = WorkspaceManager(count: 3, assignments: [first: 2, second: 3], activeWorkspace: 3)
    let firstWindow = ManagedWindow(id: WindowID(1), processID: 10, title: "Same", frame: nil, bundleIdentifier: "com.example.App")
    let secondWindow = ManagedWindow(id: WindowID(2), processID: 11, title: "Same", frame: nil, bundleIdentifier: "com.example.App")
    manager.register(firstWindow)
    manager.register(secondWindow)

    #expect(manager.activeWorkspace == 3)
    #expect(manager.persistedAssignments.count == 2)
    #expect(manager.workspace(for: firstWindow.id) == 2)
    #expect(manager.workspace(for: secondWindow.id) == 3)
}

@Test func removingWindowClearsItsPersistedAssignment() {
    let key = WindowKey(bundleIdentifier: "com.example.App", title: "Closed", processID: 10)
    var manager = WorkspaceManager(assignments: [key: 2])
    let window = ManagedWindow(id: WindowID(10), processID: 10, title: "Closed", bundleIdentifier: key.bundleIdentifier)

    manager.register(window, rules: [])
    manager.remove(window.id)

    #expect(manager.persistedAssignments[key] == nil)
}
