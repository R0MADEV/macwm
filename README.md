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
| `macwm send-to-workspace N` | Send the focused window to workspace `N` | `Option+Shift+N` |
| `macwm focus left\|down\|up\|right` | Focus the nearest visible window in that direction | `Option+H/J/K/L` |
| `macwm focus next\|prev` | Cycle focus through the visible windows of the workspace, wrapping around | none |
| `macwm move left\|down\|up\|right` | Swap the focused window with its neighbor in that direction | `Option+Shift+H/J/K/L` |
| `macwm resize grow\|shrink` | Tiled in BSP: give the window 5% more or less of its split; floating: grow or shrink by 40 points | `Option+R` / `Option+Shift+R` |
| `macwm maximize` | Toggle between maximized and the previous frame | `Option+M` |
| `macwm toggle-float` | Toggle floating for the focused window | `Option+F` |
| `macwm toggle-split` | Flip the split direction of the focused window's node in the BSP tree | none |
| `macwm preselect vertical\|horizontal` | Choose how the next window opened in the workspace splits the focused one | none |
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

The bar position is configured in `~/.config/macwm/config.toml`:

```toml
[bar]
position = "top" # top, bottom, left, or right
```

The default is `top`. Top and bottom use a horizontal layout; left and right use a vertical layout.

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

The BSP tree keeps its structure while windows come and go, like Hyprland's dwindle layout: a new window splits the window you last focused, side by side when that window is wider than tall and top to bottom otherwise, or in the direction chosen with `preselect`; a closed window hands its space back to its sibling. Ratios changed with `resize`, swaps made with `move` and directions flipped with `toggle-split` therefore survive opening and closing windows.

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

Reload a valid configuration without restarting the daemon:

```bash
macwm reload
```

## Configuration

Copy `example-config.toml` to `~/.config/macwm/config.toml`, edit it, then run `macwm reload`.

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

Modifiers are `shift`, `ctrl` (or `control`), `alt` (or `option`) and `cmd` (or `command`, `super`). Keys are letters, digits, `f1` to `f15`, `return`, `tab`, `space`, `escape`, `delete`, `grave`, `minus`, `equal`, `leftbracket`, `rightbracket`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backslash`, the arrows `left`, `right`, `up`, `down`, and `home`, `end`, `pageup`, `pagedown`, `forwarddelete`. Key names follow the US layout positions.

The older `[keys]` names such as `focus_left`, `resize`, `terminal_toggle` and `workspace_1` keep working; `[binds]` entries override them when they use the same key.

Apply changes without restarting the daemon:

```bash
macwm reload
```
