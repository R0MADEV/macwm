import Testing
@testable import MacWMCore

@Test func standardWindowsAreTileable() {
    let window = ManagedWindow(id: WindowID(1), processID: 1, title: "Main", frame: nil, subrole: "AXStandardWindow")

    #expect(window.isTileable)
}

@Test func unknownSubrolesFloat() {
    // Chrome's omnibox popup and similar transient windows report no standard subrole.
    let popup = ManagedWindow(id: WindowID(1), processID: 1, title: "", frame: nil, subrole: "")
    let unknown = ManagedWindow(id: WindowID(2), processID: 1, title: "", frame: nil, subrole: "AXUnknown")

    #expect(!popup.isTileable)
    #expect(!unknown.isTileable)
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

@Test func nonResizableWindowsFloat() {
    let fixed = ManagedWindow(id: WindowID(1), processID: 1, title: "Game", isResizable: false)

    #expect(!fixed.isTileable)
    #expect(ManagedWindow(id: WindowID(2), processID: 1, title: "Editor").isTileable)
}
