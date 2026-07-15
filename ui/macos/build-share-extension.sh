#!/bin/bash
# Build the macOS Share extension without an Xcode project. The extension is a
# separate, sandboxed binary embedded in Smash.app/Contents/PlugIns.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/Smash.app}"
APPEX="$APP/Contents/PlugIns/SmashShare.appex"
IDENT="com.pbnkp.smash.share"
CERT="Developer ID Application: NKPS MEDIA, LLC (HLT6DNEZSF)"

[ -d "$APP/Contents" ] || { echo "build Smash.app first" >&2; exit 2; }
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

swiftc -O -parse-as-library -application-extension \
  -module-name SmashShare \
  -framework AppKit -framework Social -framework UniformTypeIdentifiers \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/SmashShare" SmashShareViewController.swift

install -m 0555 ../../smash "$APPEX/Contents/Resources/smash"

cat > "$APPEX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.pbnkp.smash.share</string>
  <key>CFBundleName</key><string>Smash Share</string>
  <key>CFBundleDisplayName</key><string>Smash</string>
  <key>CFBundleExecutable</key><string>SmashShare</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>5.1</string>
  <key>CFBundleVersion</key><string>5.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key><string>SmashShare.SmashShareViewController</string>
    <key>NSExtensionAttributes</key><dict>
      <key>NSExtensionActivationRule</key><dict>
        <key>NSExtensionActivationSupportsFileWithMaxCount</key><integer>100</integer>
        <key>NSExtensionActivationSupportsImageWithMaxCount</key><integer>100</integer>
        <key>NSExtensionActivationSupportsMovieWithMaxCount</key><integer>20</integer>
        <key>NSExtensionActivationSupportsText</key><true/>
        <key>NSExtensionActivationSupportsWebURLWithMaxCount</key><integer>20</integer>
      </dict>
    </dict>
  </dict>
</dict></plist>
PLIST

plutil -lint "$APPEX/Contents/Info.plist" SmashShare.entitlements >/dev/null
if security find-identity -v -p codesigning 2>/dev/null | grep -q "NKPS MEDIA"; then
  codesign --force --options runtime --timestamp --sign "$CERT" --identifier "$IDENT" \
    --entitlements SmashShare.entitlements "$APPEX"
  codesign --force --options runtime --timestamp --sign "$CERT" --identifier com.pbnkp.smash.menubar "$APP"
else
  codesign --force --sign - --identifier "$IDENT" \
    --entitlements SmashShare.entitlements "$APPEX"
  codesign --force --sign - --identifier com.pbnkp.smash.menubar "$APP"
fi
codesign --verify --strict "$APPEX"
codesign --verify --strict "$APP"
echo "built: $APPEX"
