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
