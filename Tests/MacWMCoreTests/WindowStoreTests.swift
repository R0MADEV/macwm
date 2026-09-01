import Testing
@testable import MacWMCore

@Test func storeTracksFocusedWindow() {
    var store = WindowStore()
    let first = ManagedWindow(id: WindowID(1), processID: 10, title: "Terminal", frame: nil)
    let second = ManagedWindow(id: WindowID(2), processID: 11, title: "Safari", frame: nil)

    store.upsert(first)
    store.upsert(second)
    store.setFocusedWindow(second.id)

    #expect(store.windows == [first, second])
    #expect(store.focusedWindow?.id == second.id)
}

@Test func removingFocusedWindowClearsFocus() {
    var store = WindowStore()
    let window = ManagedWindow(id: WindowID(1), processID: 10, title: "Terminal", frame: nil)

    store.upsert(window)
    store.setFocusedWindow(window.id)
    store.remove(window.id)

    #expect(store.windows.isEmpty)
    #expect(store.focusedWindow == nil)
}

@Test func replacingProcessWindowsKeepsOtherProcesses() {
    var store = WindowStore()
    let oldWindow = ManagedWindow(id: WindowID(1), processID: 10, title: "Old", frame: nil)
    let otherProcessWindow = ManagedWindow(id: WindowID(2), processID: 11, title: "Other", frame: nil)
    let newWindow = ManagedWindow(id: WindowID(3), processID: 10, title: "New", frame: nil)

    store.upsert(oldWindow)
    store.upsert(otherProcessWindow)
    store.replace(windows: [newWindow], forProcessID: 10)

    #expect(store.windows == [newWindow, otherProcessWindow])
}

@Test func replacingAllWindowsUpdatesTheSnapshot() {
    var store = WindowStore()
    let oldWindow = ManagedWindow(id: WindowID(1), processID: 10, title: "Old", frame: nil)
    let newWindow = ManagedWindow(id: WindowID(2), processID: 11, title: "New", frame: nil)

    store.upsert(oldWindow)
    store.replaceAll([newWindow])

    #expect(store.windows == [newWindow])
}

@Test func togglingFocusedWindowPreservesItsFrame() {
    var store = WindowStore()
    let frame = Frame(x: 10, y: 20, width: 300, height: 400)
    let window = ManagedWindow(id: WindowID(1), processID: 10, title: "Terminal", frame: frame)

    store.upsert(window)
    store.setFocusedWindow(window.id)

    let toggled = store.toggleFocusedFloating()

    #expect(toggled?.isFloating == true)
    #expect(toggled?.frame == frame)
    #expect(store.focusedWindow?.isFloating == true)
}

@Test func refreshPreservesManualFloatingState() {
    var store = WindowStore()
    let window = ManagedWindow(id: WindowID(1), processID: 10, title: "Terminal", frame: nil, isFloating: true)
    let refreshed = ManagedWindow(id: window.id, processID: 10, title: "Terminal", frame: nil, isFloating: false)

    store.upsert(window)
    store.replace(windows: [refreshed], forProcessID: 10)

    #expect(store.windows.first?.isFloating == true)
}

@Test func cyclesFocusThroughCandidatesAndWraps() {
    var store = WindowStore()
    for id in [1, 2, 3, 4] { store.upsert(ManagedWindow(id: WindowID(UInt64(id)), processID: 1, title: "W\(id)")) }
    let candidates: Set<WindowID> = [WindowID(1), WindowID(2), WindowID(4)]

    store.setFocusedWindow(WindowID(2))
    #expect(store.cyclingWindow(forward: true, among: candidates)?.id == WindowID(4))
    #expect(store.cyclingWindow(forward: false, among: candidates)?.id == WindowID(1))

    store.setFocusedWindow(WindowID(4))
    #expect(store.cyclingWindow(forward: true, among: candidates)?.id == WindowID(1))

    store.setFocusedWindow(WindowID(3))
    #expect(store.cyclingWindow(forward: true, among: candidates)?.id == WindowID(1))
    #expect(store.cyclingWindow(forward: true, among: [])?.id == nil)
}
