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
