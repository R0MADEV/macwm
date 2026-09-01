import Testing
@testable import MacWMCore

private let frame = Frame(x: 0, y: 0, width: 1000, height: 600)
private let ids = [WindowID(1), WindowID(2), WindowID(3)]

@Test func masterOnTheLeftTakesItsRatioAndStacksTheRest() {
    let frames = LayoutEngine.frames(for: ids, layout: .masterStack, in: frame, outerGap: 0, innerGap: 0, master: MasterOptions(orientation: .left, ratio: 0.6, count: 1))

    #expect(frames[WindowID(1)] == Frame(x: 0, y: 0, width: 600, height: 600))
    #expect(frames[WindowID(2)] == Frame(x: 600, y: 0, width: 400, height: 300))
    #expect(frames[WindowID(3)] == Frame(x: 600, y: 300, width: 400, height: 300))
}

@Test func masterOnTheRightAndOnTop() {
    let right = LayoutEngine.frames(for: ids, layout: .masterStack, in: frame, outerGap: 0, innerGap: 0, master: MasterOptions(orientation: .right, ratio: 0.5, count: 1))
    #expect(right[WindowID(1)] == Frame(x: 500, y: 0, width: 500, height: 600))
    #expect(right[WindowID(2)] == Frame(x: 0, y: 0, width: 500, height: 300))

    let top = LayoutEngine.frames(for: ids, layout: .masterStack, in: frame, outerGap: 0, innerGap: 0, master: MasterOptions(orientation: .top, ratio: 0.5, count: 1))
    #expect(top[WindowID(1)] == Frame(x: 0, y: 0, width: 1000, height: 300))
    #expect(top[WindowID(2)] == Frame(x: 0, y: 300, width: 500, height: 300))
    #expect(top[WindowID(3)] == Frame(x: 500, y: 300, width: 500, height: 300))
}

@Test func severalMastersShareTheMasterArea() {
    let frames = LayoutEngine.frames(for: ids, layout: .masterStack, in: frame, outerGap: 0, innerGap: 0, master: MasterOptions(orientation: .left, ratio: 0.5, count: 2))

    #expect(frames[WindowID(1)] == Frame(x: 0, y: 0, width: 500, height: 300))
    #expect(frames[WindowID(2)] == Frame(x: 0, y: 300, width: 500, height: 300))
    #expect(frames[WindowID(3)] == Frame(x: 500, y: 0, width: 500, height: 600))
    // Every window is a master when count covers them all.
    let all = LayoutEngine.frames(for: ids, layout: .masterStack, in: frame, outerGap: 0, innerGap: 0, master: MasterOptions(orientation: .left, ratio: 0.5, count: 5))
    #expect(all[WindowID(3)] == Frame(x: 0, y: 400, width: 1000, height: 200))
}

@Test func masterOptionsAdjustWithinBounds() {
    var options = MasterOptions()
    options.adjustRatio(by: 0.5)
    #expect(options.ratio == 0.9)
    options.adjustRatio(by: -1)
    #expect(options.ratio == 0.1)
    options.adjustCount(by: -5)
    #expect(options.count == 1)
    options.adjustCount(by: 2)
    #expect(options.count == 3)
}

@Test func parsesMasterCommandsAndConfig() {
    #expect(Command.parse(["master", "grow"]) == .master(.grow))
    #expect(Command.parse(["master", "shrink"]) == .master(.shrink))
    #expect(Command.parse(["master", "add"]) == .master(.addMaster))
    #expect(Command.parse(["master", "remove"]) == .master(.removeMaster))
    #expect(Command.parse(["master", "orientation", "top"]) == .master(.orientation(.top)))
    #expect(Command.master(.orientation(.right)).wireValue == "master orientation right")
    #expect(Command.parse(["master", "sideways"]) == nil)

    let config = Config.parse("[master]\norientation = \"right\"\nratio = 0.65\ncount = 2")
    #expect(config?.master == MasterOptions(orientation: .right, ratio: 0.65, count: 2))
    #expect(Config.parse("[master]\nratio = 5") == nil)
    let hyprland = HyprlandConfig.parse("master {\n orientation = top\n mfact = 0.7\n}\nbind = ALT, M, layoutmsg, addmaster\nbind = ALT, O, layoutmsg, orientationnext\nbind = ALT, P, layoutmsg, mfact +0.05")
    #expect(hyprland?.master == MasterOptions(orientation: .top, ratio: 0.7, count: 1))
    #expect(hyprland?.binds["default"]?["alt+m"] == "master add")
    #expect(hyprland?.binds["default"]?["alt+o"] == "master orientation next")
    #expect(hyprland?.binds["default"]?["alt+p"] == "master grow")
}
