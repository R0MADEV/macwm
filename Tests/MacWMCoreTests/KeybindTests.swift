import Testing
@testable import MacWMCore

private func press(_ text: String) -> KeyBinding { KeyBinding.parse(text)! }

@Test func parsesBindingsWithModifierAliases() {
    #expect(KeyBinding.parse("alt+shift+h") == KeyBinding(keyCode: 4, modifiers: [.alt, .shift]))
    #expect(KeyBinding.parse("cmd+return") == KeyBinding(keyCode: 36, modifiers: [.cmd]))
    #expect(KeyBinding.parse("Option+Control+1") == KeyBinding(keyCode: 18, modifiers: [.alt, .ctrl]))
    #expect(KeyBinding.parse("super+space") == KeyBinding(keyCode: 49, modifiers: [.cmd]))
    #expect(KeyBinding.parse("grave") == KeyBinding(keyCode: 50, modifiers: []))
    #expect(KeyBinding.parse("f12") == KeyBinding(keyCode: 111, modifiers: []))
}

@Test func rejectsInvalidBindings() {
    #expect(KeyBinding.parse("") == nil)
    #expect(KeyBinding.parse("alt+") == nil)
    #expect(KeyBinding.parse("alt+nosuchkey") == nil)
    #expect(KeyBinding.parse("shift") == nil)
}

@Test func engineResolvesCommandsAndPassesUnboundKeysThrough() {
    var engine = KeybindEngine(binds: ["default": [press("alt+h"): .focus(.left)]])

    #expect(engine.handle(press("alt+h")) == .command(.focus(.left)))
    #expect(engine.handle(press("alt+shift+h")) == .unbound)
    #expect(engine.handle(press("h")) == .unbound)
}

@Test func modesSwitchBindingSetsAndConsumeTheKey() {
    var engine = KeybindEngine(binds: [
        "default": [press("alt+r"): .mode("resize")],
        "resize": [press("l"): .resize(.grow), press("escape"): .mode("default")]
    ])

    #expect(engine.handle(press("l")) == .unbound)
    #expect(engine.handle(press("alt+r")) == .consumed)
    #expect(engine.mode == "resize")
    #expect(engine.handle(press("l")) == .command(.resize(.grow)))
    #expect(engine.handle(press("escape")) == .consumed)
    #expect(engine.mode == "default")
}

@Test func unknownModeIsIgnored() {
    var engine = KeybindEngine(binds: ["default": [press("alt+r"): .mode("nope")]])

    #expect(engine.handle(press("alt+r")) == .consumed)
    #expect(engine.mode == "default")
}

@Test func legacyKeysBecomeBindings() {
    var engine = Config().keybindEngine()

    #expect(engine.handle(press("alt+h")) == .command(.focus(.left)))
    #expect(engine.handle(press("alt+shift+l")) == .command(.move(.right)))
    #expect(engine.handle(press("alt+r")) == .command(.resize(.grow)))
    #expect(engine.handle(press("alt+shift+r")) == .command(.resize(.shrink)))
    #expect(engine.handle(press("alt+3")) == .command(.workspace(3)))
    #expect(engine.handle(press("alt+shift+3")) == .command(.sendToWorkspace(3)))
    #expect(engine.handle(press("grave")) == .command(.toggleTerminal))
    #expect(engine.handle(press("alt+m")) == .command(.maximize))
    #expect(engine.handle(press("alt+f")) == .command(.toggleFloat))
}

@Test func parsesBindSectionsAndModesOverridingLegacyKeys() {
    let config = Config.parse("""
    [binds]
    "alt+h" = "workspace 1"
    "cmd+return" = "toggle-terminal"
    "alt+r" = "mode resize"

    [binds.resize]
    "h" = "resize shrink"
    "escape" = "mode default"
    """)
    var engine = config!.keybindEngine()

    #expect(engine.handle(press("alt+h")) == .command(.workspace(1)))
    #expect(engine.handle(press("cmd+return")) == .command(.toggleTerminal))
    #expect(engine.handle(press("alt+j")) == .command(.focus(.down)))
    #expect(engine.handle(press("alt+r")) == .consumed)
    #expect(engine.handle(press("h")) == .command(.resize(.shrink)))
}

@Test func rejectsInvalidBinds() {
    #expect(Config.parse("[binds]\n\"alt+h\" = \"nosuch\"") == nil)
    #expect(Config.parse("[binds]\n\"alt+nosuchkey\" = \"maximize\"") == nil)
    #expect(Config.parse("[binds]\n\"alt+h\" = \"mode\"") == nil)
}

@Test func parsesModeCommand() {
    #expect(Command.parse(["mode", "resize"]) == .mode("resize"))
    #expect(Command.mode("resize").wireValue == "mode resize")
    #expect(Command.parse(["mode"]) == nil)
}
