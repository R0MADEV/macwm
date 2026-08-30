#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PREFIX=${PREFIX:-"$HOME/.local"}
LAUNCH_AGENTS=${LAUNCH_AGENTS:-"$HOME/Library/LaunchAgents"}
VERSION=${VERSION:-0.1.0}

case "$PREFIX" in
  "$HOME"/*|/usr/local|/opt/homebrew) ;;
  *) printf '%s\n' "install.sh: PREFIX must be inside HOME or be a standard Homebrew prefix" >&2; exit 2 ;;
esac

VERSION="$VERSION" OUT="$ROOT/dist" "$ROOT/scripts/build-app.sh"
mkdir -p "$PREFIX/bin" "$LAUNCH_AGENTS"
install -m 755 "$ROOT/dist/macwm.app/Contents/MacOS/macwm-daemon" "$PREFIX/bin/macwm-daemon"
install -m 755 "$ROOT/dist/macwm.app/Contents/MacOS/macwm" "$PREFIX/bin/macwm"
install -m 755 "$ROOT/dist/macwm-bar.app/Contents/MacOS/macwm-bar" "$PREFIX/bin/macwm-bar"

daemon_plist="$LAUNCH_AGENTS/com.macwm.daemon.plist"
bar_plist="$LAUNCH_AGENTS/com.macwm.bar.plist"
sed "s|__MACWM_DAEMON__|$PREFIX/bin/macwm-daemon|g" "$ROOT/Distribution/com.macwm.daemon.plist" > "$daemon_plist"
sed "s|__MACWM_BAR__|$PREFIX/bin/macwm-bar|g" "$ROOT/Distribution/com.macwm.bar.plist" > "$bar_plist"
plutil -lint "$daemon_plist" "$bar_plist" >/dev/null

launchctl bootout "gui/$(id -u)"/com.macwm.daemon 2>/dev/null || true
launchctl bootout "gui/$(id -u)"/com.macwm.bar 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$daemon_plist"
launchctl bootstrap "gui/$(id -u)" "$bar_plist"
printf '%s\n' "installed macwm, macwm-daemon and macwm-bar in $PREFIX/bin"
