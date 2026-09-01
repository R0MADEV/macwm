import Testing
@testable import MacWMCore

private func manager() -> WorkspaceManager {
    var manager = WorkspaceManager(count: 1)
    for id in 1...3 { manager.assign(WindowID(UInt64(id)), to: 1) }
    manager.setLayoutTree(.split(
        direction: .vertical, ratio: 0.5,
        first: .leaf(WindowID(1)),
        second: .split(direction: .horizontal, ratio: 0.5, first: .leaf(WindowID(2)), second: .leaf(WindowID(3)))
    ), for: 1)
    return manager
}

@Test func togglingCreatesAndDissolvesASingleWindowGroup() {
    var manager = manager()

    let result_557 = manager.toggleGroup(containing: WindowID(1), in: 1)
    #expect(result_557)
    #expect(manager.group(containing: WindowID(1)) == [WindowID(1)])
    let result_691 = manager.toggleGroup(containing: WindowID(1), in: 1)
    #expect(result_691)
    #expect(manager.group(containing: WindowID(1)) == nil)
}

@Test func addingToAGroupRemovesTheLeafAndShowsTheNewMember() {
    var manager = manager()
    _ = manager.toggleGroup(containing: WindowID(2), in: 1)

    let result_971 = manager.addToGroup(WindowID(3), containing: WindowID(2), in: 1)
    #expect(result_971)

    #expect(manager.group(containing: WindowID(3)) == [WindowID(2), WindowID(3)])
    #expect(manager.activeMember(ofGroupContaining: WindowID(2)) == WindowID(3))
    #expect(manager.storedLayoutTree(for: 1) == .split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(2))))
    #expect(manager.layoutLeaves(for: [WindowID(1), WindowID(2), WindowID(3)]) == [WindowID(1), WindowID(2)])
    #expect(manager.hiddenGroupMembers(among: [WindowID(1), WindowID(2), WindowID(3)]) == [WindowID(2)])
}

@Test func cyclingChangesTheVisibleMember() {
    var manager = manager()
    _ = manager.toggleGroup(containing: WindowID(2), in: 1)
    _ = manager.addToGroup(WindowID(3), containing: WindowID(2), in: 1)

    let cycled_1878 = manager.cycleGroup(containing: WindowID(3), forward: true)
    #expect(cycled_1878 == WindowID(2))
    let cycled_1965 = manager.cycleGroup(containing: WindowID(2), forward: false)
    #expect(cycled_1965 == WindowID(3))
}

@Test func removingTheLeaderPromotesTheNextMemberInTheTree() {
    var manager = manager()
    _ = manager.toggleGroup(containing: WindowID(2), in: 1)
    _ = manager.addToGroup(WindowID(3), containing: WindowID(2), in: 1)

    manager.remove(WindowID(2))

    #expect(manager.group(containing: WindowID(3)) == [WindowID(3)])
    #expect(manager.storedLayoutTree(for: 1) == .split(direction: .vertical, ratio: 0.5, first: .leaf(WindowID(1)), second: .leaf(WindowID(3))))
}

@Test func leavingAGroupGivesTheWindowItsOwnTileAndDissolvingRestoresAll() {
    var manager = manager()
    _ = manager.toggleGroup(containing: WindowID(2), in: 1)
    _ = manager.addToGroup(WindowID(3), containing: WindowID(2), in: 1)

    let result_2672 = manager.leaveGroup(WindowID(3), in: 1)
    #expect(result_2672)
    #expect(manager.group(containing: WindowID(3)) == nil)
    #expect(manager.storedLayoutTree(for: 1)?.windowIDs == [WindowID(1), WindowID(2), WindowID(3)])

    _ = manager.addToGroup(WindowID(3), containing: WindowID(2), in: 1)
    let result_2956 = manager.toggleGroup(containing: WindowID(2), in: 1)
    #expect(result_2956)
    #expect(manager.group(containing: WindowID(2)) == nil)
    #expect(manager.storedLayoutTree(for: 1)?.windowIDs == [WindowID(1), WindowID(2), WindowID(3)])
}

@Test func parsesGroupCommands() {
    #expect(Command.parse(["group", "toggle"]) == .group(.toggle))
    #expect(Command.parse(["group", "add", "left"]) == .group(.add(.left)))
    #expect(Command.parse(["group", "remove"]) == .group(.leave))
    #expect(Command.parse(["group", "next"]) == .group(.cycle(forward: true)))
    #expect(Command.parse(["group", "prev"]) == .group(.cycle(forward: false)))
    #expect(Command.group(.add(.up)).wireValue == "group add up")
    #expect(Command.parse(["group", "sideways"]) == nil)
    let hyprland = HyprlandConfig.parse("bind = ALT, G, togglegroup\nbind = ALT, H, moveintogroup, l\nbind = ALT, U, moveoutofgroup\nbind = ALT, TAB, changegroupactive, f")
    #expect(hyprland?.binds["default"] == ["alt+g": "group toggle", "alt+h": "group add left", "alt+u": "group remove", "alt+tab": "group next"])
}
