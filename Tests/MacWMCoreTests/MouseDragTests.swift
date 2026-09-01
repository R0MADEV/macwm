import Testing
@testable import MacWMCore

private let start = Frame(x: 100, y: 200, width: 600, height: 400)

@Test func moveDragShiftsTheFrameByTheCursorDelta() {
    let drag = MouseDrag(kind: .move, startFrame: start, startX: 300, startY: 300)

    #expect(drag.frame(atX: 350, y: 280) == Frame(x: 150, y: 180, width: 600, height: 400))
    #expect(drag.frame(atX: 300, y: 300) == start)
}

@Test func resizeDragGrowsFromTheBottomRightCorner() {
    let drag = MouseDrag(kind: .resize, startFrame: start, startX: 300, startY: 300)

    #expect(drag.frame(atX: 400, y: 350) == Frame(x: 100, y: 200, width: 700, height: 450))
}

@Test func resizeDragRespectsTheMinimumSize() {
    let drag = MouseDrag(kind: .resize, startFrame: start, startX: 300, startY: 300)

    #expect(drag.frame(atX: -1000, y: -1000) == Frame(x: 100, y: 200, width: 120, height: 80))
}
