#!/bin/bash
# Build + bundle + sign Smash.app (menu-bar). swiftc, no Xcode project.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/Smash.app}"
IDENT="com.pbnkp.smash.menubar"
CERT="Developer ID Application: NKPS MEDIA, LLC (HLT6DNEZSF)"

BIN=/tmp/smash-menubar.build
swiftc -O -o "$BIN" smash-menubar.swift

mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.pbnkp.smash.menubar</string>
  <key>CFBundleName</key><string>Smash</string>
  <key>CFBundleDisplayName</key><string>Smash</string>
  <key>CFBundleExecutable</key><string>smash-menubar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>5.1</string>
  <key>CFBundleVersion</key><string>5.1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Files and folders</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.item</string></array>
  </dict></array>
  <key>NSServices</key><array><dict>
    <key>NSMenuItem</key><dict><key>default</key><string>Share to Smash</string></dict>
    <key>NSMessage</key><string>smashFiles</string>
    <key>NSSendFileTypes</key><array><string>public.item</string></array>
    <key>NSTimeout</key><string>30000</string>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 pbnkp.</string>
</dict></plist>
PLIST
cp "$BIN" "$APP/Contents/MacOS/smash-menubar"
chmod 755 "$APP/Contents/MacOS/smash-menubar"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "NKPS MEDIA"; then
  codesign --force --options runtime --timestamp --sign "$CERT" --identifier "$IDENT" "$APP"
else
  codesign --force --sign - --identifier "$IDENT" "$APP"
  echo "note: Developer ID cert not found — ad-hoc signed"
fi
codesign -v "$APP" && echo "signed ok"
echo "built: $APP"
