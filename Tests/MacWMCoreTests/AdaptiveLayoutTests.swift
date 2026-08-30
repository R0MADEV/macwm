import Testing
@testable import MacWMCore

@Test func adaptiveTreeAlternatesDirections() {
    let tree = BSPLayout.tree(for: [WindowID(1), WindowID(2), WindowID(3)])!

    #expect(tree.isAdaptive)
}
