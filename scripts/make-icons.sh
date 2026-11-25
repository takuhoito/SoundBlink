#!/usr/bin/env bash
# Regenerates the icon assets from their SVG sources:
#
#   Resources/AppIcon.svg       -> Resources/AppIcon.icns   (app icon)
#   Resources/StatusIcon.svg    -> Resources/StatusIcon.pdf (menu bar template image)
#   Resources/AppIcon.svg       -> site/assets/{icon,favicon}.svg, *.png (website icons)
#   Resources/SocialPreview.svg -> site/assets/og.png       (website and GitHub social preview)
#
# The generated files are committed, so building the app does not need this.
# Requires rsvg-convert (`brew install librsvg`) and iconutil (Xcode tools).
# Run it on a Mac: the social preview text is set in Helvetica Neue.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/Resources"
SITE="$ROOT/site/assets"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

# Keep the generated PDF byte-for-byte reproducible (no creation timestamp).
export SOURCE_DATE_EPOCH=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "==> AppIcon.icns"
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$RES/AppIcon.svg" -o "$iconset/icon_${size}x${size}.png"
  rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$RES/AppIcon.svg" -o "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$RES/AppIcon.icns"

echo "==> StatusIcon.pdf"
rsvg-convert -f pdf -w 18 -h 18 "$RES/StatusIcon.svg" -o "$RES/StatusIcon.pdf"

echo "==> Website assets"
mkdir -p "$SITE"
cp "$RES/AppIcon.svg" "$SITE/icon.svg"
# Favicons: crop the margin around the tile so the icon fills the browser tab.
sed 's/viewBox="0 0 1024 1024"/viewBox="92 92 840 840"/' "$RES/AppIcon.svg" > "$SITE/favicon.svg"
rsvg-convert -w 32 -h 32 "$SITE/favicon.svg" -o "$SITE/favicon-32.png"
# Apple touch icon: a full-bleed square, because iOS rounds the corners itself.
sed 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' "$RES/AppIcon.svg" > "$work/touch.svg"
rsvg-convert -w 180 -h 180 -b '#1C1C1E' "$work/touch.svg" -o "$SITE/apple-touch-icon.png"
rsvg-convert -w 1280 -h 640 "$RES/SocialPreview.svg" -o "$SITE/og.png"

echo "==> Done"
