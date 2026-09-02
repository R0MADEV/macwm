import Testing
@testable import MacWMCore

@Test func growKeepsCenterAndIncreasesFrame() {
    let frame = Frame(x: 100, y: 100, width: 400, height: 300)

    let resized = frame.resized(operation: .grow, amount: 40)

    #expect(resized == Frame(x: 80, y: 80, width: 440, height: 340))
}

@Test func shrinkStopsAtMinimumSize() {
    let frame = Frame(x: 100, y: 100, width: 100, height: 80)

    let resized = frame.resized(operation: .shrink, amount: 80, minimumSize: (120, 100))

    #expect(resized == Frame(x: 90, y: 90, width: 120, height: 100))
}

@Test func axisResizesChangeOneDimensionAroundTheCenter() {
    let frame = Frame(x: 100, y: 100, width: 400, height: 300)

    #expect(frame.resized(operation: .wider, amount: 40) == Frame(x: 80, y: 100, width: 440, height: 300))
    #expect(frame.resized(operation: .narrower, amount: 40) == Frame(x: 120, y: 100, width: 360, height: 300))
    #expect(frame.resized(operation: .taller, amount: 40) == Frame(x: 100, y: 80, width: 400, height: 340))
    #expect(frame.resized(operation: .shorter, amount: 40) == Frame(x: 100, y: 120, width: 400, height: 260))
}

@Test func parsesAxisResizeAndPseudoCommands() {
    #expect(Command.parse(["resize", "wider"]) == .resize(.wider))
    #expect(Command.parse(["resize", "shorter"]) == .resize(.shorter))
    #expect(Command.resize(.taller).wireValue == "resize taller")
    #expect(Command.parse(["toggle-pseudo"]) == .togglePseudo)
    #expect(Command.togglePseudo.wireValue == "toggle-pseudo")
    let hyprland = HyprlandConfig.parse("bind = ALT, L, resizeactive, 10 0\nbind = ALT, J, resizeactive, 0 10\nbind = ALT, K, resizeactive, 0 -10\nbind = ALT, P, pseudo")
    #expect(hyprland?.binds["default"] == ["alt+l": "resize wider", "alt+j": "resize taller", "alt+k": "resize shorter", "alt+p": "toggle-pseudo"])
}

@Test func pseudotiledWindowsKeepTheirOwnSizeCenteredInTheTile() {
    let tile = Frame(x: 0, y: 0, width: 1000, height: 600)

    #expect(Frame.pseudotile(ownSize: (400, 300), in: tile) == Frame(x: 300, y: 150, width: 400, height: 300))
    #expect(Frame.pseudotile(ownSize: (2000, 300), in: tile) == Frame(x: 0, y: 150, width: 1000, height: 300))
}
