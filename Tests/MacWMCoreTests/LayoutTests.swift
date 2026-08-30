import Testing
@testable import MacWMCore

@Test func stackLaysWindowsVerticallyWithGaps() {
    let ids = [WindowID(1), WindowID(2), WindowID(3)]
    let frames = LayoutEngine.frames(for: ids, layout: .stack, in: Frame(x: 0, y: 0, width: 100, height: 100), outerGap: 10, innerGap: 5)

    #expect(frames[WindowID(1)] == Frame(x: 10, y: 10, width: 80, height: 23.333333333333332))
    #expect(frames[WindowID(2)] == Frame(x: 10, y: 38.33333333333333, width: 80, height: 23.333333333333332))
    #expect(frames[WindowID(3)] == Frame(x: 10, y: 66.66666666666666, width: 80, height: 23.333333333333332))
}

@Test func monocleGivesEveryWindowTheSameUsableFrame() {
    let frames = LayoutEngine.frames(for: [WindowID(1), WindowID(2)], layout: .monocle, in: Frame(x: 0, y: 0, width: 100, height: 80), outerGap: 8, innerGap: 4)

    #expect(frames[WindowID(1)] == Frame(x: 8, y: 8, width: 84, height: 64))
    #expect(frames[WindowID(2)] == Frame(x: 8, y: 8, width: 84, height: 64))
}

@Test func masterStackUsesHalfForMasterAndStacksTheRest() {
    let ids = [WindowID(1), WindowID(2), WindowID(3)]
    let frames = LayoutEngine.frames(for: ids, layout: .masterStack, in: Frame(x: 0, y: 0, width: 100, height: 100), outerGap: 10, innerGap: 5)

    #expect(frames[WindowID(1)] == Frame(x: 10, y: 10, width: 37.5, height: 80))
    #expect(frames[WindowID(2)] == Frame(x: 52.5, y: 10, width: 37.5, height: 37.5))
    #expect(frames[WindowID(3)] == Frame(x: 52.5, y: 52.5, width: 37.5, height: 37.5))
}
