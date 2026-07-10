#!/bin/bash
# Sign Smash.app, emit a SHA-256 resource-integrity manifest, and VERIFY both.
# Honest posture: OS code signing is the anti-tamper boundary; the SHA-256
# manifest is an auditable record + a launch-time self-check, NOT a substitute
# for signing. Notarization is a separate, documented step (see BUILD.md).
set -euo pipefail
APP="${1:-$HOME/Applications/Smash.app}"
CERT="Developer ID Application: NKPS MEDIA, LLC (HLT6DNEZSF)"
IDENT="com.pbnkp.smash.menubar"
[ -d "$APP" ] || { echo "no app at $APP"; exit 2; }

# 1. sign FIRST (Developer ID if available, else ad-hoc — reported honestly).
#    codesign writes Contents/_CodeSignature/CodeResources — the OS-ENFORCED
#    SHA manifest of every bundled resource. That is the real anti-tamper
#    boundary; our external sidecar below is an auditable record, not a
#    substitute (a self-hash cannot vouch for itself).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "NKPS MEDIA"; then
  codesign --force --options runtime --sign "$CERT" --identifier "$IDENT" "$APP"
  MODE="Developer ID"
else
  codesign --force --sign - --identifier "$IDENT" "$APP"
  MODE="ad-hoc (no Developer ID cert in keychain)"
fi

# 2. external sidecar manifest computed on the SIGNED bundle (does not alter the
#    signature; lives outside the .app so it can't invalidate CodeResources).
MAN="$(dirname "$APP")/$(basename "$APP").integrity.sha256"
( cd "$APP" && find Contents -type f -exec shasum -a 256 {} \; | sort ) > "$MAN"
echo "sidecar manifest: $MAN ($(wc -l < "$MAN" | tr -d ' ') files)"

# 3. verify signature (OS boundary) + sidecar (audit record)
echo "== signature =="
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Authority|Signature|TeamIdentifier|flags' || true
codesign --verify --strict --verbose=2 "$APP" && echo "codesign --verify: OK ($MODE)"
echo "codesign resource manifest (CodeResources) present: $([ -f "$APP/Contents/_CodeSignature/CodeResources" ] && echo yes || echo no)"
echo "== notarization =="
if xcrun stapler validate "$APP" >/dev/null 2>&1; then echo "notarized + stapled: YES"; else echo "notarized: NO (not performed; see BUILD.md)"; fi
echo "== sidecar self-check =="
( cd "$APP" && shasum -a 256 -c "$MAN" >/dev/null 2>&1 && echo "sidecar manifest: all match" || echo "sidecar manifest: MISMATCH" )
