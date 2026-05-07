#!/usr/bin/env bash
# smash installer
# Usage: curl -fsSL https://raw.githubusercontent.com/pbnkp/smash/main/install.sh | bash

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
BINARY_URL="https://raw.githubusercontent.com/pbnkp/smash/main/smash"
BINARY_PATH="${INSTALL_DIR}/smash"

# Create install dir if needed
mkdir -p "$INSTALL_DIR"

# Check if already installed
if [[ -f "$BINARY_PATH" ]]; then
  CURRENT_VER=$(head -5 "$BINARY_PATH" 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
  printf 'smash %s already installed at %s\n' "${CURRENT_VER:-?}" "$BINARY_PATH"
  printf 'Upgrading...\n'
fi

# Download
printf 'Downloading smash from GitHub...\n'
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$BINARY_URL" -o "$BINARY_PATH"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$BINARY_PATH" "$BINARY_URL"
else
  printf 'Error: requires curl or wget\n' >&2
  exit 1
fi

chmod +x "$BINARY_PATH"
NEW_VER=$(head -5 "$BINARY_PATH" 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
printf 'Installed smash %s → %s\n' "${NEW_VER:-?}" "$BINARY_PATH"

# PATH check
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  printf '\nNote: %s is not in your PATH.\n' "$INSTALL_DIR"
  printf 'Add to your shell profile:\n'
  printf '  export PATH="$HOME/.local/bin:$PATH"\n'
else
  printf '\nsmash is ready. Run: smash --help\n'
fi
