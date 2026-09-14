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
  <key>CFBundleShortVersionString</key><string>6.0</string>
  <key>CFBundleVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
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
