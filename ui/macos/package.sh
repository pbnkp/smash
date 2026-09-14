#!/bin/bash
# Package Smash.app into a distributable zip with a checksum sidecar.
# (Ditto preserves the code signature; plain zip can corrupt it.)
set -euo pipefail
APP="${1:-$HOME/Applications/Smash.app}"
OUT="${2:-$(dirname "$0")/dist-mac}"
[ -d "$APP" ] || { echo "no app at $APP"; exit 2; }
mkdir -p "$OUT"
ZIP="$OUT/Smash.app.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$OUT/Smash.app.zip.sha256"
echo "packaged: $ZIP ($(wc -c < "$ZIP" | tr -d ' ')B)"
echo "verify signature survives packaging:"
TMP=$(mktemp -d); /usr/bin/ditto -x -k "$ZIP" "$TMP"
codesign --verify --strict "$TMP/Smash.app" && echo "  signature intact after zip round-trip" || echo "  signature broke (investigate)"
rm -rf "$TMP"
