# macwm

`macwm` is a lightweight, keyboard-first window manager for macOS. It runs as a native Swift daemon over macOS Accessibility APIs, keeping WindowServer as the compositor while adding configurable tiling, workspaces, global hotkeys, a CLI and a native navbar.

It is designed for local use: no account, network service, telemetry, Electron, Node.js or Chromium.

## Installation

The recommended installer is the PKG:

```text
macwm-0.1.0-arm64.pkg
```

It installs:

- `macwm.app` with the daemon and CLI;
- `macwm-bar.app` with the native navbar;
- CLI commands in `/usr/local/bin`;
- LaunchAgents for the daemon and navbar;
- an example configuration at `/usr/local/share/macwm/example-config.toml`;
- `~/.config/macwm/config.toml` only when the user does not already have one.

The DMG contains both applications and the complete PKG. To install everything from the DMG, open the included PKG instead of dragging only the applications.

After installation:

1. Open `System Settings > Privacy & Security > Accessibility`.
2. Enable `macwm` or the installed daemon when macOS requests permission.
3. Log out and back in, or load the LaunchAgents again, if the automatic startup does not begin immediately.
4. Verify the daemon with `macwm status`.
5. Edit `~/.config/macwm/config.toml` and apply changes with `macwm reload`.

The daemon and navbar must be signed and notarized before distributing them publicly. Unsigned local builds may trigger Gatekeeper warnings.

## Status

The package contains:

- `MacWMCore`: platform-independent window identifiers and BSP frame calculation.
- `macwm-daemon`: accessory application with an Accessibility permission check.
- `AXClient` and `AXEventObserver`: initial window discovery and focused-window tracking.
- `MacWMTransport`: local Unix socket transport for daemon/CLI commands.
- `macwm-bar`: native menu-bar app showing and switching workspaces.
- `macwm`: initial CLI entry point.
- `MacWMCoreTests`: layout and window-store tests.

## Build

```bash
swift build
swift build --build-tests
```

Tests use the Swift Testing module bundled with the Xcode toolchain. Command
Line Tools do not ship it, so build the test target with Xcode selected
(`sudo xcode-select -s /Applications/Xcode.app`) or by prefixing the command
with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run the tests
from Xcode or an approved test service; this repository does not require
credentials or user configuration changes.

The daemon requires Accessibility permission in System Settings. Display
parameter changes and sleep/wake trigger a rescan; layout still uses the
primary display. `AXWindowNumber` is used when CoreGraphics can correlate it,
with the historical bundle/title fallback for older state files.

All commands go through the `macwm` CLI and can be bound to any key under `[binds]` (see Custom Hotkeys). The hotkey column lists the defaults that ship with macwm.

| Command | What it does | Default hotkey |
| --- | --- | --- |
| `macwm status` | Active workspace, layout, hotkey mode, window count and focused window | none |
| `macwm query state\|windows\|workspaces` | The same and more as JSON, for scripts and external bars (see IPC) | none |
| `macwm reload` | Reload `~/.config/macwm/config.toml`: rules, hotkeys, modes, scratchpads, terminal, bar | none |
| `macwm layout bsp\|stack\|monocle\|master` | Set the layout of the active workspace | none |
| `macwm workspace N` | Switch to workspace `N` (1 to 9) and focus the window you last used there | `Option+N` |
| `macwm workspace previous` | Back to the workspace you came from, Hyprland's back-and-forth | none |
| `macwm send-to-workspace N` | Send the focused window to workspace `N` and stay, Hyprland's `movetoworkspacesilent` | `Option+Shift+N` |
| `macwm move-to-workspace N` | Send the focused window to workspace `N` and follow it, Hyprland's `movetoworkspace` | none |
| `macwm focus left\|down\|up\|right` | Focus the nearest visible window in that direction | `Option+H/J/K/L` |
| `macwm focus next\|prev` | Cycle focus through the visible windows of the workspace, wrapping around | none |
| `macwm move left\|down\|up\|right` | Tiled: swap the focused window with its neighbor in that direction; floating: nudge it 40 points | `Option+Shift+H/J/K/L` |
| `macwm center` | Center the focused floating window on its screen | none |
| `macwm resize grow\|shrink` | Tiled in BSP: give the window 5% more or less of its split; floating: grow or shrink by 40 points | `Option+R` / `Option+Shift+R` |
| `macwm maximize` | Toggle between maximized and the previous frame | `Option+M` |
| `macwm toggle-float` | Toggle floating for the focused window | `Option+F` |
| `macwm toggle-split` | Flip the split direction of the focused window's node in the BSP tree | none |
| `macwm preselect vertical\|horizontal` | Choose how the next window opened in the workspace splits the focused one | none |
| `macwm master grow\|shrink\|add\|remove\|orientation left\|right\|top\|bottom\|next` | Shape the master layout: master ratio, number of masters and the side they take | none |
| `macwm group toggle\|add left\|right\|up\|down\|remove\|next\|prev` | Tab groups: start or dissolve one, pull the neighbor in, leave, cycle the visible member | none |
| `macwm close` | Press the focused window's close button | none |
| `macwm toggle-terminal` | Show or hide the configured terminal covering the screen | `` ` `` (grave) |
| `macwm scratchpad NAME` | Show or hide a scratchpad application configured under `[scratchpads]` | none |
| `macwm exec COMMAND...` | Run the rest of the line through your login shell | none |
| `macwm mode NAME` | Enter a hotkey mode; `mode default` leaves it | none |

Commands without a default hotkey are meant to be bound in `[binds]`, for example:

```toml
[binds]
"alt+q" = "close"
"alt+tab" = "focus next"
"alt+shift+tab" = "focus prev"
"alt+e" = "toggle-split"
"alt+v" = "preselect vertical"
"alt+s" = "preselect horizontal"
"alt+return" = "exec open -a iTerm"
"alt+w" = "scratchpad chat"
"alt+r" = "mode resize"
```

The daemon applies the configured layout to the primary display when it starts and when Accessibility reports a new window. Default gaps are `8` points. `Option+R` grows the focused window and `Option+Shift+R` shrinks it. `Option+M` toggles maximize and restore.

The daemon must be running before using the CLI.

`macwm-bar` is included in the distribution and runs independently from the daemon. It receives workspace changes through native macOS notifications and does not poll.

## IPC

Scripts and external bars such as sketchybar have two entry points.

`macwm query` returns JSON on one line with sorted keys:

```bash
macwm query state        # {"focused":{...},"layout":"bsp","mode":"default","windows":[...],"workspace":2,"workspaces":[...]}
macwm query workspaces   # [{"active":false,"id":1,"windows":2},{"active":true,"id":2,"windows":1},...]
macwm query windows      # [{"app":"Code","bundleIdentifier":"com.microsoft.VSCode","floating":false,"focused":true,"frame":{...},"hidden":false,"id":...,"title":"...","workspace":2},...]
```

The events socket at `/tmp/macwm-events.sock` pushes one JSON line per change, `{"event":"state","state":{...}}` with the same state object, whenever the workspace, layout, mode, window set or focus changes. Connect and read lines:

```bash
nc -U /tmp/macwm-events.sock | while read -r line; do
  workspace=$(printf '%s' "$line" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["state"]["workspace"])')
  sketchybar --set workspace label="$workspace"
done
```

`macwm-bar` keeps using native distributed notifications and does not depend on the socket.

## Agent status in the bar

`macwm-bar` watches the AI coding agents on the Mac, Claude Code, Codex and OpenCode, and shows one entry per agent that is running or was active in the last hour: `● claude ×3 plan 37% ctx 42%`. The dot is filled while the agent is using CPU, that is, working rather than waiting for input; `×3` counts live sessions; `plan` is the highest usage of the agent's rate-limit windows, turning yellow at 70% and red at 90%; `ctx` is the fullest context window. Hover the entry for every session with project, model, context, each limit and its reset time.

Sources: Codex writes its rate limits and token counts into its rollout files, OpenCode keeps token counts in its database, and Claude Code reports usage through its status line. For Claude Code, add macwm to the status line command in `~/.claude/settings.json`; it records the session and passes the JSON through to whatever status line you already use:

```json
"statusLine": {
  "type": "command",
  "command": "TMP=$(mktemp); cat > \"$TMP\"; \"$HOME/.local/bin/macwm\" agent-status claude < \"$TMP\" > /dev/null 2>&1; cat \"$TMP\"; rm -f \"$TMP\""
}
```

Replace the final `cat "$TMP"` with your own status line command reading from `"$TMP"` if you have one; without one, `"$HOME/.local/bin/macwm" agent-status claude --render` records the session and prints `model · ctx · 5h · 7d` as the status line. Claude Code only includes plan usage for Claude.ai subscriptions, after the first response of a session.

Several Claude accounts, each launched with its own `CLAUDE_CONFIG_DIR`, get one entry each, `claude-max`, `claude-pro`, with their own limits; add the status line to the `settings.json` inside every config directory.

## Packaging

Build a visual installer:

```bash
VERSION=0.1.0 sh scripts/package-dmg.sh
```

The DMG contains the complete PKG installer as well as the applications. Dragging the apps installs only the applications; double-click the included PKG to install the CLI and LaunchAgents too.

Build a native macOS package installer:

```bash
VERSION=0.1.0 sh scripts/package-pkg.sh
```

The generated files are placed in `dist/` and are ignored by Git. Sign the applications and package before public distribution.

The bar is configured in `~/.config/macwm/config.toml`, in the spirit of waybar:

```toml
[bar]
position = "top"          # top, bottom, left, or right
height = 34
font_size = 11
accent = "#5e81ac"        # active workspace and highlights
opacity = 0.85            # dark tint over the blurred desktop, 0 to 1
hide_empty_workspaces = false
left = ["workspaces", "layout"]
center = ["window"]
right = ["agents", "network", "cpu", "battery", "clock", "settings"]
```

Modules: `workspaces` (pills; the active one in the accent color, a dot on those with windows; click to switch), `layout` (the workspace's layout, or the hotkey mode while one is active), `window` (the focused application and title; click to focus the next window), `agents` (AI coding agents, see below; click for details), `network`, `cpu`, `battery`, `clock` and `settings` (left click opens the settings window, right click offers reload and daemon restart). Scrolling anywhere on the bar switches workspaces. Top and bottom bars are horizontal; left and right bars are vertical and 48 points wide. Changes to `[bar]` apply as soon as the file is saved.

## Distribution

`Distribution/macwm.app/Contents/Info.plist` fixes the bundle identifier at
`com.macwm.app`. `scripts/build-app.sh` creates the app bundle, while
`scripts/codesign.sh` and `scripts/notarize.sh` require explicit environment
variables (`CODESIGN_IDENTITY`, `APPLE_ID`, `TEAM_ID`, and
`KEYCHAIN_PROFILE`). `Distribution/com.macwm.daemon.plist` is a LaunchAgent
template; replace `__MACWM_DAEMON__` during installation. A Homebrew formula
template is in `Formula/macwm.rb.template`.

For a local installation, run `scripts/install.sh` with an optional `PREFIX`
(default `~/.local`). It installs all three executables and idempotently
bootstraps both LaunchAgents without editing the macwm config file.

## Shortcuts

Default hotkeys. `Option` is the `alt` modifier in the configuration.

| Shortcut | Action |
| --- | --- |
| `Option+H` | Focus left |
| `Option+J` | Focus down |
| `Option+K` | Focus up |
| `Option+L` | Focus right |
| `Option+Shift+H/J/K/L` | Swap focused window with its neighbor in that direction |
| `Option+R` | Grow focused window |
| `Option+Shift+R` | Shrink focused window |
| `Option+M` | Toggle maximize and restore |
| `Option+F` | Toggle focused window floating |
| `Option+1..9` | Switch workspace |
| `Option+Shift+1..9` | Send window to workspace |
| `` ` `` (grave) | Show or hide the terminal |

Every default can be changed under `[keys]`, and any command in the table above can be bound to any key or grouped into a mode under `[binds]`; see Custom Hotkeys. Inside a mode only that mode's bindings apply until you leave it, and the bar shows the mode name next to the workspace.

When BSP is active, `move` is structural: it swaps the focused window with the nearest tileable window in that direction and recalculates all cells. It does not translate a window by a fixed pixel distance.

The BSP tree keeps its structure while windows come and go, like Hyprland's dwindle layout: a new window splits the window you last focused, side by side when that window is wider than tall and top to bottom otherwise, or in the direction chosen with `preselect`; a closed window hands its space back to its sibling. Because macOS applications often refuse sizes below roughly 400x300 points and would overflow their tile, a new window splits the largest leaf instead when splitting the focused one would leave cells under that minimum. Ratios changed with `resize`, swaps made with `move` and directions flipped with `toggle-split` therefore survive opening and closing windows.

The BSP layout is recursive and supports any number of tileable windows. With three windows it produces one half-height/full-height area and two stacked areas; with four windows it produces a balanced four-cell layout. Every cell is constrained to the available visible frame and gaps.

On startup, the daemon reads `~/.config/macwm/config.toml`. The loader applies `general.layout`, `general.gap`, `general.auto_tile`, `display.outer_gap` and `display.inner_gap`, plus configurable hotkeys and window rules.

Workspaces `1` through `9` are logical workspaces. `Option+1` through `Option+9` switches workspace; adding Shift sends the focused window there. Windows that belong to other workspaces are parked off-screen at the bottom-right corner of their display instead of being minimized, so switching is instant, never animates through the Dock and keeps the Dock free of minimized windows. Focusing a parked window, for example through `Cmd+Tab`, switches to its workspace. Switching to a workspace returns keyboard focus to the window you last used there, or to its first visible window. Floating and maximized windows return to their previous frame when their workspace becomes active again. Minimized windows and windows of applications hidden with `Cmd+H` leave the layout and rejoin it when restored; the `monocle` layout parks its non-visible windows the same way.

Workspace assignments, floating state, maximize restore frames and bar position
are persisted in `~/.config/macwm/state.json` using bundle identifier, title,
process ID and (when available) window number. Closed windows are removed from
the exported state; older state files remain readable.

Only windows whose Accessibility subrole is `AXStandardWindow` and whose size can be changed are tiled; dialogs, panels, transient popups and fixed-size windows such as iOS apps or games float. Only regular applications, the ones with a Dock icon, are managed; menu bar and accessory apps such as `macwm-bar` or border drawers are never touched. Rules apply automatically when a window is discovered. `bundle_id` is required; `title` and `subrole` are optional additional filters. Actions include workspace assignment, floating, centering and explicit dimensions:

```toml
[[rules]]
bundle_id = "com.apple.finder"
float = true

[[rules]]
bundle_id = "com.microsoft.VSCode"
title = "Welcome"
workspace = 2
float = true
center = true
width = 800
height = 600
```

Saving the configuration file applies it automatically, like Hyprland; an invalid file is reported in `/tmp/macwm-daemon.log` and the previous configuration stays in force. You can also reload by hand:

```bash
macwm reload
```

## Configuration

Copy `example-config.toml` to `~/.config/macwm/config.toml`, edit it, then run `macwm reload`.

### Stopping macwm

Stop or restart the daemon through launchd, not by switching its Accessibility permission off:

```bash
launchctl bootout gui/$(id -u)/com.macwm.daemon     # stop
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.macwm.daemon.plist   # start again
```

If Accessibility is revoked while the daemon runs, it pauses its keyboard and mouse handling within three seconds and resumes when the permission comes back.

### Settings window

The gear at the right end of `macwm-bar` opens a settings window. Its Hotkeys tab lists every binding per mode: click a key field and press the shortcut to record it, pick or type the command, add or delete rows; rows that share a key or name an unknown command turn red and block saving. The General tab covers layout, gaps, smart gaps, focus follows mouse, bar position and terminal; the Apps tab adds floating rules and scratchpads from the list of running applications. Save writes `config.toml`, which the daemon applies immediately. The file is regenerated, so comments in it are not kept. When `macwm.conf` is in use the window is read-only.

### Hyprland dialect

If `~/.config/macwm/macwm.conf` exists it is used instead of `config.toml`, and it is read as a Hyprland configuration, so most of a Hyprland dotfile works after changing window classes to bundle identifiers:

```
$mod = ALT

general {
    gaps_in = 6
    gaps_out = 12
    layout = dwindle
    terminal = com.googlecode.iterm2
}

dwindle {
    no_gaps_when_only = 1
}

input {
    follow_mouse = 1
}

exec-once = sketchybar

bind = $mod, H, movefocus, l
bind = $mod SHIFT, H, movewindow, l
bind = $mod, 1, workspace, 1
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod, Q, killactive
bind = $mod, F, togglefloating
bind = $mod, Return, exec, open -a iTerm
bind = $mod, W, togglespecialworkspace, chat
bind = $mod, R, submap, resize

submap = resize
binde = , L, resizeactive, 10 0
binde = , H, resizeactive, -10 0
bind = , escape, submap, reset
submap = reset

scratchpad = chat, net.whatsapp.WhatsApp
windowrule = float, class:^(com.apple.finder)$
windowrulev2 = workspace 2, class:^(com\.microsoft\.VSCode)$
```

Supported dispatchers: `movefocus`, `movewindow`, `swapwindow`, `workspace` (numbers and `previous`), `movetoworkspace`, `movetoworkspacesilent`, `killactive`, `togglefloating`, `fullscreen` (maps to `maximize`), `togglesplit`, `centerwindow`, `cyclenext`, `exec`, `submap`, `togglespecialworkspace` (maps to `scratchpad`), `resizeactive` and `splitratio` (sign chooses grow or shrink) and `layoutmsg preselect`. Window rules understand `float`, `tile`, `center`, `workspace N` and `size W H` with `class:` as the bundle identifier and `title:`; rules for the same matcher merge. `general.terminal` and `scratchpad = name, bundle.id` are macwm extensions. Dispatchers and sections without a macOS equivalent, `decoration`, `animations`, `bindm`, are ignored; malformed values reject the file, as with the TOML format.


### Terminal

The global terminal toggle works with any installed terminal application. Configure its bundle identifier:

```toml
[terminal]
bundle_id = "com.googlecode.iterm2"
```

Available examples:

```text
Terminal.app  com.apple.Terminal
iTerm2        com.googlecode.iterm2
Ghostty       com.mitchellh.ghostty
Alacritty     org.alacritty
```

`terminal_toggle` defaults to `grave` (the backtick key) and is registered globally without modifiers. Change it under `[keys]`, for example `terminal_toggle = "ctrl+grave"`, or run `macwm toggle-terminal`.

The toggle launches the terminal when it is not running, minimizes its visible window, and restores, activates and resizes a minimized or hidden window to cover the whole current screen. The terminal is excluded from workspace assignments, hiding and tiling, so macwm never moves or hides it during workspace changes. macOS provides no public API to keep another application's window always on top or visible on every Space; this limitation cannot be removed without private APIs.

### Mouse

Windows can be handled with the mouse, like `bindm` in Hyprland, by holding `Option` while dragging:

- left button on a floating window moves it; on a tiled window, dropping it on another tiled window swaps the two;
- right button on a floating window resizes it from its bottom-right corner; on a tiled window it moves the splits around it, so dragging right makes it wider and dragging down makes it taller.

Windows that macwm does not manage are not affected, so `Option+click` keeps working in them.

### Smart gaps and autostart

```toml
[general]
smart_gaps = true

[autostart]
borders = "borders width=4"
bar = "sketchybar"
```

`smart_gaps` removes every gap when a workspace shows a single tiled window, like `no_gaps_when_only` in Hyprland. `[autostart]` is the equivalent of `exec-once`: each command line runs once through your login shell when the daemon starts, in the order of the names.

### Tab groups

Several windows can share one tile like tabs, Hyprland's `togglegroup`:

```toml
[binds]
"alt+g" = "group toggle"
"alt+shift+g" = "group remove"
"alt+ctrl+h" = "group add left"
"alt+ctrl+l" = "group add right"
"alt+bracketright" = "group next"
"alt+bracketleft" = "group prev"
```

`group toggle` turns the focused window into a group of one, or dissolves the group it is in, giving every member its own tile again. `group add <direction>` pulls the focused window into the neighbor in that direction, creating a group there when needed, and shows it. `group remove` takes the focused window out into a tile next to the group. `group next` and `group prev` cycle the visible member; clicking a tab does the same. A strip above the group lists its members with the visible one highlighted. Hidden members are parked off-screen and skipped by keyboard focus; focusing one another way, for example through `Cmd+Tab`, brings it to the front of its group. Groups are not kept across daemon restarts. In the Hyprland dialect, `togglegroup`, `moveintogroup`, `moveoutofgroup` and `changegroupactive` map onto these.

### Focus border

```toml
[border]
enabled = true
width = 3
color = "#5e81ac"
```

macwm can draw a frame around the focused window, the way Hyprland's `col.active_border` does, without any extra application. It is a click-through overlay that follows focus, tiling, workspace switches and mouse drags. Off by default; if you run JankyBorders or similar, leave it off. In the Hyprland dialect `general { border_size, col.active_border }` map onto it, taking the first color of a gradient.

### Master layout

```toml
[master]
orientation = "left"   # left, right, top or bottom
ratio = 0.55           # share of the frame the masters take
count = 1              # windows treated as masters
```

The `master` layout, `macwm layout master`, keeps the first `count` windows on the chosen side and stacks the rest. `resize grow` and `resize shrink` change the ratio while that layout is active, and the `master` commands change ratio, count and orientation at runtime until the next reload. In the Hyprland dialect, `master { orientation, mfact }` and `layoutmsg addmaster|removemaster|orientation*|mfact` map onto them.

### Cursor warp

```toml
[general]
cursor_warp = true
```

On by default, as in Hyprland: focusing a window from the keyboard, with `focus`, `focus next` or a workspace switch, moves the pointer to its center. Set it to `false`, or `cursor { no_warps = true }` in the Hyprland dialect, to leave the pointer alone.

### Focus follows mouse

```toml
[general]
focus_follows_mouse = true
```

When enabled, resting the pointer over a different window of the active workspace focuses and raises it, without clicking. It is off by default and can be toggled with `macwm reload`.

### Scratchpads

Any application can be toggled like the drop-down terminal. Give it a name under `[scratchpads]` and bind `scratchpad <name>`:

```toml
[scratchpads]
chat = "net.whatsapp.WhatsApp"
notes = "com.apple.Notes"

[binds]
"alt+w" = "scratchpad chat"
"alt+n" = "scratchpad notes"
```

`scratchpad` launches the application when it is not running, minimizes its window when visible and restores and focuses it otherwise, keeping the window's own size. Scratchpad applications, like the terminal, are never tiled, parked or hidden by workspace switches. `scratchpad` also accepts a bundle identifier directly.

### Navbar

The native macwm navbar can be placed at any screen edge:

```toml
[bar]
position = "bottom"
```

Valid positions are `top`, `bottom`, `left` and `right`.

### Custom Hotkeys

Bind any key to any command under `[binds]`. A binding is a `+` separated list of modifiers and one key; the command is what you would pass to the `macwm` CLI:

```toml
[binds]
"alt+h" = "focus left"
"alt+shift+h" = "move left"
"cmd+return" = "toggle-terminal"
"alt+1" = "workspace 1"
"alt+shift+1" = "send-to-workspace 1"
"alt+r" = "mode resize"

[binds.resize]
"h" = "resize shrink"
"l" = "resize grow"
"escape" = "mode default"
```

`[binds.<name>]` defines a mode, the equivalent of a Hyprland submap: while a mode is active only its bindings apply, and `mode default` leaves it. Keys that are not bound in the active mode reach the focused application as usual. The current mode is reported by `macwm status` and can also be set with `macwm mode <name>`.

Modifiers are `shift`, `ctrl` (or `control`), `alt` (or `option`) and `cmd` (or `command`, `super`). Keys are letters, digits, `f1` to `f15`, `return`, `tab`, `space`, `escape`, `delete`, `grave`, `minus`, `equal`, `leftbracket`, `rightbracket`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backslash`, the arrows `left`, `right`, `up`, `down`, and `home`, `end`, `pageup`, `pagedown`, `forwarddelete`. Symbol names follow the active keyboard layout: `minus` is whichever key types `-` on your layout, and falls back to the US position when no key types that character without modifiers. Any single character your layout types without modifiers is also a valid key name, for example `"alt+ñ"` on a Spanish keyboard. Letters, digits and named keys such as `return` keep their physical positions. Hotkeys are rebuilt when you switch input sources.

The older `[keys]` names such as `focus_left`, `resize`, `terminal_toggle` and `workspace_1` keep working; `[binds]` entries override them when they use the same key.

Apply changes without restarting the daemon:

```bash
macwm reload
```
