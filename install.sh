#!/usr/bin/env bash
# smash installer.
#
#   curl -fsSL https://raw.githubusercontent.com/pbnkp/smash/main/install.sh | bash
#   ./install.sh --all          CLI + exact tokenizer + Finder Services + menubar app + MCP
#   ./install.sh --minimal      CLI only
#   ./install.sh --with-tokenizer
#
# Default: CLI + the exact tokenizer, because without a tokenizer smash can only
# ESTIMATE token counts, and it will tell you so on every report. Everything else
# is opt-in via --all or its own flag.
#
# Every optional component fails SOFT and says why it was skipped. The installer
# never reports something as installed that it did not install.
set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/pbnkp/smash/main"
INSTALL_DIR="${SMASH_INSTALL_DIR:-$HOME/.local/bin}"
SHARE_DIR="${SMASH_SHARE_DIR:-$HOME/.local/share/smash}"
BINARY_PATH="$INSTALL_DIR/smash"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '')"

WANT_TOKENIZER=1; WANT_SERVICES=0; WANT_APP=0; WANT_MCP=0
for a in "$@"; do
  case "$a" in
    --all)             WANT_TOKENIZER=1; WANT_SERVICES=1; WANT_APP=1; WANT_MCP=1 ;;
    --minimal)         WANT_TOKENIZER=0 ;;
    --with-tokenizer)  WANT_TOKENIZER=1 ;;
    --with-services)   WANT_SERVICES=1 ;;
    --with-app)        WANT_APP=1 ;;
    --with-mcp)        WANT_MCP=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$a" >&2; exit 2 ;;
  esac
done

SKIPPED=(); DONE=()
note() { printf '  %s\n' "$1"; }
skip() { SKIPPED+=("$1"); note "skipped: $1"; }
did()  { DONE+=("$1");    note "ok: $1"; }

# smash_version <path> — read the SSOT assignment, not a banner comment. The
# header deliberately carries no version (it used to drift), so grepping the
# first few lines for "v<N>" finds nothing.
smash_version() {
  sed -n 's/^VERSION="\([0-9.]*\)".*/\1/p' "$1" 2>/dev/null | head -1
}

printf 'smash installer\n'

# ---------------------------------------------------------------- 1. the CLI
mkdir -p "$INSTALL_DIR" || { printf 'cannot create %s\n' "$INSTALL_DIR" >&2; exit 1; }
if [[ -f "$BINARY_PATH" ]]; then
  note "replacing smash $(smash_version "$BINARY_PATH" || echo '?') at $BINARY_PATH"
  cp -p "$BINARY_PATH" "$BINARY_PATH.v-prev.$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null || true
fi
if [[ -n "$HERE" && -f "$HERE/smash" ]]; then
  cp "$HERE/smash" "$BINARY_PATH"                      # local clone
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_RAW/smash" -o "$BINARY_PATH"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$BINARY_PATH" "$REPO_RAW/smash"
else
  printf 'error: need curl or wget (or run install.sh from a clone)\n' >&2; exit 1
fi
chmod +x "$BINARY_PATH"
did "smash $(smash_version "$BINARY_PATH" || echo '?') -> $BINARY_PATH"

# ------------------------------------------------- 2. the exact token counter
# Without this, tok_count falls back to a segment-aware ESTIMATE and every
# report says est(seg) instead of exact(o200k). Nothing breaks; the numbers are
# just modelled rather than counted, and smash says which.
if [[ "$WANT_TOKENIZER" -eq 1 ]]; then
  mkdir -p "$SHARE_DIR"
  if [[ -n "$HERE" && -f "$HERE/tools/tokcount.py" ]]; then
    cp "$HERE/tools/tokcount.py" "$SHARE_DIR/tokcount.py"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/tools/tokcount.py" -o "$SHARE_DIR/tokcount.py" || true
  fi
  if [[ ! -f "$SHARE_DIR/tokcount.py" ]]; then
    skip "exact tokenizer (could not fetch tools/tokcount.py) — smash will estimate and label est(seg)"
  elif ! command -v python3 >/dev/null 2>&1; then
    skip "exact tokenizer (no python3 on this host) — smash will estimate and label est(seg)"
  else
    if [[ ! -x "$SHARE_DIR/tokvenv/bin/python" ]]; then
      python3 -m venv "$SHARE_DIR/tokvenv" >/dev/null 2>&1 || true
    fi
    if [[ -x "$SHARE_DIR/tokvenv/bin/pip" ]] \
       && "$SHARE_DIR/tokvenv/bin/pip" -q install tiktoken >/dev/null 2>&1 \
       && "$SHARE_DIR/tokvenv/bin/python" -c 'import tiktoken' >/dev/null 2>&1; then
      did "exact tokenizer (o200k) -> $SHARE_DIR/tokvenv"
      if [[ -n "$HERE" && -x "$HERE/tools/derive-tok-constants.sh" ]]; then
        if "$HERE/tools/derive-tok-constants.sh" >/dev/null 2>&1; then
          did "bytes-per-token constants measured -> $SHARE_DIR/tok-constants.tsv"
        else
          skip "constants derivation (built-in measured defaults will be used)"
        fi
      fi
    else
      skip "exact tokenizer (venv or tiktoken install failed) — smash will estimate and label est(seg)"
    fi
  fi
fi

# ------------------------------------------------------- 3. Finder Services
if [[ "$WANT_SERVICES" -eq 1 ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then skip "Finder Services (macOS only)"
  elif [[ -z "$HERE" || ! -x "$HERE/ui/macos/install-quickactions.sh" ]]; then
    skip "Finder Services (run install.sh from a clone)"
  elif "$HERE/ui/macos/install-quickactions.sh" >/dev/null 2>&1; then
    did "Finder Quick Actions"
  else
    skip "Finder Services (installer returned non-zero)"
  fi
fi

# ----------------------------------------------------------- 4. menubar app
if [[ "$WANT_APP" -eq 1 ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then skip "menubar app (macOS only)"
  elif ! command -v swiftc >/dev/null 2>&1; then
    skip "menubar app (no swiftc — install Xcode command line tools)"
  elif [[ -z "$HERE" || ! -x "$HERE/ui/macos/build-app.sh" ]]; then
    skip "menubar app (run install.sh from a clone)"
  elif "$HERE/ui/macos/build-app.sh" >/dev/null 2>&1; then
    did "menubar app -> $HOME/Applications/Smash.app (ad-hoc signed unless SMASH_CODESIGN_ID is set)"
  else
    skip "menubar app (build failed)"
  fi
fi

# ------------------------------------------------------------ 5. MCP server
if [[ "$WANT_MCP" -eq 1 ]]; then
  if ! command -v go >/dev/null 2>&1; then skip "MCP server (no Go toolchain)"
  elif [[ -z "$HERE" || ! -d "$HERE/mcp/smash-mcp" ]]; then
    skip "MCP server (run install.sh from a clone)"
  elif ( cd "$HERE/mcp/smash-mcp" && go build -o "$INSTALL_DIR/smash-mcp" . ) >/dev/null 2>&1; then
    did "smash-mcp -> $INSTALL_DIR/smash-mcp (register it with your MCP client; see mcp/PROTOCOL.md)"
  else
    skip "MCP server (go build failed)"
  fi
fi

# ------------------------------------------------------------------ summary
printf '\ninstalled %d component(s)' "${#DONE[@]}"
[[ "${#SKIPPED[@]}" -gt 0 ]] && printf ', skipped %d' "${#SKIPPED[@]}"
printf '\n'
if ! printf '%s' "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  printf '\n%s is not on your PATH. Add to your shell profile:\n' "$INSTALL_DIR"
  printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
else
  printf '\nReady: smash --help   |   smash --tokinfo <file>   |   smash --tok <file>\n'
fi
