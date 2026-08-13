# smash — Install Guide

## CLI

### Homebrew (custom tap)
> **Accurate status:** smash is distributed through the author's **custom tap**
> `pbnkp/smash`. It is **not** in homebrew-core and has **not** been submitted
> to or accepted by official Homebrew.

```
brew tap pbnkp/smash
brew install smash
smash -V            # -> smash v5.0
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
`smash v5.0`. Optional local HTTP transport:
`smash-mcp -http 127.0.0.1:7461` (bearer token printed to stderr).

## macOS app
```
cp -R Smash.app ~/Applications/        # or run ui/macos/build-app.sh
open ~/Applications/Smash.app
```
Menu-bar icon (`archivebox`). Drag files/folders/artifacts onto it, or click
for settings. First launch of an ad-hoc/Developer-ID app not notarized may need
right-click → Open (Gatekeeper). Install Finder actions with
`ui/macos/install-quickactions.sh`.

## Web / PWA

Two deployable variants — pick based on whether you want offline support or
zero-file-count simplicity. Both are production-complete, not demos.

**`ui/web/index.html` — single file, production-complete.**
Copy this one file anywhere: any static host, `file://` locally, a
`data:`/blob URL, an internal wiki attachment. Self-contained (zero external
requests — the app code, favicon, and PWA manifest are all inlined), with a
hash-sourced Content-Security-Policy (`script-src` allows only the exact
known-good script bytes by SHA-256 — no `'unsafe-inline'`). Installable as a
real app on Chromium/Android (`beforeinstallprompt` — verified this fires
correctly against the inlined `data:` URI manifest); on iPhone/iPad, Safari
→ Share → **Add to Home Screen**. **Trade-off:** no offline support — there's
no separate file a service worker can be registered against, so this variant
always runs online. If offline matters more than file count, use `dist/`
below instead.

**`ui/web/dist/` — multi-file, offline-capable.**
Copy the whole directory to any static host. Apply the headers in
`dist/deploy-csp.conf` (a plain file host without header support still gets
the CSP via `dist/index.html`'s `<meta>` tag, minus `frame-ancestors`, which
browsers only honor via a real header — see `deploy-csp.conf`'s own comment).
Loads `app.min.js` via Subresource Integrity instead of inlining it, and
registers a service worker that hash-verifies every cached asset at install
and fails closed on mismatch — this is the variant that works offline after
first load. On iPhone/iPad: Safari → Share → **Add to Home Screen**.

## Requirements summary
| Component | Needs |
|---|---|
| CLI | bash 3.2+, openssl, xz, gzip (zstd for `-z`; jq+curl for `--ai-api`) |
| MCP | the `smash` CLI on PATH (or `-smash`), openssl |
| macOS app | macOS 13+, the `smash` CLI |
| Web/PWA | a modern browser with `CompressionStream` (Chrome/Edge/Safari 16.4+) |
