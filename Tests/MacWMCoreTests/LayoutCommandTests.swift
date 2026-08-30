import Testing
@testable import MacWMCore

@Test func layoutCommandAcceptsAllLayouts() {
    #expect(Command.parse(["layout", "bsp"]) == .layout(.bsp))
    #expect(Command.parse(["layout", "stack"]) == .layout(.stack))
    #expect(Command.parse(["layout", "monocle"]) == .layout(.monocle))
    #expect(Command.parse(["layout", "master"]) == .layout(.masterStack))
    #expect(Command.parse(["layout", "invalid"]) == nil)
}

@Test func workspaceLayoutsAreKeptPerWorkspace() {
    var manager = WorkspaceManager(count: 2)
    manager.setLayout(.stack, for: 1)
    manager.setLayout(.monocle, for: 2)

    #expect(manager.layout(for: 1) == .stack)
    #expect(manager.layout(for: 2) == .monocle)
    #expect(manager.persistedLayouts == [1: .stack, 2: .monocle])
}
