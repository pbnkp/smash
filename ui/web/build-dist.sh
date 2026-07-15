#!/bin/bash
# smash web — production static build (SRI + strict CSP + service worker + PWA).
# No Node/bundlers: openssl + python3 (stdlib) only. Output: ui/web/dist/.
# Readable source (smash-web.app.js) is intentionally NOT copied into dist.
set -euo pipefail
cd "$(dirname "$0")"
SRC=smash-web.app.js
DIST=dist
rm -rf "$DIST"; mkdir -p "$DIST"

# 1. minify (safe line-level compaction)
python3 minify.py "$SRC" > "$DIST/app.min.js"

# 2. SRI (sha384, base64) for the external module + sha256 hex for SW manifest
sri() { printf 'sha384-%s' "$(openssl dgst -sha384 -binary "$1" | openssl base64 -A)"; }
sha256hex() { openssl dgst -sha256 "$1" | awk '{print $NF}'; }

cp icon.svg manifest.webmanifest "$DIST/"
APPSRI=$(sri "$DIST/app.min.js")

# 3. strict-CSP index.html (external app.min.js via SRI; no inline script)
cat > "$DIST/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="smash">
<meta name="theme-color" content="#0b0b0e">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon.svg">
<title>smash</title>
</head>
<body>
<script src="app.min.js" integrity="${APPSRI}" crossorigin="anonymous"></script>
</body>
</html>
HTML

# 4. integrity manifest (SHA-256 of every SW-cached asset) + version-stamped SW
IDX_SHA=$(sha256hex "$DIST/index.html")
APP_SHA=$(sha256hex "$DIST/app.min.js")
MAN_SHA=$(sha256hex "$DIST/manifest.webmanifest")
ICO_SHA=$(sha256hex "$DIST/icon.svg")
CACHE_TAG="smash-v5.2-${APP_SHA:0:8}"

python3 - "$IDX_SHA" "$APP_SHA" "$MAN_SHA" "$ICO_SHA" > "$DIST/integrity.json" <<'PY'
import json,sys
idx,app,man,ico=sys.argv[1:5]
print(json.dumps({"version":"5.2","assets":{
 "index.html":idx,"app.min.js":app,"manifest.webmanifest":man,"icon.svg":ico}},indent=2))
PY

INTEG=$(python3 - "$IDX_SHA" "$APP_SHA" "$MAN_SHA" "$ICO_SHA" <<'PY'
import json,sys
idx,app,man,ico=sys.argv[1:5]
print(json.dumps({"index.html":idx,"app.min.js":app,"manifest.webmanifest":man,"icon.svg":ico}))
PY
)
sed -e "s|__CACHE__|${CACHE_TAG}|" -e "s|__INTEGRITY__|${INTEG}|" sw.js.tpl > "$DIST/sw.js"

# 5. CSP/deploy example for static hosts (headers, not just meta)
cat > "$DIST/deploy-csp.conf" <<CONF
# Example static-host headers for smash/dist (nginx-style).
# The CSP is also embedded as a <meta> in index.html so it holds even on hosts
# that cannot set headers (e.g. plain file servers, IPFS).
add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header Cross-Origin-Resource-Policy "same-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
# Serve .webmanifest with the right type:
types { application/manifest+json webmanifest; }
CONF

echo "dist built:"
( cd "$DIST" && for f in index.html app.min.js sw.js manifest.webmanifest icon.svg integrity.json; do printf '  %-22s %8sB  sha256:%s\n' "$f" "$(wc -c < "$f" | tr -d ' ')" "$(sha256hex "$f" | cut -c1-16)"; done )
echo "app.min.js SRI: $APPSRI"
echo "SW cache tag:   $CACHE_TAG"
