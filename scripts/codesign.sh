#!/bin/sh
set -eu

APP=${APP:-"$(CDPATH= cd -- "$(dirname -- "$0")/../dist" && pwd)/macwm.app"}
BAR_APP=${BAR_APP:-"$(dirname -- "$APP")/macwm-bar.app"}
IDENTITY=${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a signing identity}
ENTITLEMENTS=${ENTITLEMENTS:-}

if [ -n "$ENTITLEMENTS" ]; then
  codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
if [ -d "$BAR_APP" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$BAR_APP"
  codesign --verify --deep --strict --verbose=2 "$BAR_APP"
fi
