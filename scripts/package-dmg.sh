#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-0.2.0}
OUT=${OUT:-"$ROOT/dist"}
NAME="macwm-$VERSION-arm64"
STAGING="$OUT/.dmg-staging"
DMG="$OUT/$NAME.dmg"

VERSION="$VERSION" OUT="$OUT" "$ROOT/scripts/build-app.sh"
VERSION="$VERSION" OUT="$OUT" "$ROOT/scripts/package-pkg.sh"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$OUT/macwm.app" "$STAGING/macwm.app"
cp -R "$OUT/macwm-bar.app" "$STAGING/macwm-bar.app"
cp "$OUT/$NAME.pkg" "$STAGING/macwm-$VERSION.pkg"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/README.md" "$STAGING/README.md"

hdiutil create -volname "macwm $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
printf '%s\n' "created $DMG"
