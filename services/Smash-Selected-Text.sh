#!/bin/bash
# Service: Smash Selected Text. The selection arrives on stdin.
# --exact keeps legacy xz + base64 so the artifact can be pasted and read.
set -eo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:${HOME}/bin:${HOME}/.local/bin:/usr/bin:/bin:${PATH:-}"
mkdir -p "${HOME}/smashes"
SMASH="${HOME}/bin/smash"
if [[ ! -x "$SMASH" ]]; then SMASH="$(command -v smash || true)"; fi
if [[ -z "${SMASH}" || ! -x "$SMASH" ]]; then printf 'smash: CLI not found\n' >&2; exit 1; fi
export B64_OUTDIR="${HOME}/smashes"
export SMASH_PRINT_PATH=1
finish() {
  local last="$1"
  [[ -n "$last" && -e "$last" ]] || return 0
  if [[ "$(uname -s)" == "Darwin" ]]; then
    /usr/bin/osascript - "$last" -e 'on run argv' -e 'display notification (item 1 of argv) with title "Smash"' -e 'end run' >/dev/null 2>&1 || true
    open -R "$last" >/dev/null 2>&1 || true
  fi
}
if line="$(cat | "$SMASH" -q --exact --origin "Selected Text" -o "${HOME}/smashes/Selected Text" -)"; then
  line="${line##*$'\n'}"
  [[ -n "$line" ]] && finish "$line"
else
  status=$?
  exit "$status"
fi
