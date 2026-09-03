#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-0.2.0}
OUT=${OUT:-"$ROOT/dist"}
NAME="macwm-$VERSION-arm64"
PAYLOAD="$OUT/.pkg-payload"
SCRIPTS="$OUT/.pkg-scripts"
PKG="$OUT/$NAME.pkg"

VERSION="$VERSION" OUT="$OUT" "$ROOT/scripts/build-app.sh"
rm -rf "$PAYLOAD" "$SCRIPTS" "$PKG"
mkdir -p "$PAYLOAD/Applications" "$PAYLOAD/usr/local/bin" "$PAYLOAD/usr/local/share/macwm" "$SCRIPTS"
cp -R "$OUT/macwm.app" "$PAYLOAD/Applications/macwm.app"
cp -R "$OUT/macwm-bar.app" "$PAYLOAD/Applications/macwm-bar.app"
install -m 755 "$OUT/macwm.app/Contents/MacOS/macwm" "$PAYLOAD/usr/local/bin/macwm"
install -m 755 "$OUT/macwm.app/Contents/MacOS/macwm-daemon" "$PAYLOAD/usr/local/bin/macwm-daemon"
install -m 755 "$OUT/macwm-bar.app/Contents/MacOS/macwm-bar" "$PAYLOAD/usr/local/bin/macwm-bar"
cp "$ROOT/example-config.toml" "$PAYLOAD/usr/local/share/macwm/example-config.toml"
sed 's|__MACWM_DAEMON__|/usr/local/bin/macwm-daemon|g' "$ROOT/Distribution/com.macwm.daemon.plist" > "$PAYLOAD/usr/local/share/macwm/com.macwm.daemon.plist"
sed 's|__MACWM_BAR__|/usr/local/bin/macwm-bar|g' "$ROOT/Distribution/com.macwm.bar.plist" > "$PAYLOAD/usr/local/share/macwm/com.macwm.bar.plist"

cat > "$SCRIPTS/postinstall" <<EOF
#!/bin/sh
set -eu
CONSOLE_USER=\$(stat -f '%Su' /dev/console)
CONSOLE_UID=\$(id -u "\$CONSOLE_USER")
CONSOLE_HOME=\$(dscl . -read "/Users/\$CONSOLE_USER" NFSHomeDirectory | cut -d ' ' -f 2-)
LAUNCH_AGENTS="\$CONSOLE_HOME/Library/LaunchAgents"
mkdir -p "\$LAUNCH_AGENTS"
cp /usr/local/share/macwm/com.macwm.daemon.plist "\$LAUNCH_AGENTS/com.macwm.daemon.plist"
cp /usr/local/share/macwm/com.macwm.bar.plist "\$LAUNCH_AGENTS/com.macwm.bar.plist"
if [ ! -f "\$CONSOLE_HOME/.config/macwm/config.toml" ]; then
  mkdir -p "\$CONSOLE_HOME/.config/macwm"
  cp /usr/local/share/macwm/example-config.toml "\$CONSOLE_HOME/.config/macwm/config.toml"
  chown "\$CONSOLE_USER" "\$CONSOLE_HOME/.config/macwm/config.toml"
fi
chown "\$CONSOLE_USER" "\$LAUNCH_AGENTS/com.macwm.daemon.plist" "\$LAUNCH_AGENTS/com.macwm.bar.plist"
plutil -lint "\$LAUNCH_AGENTS/com.macwm.daemon.plist" "\$LAUNCH_AGENTS/com.macwm.bar.plist" >/dev/null
# bootout returns before the service is gone; bootstrapping too early fails.
unload() {
  launchctl bootout "gui/\$CONSOLE_UID/\$1" 2>/dev/null || true
  for _ in \$(seq 1 50); do
    launchctl print "gui/\$CONSOLE_UID/\$1" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}
unload com.macwm.daemon
unload com.macwm.bar
# Run the agents as the console user; the installer itself runs as root.
launchctl asuser "\$CONSOLE_UID" launchctl bootstrap "gui/\$CONSOLE_UID" "\$LAUNCH_AGENTS/com.macwm.daemon.plist" || true
launchctl asuser "\$CONSOLE_UID" launchctl bootstrap "gui/\$CONSOLE_UID" "\$LAUNCH_AGENTS/com.macwm.bar.plist" || true
EOF
chmod 755 "$SCRIPTS/postinstall"

pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" --identifier com.macwm.pkg --version "$VERSION" --install-location / "$PKG"
rm -rf "$PAYLOAD" "$SCRIPTS"
printf '%s\n' "created $PKG"
