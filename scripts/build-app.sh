#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Builds build/<APP_NAME>.app (universal, ad-hoc signed) and a zip for distribution.
#
#   scripts/build-app.sh                # arm64 + x86_64
#   ARCHS=arm64 scripts/build-app.sh    # faster local build
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=config.sh
source "$ROOT/scripts/config.sh"
cd "$ROOT"

ARCHS="${ARCHS:-arm64 x86_64}"
arch_flags=()
for arch in $ARCHS; do
  arch_flags+=(--arch "$arch")
done

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build -c release "${arch_flags[@]}"
bin_dir="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

app="$ROOT/build/$APP_NAME.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_dir/$APP_NAME" "$app/Contents/MacOS/$APP_NAME"

sed -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@BUILD_NUMBER@|$BUILD_NUMBER|g" \
    -e "s|@AUTHOR@|$AUTHOR|g" \
    -e "s|@GITHUB_REPO@|$GITHUB_REPO|g" \
    "$ROOT/Resources/Info.plist.in" > "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist"

cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/StatusIcon.pdf" "$app/Contents/Resources/"

for lproj in "$ROOT"/Resources/*.lproj; do
  for strings in "$lproj"/*.strings; do
    plutil -lint -s "$strings"
  done
  cp -R "$lproj" "$app/Contents/Resources/"
done

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

zip="$ROOT/build/$APP_NAME-$VERSION.zip"
rm -f "$zip"
(cd "$ROOT/build" && ditto -c -k --keepParent "$APP_NAME.app" "$(basename "$zip")")

echo "==> Done"
echo "    App: $app"
echo "    Zip: $zip"
lipo -info "$app/Contents/MacOS/$APP_NAME"
