#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Re-signs build/<APP_NAME>.app with a Developer ID certificate, notarizes it and
# staples the ticket. Not used by CI yet; releases are ad-hoc signed for now.
#
# Requires an Apple Developer Program membership and:
#   DEVELOPER_ID   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE a profile saved with `xcrun notarytool store-credentials`
#
#   scripts/build-app.sh && DEVELOPER_ID=... NOTARY_PROFILE=... scripts/notarize.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=config.sh
source "$ROOT/scripts/config.sh"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

app="$ROOT/build/$APP_NAME.app"
zip="$ROOT/build/$APP_NAME-$VERSION.zip"
[[ -d "$app" ]] || { echo "Missing $app; run scripts/build-app.sh first." >&2; exit 1; }

echo "==> Signing with $DEVELOPER_ID (hardened runtime)"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$app"
codesign --verify --strict --verbose=2 "$app"

echo "==> Notarizing"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "==> Done: $zip"
