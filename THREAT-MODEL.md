# smash — Threat Model

Scope: the `smash` CLI, the `smash-mcp` server, the web/PWA, and the macOS app.
Out of scope: the operating system, the terminal emulator's own escape parsing,
the AI provider you configure, and the transport network beyond loopback.

## Assets
- The **user's terminal session** (must not be hijacked by content smash prints).
- **Secrets** (API keys) used by `--ai-api` and the macOS app.
- **File-system integrity** (smash must not write outside intended locations or
  extract archives that escape their directory).
- **Artifact integrity** (a restored file must equal the source for lossless
  modes).
- **The web app's code integrity** (a served bundle must not be silently
  altered).
- **History metadata** (filenames, sizes, sha256s, timestamps kept in
  IndexedDB) — not secret, but not meant to leak cross-origin or persist
  beyond the user's intent either.
- **Persisted file-access capability** (`FileSystemFileHandle`s stored for
  relink on Chromium) — must require a live permission check on every use,
  never silent re-access.

## Actors / entry points
1. A **hostile artifact or file** handed to `smash -d` / dropped in the web app.
2. A **hostile filename** (control bytes, leading dash, traversal, glob chars).
3. A **malicious/compromised AI provider** returning oversized, malformed, or
   escape-laden responses to `--ai-api`.
4. An **MCP client** (the model) attempting to exceed its typed surface.
5. A **network attacker** against the optional HTTP transport.
6. A **CDN/host compromise** altering served web assets.
7. A **local attacker** reading temp files or process args for secrets.
8. A **script on the same web origin** (XSS elsewhere, a malicious browser
   extension with storage access) reading IndexedDB history or attempting to
   invoke a persisted `FileSystemFileHandle`.

## Threats & mitigations

| # | Threat | Mitigation | Evidence |
|---|---|---|---|
| T1 | Terminal-escape injection via filename/content/provider body | All printed dynamic strings sanitized (control bytes stripped); content never printed | zero-ESC test (CLI); sanitizeErr (MCP) |
| T2 | Payload executed/eval'd | No `eval`/`source`/exec of payload anywhere; artifacts mode 0600, non-exec | code audit; perms test |
| T3 | Archive traversal (`../etc/x` in a `.dtar`) | Reject absolute/`..` members before `tar x` | dtar traversal test |
| T4 | Path traversal / symlink escape via MCP paths | `EvalSymlinks` + approved-root containment; reject outside | MCP traversal test (rejected) |
| T5 | Secret leak via `ps`/args | keys via `curl -K`/`-d @file`; Keychain on macOS; never argv | ai-api sentinel test (no leak) |
| T6 | Secret residue after crash/interrupt | temp files trap-cleaned on EXIT/INT/HUP/TERM | interrupt test (0 residue) |
| T7 | Provider DoS (timeout/oversize/malformed) | `curl --max-time`; oversize warning; strict response parse → die | ai-api matrix (all branches) |
| T8 | Model runs arbitrary commands via MCP | argv-only, typed tools, no shell, no arbitrary flags | protocol battery |
| T9 | Network attacker calls HTTP transport | loopback-default; bearer auth (constant-time); TLS off-loopback; CORS off; rate/size/concurrency caps | HTTP battery (401/405/refuse) |
| T10 | Duplicate/malformed/oversized JSON-RPC | parse-error responses; per-request limits; notification stays silent | protocol battery |
| T11 | Served web bundle altered (CDN/host compromise) | SRI (sha384) on the module + strict CSP; SW hash-verify fails closed | SRI tamper test (blocked); SW map verified |
| T12 | XSS via hostile filename/content in the web UI | untrusted values via `textContent`; `innerHTML` only static/numeric; strict CSP, no inline/eval | code audit; CSP |
| T13 | Cache poisoning of the PWA | SW verifies SHA-256 at install, fails closed; never caches unverified bytes | logic static-verified; hashes runtime-correct |
| T14 | Downgrade/format confusion (v5 vs pre-v5) | manifest is `#`-prefixed and stripped on decode; pre-v5 still decodes; lossy flagged | decode-compat tests |
| T15 | XSS/malicious extension reads history metadata (filenames, sha256s, timestamps) from IndexedDB | reference-metadata-only — never source or artifact bytes; same-origin-sandboxed by the browser; user-clearable | code audit; not a secret store by design |
| T16 | Persisted `FileSystemFileHandle` used to silently re-read a file after the tab closes | handle only exists from an explicit user gesture; `queryPermission`/`requestPermission` re-checked on every relink, not cached as "always allow"; sha256 re-verified and mismatches surfaced, never hidden | code audit; caniuse-verified Safari/Firefox have no such API at all |
| T17 | Single-file build's hash-sourced CSP silently diverges from what the browser actually executes, breaking the page (or worse, permitting more than intended) | hashes computed from the byte sequence the browser actually evaluates (UTF-8 re-encoding of the reconstructed string), not the source file on disk | real headless-Chrome CSP-violation test caught an actual divergence pre-fix; zero violations post-fix |

## Residual risk / accepted
- **SW runtime activation** is not runtime-proven in the headless build
  environment (it rejects all SW registration). Logic is static-verified and
  the pinned hashes are runtime-correct; confirm on a GUI browser. (T13)
- **External `--ai-api` provider proof** (real Anthropic/OpenAI key) is not
  exercised — no API credential is available and a subscription consumer
  account is not treated as one. Local-endpoint proof (mock + Ollama) stands
  in. (T7)
- **Notarization** of the macOS app is not performed in this environment.
- **Actual mobile browsers on physical hardware** are not exercised — the
  streaming-pipeline memory-safety claim (T-none-numbered, see CHANGELOG web
  v5.4) rests on a headless-Chrome-desktop synthetic test plus the
  architectural fix itself, not a real iOS/Android device. Verify before
  relying on it for genuinely large mobile uploads.
- **TLS termination** for the off-loopback HTTP transport is delegated to the
  operator's certs; smash refuses off-loopback without them but does not manage
  rotation.
- smash is **not encryption**; `--ai-api` is an explicit outbound action to a
  user-chosen provider.
