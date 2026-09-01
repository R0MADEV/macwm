import Foundation
import Testing
@testable import MacWMCore

@Test func verticalSplitProducesTwoFrames() {
    let tree = WindowTree.split(
        direction: .vertical,
        ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .leaf(WindowID(2))
    )

    let frames = tree.frames(in: Frame(x: 0, y: 0, width: 1000, height: 800))

    #expect(frames[WindowID(1)] == Frame(x: 0, y: 0, width: 500, height: 800))
    #expect(frames[WindowID(2)] == Frame(x: 500, y: 0, width: 500, height: 800))
}

@Test func windowTreeRoundTripsAndIsRestoredForMatchingWorkspaceWindows() throws {
    let tree = WindowTree.split(
        direction: .vertical,
        ratio: 0.65,
        first: .leaf(WindowID(1)),
        second: .leaf(WindowID(2))
    )
    let data = try JSONEncoder().encode(tree)
    #expect(try JSONDecoder().decode(WindowTree.self, from: data) == tree)

    let manager = WorkspaceManager(count: 2, trees: [2: tree])
    #expect(manager.layoutTree(for: [WindowID(1), WindowID(2)], in: 2) == tree)
}

@Test func staleWorkspaceTreeIsRebuilt() {
    let stale = WindowTree.leaf(WindowID(99))
    let manager = WorkspaceManager(count: 2, trees: [1: stale])

    #expect(manager.layoutTree(for: [WindowID(1), WindowID(2)], in: 1) != stale)
}

@Test func invalidTreeIsReplacedOnlyWhenAllTileableWindowIDsMatch() {
    let stale = WindowTree.split(
        direction: .vertical,
        ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .leaf(WindowID(99))
    )
    var manager = WorkspaceManager(count: 1, trees: [1: stale])

    let replacement = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2)], in: 1)

    #expect(replacement?.windowIDs == [WindowID(1), WindowID(2)])
    #expect(manager.storedLayoutTree(for: 1) == replacement)
}

@Test func duplicateTreeLeavesAreInvalidEvenWhenTheIDSetMatches() {
    let duplicate = WindowTree.split(
        direction: .vertical,
        ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .leaf(WindowID(1))
    )
    var manager = WorkspaceManager(count: 1, trees: [1: duplicate])

    let replacement = manager.validatedLayoutTree(for: [WindowID(1)], in: 1)

    #expect(replacement == .leaf(WindowID(1)))
    #expect(manager.storedLayoutTree(for: 1) == replacement)
}

@Test func emptyTileableSetRemovesPersistedTree() {
    let stale = WindowTree.leaf(WindowID(99))
    var manager = WorkspaceManager(count: 1, trees: [1: stale])

    #expect(manager.validatedLayoutTree(for: [], in: 1) == nil)
    #expect(manager.storedLayoutTree(for: 1) == nil)
}

private let wideFrame = Frame(x: 0, y: 0, width: 1000, height: 600)

@Test func newWindowsSplitTheLastFocusedLeafInsteadOfRebuilding() {
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(.split(direction: .vertical, ratio: 0.3, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))), for: 1)
    manager.assign(WindowID(1), to: 1)
    manager.assign(WindowID(2), to: 1)
    manager.recordFocus(WindowID(1))

    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3)], in: 1, frame: wideFrame)

    // Window 1 is 300x600 in a 1000x600 frame, so the new window goes below it and the 0.3 ratio survives.
    #expect(tree == .split(
        direction: .vertical, ratio: 0.3,
        first: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(3))),
        second: .leaf(WindowID(2))
    ))
}

@Test func closedWindowsCollapseTheirSplit() {
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(.split(
        direction: .vertical, ratio: 0.3,
        first: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(3))),
        second: .leaf(WindowID(2))
    ), for: 1)

    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2)], in: 1, frame: wideFrame)

    #expect(tree == .split(direction: .vertical, ratio: 0.3, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))))
}

@Test func preselectedDirectionAppliesToTheNextWindowOnly() {
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(.split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))), for: 1)
    manager.assign(WindowID(1), to: 1)
    manager.assign(WindowID(2), to: 1)
    manager.recordFocus(WindowID(2))
    manager.preselect(.vertical, in: 1)

    let first = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3)], in: 1, frame: wideFrame)
    #expect(first == .split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(3)))
    ))

    // Window 2 is now 250x600, so without a preselection the next window goes below it.
    let second = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3), WindowID(4)], in: 1, frame: wideFrame)
    #expect(second == .split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(
            direction: .vertical, ratio: 0.5,
            first: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(4))),
            second: .leaf(WindowID(3))
        )
    ))
}

@Test func windowsWithoutAFocusedTargetJoinTheLastLeaf() {
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(.split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))), for: 1)

    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3)], in: 1, frame: wideFrame)

    #expect(tree == .split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(3)))
    ))
}
