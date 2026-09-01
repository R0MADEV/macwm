import Testing
@testable import MacWMCore

private let screen = Frame(x: 0, y: 0, width: 1920, height: 1080)

@Test func parkedFrameKeepsSizeAndLeavesOnePointVisibleAtBottomRight() {
    let frame = Frame(x: 100, y: 100, width: 800, height: 600)

    #expect(frame.parked(in: screen) == Frame(x: 1919, y: 1079, width: 800, height: 600))
}

@Test func parkingIsIdempotent() {
    let parked = Frame(x: 100, y: 100, width: 800, height: 600).parked(in: screen)

    #expect(parked.parked(in: screen) == parked)
}

@Test func detectsParkedFrames() {
    let frame = Frame(x: 100, y: 100, width: 800, height: 600)

    #expect(!frame.isParked(in: screen))
    #expect(frame.parked(in: screen).isParked(in: screen))
}

@Test func partiallyOffscreenFrameIsNotParked() {
    let draggedToEdge = Frame(x: 1800, y: 900, width: 800, height: 600)

    #expect(!draggedToEdge.isParked(in: screen))
}

@Test func centeredKeepsSizeAndCentersInContainer() {
    let parked = Frame(x: 1919, y: 1079, width: 800, height: 600)
    let visible = Frame(x: 0, y: 25, width: 1920, height: 1055)

    #expect(parked.centered(in: visible) == Frame(x: 560, y: 252.5, width: 800, height: 600))
}
