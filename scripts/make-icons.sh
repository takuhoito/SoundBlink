#!/usr/bin/env bash
# Regenerates the icon assets from their SVG sources:
#
#   Resources/AppIcon.svg    -> Resources/AppIcon.icns   (app icon)
#   Resources/StatusIcon.svg -> Resources/StatusIcon.pdf (menu bar template image)
#
# The generated files are committed, so building the app does not need this.
# Requires rsvg-convert (`brew install librsvg`) and iconutil (Xcode tools).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/Resources"

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

echo "==> Done"
