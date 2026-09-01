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

@Test func reopenedWindowsOpenOnTheActiveWorkspace() {
    let closed = ManagedWindow(id: WindowID(1), processID: 10, title: "Finder", bundleIdentifier: "com.apple.finder")
    var manager = WorkspaceManager(count: 3, activeWorkspace: 1)
    manager.register(closed, rules: [], defaultWorkspace: 3)
    manager.remove(closed.id)

    let reopened = ManagedWindow(id: WindowID(2), processID: 10, title: "Finder", bundleIdentifier: "com.apple.finder")
    manager.register(reopened, rules: [], defaultWorkspace: 1)

    #expect(manager.workspace(for: reopened.id) == 1)
}

@Test func newWindowsIgnorePersistedAssignmentsButRulesStillApply() {
    let window = ManagedWindow(id: WindowID(1), processID: 10, title: "Finder", bundleIdentifier: "com.apple.finder")
    var manager = WorkspaceManager(count: 3, assignments: [window.persistentKey: 3], activeWorkspace: 1)

    manager.register(window, rules: [], defaultWorkspace: 1, restorePersisted: false)
    #expect(manager.workspace(for: window.id) == 1)

    let ruled = ManagedWindow(id: WindowID(2), processID: 10, title: "Mail", bundleIdentifier: "com.apple.mail")
    manager.register(ruled, rules: [WindowRule(bundleIdentifier: "com.apple.mail", float: false, workspace: 2)], defaultWorkspace: 1, restorePersisted: false)
    #expect(manager.workspace(for: ruled.id) == 2)
}

@Test func remembersLastFocusedWindowPerWorkspace() {
    var manager = WorkspaceManager(count: 3)
    manager.assign(WindowID(1), to: 1)
    manager.assign(WindowID(2), to: 1)
    manager.assign(WindowID(3), to: 2)

    manager.recordFocus(WindowID(1))
    manager.recordFocus(WindowID(3))
    manager.recordFocus(WindowID(2))

    #expect(manager.lastFocusedWindow(in: 1) == WindowID(2))
    #expect(manager.lastFocusedWindow(in: 2) == WindowID(3))
    #expect(manager.lastFocusedWindow(in: 3) == nil)
}

@Test func forgetsLastFocusedWindowWhenItMovesOrCloses() {
    var manager = WorkspaceManager(count: 3)
    manager.assign(WindowID(1), to: 1)
    manager.recordFocus(WindowID(1))

    manager.assign(WindowID(1), to: 2)
    #expect(manager.lastFocusedWindow(in: 1) == nil)

    manager.recordFocus(WindowID(1))
    manager.remove(WindowID(1))
    #expect(manager.lastFocusedWindow(in: 2) == nil)
}

@Test func remembersThePreviousWorkspaceForBackAndForth() {
    var manager = WorkspaceManager(count: 5, activeWorkspace: 1)

    #expect(manager.previousWorkspace == nil)
    manager.activate(3)
    #expect(manager.previousWorkspace == 1)
    manager.activate(3)
    #expect(manager.previousWorkspace == 1)
    manager.activate(5)
    #expect(manager.previousWorkspace == 3)
}
