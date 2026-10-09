#!/bin/bash
# Assemble Smash.app from the SwiftPM executable.
#
# SwiftPM builds a bare Mach-O; a SwiftUI app with a MenuBarExtra needs a real
# bundle with an Info.plist, and LSUIElement=false so it gets both a window and
# a menubar item. Ad-hoc signed so it launches locally without a developer
# account; replace the identity to distribute.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SmashMac"
APP="build/Smash.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Smash"
ICON_SRC="../SmashiOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  ICONSET="$(mktemp -d)/Smash.iconset"
  mkdir -p "$ICONSET"
  for px in 16 32 128 256 512; do
    sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$ICON_SRC" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Smash.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Smash</string>
  <key>CFBundleDisplayName</key><string>Smash</string>
  <key>CFBundleIdentifier</key><string>com.pbnkp.smash.mac</string>
  <key>CFBundleExecutable</key><string>Smash</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>6.1</string>
  <key>CFBundleVersion</key><string>6.1.1</string>
  <key>CFBundleIconFile</key><string>Smash</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>smash</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Smash Artifact</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key><array><string>public.plain-text</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "warning: ad-hoc signing failed; the app may not launch"
echo "built: $APP"
