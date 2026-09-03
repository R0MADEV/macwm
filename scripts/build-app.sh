#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-0.2.0}
OUT=${OUT:-"$ROOT/dist"}
APP="$OUT/macwm.app"
BAR_APP="$OUT/macwm-bar.app"

swift build --configuration release --product macwm-daemon
swift build --configuration release --product macwm
swift build --configuration release --product macwm-bar
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/macwm-daemon" "$APP/Contents/MacOS/macwm-daemon"
cp "$ROOT/.build/release/macwm" "$APP/Contents/MacOS/macwm"
sed "s/<string>0.1.0<\//<string>$VERSION<\//; s/<string>1<\//<string>$VERSION<\//" \
  "$ROOT/Distribution/macwm.app/Contents/Info.plist" > "$APP/Contents/Info.plist"
printf '%s\n' "built $APP"
rm -rf "$BAR_APP"
mkdir -p "$BAR_APP/Contents/MacOS"
cp "$ROOT/.build/release/macwm-bar" "$BAR_APP/Contents/MacOS/macwm-bar"
cp "$ROOT/Distribution/macwm-bar.app/Contents/Info.plist" "$BAR_APP/Contents/Info.plist"
printf '%s\n' "built $BAR_APP"
