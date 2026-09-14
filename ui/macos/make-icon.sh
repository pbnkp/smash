#!/bin/bash
# Build real macOS icon assets from the SVG sources. No external dependencies:
# macOS `sips` rasterises the SVG and `iconutil` packs the .icns.
#
#   ui/macos/make-icon.sh            # writes build/AppIcon.icns + menubar PNGs
#
# Outputs (git-ignored build products, regenerated on demand):
#   build/AppIcon.icns          the Finder/Dock icon, all 10 required variants
#   build/menubar.png           16pt template glyph @1x
#   build/menubar@2x.png        16pt template glyph @2x
set -euo pipefail
cd "$(dirname "$0")"
SRC_APP="appicon.svg"          # the macOS-grid icon; ../../logo.svg is the wordmark/web logo
SRC_BAR="menubar-icon.svg"
OUT="build"; ICONSET="$OUT/AppIcon.iconset"
[ -f "$SRC_APP" ] || { echo "missing $SRC_APP" >&2; exit 2; }
command -v sips >/dev/null || { echo "sips not found (macOS only)" >&2; exit 2; }
command -v iconutil >/dev/null || { echo "iconutil not found (macOS only)" >&2; exit 2; }

rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# Apple's required set: each logical size at 1x and 2x.
render() { # <src> <px> <dest>
  sips -s format png -z "$2" "$2" "$1" --out "$3" >/dev/null
}
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $spec
  render "$SRC_APP" "$1" "$ICONSET/$2.png"
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"
echo "built $OUT/AppIcon.icns ($(wc -c < "$OUT/AppIcon.icns" | tr -d ' ') bytes, $(ls "$ICONSET" | wc -l | tr -d ' ') variants)"

# Menu-bar template glyph. 16pt logical; @2x for Retina.
if [ -f "$SRC_BAR" ]; then
  render "$SRC_BAR" 16 "$OUT/menubar.png"
  render "$SRC_BAR" 32 "$OUT/menubar@2x.png"
  echo "built $OUT/menubar.png + @2x (template glyph)"
fi
