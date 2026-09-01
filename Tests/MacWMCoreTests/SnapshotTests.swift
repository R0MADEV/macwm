import Testing
@testable import MacWMCore

@Test func stateSnapshotDescribesWorkspacesAndWindows() {
    var store = WindowStore()
    store.upsert(ManagedWindow(id: WindowID(1), processID: 1, appName: "Code", title: "main.swift", frame: Frame(x: 0, y: 0, width: 800, height: 600), bundleIdentifier: "com.microsoft.VSCode"))
    store.upsert(ManagedWindow(id: WindowID(2), processID: 2, appName: "Safari", title: "Docs", isFloating: true))
    store.setFocusedWindow(WindowID(1))
    var workspaces = WorkspaceManager(count: 3, activeWorkspace: 2)
    workspaces.assign(WindowID(1), to: 2)
    workspaces.assign(WindowID(2), to: 3)

    let snapshot = StateSnapshot(store: store, workspaces: workspaces, layout: "bsp", mode: "default")

    #expect(snapshot.workspace == 2)
    #expect(snapshot.focused?.title == "main.swift")
    #expect(snapshot.workspaces == [
        WorkspaceSnapshot(id: 1, active: false, windows: 0),
        WorkspaceSnapshot(id: 2, active: true, windows: 1),
        WorkspaceSnapshot(id: 3, active: false, windows: 1)
    ])
    #expect(snapshot.windows.map(\.app) == ["Code", "Safari"])
    #expect(snapshot.windows[1].floating == true)
    #expect(snapshot.windows[1].workspace == 3)
}

@Test func snapshotsEncodeAsSingleLineJSONWithSortedKeys() {
    let json = StateJSON.encode(WorkspaceSnapshot(id: 2, active: true, windows: 3))

    #expect(json == #"{"active":true,"id":2,"windows":3}"#)
}
