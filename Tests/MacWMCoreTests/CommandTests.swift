import Testing
@testable import MacWMCore

@Test func parsesFocusAndResizeCommands() {
    #expect(Command.parse(["focus", "left"]) == .focus(.left))
    #expect(Command.parse(["resize", "grow"]) == .resize(.grow))
    #expect(Command.parse(["layout", "bsp"]) == .layout(.bsp))
    #expect(Command.parse(["workspace", "3"]) == .workspace(3))
    #expect(Command.parse(["send-to-workspace", "4"]) == .sendToWorkspace(4))
    #expect(Command.parse(["maximize"]) == .maximize)
    #expect(Command.maximize.wireValue == "maximize")
    #expect(Command.parse(["toggle-float"]) == .toggleFloat)
    #expect(Command.toggleFloat.wireValue == "toggle-float")
    #expect(Command.parse(["toggle-terminal"]) == .toggleTerminal)
    #expect(Command.toggleTerminal.wireValue == "toggle-terminal")
}

@Test func rejectsIncompleteCommands() {
    #expect(Command.parse(["move"]) == nil)
    #expect(Command.parse(["resize", "sideways"]) == nil)
}

@Test func parsesDispatcherCommands() {
    #expect(Command.parse(["close"]) == .close)
    #expect(Command.parse(["focus", "next"]) == .cycleFocus(forward: true))
    #expect(Command.parse(["focus", "prev"]) == .cycleFocus(forward: false))
    #expect(Command.parse(["toggle-split"]) == .toggleSplit)
    #expect(Command.parse(["exec", "open", "-a", "Safari"]) == .exec("open -a Safari"))
    #expect(Command.exec("open -a Safari").wireValue == "exec open -a Safari")
    #expect(Command.parse("exec open -a Safari") == .exec("open -a Safari"))
    #expect(Command.parse(["exec"]) == nil)
}

@Test func parsesScratchpadCommand() {
    #expect(Command.parse(["scratchpad", "chat"]) == .scratchpad("chat"))
    #expect(Command.scratchpad("chat").wireValue == "scratchpad chat")
    #expect(Command.parse(["scratchpad"]) == nil)
}

@Test func parsesPreselectCommand() {
    #expect(Command.parse(["preselect", "vertical"]) == .preselect(.vertical))
    #expect(Command.parse(["preselect", "horizontal"]) == .preselect(.horizontal))
    #expect(Command.preselect(.vertical).wireValue == "preselect vertical")
    #expect(Command.parse(["preselect", "diagonal"]) == nil)
}
