#!/bin/bash
# Derive smash's bytes-per-token constants from REAL corpora, so no constant in
# the tool is folklore. Corpora are this repository's own files, so the script is
# reproducible by anyone who clones it.
#
#   tools/derive-tok-constants.sh           # print the table, write the constants
#   tools/derive-tok-constants.sh --check   # print only
#
# Why: smash once estimated tokens as `bytes/4` for every content type. Measured,
# that is -63.1% on base64, -10% on prose and -18% on code: wrong in the
# flattering direction, and worst on smash's own primary output format.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$HERE")"
PY="${SMASH_TOKPY:-$HOME/.local/share/smash/tokvenv/bin/python}"
TC="${SMASH_TOKCOUNT:-$HOME/.local/share/smash/tokcount.py}"
OUT="${SMASH_TOKCONST:-$HOME/.local/share/smash/tok-constants.tsv}"
[[ -x "$PY" && -r "$TC" ]] || { echo "no tokenizer: run install.sh first (looked for $PY)" >&2; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
count() { "$PY" "$TC" "$1" 2>/dev/null; }

mkdir -p "$TMP/prose" "$TMP/code" "$TMP/b64"
for f in "$REPO"/README.md "$REPO"/CHANGELOG.md "$REPO"/SECURITY.md "$REPO"/THREAT-MODEL.md; do
  [[ -f "$f" ]] && cp "$f" "$TMP/prose/$(basename "$f")"
done
for f in "$REPO"/smash "$REPO"/install.sh "$HERE"/tokcount.py; do
  [[ -f "$f" ]] && cp "$f" "$TMP/code/$(basename "$f")"
done
i=0
for f in "$TMP/prose"/* "$TMP/code"/*; do
  [[ -f "$f" ]] || continue
  i=$((i+1)); xz -9e -c "$f" 2>/dev/null | base64 > "$TMP/b64/p$i.b64"
done

printf '%-8s %-26s %10s %9s %9s\n' BUCKET FILE BYTES TOKENS B/TOK
rows=()
for bucket in prose code b64; do
  tb=0; tt=0
  for f in "$TMP/$bucket"/*; do
    [[ -f "$f" ]] || continue
    b=$(wc -c < "$f" | tr -d ' '); t=$(count "$f")
    [[ -n "${t:-}" && "${t:-0}" -gt 0 ]] || continue
    printf '%-8s %-26s %10d %9d %9.2f\n' "$bucket" "$(basename "$f" | cut -c1-26)" "$b" "$t" \
      "$(awk -v b="$b" -v t="$t" 'BEGIN{printf "%.2f", b/t}')"
    tb=$((tb+b)); tt=$((tt+t))
  done
  if [[ "$tt" -gt 0 ]]; then
    r=$(awk -v b="$tb" -v t="$tt" 'BEGIN{printf "%.3f", b/t}')
    rows+=("$bucket	$r	$tb	$tt")
    printf '%-8s %-26s %10d %9d %9s  <== bucket constant\n' "$bucket" ALL "$tb" "$tt" "$r"
  fi
done
if [[ "${1:-}" != "--check" ]]; then
  mkdir -p "$(dirname "$OUT")"
  { printf '# smash bytes-per-token constants - derived %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# bucket\tbytes_per_token\tcorpus_bytes\tcorpus_tokens\n'
    for r in "${rows[@]}"; do printf '%s\n' "$r"; done; } > "$OUT"
  echo "wrote $OUT"
fi
