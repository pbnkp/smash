#!/bin/bash
# Build an all-in-one macOS installer package.
set -euo pipefail
export COPYFILE_DISABLE=1
cd "$(dirname "$0")/../.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"
SCRIPTS="$WORK/scripts"
OUT="${1:-$PWD/dist-mac/Smash-5.2.pkg}"
mkdir -p "$ROOT/Applications" "$ROOT/usr/local/bin" "$ROOT/usr/local/libexec/smash" "$SCRIPTS" "$(dirname "$OUT")"

install -m 0555 smash "$ROOT/usr/local/bin/smash"
(cd mcp/smash-mcp && go build -trimpath -ldflags='-s -w' -o "$ROOT/usr/local/bin/smash-mcp" .)
ui/macos/build-app.sh "$ROOT/Applications/Smash.app"
ui/macos/build-share-extension.sh "$ROOT/Applications/Smash.app"
install -m 0555 ui/macos/install-quickactions.sh "$ROOT/usr/local/libexec/smash/install-quickactions.sh"
install -m 0555 ui/macos/uninstall-macos.sh "$ROOT/usr/local/libexec/smash/uninstall-macos.sh"
xattr -cr "$ROOT" 2>/dev/null || true
codesign --verify --strict --deep "$ROOT/Applications/Smash.app"

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
set -e
console_user=$(stat -f '%Su' /dev/console)
if [ -n "$console_user" ] && [ "$console_user" != root ]; then
  user_home=$(dscl . -read "/Users/$console_user" NFSHomeDirectory | awk '{print $2}')
  user_uid=$(id -u "$console_user")
  launchctl bootout "gui/$user_uid" "$user_home/Library/LaunchAgents/com.boy.smash-dropzone.plist" 2>/dev/null \
    || launchctl remove com.boy.smash-dropzone 2>/dev/null || true
  rm -f "$user_home/Library/LaunchAgents/com.boy.smash-dropzone.plist"
  rm -rf "$user_home/.boy-data/smash-dropzone"
  sudo -u "$console_user" env HOME="$user_home" SMASH_BIN=/usr/local/bin/smash \
    /usr/local/libexec/smash/install-quickactions.sh || true
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/Smash.app >/dev/null 2>&1 || true
exit 0
POST
chmod 0555 "$SCRIPTS/postinstall"

COMPONENT="$WORK/Smash-component.pkg"
pkgbuild --root "$ROOT" --scripts "$SCRIPTS" \
  --identifier com.pbnkp.smash --version 5.2 --install-location / "$COMPONENT"

if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Installer: NKPS MEDIA'; then
  productbuild --package "$COMPONENT" --sign 'Developer ID Installer: NKPS MEDIA, LLC (HLT6DNEZSF)' "$OUT"
else
  productbuild --package "$COMPONENT" "$OUT"
  echo "note: Developer ID Installer certificate not found; package is unsigned"
fi
pkgutil --check-signature "$OUT" || true
echo "built: $OUT"
