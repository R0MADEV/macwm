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

private let screenFrame = Frame(x: 0, y: 0, width: 1600, height: 1000)

@Test func newWindowsJoinTheGridAfterTheExistingOnes() {
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(.split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(1))), for: 1)

    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3)], in: 1, frame: screenFrame)

    #expect(tree?.leafOrder == [WindowID(2), WindowID(1), WindowID(3)])
    #expect(tree == WindowTree.grid(for: [WindowID(2), WindowID(1), WindowID(3)], in: screenFrame))
}

@Test func closedWindowsLeaveTheGridWhichCloses() {
    var manager = WorkspaceManager(count: 1)
    for id in [1, 2, 3] { manager.assign(WindowID(UInt64(id)), to: 1) }
    _ = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2), WindowID(3)], in: 1, frame: screenFrame)

    manager.remove(WindowID(2))
    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(3)], in: 1, frame: screenFrame)

    #expect(tree == WindowTree.grid(for: [WindowID(1), WindowID(3)], in: screenFrame))
}

@Test func manualRatiosSurviveWhileTheWindowSetIsUnchanged() {
    let resized = WindowTree.split(direction: .vertical, ratio: 0.3, first: .leaf(WindowID(1)), second: .leaf(WindowID(2)))
    var manager = WorkspaceManager(count: 1)
    manager.setLayoutTree(resized, for: 1)

    #expect(manager.validatedLayoutTree(for: [WindowID(1), WindowID(2)], in: 1, frame: screenFrame) == resized)
}

@Test func theGridFillsTheScreenWithoutOverlapHoweverManyWindowsAreOpen() {
    var manager = WorkspaceManager(count: 1)
    var windows: [WindowID] = []
    for id in 1...16 {
        windows.append(WindowID(UInt64(id)))
        let frames = Array((manager.validatedLayoutTree(for: windows, in: 1, frame: screenFrame)?.frames(in: screenFrame) ?? [:]).values)
        let totalArea = frames.reduce(0) { $0 + $1.width * $1.height }
        let fitsTheScreen = frames.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x + $0.width <= 1600.5 && $0.y + $0.height <= 1000.5 }
        #expect(frames.count == id && fitsTheScreen && abs(totalArea - 1600 * 1000) < 1, "\(id) windows")
    }
}

@Test func learnedMinimumSizesReshapeTheGrid() {
    let wide = Frame(x: 0, y: 0, width: 2400, height: 600)
    let windows: [WindowID] = [1, 2, 3].map { WindowID(UInt64($0)) }
    var manager = WorkspaceManager(count: 1)
    for window in windows { manager.assign(window, to: 1) }
    _ = manager.validatedLayoutTree(for: windows, in: 1, frame: wide)

    let learnedWider = manager.recordMinimumSize(Size(width: 1000, height: 0), for: WindowID(3))
    let learnedNarrower = manager.recordMinimumSize(Size(width: 900, height: 0), for: WindowID(3))
    #expect(learnedWider)
    #expect(!learnedNarrower)
    let frames = manager.validatedLayoutTree(for: windows, in: 1, frame: wide)?.frames(in: wide) ?? [:]

    #expect(abs((frames[WindowID(3)]?.width ?? 0) - 1000) < 0.01)
}

@Test func minimumSizesIgnoreSubPointNoise() {
    var manager = WorkspaceManager(count: 1)
    let first = manager.recordMinimumSize(Size(width: 500, height: 375), for: WindowID(1))
    let noise = manager.recordMinimumSize(Size(width: 500.5, height: 375.5), for: WindowID(1))

    #expect(first)
    #expect(!noise)
}

@Test func handResizesThatCrushAWindowBelowItsMinimumAreRejected() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 1000)
    let tree = WindowTree.split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(2)))
    var manager = WorkspaceManager(count: 1)
    for id in [1, 2] { manager.assign(WindowID(UInt64(id)), to: 1) }
    manager.setLayoutTree(tree, for: 1)
    _ = manager.recordMinimumSize(Size(width: 0, height: 400), for: WindowID(2))

    let crushes = manager.fitTiled(WindowID(1), to: Frame(x: 0, y: 0, width: 1000, height: 900), frame: frame, in: 1)
    let fits = manager.fitTiled(WindowID(1), to: Frame(x: 0, y: 0, width: 1000, height: 600), frame: frame, in: 1)

    #expect(!crushes)
    #expect(fits)
    #expect(manager.storedLayoutTree(for: 1) == .split(direction: .horizontal, ratio: 0.6, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))))
}

@Test func aStoredTreeThatCrushesAWindowIsLaidOutAgain() {
    let frame = Frame(x: 0, y: 0, width: 1000, height: 1000)
    let crushed = WindowTree.split(direction: .horizontal, ratio: 0.95, first: .leaf(WindowID(1)), second: .leaf(WindowID(2)))
    var manager = WorkspaceManager(count: 1)
    for id in [1, 2] { manager.assign(WindowID(UInt64(id)), to: 1) }
    manager.setLayoutTree(crushed, for: 1)
    _ = manager.recordMinimumSize(Size(width: 0, height: 400), for: WindowID(2))

    let tree = manager.validatedLayoutTree(for: [WindowID(1), WindowID(2)], in: 1, frame: frame)

    #expect(tree != crushed)
    #expect((tree?.frames(in: frame)[WindowID(2)]?.height ?? 0) >= 400)
}

@Test func knowsWhichWindowsHaveALearnedMinimum() {
    var manager = WorkspaceManager(count: 1)
    _ = manager.recordMinimumSize(Size(width: 1000, height: 0), for: WindowID(1))

    #expect(manager.hasMinimumSize(WindowID(1)))
    #expect(!manager.hasMinimumSize(WindowID(2)))
}
