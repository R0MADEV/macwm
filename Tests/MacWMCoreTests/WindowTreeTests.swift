import Testing
@testable import MacWMCore

@Test func swappingWindowsKeepsTheTreeShape() {
    let tree = WindowTree.split(
        direction: .vertical,
        ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .leaf(WindowID(2))
    )

    let swapped = tree.swapped(WindowID(1), WindowID(2))

    #expect(swapped == .split(
        direction: .vertical,
        ratio: 0.5,
        first: .leaf(WindowID(2)),
        second: .leaf(WindowID(1))
    ))
}

@Test func togglingSplitFlipsOnlyTheParentOfTheWindow() {
    let tree = WindowTree.split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(3)))
    )

    let toggled = tree.togglingSplit(containing: WindowID(3))

    #expect(toggled == .split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(3)))
    ))
    #expect(tree.togglingSplit(containing: WindowID(1)).windowIDs == tree.windowIDs)
    #expect(tree.togglingSplit(containing: WindowID(99)) == tree)
    #expect(WindowTree.leaf(WindowID(1)).togglingSplit(containing: WindowID(1)) == .leaf(WindowID(1)))
}

private func v(_ ratio: Double, _ first: WindowTree, _ second: WindowTree) -> WindowTree { .split(direction: .vertical, ratio: ratio, first: first, second: second) }
private func h(_ ratio: Double, _ first: WindowTree, _ second: WindowTree) -> WindowTree { .split(direction: .horizontal, ratio: ratio, first: first, second: second) }
private func leaf(_ id: UInt64) -> WindowTree { .leaf(WindowID(id)) }

@Test func insertingSplitsTheTargetLeaf() {
    let tree = v(0.5, leaf(1), leaf(2))

    #expect(tree.inserting(WindowID(3), at: WindowID(2), direction: .horizontal) == v(0.5, leaf(1), h(0.5, leaf(2), leaf(3))))
    #expect(tree.inserting(WindowID(3), at: WindowID(99), direction: .horizontal) == tree)
}

@Test func removingCollapsesTheParentSplit() {
    let tree = v(0.5, leaf(1), h(0.3, leaf(2), leaf(3)))

    #expect(tree.removing(WindowID(2)) == v(0.5, leaf(1), leaf(3)))
    #expect(tree.removing(WindowID(1)) == h(0.3, leaf(2), leaf(3)))
    #expect(tree.removing(WindowID(99)) == tree)
    #expect(leaf(1).removing(WindowID(1)) == nil)
}

@Test func adjustingRatioGrowsTheLeafSideOfItsNearestSplit() {
    let tree = v(0.5, leaf(1), h(0.5, leaf(2), leaf(3)))

    #expect(tree.adjustingRatio(for: WindowID(1), by: 0.1) == v(0.6, leaf(1), h(0.5, leaf(2), leaf(3))))
    #expect(tree.adjustingRatio(for: WindowID(3), by: 0.1) == v(0.5, leaf(1), h(0.4, leaf(2), leaf(3))))
    #expect(tree.adjustingRatio(for: WindowID(99), by: 0.1) == tree)
    #expect(leaf(1).adjustingRatio(for: WindowID(1), by: 0.1) == leaf(1))
}

@Test func adjustingRatioStaysWithinBounds() {
    let tree = v(0.85, leaf(1), leaf(2))

    #expect(tree.adjustingRatio(for: WindowID(1), by: 0.2) == v(0.9, leaf(1), leaf(2)))
    #expect(tree.adjustingRatio(for: WindowID(2), by: 0.9) == v(0.1, leaf(1), leaf(2)))
}

@Test func mouseResizeAdjustsTheNearestSplitOfEachAxis() {
    let tree = v(0.5, leaf(1), h(0.5, leaf(2), leaf(3)))
    let frame = Frame(x: 0, y: 0, width: 1000, height: 600)

    // Window 3 sits in the right half and at the bottom: dragging right shrinks
    // the left column, dragging up makes it shorter.
    #expect(tree.resizing(WindowID(3), deltaX: 100, deltaY: -60, in: frame) == v(0.4, leaf(1), h(0.6, leaf(2), leaf(3))))
    // Window 1 has no horizontal split above it, so the vertical delta is ignored.
    #expect(tree.resizing(WindowID(1), deltaX: 100, deltaY: 100, in: frame) == v(0.6, leaf(1), h(0.5, leaf(2), leaf(3))))
    #expect(tree.resizing(WindowID(99), deltaX: 100, deltaY: 100, in: frame) == tree)
}

@Test func gridOfFourIsTwoByTwo() {
    let windows: [WindowID] = (1...4).map { WindowID(UInt64($0)) }
    let frames: [Frame] = Array((WindowTree.grid(for: windows, in: screen)?.frames(in: screen) ?? [:]).values)

    #expect(frames.count == 4)
    #expect(frames.allSatisfy { $0.width == 800 && $0.height == 500 })
}

@Test func gridOfThreeGivesTheLastRowTheFullWidth() {
    let frames = WindowTree.grid(for: (1...3).map { WindowID(UInt64($0)) }, in: screen)?.frames(in: screen)

    #expect(frames?[WindowID(1)] == Frame(x: 0, y: 0, width: 800, height: 500))
    #expect(frames?[WindowID(2)] == Frame(x: 800, y: 0, width: 800, height: 500))
    #expect(frames?[WindowID(3)] == Frame(x: 0, y: 500, width: 1600, height: 500))
}

@Test func gridSpreadsTenWindowsOverEvenRows() {
    let windows: [WindowID] = (1...10).map { WindowID(UInt64($0)) }
    let frames: [Frame] = Array((WindowTree.grid(for: windows, in: screen)?.frames(in: screen) ?? [:]).values)
    let windowsPerRow = Dictionary(grouping: frames) { Int($0.y.rounded()) }.sorted { $0.key < $1.key }.map(\.value.count)

    #expect(windowsPerRow == [4, 3, 3])
}

@Test func leafOrderReadsTheTreeLeftToRight() {
    #expect(v(0.5, leaf(2), h(0.5, leaf(3), leaf(1))).leafOrder == [WindowID(2), WindowID(3), WindowID(1)])
}

private let screen = Frame(x: 0, y: 0, width: 1600, height: 1000)

@Test func gridGivesWindowsTheirMinimumWidthAndSharesTheRest() {
    let wide = Frame(x: 0, y: 0, width: 2400, height: 600)
    let windows: [WindowID] = [1, 2, 3].map { WindowID(UInt64($0)) }
    let frames = WindowTree.grid(for: windows, in: wide, minimumSizes: [WindowID(3): Size(width: 1000, height: 0)])?.frames(in: wide) ?? [:]

    #expect(abs((frames[WindowID(1)]?.width ?? 0) - 700) < 0.01)
    #expect(abs((frames[WindowID(2)]?.width ?? 0) - 700) < 0.01)
    #expect(abs((frames[WindowID(3)]?.width ?? 0) - 1000) < 0.01)
}

@Test func gridGivesRowsTheHeightTheirTallestWindowNeeds() {
    let windows: [WindowID] = (1...4).map { WindowID(UInt64($0)) }
    let frames = WindowTree.grid(for: windows, in: screen, minimumSizes: [WindowID(2): Size(width: 0, height: 700)])?.frames(in: screen) ?? [:]

    #expect(abs((frames[WindowID(1)]?.height ?? 0) - 700) < 0.01)
    #expect(abs((frames[WindowID(3)]?.height ?? 0) - 300) < 0.01)
}

@Test func fittingMovesTheSplitOnTheEdgeTheUserDragged() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 600)
    let tree = v(0.5, leaf(1), leaf(2))

    // Window 2's left edge dragged from 500 to 300.
    #expect(tree.fitting(WindowID(2), to: Frame(x: 300, y: 0, width: 700, height: 600), in: frame) == v(0.3, leaf(1), leaf(2)))
    // Window 1's right edge dragged from 500 to 700.
    #expect(tree.fitting(WindowID(1), to: Frame(x: 0, y: 0, width: 700, height: 600), in: frame) == v(0.7, leaf(1), leaf(2)))
}

@Test func fittingMovesTheNearestSplitOfEachDraggedEdge() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 600)
    let tree = v(0.5, leaf(1), h(0.5, leaf(2), leaf(3)))

    // Window 3 (500,300 500x300): top edge to 200 and left edge to 400.
    let fitted = tree.fitting(WindowID(3), to: Frame(x: 400, y: 200, width: 600, height: 400), in: frame)

    #expect(fitted == v(0.4, leaf(1), h(1.0 / 3.0, leaf(2), leaf(3))))
}

@Test func fittingIgnoresEdgesOnTheScreenBorder() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 600)
    let tree = v(0.5, leaf(1), leaf(2))

    #expect(tree.fitting(WindowID(1), to: Frame(x: 50, y: 0, width: 450, height: 600), in: frame) == tree)
}
