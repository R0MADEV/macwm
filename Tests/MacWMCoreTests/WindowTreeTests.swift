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

@Test func automaticDirectionSplitsAlongTheLongerSide() {
    let wide = Frame(x: 0, y: 0, width: 1000, height: 600)

    #expect(leaf(1).automaticSplitDirection(for: WindowID(1), in: wide) == .vertical)
    #expect(v(0.5, leaf(1), leaf(2)).automaticSplitDirection(for: WindowID(2), in: wide) == .horizontal)
    #expect(v(0.5, leaf(1), leaf(2)).lastLeaf == WindowID(2))
}
