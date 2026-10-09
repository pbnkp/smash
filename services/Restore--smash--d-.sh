#!/bin/bash
# Finder service: Restore (smash -d). Restored files land beside the artifact.
set -eo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:${HOME}/bin:${HOME}/.local/bin:/usr/bin:/bin:${PATH:-}"
SMASH="${HOME}/bin/smash"
if [[ ! -x "$SMASH" ]]; then SMASH="$(command -v smash || true)"; fi
if [[ -z "${SMASH}" || ! -x "$SMASH" ]]; then printf 'smash: CLI not found\n' >&2; exit 1; fi
export SMASH_PRINT_PATH=1
unset B64_OUTDIR
finish() {
  local last="$1"
  [[ -n "$last" && -e "$last" ]] || return 0
  if [[ "$(uname -s)" == "Darwin" ]]; then
    /usr/bin/osascript - "$last" -e 'on run argv' -e 'display notification (item 1 of argv) with title "Smash"' -e 'end run' >/dev/null 2>&1 || true
    open -R "$last" >/dev/null 2>&1 || true
  fi
}
last=""
for f in "$@"; do
  [[ -n "$f" ]] || continue
  if line="$("$SMASH" -q -d -- "$f")"; then
    line="${line##*$'\n'}"
    [[ -n "$line" ]] && last="$line"
  else
    status=$?
    exit "$status"
  fi
done
[[ -n "$last" ]] && finish "$last"
