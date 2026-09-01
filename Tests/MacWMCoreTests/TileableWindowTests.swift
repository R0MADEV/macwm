import Testing
@testable import MacWMCore

@Test func unknownSubrolesRemainTileable() {
    let window = ManagedWindow(id: WindowID(1), processID: 1, title: "Main", frame: nil, subrole: "")

    #expect(window.isTileable)
}

@Test func auxiliarySubrolesRemainFloating() {
    let window = ManagedWindow(id: WindowID(1), processID: 1, title: "Dialog", frame: nil, subrole: "AXDialog")

    #expect(!window.isTileable)
}

@Test func minimizedOrHiddenWindowsLeaveTheLayout() {
    let window = ManagedWindow(id: WindowID(1), processID: 1, title: "Main", isHidden: true)

    #expect(!window.isTileable)
}

@Test func storeRefreshUpdatesHiddenStateButKeepsFloating() {
    var store = WindowStore()
    store.upsert(ManagedWindow(id: WindowID(1), processID: 1, title: "Main", isFloating: true))

    store.upsert(ManagedWindow(id: WindowID(1), processID: 1, title: "Main", isHidden: true))

    #expect(store.windows.first?.isHidden == true)
    #expect(store.windows.first?.isFloating == true)
}
