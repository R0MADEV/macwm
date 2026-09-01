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
