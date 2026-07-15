# smash — Install Guide

## CLI

### Homebrew (custom tap)
> **Accurate status:** smash is distributed through the author's **custom tap**
> `pbnkp/smash`. It is **not** in homebrew-core and has **not** been submitted
> to or accepted by official Homebrew.

```
brew tap pbnkp/smash
brew install smash
smash -V            # -> smash v5.1
```
Or in one line: `brew install pbnkp/smash/smash`.

- Formula declares `depends_on "xz"`. smash also uses `openssl` and `gzip`
  (present by default on macOS and in most Linux base images).
- **Verified end-to-end:** `brew tap` → `install` → `-V` → encode/decode
  round-trip through the brew binary → `brew deps` = `xz` → the downloaded
  source's SHA-256 equals the formula's pinned `sha256`
  (`98089bdd…af90`) → `brew uninstall`/reinstall. Upgrades track the formula's
  pinned version; a new smash release bumps formula `version` + `sha256` in
  lockstep.

### One-liner (no Homebrew)
```
curl -fsSL https://raw.githubusercontent.com/pbnkp/smash/main/install.sh | bash
# installs to ~/.local/bin/smash
```

### Manual
```
curl -fsSL https://raw.githubusercontent.com/pbnkp/smash/main/smash -o ~/bin/smash
chmod +x ~/bin/smash
```

## MCP server (AI-app integration)

Build (`mcp/smash-mcp`, see BUILD.md) or copy the binary to `~/bin/smash-mcp`,
then register with your client:

```
# Claude Code
claude mcp add -s user smash ~/bin/smash-mcp

# Claude Desktop — claude_desktop_config.json
{ "mcpServers": { "smash": { "command": "/Users/you/bin/smash-mcp" } } }
```
Verify: ask the client to call `smash_capabilities` — it returns
`smash v5.1`. Optional local HTTP transport:
`smash-mcp -http 127.0.0.1:7461` (bearer token printed to stderr).

## macOS package (recommended)
```
ui/macos/build-pkg.sh dist-mac/Smash-5.1.pkg
open dist-mac/Smash-5.1.pkg
```
The package installs `/Applications/Smash.app`, `/usr/local/bin/smash`,
`/usr/local/bin/smash-mcp`, four Finder actions, and the Share extension.

For a user-level custom install instead:
```
ui/macos/install-macos.sh
```
This installs into `~/Applications`, `~/bin`, and `~/Library/Services`.
Remove either installation with `ui/macos/uninstall-macos.sh` (use `sudo` for
a system package installation). Artifacts in `~/smashes` are preserved.

The menu-bar icon accepts drops and opens settings on click. Finder exposes
Smash under Quick Actions/Services and Open With; the system Share menu exposes
the embedded Smash Share extension. A newly installed Share extension may
need enabling once in System Settings → General → Login Items & Extensions.

## Web / PWA
Static hosting — copy `ui/web/dist/` to any static host (or open
`ui/web/index.html` directly via `file://` for the self-contained variant).
Apply the headers in `dist/deploy-csp.conf`. On iPhone/iPad: open the hosted
URL in Safari → Share → **Add to Home Screen** to install the PWA.

## Requirements summary
| Component | Needs |
|---|---|
| CLI | bash 3.2+, openssl, xz, gzip (zstd for `-z`; jq+curl for `--ai-api`) |
| MCP | the `smash` CLI on PATH (or `-smash`), openssl |
| macOS app | macOS 13+, the `smash` CLI |
| Web/PWA | a modern browser with `CompressionStream` (Chrome/Edge/Safari 16.4+) |
