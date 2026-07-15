#!/bin/bash
# Remove package or custom user-level Smash installations and registrations.
set -euo pipefail

for app in "$HOME/Applications/Smash.app" /Applications/Smash.app; do
  if [ -d "$app" ]; then
    pluginkit -r "$app/Contents/PlugIns/SmashShare.appex" 2>/dev/null || true
    rm -rf "$app"
  fi
done

rm -f "$HOME/bin/smash" "$HOME/bin/smash-mcp" \
      "$HOME/.local/bin/smash" "$HOME/.local/bin/smash-mcp"
if [ "$(id -u)" -eq 0 ]; then
  rm -f /usr/local/bin/smash /usr/local/bin/smash-mcp
  rm -rf /usr/local/libexec/smash
fi

rm -rf "$HOME/Library/Services/Smash.workflow" \
       "$HOME/Library/Services/Smash (semantic).workflow" \
       "$HOME/Library/Services/Restore (smash -d).workflow" \
       "$HOME/Library/Services/Smash Selected Text.workflow"

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
pkill -x smash-menubar 2>/dev/null || true
echo "Smash uninstalled (artifacts in ~/smashes were preserved)"

