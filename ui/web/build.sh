#!/bin/bash
# smash web build — packs the payload module into integrity-gated loaders.
# No Node, no bundlers: openssl + awk. Reproducible from smash-web.app.js.
#   index.html    — full standalone page (file://, any static host, iOS A2HS)
#   artifact.html — content-only body for claude.ai Artifact deploy
# The loader refuses to execute the payload unless its SHA-256 matches the
# pinned hash — every single boot. Tamper one byte and it seals shut.
set -euo pipefail
cd "$(dirname "$0")"

PIN=$(openssl dgst -sha256 < smash-web.app.js | awk '{print $NF}')
PAYLOAD=$(openssl enc -base64 -A < smash-web.app.js)

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
 if(!(window.crypto&&crypto.subtle&&window.CompressionStream)){fail("this browser lacks WebCrypto/CompressionStream; refusing to run unverified.");return}
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

# --- artifact.html: content-only (Artifact wrapper adds the skeleton) ---
{
  printf '<title>smash</title>\n<script>\n'
  loader_js
  printf '</script>\n'
} > artifact.tpl

# --- index.html: full standalone with iOS installability meta ---
{
  printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
  printf '<meta name="apple-mobile-web-app-capable" content="yes">\n'
  printf '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n'
  printf '<meta name="apple-mobile-web-app-title" content="smash">\n'
  printf '<meta name="theme-color" content="#0b0b0e">\n'
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

printf 'built: index.html (%sB) artifact.html (%sB)\npin: %s\n' \
  "$(wc -c < index.html | tr -d ' ')" "$(wc -c < artifact.html | tr -d ' ')" "$PIN"
