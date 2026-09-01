import Testing
@testable import MacWMCore

@Test func bspCreatesTwoColumnsWithGaps() {
    let windows = [WindowID(1), WindowID(2)]
    let frames = BSPLayout.frames(
        for: windows,
        in: Frame(x: 0, y: 0, width: 1000, height: 600),
        outerGap: 10,
        innerGap: 10
    )

    #expect(frames[windows[0]] == Frame(x: 10, y: 10, width: 485, height: 580))
    #expect(frames[windows[1]] == Frame(x: 505, y: 10, width: 485, height: 580))
}

@Test func bspKeepsAllWindowsInsideLayout() {
    let windows = [WindowID(1), WindowID(2), WindowID(3)]
    let frames = BSPLayout.frames(
        for: windows,
        in: Frame(x: 0, y: 0, width: 1200, height: 800),
        outerGap: 8,
        innerGap: 8
    )

    #expect(frames.count == windows.count)
    #expect(frames.values.allSatisfy { $0.width > 0 && $0.height > 0 })
}

@Test func smartGapsDropAllGapsForASingleWindow() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 600)

    #expect(LayoutEngine.gaps(outer: 8, inner: 8, smart: true, windowCount: 1) == (0, 0))
    #expect(LayoutEngine.gaps(outer: 8, inner: 8, smart: true, windowCount: 2) == (8, 8))
    #expect(LayoutEngine.gaps(outer: 8, inner: 8, smart: false, windowCount: 1) == (8, 8))
    #expect(BSPLayout.frames(for: [WindowID(1)], in: frame, outerGap: 0, innerGap: 0)[WindowID(1)] == frame)
}
