import Testing
@testable import MacWMCore

private func richConfig() -> Config {
    var config = Config(layout: .masterStack, outerGap: 10, innerGap: 6, autoTile: true, focusFollowsMouse: true, smartGaps: true, autostart: ["01": "sketchybar"], barPosition: .bottom, terminalBundleIdentifier: "com.apple.Terminal")
    config.rules = [
        WindowRule(bundleIdentifier: "com.apple.finder", float: true),
        WindowRule(bundleIdentifier: "com.microsoft.VSCode", title: "Welcome", float: true, workspace: 2, center: true, width: 800, height: 600)
    ]
    config.scratchpads = ["chat": "net.whatsapp.WhatsApp"]
    config.hotkeys["focus_left"] = "ctrl+h"
    config.cursorWarp = false
    config.border = BorderOptions(enabled: true, width: 2, color: "#ff8800")
    config.binds = ["default": ["alt+q": "close"], "resize": ["h": "resize shrink", "escape": "mode default"]]
    return config
}

@Test func tomlRoundTripsTheWholeConfig() throws {
    let config = richConfig()

    let parsed = try #require(Config.parse(config.toml()))

    #expect(parsed == config)
}

@Test func keysCanDisableADefaultHotkeyWithNone() {
    let config = Config.parse("[keys]\nmaximize = \"none\"")

    #expect(config?.hotkeys["maximize"] == nil)
    #expect(config?.hotkeys["toggle_float"] == "alt+f")
}

@Test func hotkeyEntriesExpandLegacyNamesAndApplyOverrides() {
    var config = Config()
    config.binds = ["default": ["alt+h": "workspace 1", "alt+q": "close"], "resize": ["l": "resize grow"]]

    let entries = config.hotkeyEntries
    func command(_ binding: String, mode: String = "default") -> String? {
        entries.first { $0.mode == mode && $0.binding == binding }?.command
    }

    #expect(command("alt+h") == "workspace 1")
    #expect(command("alt+j") == "focus down")
    #expect(command("alt+shift+r") == "resize shrink")
    #expect(command("alt+shift+3") == "send-to-workspace 3")
    #expect(command("grave") == "toggle-terminal")
    #expect(command("alt+q") == "close")
    #expect(command("l", mode: "resize") == "resize grow")
}

@Test func settingHotkeyEntriesKeepsLegacyNamesWhenTheyStillMatch() throws {
    var config = Config()
    var entries = config.hotkeyEntries
    entries.removeAll { $0.command == "maximize" }
    entries = entries.map { entry in
        entry.command == "focus left" ? HotkeyEntry(mode: "default", binding: "ctrl+h", command: "focus left") : entry
    }
    entries.append(HotkeyEntry(mode: "default", binding: "alt+q", command: "close"))
    entries.append(HotkeyEntry(mode: "resize", binding: "escape", command: "mode default"))

    config.setHotkeyEntries(entries)

    #expect(config.hotkeys["focus_left"] == "ctrl+h")
    #expect(config.hotkeys["maximize"] == nil)
    #expect(config.binds["default"] == ["alt+q": "close"])
    #expect(config.binds["resize"] == ["escape": "mode default"])
    let reparsed = try #require(Config.parse(config.toml()))
    #expect(reparsed.hotkeyEntries.sorted() == entries.sorted())
}

@Test func keyNamesRoundTripThroughCodes() {
    #expect(KeyCodes.name(for: 4) == "h")
    #expect(KeyCodes.name(for: 36) == "return")
    #expect(KeyCodes.name(for: 50) == "grave")
    #expect(KeyBinding(keyCode: 4, modifiers: [.alt, .shift]).text == "alt+shift+h")
    #expect(KeyBinding(keyCode: 36, modifiers: [.cmd, .ctrl]).text == "ctrl+cmd+return")
}
