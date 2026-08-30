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
