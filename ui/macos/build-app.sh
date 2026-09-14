#!/bin/bash
# Build + bundle + sign Smash.app (menu-bar). swiftc, no Xcode project.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/Smash.app}"
IDENT="com.pbnkp.smash.menubar"
# Set SMASH_CODESIGN_ID to your own "Developer ID Application: NAME (TEAMID)"
# to get a Developer ID signature. Unset = ad-hoc signing, reported honestly.
CERT="${SMASH_CODESIGN_ID:-}"

# Icon assets are generated from the SVG sources so the bundle always carries a
# real .icns and a real template glyph rather than an SF Symbol stand-in.
bash "$(dirname "$0")/make-icon.sh" >/dev/null 2>&1 || echo "note: icon build skipped (sips/iconutil unavailable)"

# Version is read from the CLI, which is the single source of truth. Hardcoding
# it here is how the bundle came to claim 5.3 while the tool was 6.x.
VER="$(sed -n 's/^VERSION="\([0-9.]*\)".*/\1/p' ../../smash | head -1)"
VER="${VER:-0.0}"

BIN=/tmp/smash-menubar.build
swiftc -O -o "$BIN" smash-menubar.swift

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.pbnkp.smash.menubar</string>
  <key>CFBundleName</key><string>Smash</string>
  <key>CFBundleDisplayName</key><string>Smash</string>
  <key>CFBundleExecutable</key><string>smash-menubar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VER}</string>
  <key>CFBundleVersion</key><string>${VER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 pbnkp.</string>
</dict></plist>
PLIST
# Ship the icon assets. CFBundleIconFile names AppIcon.icns; the menu-bar
# template glyph is looked up by name at runtime.
for a in build/AppIcon.icns build/menubar.png build/menubar@2x.png; do
  [ -f "$a" ] && cp "$a" "$APP/Contents/Resources/"
done

cp "$BIN" "$APP/Contents/MacOS/smash-menubar"
chmod 755 "$APP/Contents/MacOS/smash-menubar"

if [ -n "$CERT" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT"; then
  codesign --force --sign "$CERT" --identifier "$IDENT" "$APP"
else
  codesign --force --sign - --identifier "$IDENT" "$APP"
  echo "note: no SMASH_CODESIGN_ID set (or cert absent) — ad-hoc signed"
fi
codesign -v "$APP" && echo "signed ok"
echo "built: $APP"
