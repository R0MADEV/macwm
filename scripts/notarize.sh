#!/bin/sh
set -eu

APP=${APP:-"$(CDPATH= cd -- "$(dirname -- "$0")/../dist" && pwd)/macwm.app"}
APPLE_ID=${APPLE_ID:?Set APPLE_ID}
TEAM_ID=${TEAM_ID:?Set TEAM_ID}
KEYCHAIN_PROFILE=${KEYCHAIN_PROFILE:?Set KEYCHAIN_PROFILE for notarytool}

ditto -c -k --keepParent "$APP" "${APP%.app}.zip"
xcrun notarytool submit "${APP%.app}.zip" --keychain-profile "$KEYCHAIN_PROFILE" --team-id "$TEAM_ID" --apple-id "$APPLE_ID" --wait
xcrun stapler staple "$APP"
