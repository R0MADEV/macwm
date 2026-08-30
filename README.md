# macwm

Lightweight, keyboard-first window management for macOS.

## Status

Planning scaffold. The current package contains:

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

Tests use the explicit `swift-testing` package because this manifest targets
Swift tools 6.0 while the current test sources import `Testing`. The test
bundle is therefore buildable without relying on an undeclared module. Run it
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
```

The daemon applies the configured layout to the primary display when it starts and when Accessibility reports a new window. Default gaps are `8` points. `Option+R` grows the focused window and `Option+Shift+R` shrinks it. `Option+M` toggles maximize and restore.

The daemon must be running before using the CLI.

`macwm-bar` is included in the distribution and runs independently from the daemon. It receives workspace changes through native macOS notifications and does not poll.

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

Workspaces `1` through `9` are logical workspaces. `Option+1` through `Option+9` switches workspace; adding Shift sends the focused window there. The current implementation uses Accessibility window minimization to hide windows, because macOS does not reliably support `AXHidden` on individual windows.

Workspace assignments, floating state, maximize restore frames and bar position
are persisted in `~/.config/macwm/state.json` using bundle identifier, title,
process ID and (when available) window number. Closed windows are removed from
the exported state; older state files remain readable.

Rules apply automatically when a window is discovered. `bundle_id` is required; `title` and `subrole` are optional additional filters. Actions include workspace assignment, floating, centering and explicit dimensions:

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
