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

The current IPC commands are:

```bash
macwm status
macwm focus left
macwm move right
macwm resize grow
macwm resize shrink
macwm workspace 2
macwm send-to-workspace 3
macwm layout bsp
macwm layout stack
macwm layout monocle
macwm layout master
macwm reload
macwm toggle-float
macwm maximize
macwm toggle-terminal
```

The daemon applies the configured layout to the primary display when it starts and when Accessibility reports a new window. Default gaps are `8` points. `Option+R` grows the focused window and `Option+Shift+R` shrinks it. `Option+M` toggles maximize and restore.

The daemon must be running before using the CLI.

`macwm-bar` is included in the distribution and runs independently from the daemon. It receives workspace changes through native macOS notifications and does not poll.

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

| Shortcut | Action |
| --- | --- |
| `Option+H` | Focus left |
| `Option+J` | Focus down |
| `Option+K` | Focus up |
| `Option+L` | Focus right |
| `Option+Shift+H/J/K/L` | Swap focused window with directional neighbor |
| `Option+R` | Grow focused window |
| `Option+Shift+R` | Shrink focused window |
| `Option+F` | Toggle focused window floating |
| `Option+1..9` | Switch workspace |
| `Option+Shift+1..9` | Send window to workspace |

When BSP is active, `move` is structural: it swaps the focused window with the nearest tileable window in that direction and recalculates all cells. It does not translate a window by a fixed pixel distance.

The BSP layout is recursive and supports any number of tileable windows. With three windows it produces one half-height/full-height area and two stacked areas; with four windows it produces a balanced four-cell layout. Every cell is constrained to the available visible frame and gaps.

On startup, the daemon reads `~/.config/macwm/config.toml`. The loader applies `general.layout`, `general.gap`, `general.auto_tile`, `display.outer_gap` and `display.inner_gap`, plus configurable hotkeys and window rules.

Workspaces `1` through `9` are logical workspaces. `Option+1` through `Option+9` switches workspace; adding Shift sends the focused window there. Windows that belong to other workspaces are parked off-screen at the bottom-right corner of their display instead of being minimized, so switching is instant, never animates through the Dock and keeps the Dock free of minimized windows. Focusing a parked window, for example through `Cmd+Tab`, switches to its workspace. Floating and maximized windows return to their previous frame when their workspace becomes active again. Minimized windows and windows of applications hidden with `Cmd+H` leave the layout and rejoin it when restored; the `monocle` layout parks its non-visible windows the same way.

Workspace assignments, floating state, maximize restore frames and bar position
are persisted in `~/.config/macwm/state.json` using bundle identifier, title,
process ID and (when available) window number. Closed windows are removed from
the exported state; older state files remain readable.

Only windows whose Accessibility subrole is `AXStandardWindow` are tiled; dialogs, panels and transient popups float. Only regular applications, the ones with a Dock icon, are managed; menu bar and accessory apps such as `macwm-bar` or border drawers are never touched. Rules apply automatically when a window is discovered. `bundle_id` is required; `title` and `subrole` are optional additional filters. Actions include workspace assignment, floating, centering and explicit dimensions:

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

### Navbar

The native macwm navbar can be placed at any screen edge:

```toml
[bar]
position = "bottom"
```

Valid positions are `top`, `bottom`, `left` and `right`.

### Custom Hotkeys

All supported hotkeys can be changed without recompiling:

```toml
[keys]
terminal_toggle = "ctrl+grave"
workspace_1 = "alt+1"
workspace_2 = "alt+2"
workspace_3 = "alt+3"
workspace_4 = "alt+4"
workspace_5 = "alt+5"
workspace_6 = "alt+6"
workspace_7 = "alt+7"
workspace_8 = "alt+8"
workspace_9 = "alt+9"
```

Apply changes without restarting the daemon:

```bash
macwm reload
```
