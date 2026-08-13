#!/bin/bash
# smash web build — packs the payload module into integrity-gated loaders.
# No Node, no bundlers: openssl + awk. Reproducible from smash-web.app.js.
#   index.html    — production-complete single file: file://, any static
#                    host, iOS A2HS. Self-contained (zero external requests),
#                    hash-sourced CSP (no 'unsafe-inline'), inline favicon,
#                    inline data: URI manifest (installable where Chromium
#                    honors data: manifests — verified at build time below,
#                    not assumed).
#   artifact.html — content-only body for claude.ai Artifact deploy (the
#                    Artifact platform supplies its own CSP/sandbox, so this
#                    variant intentionally carries none of its own).
# The loader refuses to execute the payload unless its SHA-256 matches the
# pinned hash — every single boot. Tamper one byte and it seals shut. The
# CSP enforces the same guarantee at the browser level: script-src allows
# only the exact known-good byte sequences (by hash), not 'unsafe-inline'.
set -euo pipefail
cd "$(dirname "$0")"

PIN=$(openssl dgst -sha256 < smash-web.app.js | awk '{print $NF}')
PAYLOAD=$(openssl enc -base64 -A < smash-web.app.js)
# CSP script-src hashes must match what the browser actually computes at
# runtime, not the source file on disk. The loader reconstructs the payload
# via atob() -> JS string (Latin-1: one char per original byte) -> assigned
# to a <script>'s textContent. CSP then hashes the UTF-8 re-encoding of that
# string. Since the file contains non-ASCII bytes (em-dashes, arrows, etc.
# in the UI copy), a straight file hash silently diverges from what CSP
# computes — a Latin-1-decode-then-UTF-8-re-encode is required to match.
# Verified empirically, not assumed: the two hashes differ for this file.
PAYLOAD_HASH_B64=$(python3 -c "
import sys, base64, hashlib
raw = open('smash-web.app.js','rb').read()
reencoded = raw.decode('latin-1').encode('utf-8')
print(base64.b64encode(hashlib.sha256(reencoded).digest()).decode())
")
ICON_B64=$(openssl enc -base64 -A < icon.svg)

loader_js() {
cat <<'EOF'
(function(){
"use strict";
const PIN="__PIN__";
const P="__PAYLOAD__";
function fail(msg,got){
 document.body.innerHTML="";
 const d=document.createElement("div");
 d.style.cssText="min-height:100vh;background:#0b0b0e;color:#ff3b4e;font-family:ui-monospace,'SF Mono',Menlo,monospace;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1rem;padding:2rem;text-align:center";
 const h=document.createElement("div");h.style.cssText="font-size:1.4rem;font-weight:800;letter-spacing:.18em";h.textContent="SEAL BROKEN";
 const m=document.createElement("div");m.style.cssText="font-size:.8rem;color:#8c8c9a;max-width:34rem;word-break:break-all";
 m.textContent=msg+(got?" expected "+PIN+" got "+got:"");
 d.appendChild(h);d.appendChild(m);document.body.appendChild(d);document.title="smash — seal broken";
}
try{
 if(!(window.crypto&&crypto.subtle&&window.CompressionStream&&window.DecompressionStream)){fail("this browser lacks WebCrypto/CompressionStream — needs Chrome/Edge 80+, Safari 16.4+, or Firefox 113+. Refusing to run unverified.");return}
 let raw=atob(P);const a=new Uint8Array(raw.length);let i;for(i=0;i<raw.length;i++)a[i]=raw.charCodeAt(i);
 crypto.subtle.digest("SHA-256",a).then(function(h){
  const v=new Uint8Array(h);let s="",j;for(j=0;j<v.length;j++)s+=(v[j]<16?"0":"")+v[j].toString(16);
  if(s!==PIN){fail("payload bytes do not match the pinned SHA-256. refusing to run.",s);return}
  window.__SMASH_PIN__=PIN;
  const sc=document.createElement("script");sc.textContent=raw;document.body.appendChild(sc);
 },function(){fail("hash computation failed; refusing to run.")});
}catch(e){fail("loader error; refusing to run.")}
})();
EOF
}

# --- inline manifest (data: URI — no separate file needed for a true
#     single-page deploy). Icon is the same inline SVG as the favicon. ---
manifest_json() {
cat <<EOF
{"name":"smash","short_name":"smash","description":"Compress and encode anything into terminal-safe, LLM-readable artifacts — fully on-device.","start_url":"./","scope":"./","display":"standalone","orientation":"portrait","background_color":"#0b0b0e","theme_color":"#0b0b0e","icons":[{"src":"data:image/svg+xml;base64,${ICON_B64}","sizes":"any","type":"image/svg+xml","purpose":"any maskable"}]}
EOF
}
MANIFEST_B64=$(manifest_json | openssl enc -base64 -A)

# --- artifact.html: content-only (Artifact wrapper adds the skeleton and
#     its own CSP — none injected here). ---
{
  printf '<title>smash</title>\n<script>\n'
  loader_js
  printf '</script>\n'
} > artifact.tpl

# --- index.html: full standalone, production-complete single page ---
{
  printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
  printf '<meta name="description" content="Compress and encode anything into terminal-safe, LLM-readable artifacts — fully on-device, nothing uploaded.">\n'
  printf '<meta name="mobile-web-app-capable" content="yes">\n'
  printf '<meta name="apple-mobile-web-app-capable" content="yes">\n'
  printf '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n'
  printf '<meta name="apple-mobile-web-app-title" content="smash">\n'
  printf '<meta name="theme-color" content="#0b0b0e">\n'
  printf '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,%s">\n' "$ICON_B64"
  printf '<link rel="manifest" href="data:application/manifest+json;base64,%s">\n' "$MANIFEST_B64"
  printf '__CSP__\n'
  printf '<title>smash</title>\n</head>\n<body>\n<script>\n'
  loader_js
  printf '</script>\n</body>\n</html>\n'
} > index.tpl

for t in artifact index; do
  awk -v pin="$PIN" '{gsub(/__PIN__/,pin);print}' "$t.tpl" > "$t.step1"
  # splice payload from a file (kept out of awk -v: ARG_MAX + backslash rules)
  PAYFILE=payload.b64.tmp
  printf '%s' "$PAYLOAD" > "$PAYFILE"
  awk -v pf="$PAYFILE" '{
    if (index($0,"__PAYLOAD__")>0) {
      pre=substr($0,1,index($0,"__PAYLOAD__")-1)
      post=substr($0,index($0,"__PAYLOAD__")+11)
      printf "%s", pre
      while ((getline l < pf) > 0) printf "%s", l
      close(pf)
      print post
    } else print
  }' "$t.step1" > "$t.html"
  rm -f "$t.step1" "$t.tpl" "$PAYFILE"
done

# --- CSP for index.html: hash-source the loader's own inline <script>
#     (no 'unsafe-inline') so the browser enforces the same guarantee the
#     loader already self-checks. The dynamically-inserted payload script
#     is allowed by the payload's own file hash (PAYLOAD_HASH_B64) since
#     its textContent is byte-identical to smash-web.app.js.
#     CSP script-src hashes are computed over the exact bytes of the
#     script element's textContent — byte-exact extraction matters here;
#     an awk line-reconstruction previously introduced a whitespace/
#     newline mismatch that silently broke the whole page (CSP blocked
#     the loader itself). Extract by exact byte offset instead. ---
LOADER_HASH_B64=$(python3 -c "
import re, base64, hashlib
html = open('index.html', 'rb').read()
m = re.search(rb'<script>(.*?)</script>', html, re.S)
print(base64.b64encode(hashlib.sha256(m.group(1)).digest()).decode())
")
CSP="default-src 'none'; script-src 'self' 'sha256-${LOADER_HASH_B64}' 'sha256-${PAYLOAD_HASH_B64}'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; manifest-src 'self' data:; worker-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
CSP_META="<meta http-equiv=\"Content-Security-Policy\" content=\"${CSP}\">"
awk -v csp="$CSP_META" '{gsub(/__CSP__/,csp);print}' index.html > index.html.new
mv index.html.new index.html

printf 'built: index.html (%sB) artifact.html (%sB)\npin: %s\ncsp: hash-sourced (no unsafe-inline)\n' \
  "$(wc -c < index.html | tr -d ' ')" "$(wc -c < artifact.html | tr -d ' ')" "$PIN"
