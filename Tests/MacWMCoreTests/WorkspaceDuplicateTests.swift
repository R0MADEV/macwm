import Testing
@testable import MacWMCore

@Test func duplicateWindowKeyUsesActiveWorkspaceForNewWindow() {
    let key = WindowKey(bundleIdentifier: "com.microsoft.VSCode", title: "Welcome", processID: 42)
    var manager = WorkspaceManager(assignments: [key: 1])
    let first = ManagedWindow(id: WindowID(1), processID: 42, title: "Welcome", bundleIdentifier: key.bundleIdentifier)
    let second = ManagedWindow(id: WindowID(2), processID: 42, title: "Welcome", bundleIdentifier: key.bundleIdentifier)

    manager.register(first, rules: [], defaultWorkspace: 1)
    manager.register(second, rules: [], defaultWorkspace: 2)

    #expect(manager.workspace(for: first.id) == 1)
    #expect(manager.workspace(for: second.id) == 2)
}

@Test func windowNumberDisambiguatesSameTitleAcrossRestarts() {
    let firstKey = WindowKey(bundleIdentifier: "com.example.Editor", title: "Untitled", windowNumber: 101)
    let secondKey = WindowKey(bundleIdentifier: "com.example.Editor", title: "Untitled", windowNumber: 202)
    var manager = WorkspaceManager(assignments: [firstKey: 2, secondKey: 3])
    let first = ManagedWindow(id: WindowID(1), processID: 10, title: "Untitled", frame: nil, bundleIdentifier: "com.example.Editor", windowNumber: 101)
    let second = ManagedWindow(id: WindowID(2), processID: 11, title: "Untitled", frame: nil, bundleIdentifier: "com.example.Editor", windowNumber: 202)

    manager.register(first, rules: [])
    manager.register(second, rules: [])

    #expect(manager.workspace(for: first.id) == 2)
    #expect(manager.workspace(for: second.id) == 3)
}
