import Testing
@testable import MacWMCore

@Test func defaultsMaximizeHotkeyToAltM() {
    #expect(Config().hotkeys["maximize"] == "alt+m")
    #expect(Config().hotkeys["toggle_float"] == "alt+f")
    #expect(Config().hotkeys["terminal_toggle"] == "grave")
}

@Test
func parsesTerminalBundleIdentifierAndRejectsInvalidValues() {
    let config = Config.parse("""
    [terminal]
    bundle_id = "com.mitchellh.ghostty"
    """)
    #expect(config?.terminalBundleIdentifier == "com.mitchellh.ghostty")
    #expect(Config().terminalBundleIdentifier == "com.googlecode.iterm2")
    #expect(Config.parse("[terminal]\nbundle_id = \"\"") == nil)
    #expect(Config.parse("[terminal]\nbundle_id = \"not valid\"") == nil)
}

@Test func parsesLayoutGapsAndAutoTile() {
    let config = Config.parse("""
    [general]
    layout = "master-stack"
    gap = 12
    auto_tile = false

    [display]
    outer_gap = 20
    inner_gap = 6
    """)

    #expect(config == Config(layout: .masterStack, outerGap: 20, innerGap: 6, autoTile: false))
}

@Test func parsesBarPositionAndDefaultsToTop() {
    #expect(Config().barPosition == .top)
    #expect(Config.parse("[bar]\nposition = \"left\"")?.barPosition == .left)
    #expect(Config.parse("[bar]\nposition = \"invalid\"") == nil)
}

@Test func rejectsInvalidConfiguration() {
    #expect(Config.parse("[display]\ninner_gap = -1") == nil)
    #expect(Config.parse("[general]\nlayout = \"invalid\"") == nil)
}

@Test func parsesConfiguredHotkeysAndExtendedWindowRule() {
    let config = Config.parse("""
    [keys]
    focus_left = "ctrl+h"

    [[rules]]
    bundle_id = "com.example.App"
    float = true
    workspace = 3
    center = true
    width = 800
    height = 600
    """)

    #expect(config?.hotkeys["focus_left"] == "ctrl+h")
    #expect(config?.rules == [WindowRule(bundleIdentifier: "com.example.App", float: true, workspace: 3, center: true, width: 800, height: 600)])
}

@Test func parsesTerminalToggleHotkey() {
    #expect(Config.parse("[keys]\nterminal_toggle = \"ctrl+grave\"")?.hotkeys["terminal_toggle"] == "ctrl+grave")
}

@Test func parsesScratchpadsAndKeepsThemUnmanaged() {
    let config = Config.parse("""
    [terminal]
    bundle_id = "com.googlecode.iterm2"

    [scratchpads]
    chat = "net.whatsapp.WhatsApp"
    notes = "com.apple.Notes"
    """)

    #expect(config?.scratchpads == ["chat": "net.whatsapp.WhatsApp", "notes": "com.apple.Notes"])
    #expect(config?.unmanagedBundleIdentifiers == ["com.googlecode.iterm2", "net.whatsapp.WhatsApp", "com.apple.Notes"])
    #expect(Config.parse("[scratchpads]\nchat = \"\"") == nil)
    #expect(Config.parse("[scratchpads]\nchat = \"not valid\"") == nil)
}
