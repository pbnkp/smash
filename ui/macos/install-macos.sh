#!/bin/bash
# User-level custom installer. For the all-in-one system package, use build-pkg.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."

BIN_DIR="${SMASH_BIN_DIR:-$HOME/bin}"
APP="${SMASH_APP_PATH:-$HOME/Applications/Smash.app}"
mkdir -p "$BIN_DIR" "$(dirname "$APP")" "$HOME/smashes"

install -m 0555 smash "$BIN_DIR/smash"
(cd mcp/smash-mcp && go build -trimpath -ldflags='-s -w' -o "$BIN_DIR/smash-mcp" .)

ui/macos/build-app.sh "$APP"
ui/macos/build-share-extension.sh "$APP"
SMASH_BIN="$BIN_DIR/smash" ui/macos/install-quickactions.sh

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true
pluginkit -a "$APP/Contents/PlugIns/SmashShare.appex" 2>/dev/null || true
open "$APP"

echo "installed Smash.app, CLI, MCP helper, 4 Finder actions, and Share extension"
echo "app: $APP"
echo "commands: $BIN_DIR/smash and $BIN_DIR/smash-mcp"

