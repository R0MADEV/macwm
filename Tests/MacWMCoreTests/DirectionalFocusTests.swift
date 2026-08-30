import Testing
@testable import MacWMCore

@Test func findsNearestWindowToTheLeft() {
    var store = WindowStore()
    let focused = ManagedWindow(id: WindowID(1), processID: 1, title: "Focused", frame: Frame(x: 400, y: 200, width: 200, height: 200))
    let nearest = ManagedWindow(id: WindowID(2), processID: 1, title: "Nearest", frame: Frame(x: 100, y: 210, width: 200, height: 180))
    let farther = ManagedWindow(id: WindowID(3), processID: 1, title: "Farther", frame: Frame(x: -400, y: 200, width: 200, height: 200))
    let right = ManagedWindow(id: WindowID(4), processID: 1, title: "Right", frame: Frame(x: 700, y: 200, width: 200, height: 200))

    for window in [focused, nearest, farther, right] {
        store.upsert(window)
    }
    store.setFocusedWindow(focused.id)

    #expect(store.window(in: .left)?.id == nearest.id)
}

@Test func ignoresWindowsWithoutFrames() {
    var store = WindowStore()
    let focused = ManagedWindow(id: WindowID(1), processID: 1, title: "Focused", frame: Frame(x: 400, y: 200, width: 200, height: 200))
    let unknown = ManagedWindow(id: WindowID(2), processID: 1, title: "Unknown", frame: nil)

    store.upsert(focused)
    store.upsert(unknown)
    store.setFocusedWindow(focused.id)

    #expect(store.window(in: .left) == nil)
}
