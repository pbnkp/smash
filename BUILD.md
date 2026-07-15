# smash — Build Guide

Everything builds from the repo with tools already on a normal dev Mac /
FreeBSD box. No Node, no bundlers, no package managers beyond Homebrew for the
CLI's runtime `xz`.

## CLI (`smash`)
The CLI is a single Bash script — nothing to build. Lint + smoke:
```
bash -n smash            # syntax (bash 3.2-safe)
./smash -V               # -> smash v5.1
```
Runtime deps: `openssl`, `xz`, `gzip` (all present on macOS/FreeBSD); `zstd`
only for `-z`; `jq`+`curl` only for `--ai-api`.

## MCP server (`smash-mcp`)  — Go
Written to the **Go 1.13** language level (`io/ioutil`, no generics, no
post-1.13 stdlib). Builds on any Go ≥ 1.13.
```
cd mcp/smash-mcp
go vet ./...
go build -trimpath -ldflags="-s -w" -o smash-mcp .
./smash-mcp -V           # -> smash-mcp v1.2 (proto 2025-06-18)
```
- **Verified:** vet clean + build on go1.26 (macOS arm64) and go1.22.12
  (FreeBSD amd64). Language-level 1.13 compatibility is by construction
  (API audit) + the `go 1.13` directive in `go.mod`; no 1.13 toolchain was
  reachable to runtime-confirm that exact version.

## Web / PWA
No build tools. `ui/web/` holds the readable source; two build scripts emit
artifacts:
```
cd ui/web
./build.sh          # self-verifying file:// variant: index.html + artifact.html
./build-dist.sh     # production static site: dist/ (SRI + CSP + SW + PWA + minified)
```
`build-dist.sh` needs only `openssl` + `python3` (stdlib). It minifies
`smash-web.app.js` (safe line-level compaction), pins the module via SRI
(`sha384`), writes a SHA-256 integrity map into `sw.js` + `integrity.json`, and
emits a CSP header example. The readable source is intentionally **not** copied
into `dist/`.

## macOS app
```
cd ui/macos
./build-app.sh [~/Applications/Smash.app]
```
- Compiles `smash-menubar.swift` with `swiftc -O`, bundles `Smash.app`
  (`LSUIElement` menu-bar app), and code-signs it.
- **Signing status (honest):** the script uses the Developer ID cert
  `NKPS MEDIA, LLC (HLT6DNEZSF)` when present in the keychain; in an
  environment without it (e.g. CI/headless) it falls back to **ad-hoc**
  signing and says so. The build in this session is **ad-hoc signed**.
- **Notarization: NOT performed.** Distributing outside your own machines
  requires `xcrun notarytool submit` + stapling with an Apple Developer
  account; that step is not automated here.
- **SDK compatibility:** built against whatever `swiftc` is installed
  (`swiftc --version` to check); `LSMinimumSystemVersion` is 13.0. The CLI is
  always the fallback if the app can't run.

Build the app plus embedded Share extension:
```
ui/macos/build-app.sh ~/Applications/Smash.app
ui/macos/build-share-extension.sh ~/Applications/Smash.app
```

Build the all-in-one installer package (app, CLI, MCP, Share extension, and
Finder actions):
```
ui/macos/build-pkg.sh dist-mac/Smash-5.1.pkg
```

## Finder integration
```
cd ui/macos
./install-quickactions.sh     # installs Services/Quick Actions into ~/Library/Services
```
Registers "Smash", "Smash (semantic)", "Restore (smash -d)", and "Smash
Selected Text" via `pbs -update`.

## Release manifest
`release-manifest.sha256` records the SHA-256 of every shipped artifact. Verify
a checkout with:
```
shasum -a 256 -c release-manifest.sha256
```
