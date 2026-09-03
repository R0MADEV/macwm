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

@Test func parsesFocusFollowsMouse() {
    #expect(Config().focusFollowsMouse == false)
    #expect(Config.parse("[general]\nfocus_follows_mouse = true")?.focusFollowsMouse == true)
    #expect(Config.parse("[general]\nfocus_follows_mouse = maybe") == nil)
}

@Test func parsesSmartGapsAndAutostart() {
    let config = Config.parse("""
    [general]
    smart_gaps = true

    [autostart]
    bar = "sketchybar"
    borders = "borders width=4"
    """)

    #expect(config?.smartGaps == true)
    #expect(Config().smartGaps == false)
    #expect(config?.autostart == ["bar": "sketchybar", "borders": "borders width=4"])
    #expect(Config.parse("[autostart]\nbar = \"\"") == nil)
}

@Test func parsesCursorWarp() {
    #expect(Config().cursorWarp == true)
    #expect(Config.parse("[general]\ncursor_warp = false")?.cursorWarp == false)
    #expect(HyprlandConfig.parse("cursor {\n no_warps = true\n}")?.cursorWarp == false)
}

@Test func parsesBorderOptionsAndColors() {
    let config = Config.parse("[border]\nenabled = true\nwidth = 4\ncolor = \"#33ccff\"")
    #expect(config?.border == BorderOptions(enabled: true, width: 4, color: "#33ccff"))
    #expect(Config().border.enabled == false)
    #expect(Config.parse("[border]\nwidth = -1") == nil)
    #expect(Config.parse("[border]\ncolor = \"blue\"") == nil)

    #expect(BorderOptions.rgba("#33ccff") != nil)
    let rgba = BorderOptions.rgba("#33ccff80")!
    #expect(abs(rgba.red - 0.2) < 0.01 && abs(rgba.green - 0.8) < 0.01 && abs(rgba.blue - 1) < 0.01 && abs(rgba.alpha - 0.5) < 0.01)
    #expect(BorderOptions.rgba("zzz") == nil)

    let hyprland = HyprlandConfig.parse("general {\n border_size = 2\n col.active_border = rgba(33ccffee)\n}")
    #expect(hyprland?.border == BorderOptions(enabled: true, width: 2, color: "#33ccffee"))
    #expect(HyprlandConfig.parse("general {\n col.active_border = rgb(ff0000) rgb(00ff00) 45deg\n}")?.border.color == "#ff0000")
}

@Test func parsesBarOptions() {
    let config = Config.parse("""
    [bar]
    position = "bottom"
    height = 30
    font_size = 12
    accent = "#ff8800"
    opacity = 0.6
    hide_empty_workspaces = true
    left = ["workspaces"]
    center = []
    right = ["clock", "settings"]
    """)

    #expect(config?.bar == BarOptions(height: 30, fontSize: 12, accent: "#ff8800", opacity: 0.6, hideEmptyWorkspaces: true, left: ["workspaces"], center: [], right: ["clock", "settings"]))
    #expect(Config().bar.left == ["workspaces", "layout"])
    #expect(Config().barThickness == 34)
    #expect(config?.barThickness == 30)
    #expect(Config.parse("[bar]\nleft = [\"nosuchmodule\"]") == nil)
    #expect(Config.parse("[bar]\nopacity = 2") == nil)
    let hyprland = HyprlandConfig.parse("bar {\n height = 28\n right = clock settings\n accent = rgb(112233)\n}")
    #expect(hyprland?.bar.height == 28)
    #expect(hyprland?.bar.right == ["clock", "settings"])
    #expect(hyprland?.bar.accent == "#112233")
}

@Test func parsesWorkspaceLayoutsAndHideMode() {
    let config = Config.parse("""
    [general]
    hide_mode = "minimize"

    [workspaces.layouts]
    3 = "master"
    5 = "monocle"
    """)

    #expect(config?.hideMode == .minimize)
    #expect(Config().hideMode == .park)
    #expect(config?.workspaceLayouts == [3: .masterStack, 5: .monocle])
    #expect(config?.defaultLayout(for: 3) == .masterStack)
    #expect(config?.defaultLayout(for: 1) == .bsp)
    #expect(Config.parse("[workspaces.layouts]\n12 = \"bsp\"") == nil)
    #expect(Config.parse("[general]\nhide_mode = \"vanish\"") == nil)
    let hyprland = HyprlandConfig.parse("general {\n hide_mode = minimize\n}\nworkspace = 2, layout:master\nworkspace = 4, persistent:true")
    #expect(hyprland?.hideMode == .minimize)
    #expect(hyprland?.workspaceLayouts == [2: .masterStack])
}

@Test func parsesTerminalHeight() {
    #expect(Config().terminalHeightPercent == 100)
    #expect(Config.parse("[terminal]\nheight = 60")?.terminalHeightPercent == 60)
    #expect(Config.parse("[terminal]\nheight = 0") == nil)
    #expect(Config.parse("[terminal]\nheight = 120") == nil)
    #expect(HyprlandConfig.parse("general {\n terminal_height = 55\n}")?.terminalHeightPercent == 55)
}
