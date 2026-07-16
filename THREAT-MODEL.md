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

## Actors / entry points
1. A **hostile artifact or file** handed to `smash -d` / dropped in the web app.
2. A **hostile filename** (control bytes, leading dash, traversal, glob chars).
3. A **malicious/compromised AI provider** returning oversized, malformed, or
   escape-laden responses to `--ai-api`.
4. An **MCP client** (the model) attempting to exceed its typed surface.
5. A **network attacker** against the optional HTTP transport.
6. A **CDN/host compromise** altering served web assets.
7. A **local attacker** reading temp files or process args for secrets.

## Threats & mitigations

| # | Threat | Mitigation | Evidence |
|---|---|---|---|
| T1 | Terminal-escape injection via filename/content/provider body | All printed dynamic strings sanitized (control bytes stripped); content never printed | zero-ESC test (CLI); sanitizeErr (MCP) |
| T2 | Payload executed/eval'd | No `eval`/`source`/exec of payload anywhere; artifacts mode 0600, non-exec | code audit; perms test |
| T3 | Archive traversal or privilege-bearing entries in a `.dtar` | Private staged extraction; reject absolute/`..`, unsafe links and special nodes; sanitize set-ID/world-write bits | dtar permission/traversal tests |
| T4 | Path traversal / symlink escape via MCP paths | `EvalSymlinks` + approved-root containment; reject outside | MCP traversal test (rejected) |
| T5 | Secret leak via `ps`/args | keys via `curl -K`/`-d @file`; Keychain on macOS; never argv | ai-api sentinel test (no leak) |
| T6 | Secret residue after crash/interrupt | temp files trap-cleaned on EXIT/INT/HUP/TERM | interrupt test (0 residue) |
| T7 | Provider DoS (timeout/oversize/malformed) | `curl --max-time`; oversize warning; strict response parse → die | ai-api matrix (all branches) |
| T8 | Model runs arbitrary commands via MCP | argv-only, typed tools, no shell, no arbitrary flags | protocol battery |
| T9 | Network attacker calls HTTP transport | loopback-default; bearer auth (constant-time); TLS off-loopback; CORS off; rate/size/concurrency caps | HTTP battery (401/405/refuse) |
| T10 | Duplicate/malformed/oversized or gzip-bomb JSON-RPC | parse-error responses; decompressed-size limits; notification stays silent | protocol + gzip tests |
| T11 | Served web bundle altered (CDN/host compromise) | SRI (sha384) on the module + strict CSP; SW hash-verify fails closed | SRI tamper test (blocked); SW map verified |
| T12 | XSS via hostile filename/content in the web UI | untrusted values via `textContent`; `innerHTML` only static/numeric; strict CSP, no inline/eval | code audit; CSP |
| T13 | Cache poisoning of the PWA | SW verifies SHA-256 at install, fails closed; never caches unverified bytes | logic static-verified; hashes runtime-correct |
| T14 | Downgrade/format confusion (v5 vs pre-v5) | manifest is `#`-prefixed and stripped on decode; pre-v5 still decodes; lossy flagged | decode-compat tests |

## Residual risk / accepted
- **SW runtime activation** is not runtime-proven in the headless build
  environment (it rejects all SW registration). Logic is static-verified and
  the pinned hashes are runtime-correct; confirm on a GUI browser. (T13)
- **External `--ai-api` provider proof** (real Anthropic/OpenAI key) is not
  exercised — no API credential is available and a subscription consumer
  account is not treated as one. Local-endpoint proof (mock + Ollama) stands
  in. (T7)
- **Notarization** of the macOS app is not performed in this environment.
- **TLS termination** for the off-loopback HTTP transport is delegated to the
  operator's certs; smash refuses off-loopback without them but does not manage
  rotation.
- smash is **not encryption**; `--ai-api` is an explicit outbound action to a
  user-chosen provider.
