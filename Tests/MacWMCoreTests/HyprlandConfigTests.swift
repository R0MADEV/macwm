import Testing
@testable import MacWMCore

private let sample = """
# Hyprland-style config
$mod = ALT
$terminal = com.googlecode.iterm2

general {
    gaps_in = 6
    gaps_out = 12
    layout = dwindle
    terminal = $terminal
}

dwindle {
    no_gaps_when_only = 1
}

input {
    follow_mouse = 1
}

decoration {
    rounding = 10   # ignored on macOS
}

exec-once = sketchybar
exec-once = borders width=4

bind = $mod, H, movefocus, l
bind = $mod SHIFT, L, movewindow, r
bind = $mod, 1, workspace, 1
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod, Q, killactive
bind = $mod, F, togglefloating
bind = $mod, Return, exec, open -a iTerm
bind = $mod, grave, workspace, previous
bind = $mod, W, togglespecialworkspace, chat
bind = $mod, R, submap, resize
bindm = $mod, mouse:272, movewindow

submap = resize
binde = , L, resizeactive, 10 0
binde = , H, resizeactive, -10 0
bind = , escape, submap, reset
submap = reset

scratchpad = chat, net.whatsapp.WhatsApp
windowrule = float, class:^(com.apple.finder)$
windowrulev2 = workspace 2, class:^(com\\.microsoft\\.VSCode)$
windowrulev2 = float, class:^(com\\.microsoft\\.VSCode)$, title:^(Welcome)$
windowrulev2 = size 800 600, class:^(com\\.microsoft\\.VSCode)$, title:^(Welcome)$
"""

@Test func parsesGeneralSectionsVariablesAndAutostart() throws {
    let config = try #require(HyprlandConfig.parse(sample))

    #expect(config.innerGap == 6)
    #expect(config.outerGap == 12)
    #expect(config.layout == .bsp)
    #expect(config.terminalBundleIdentifier == "com.googlecode.iterm2")
    #expect(config.smartGaps == true)
    #expect(config.focusFollowsMouse == true)
    #expect(config.autostart == ["01": "sketchybar", "02": "borders width=4"])
    #expect(config.scratchpads == ["chat": "net.whatsapp.WhatsApp"])
}

@Test func translatesBindsAndSubmaps() throws {
    let config = try #require(HyprlandConfig.parse(sample))
    let binds = config.binds["default"] ?? [:]

    #expect(binds["alt+h"] == "focus left")
    #expect(binds["alt+shift+l"] == "move right")
    #expect(binds["alt+1"] == "workspace 1")
    #expect(binds["alt+shift+1"] == "send-to-workspace 1")
    #expect(binds["alt+q"] == "close")
    #expect(binds["alt+f"] == "toggle-float")
    #expect(binds["alt+return"] == "exec open -a iTerm")
    #expect(binds["alt+grave"] == "workspace previous")
    #expect(binds["alt+w"] == "scratchpad chat")
    #expect(binds["alt+r"] == "mode resize")
    #expect(config.binds["resize"] == ["l": "resize grow", "h": "resize shrink", "escape": "mode default"])
}

@Test func translatesAndMergesWindowRules() throws {
    let config = try #require(HyprlandConfig.parse(sample))

    #expect(config.rules == [
        WindowRule(bundleIdentifier: "com.apple.finder", float: true),
        WindowRule(bundleIdentifier: "com.microsoft.VSCode", float: false, workspace: 2),
        WindowRule(bundleIdentifier: "com.microsoft.VSCode", title: "Welcome", float: true, width: 800, height: 600)
    ])
}

@Test func unknownDispatchersAreSkippedAndBrokenLinesRejected() {
    let lenient = HyprlandConfig.parse("bind = ALT, K, pseudo\nbind = ALT, J, movefocus, d")
    #expect(lenient?.binds["default"] == ["alt+j": "focus down"])
    #expect(HyprlandConfig.parse("general {\n gaps_in = many\n}") == nil)
    #expect(HyprlandConfig.parse("bind = ALT, nosuchkey, killactive") == nil)
}
