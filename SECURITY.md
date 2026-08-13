# smash — Security Model

smash moves untrusted bytes between systems. Its security posture is built on
one idea: **the payload is inert data, never instructions, and never touches
the terminal.**

## CLI (`smash`)

- **No terminal bleed.** Source content is never written to stdout/stderr.
  Every dynamic string smash prints (filenames, API error bodies) is stripped
  of control/escape bytes first, so a hostile filename or provider response
  cannot inject ANSI/OSC sequences (title rewrites, OSC-52 clipboard writes,
  cursor games) into your terminal. *Verified: zero ESC bytes across captured
  stdout+stderr while encoding files whose names and contents contain OSC/CSI
  sequences.*
- **Inert, non-executable artifacts.** smash contains no `eval`; it never
  sources or executes payload bytes. Artifacts and restored files are written
  mode `0600`. The manifest states this contract inside every artifact.
- **Pure-ASCII artifacts.** Whatever the source bytes were — binary,
  encrypted, escape-laden — the artifact is printable ASCII (manifest +
  base64), safe for cat, clipboards, chat, and LLM/agent file readers.
- **Traversal-safe restore.** `.dtar` extraction refuses archive members with
  absolute paths or `..` components before `tar x` runs.
- **Typo guard over silent fallback.** A mostly-real file list with one missing
  name dies naming it; nothing is silently re-interpreted as prose.
- **Secret hygiene (`--ai-api`).** API keys are passed to `curl` via `-K
  tmpfile` and request bodies via `-d @tmpfile` — never on the command line
  where `ps(1)` would expose them. Temp files (payload, curl auth config,
  stdin copies) live in `$TMPDIR` (mode-700 per-user on macOS) and are removed
  on exit **and on interrupt** (trap on EXIT/INT/HUP/TERM). *Verified: after
  SIGINT mid-request, zero smash temp files and no key residue remain.*
- **Provider error bodies** are surfaced to the user but pass through the same
  control-byte sanitizer; the API key is never echoed. *Verified: a sentinel
  key never appears in any stdout, artifact, or temp file across the full
  `--ai-api` matrix.*

## MCP server (`smash-mcp`)

- **argv-only execution.** The server calls the `smash` binary with an argument
  vector; there is no shell, no string interpolation, no `sh -c`. The model
  cannot inject flags or commands.
- **Typed tool surface.** The model can encode/decode/verify/inspect — it
  cannot pass arbitrary smash flags or choose arbitrary behavior.
- **Path containment.** In HTTP mode (and stdio with `-roots`), every input
  path and output dir is resolved through `filepath.EvalSymlinks` and must land
  inside an approved root; `..` traversal and symlink escapes are rejected.
- **No content dumps.** Results are paths, sizes, hashes, and manifests — never
  raw file bytes. *Verified: payload text never appears in the protocol
  channel.*
- **No payload logging.** Request bodies are consumed but never logged; the
  only log stream is startup/status on stderr.
- **Sanitized structured errors.** Error strings are stripped of control bytes
  and length-capped, so a hostile filename cannot escape through an error
  message.
- **HTTP hardening.** Loopback-only by default (non-loopback refused unless
  `-allow-remote` **and** TLS); bearer auth required; **constant-time** token
  comparison over SHA-256 digests (length not leaked); CORS disabled;
  request-size cap; concurrency cap; fixed-window rate limit; per-op timeouts;
  `GET`→405. *Verified: 401 on missing/wrong token, 405 on GET, no CORS header,
  non-loopback bind refused, supplied token not logged.*

## Web/PWA

- **All local.** Encode/decode run entirely in the browser via native
  `CompressionStream`/`DecompressionStream`. Nothing is uploaded. There is no
  provider key in client code; provider-backed semantic compression is left to
  the CLI or a user-run local helper.
- **SRI + strict CSP.** The production `dist/index.html` loads `app.min.js` via
  Subresource Integrity (`sha384-…`) under a strict CSP (`default-src 'none'`;
  `script-src 'self'`; no inline script; no `eval`). *Verified: a one-byte
  change to `app.min.js` causes the browser to refuse the script (page renders
  empty); the unmodified bundle runs.*
- **Service worker fails closed.** At install the SW fetches every cached asset,
  computes SHA-256, and compares to a pinned map; any mismatch throws so the SW
  never activates — offline use can't be silently poisoned. *The pinned map is
  verified to equal the real asset hashes. Runtime activation must be confirmed
  in a GUI browser; headless Chrome in the build environment rejects all SW
  registration.*
- **No `innerHTML` with untrusted data.** All untrusted values (filenames,
  content, manifests) are inserted via `textContent`; `innerHTML` is used only
  with static/numeric strings.
- **Minification is not a security boundary.** `app.min.js` is compacted for
  size; the integrity boundary is SRI + the SW hash check, not obscurity. The
  readable source (`smash-web.app.js`) is kept out of `dist/`.
- **Single-file build: hash-sourced CSP, no `'unsafe-inline'`.** `ui/web/index.html`
  (the production-complete single page) can't use SRI on an external script —
  there is no external script, everything is inline by design. Instead its CSP
  allows script execution only via exact `sha256-…` hash sources for the
  loader's own inline script and the dynamically-injected payload script; no
  `'unsafe-inline'`, no `'unsafe-eval'`. *Verified: a real headless-Chrome run
  against a build with an incorrectly-computed hash showed the browser's own
  CSP-violation console message and refused to execute — caught and fixed
  before shipping. The hash computation matches the browser's actual runtime
  behavior (UTF-8 re-encoding of the `atob()`-reconstructed string, not a
  plain file hash — the file's own em-dashes/arrows made this a real, not
  theoretical, divergence).*
- **History (IndexedDB) is metadata-only, but it is client-side storage, not a
  secret store.** Encode/decode history keeps name, size, sha256, mode, and
  timestamp — never source or artifact bytes. That metadata sits unencrypted
  in the browser's IndexedDB for the page's origin, readable by any script
  that runs on that origin (e.g. an XSS elsewhere on the same origin, or a
  malicious browser extension with storage access) — filenames and content
  hashes are not secrets by smash's own model, but a user should not assume
  history is private in the same way "nothing is uploaded" implies. History
  is user-clearable from the UI and is never transmitted anywhere by smash
  itself.
- **Relink (File System Access) persists a capability, not a secret, and it is
  re-checked, not silent.** On Chromium, picking/dropping a file captures a
  `FileSystemFileHandle` and stores it in the same IndexedDB history record.
  That handle is a live capability to re-read that specific file later — it
  outlives the tab. Two things bound it: (1) the handle only exists because
  the user made an explicit, real file-picker/drop gesture in the first
  place — smash cannot mint one itself; (2) every use calls
  `queryPermission`/`requestPermission` before reading, so a stale or
  revoked-by-the-OS handle is caught, not silently honored, and the relinked
  file's sha256 is re-verified and any mismatch is surfaced in the UI, never
  hidden. Safari/Firefox have no such API at all (verified against current
  browser support data, not assumed) — relink there is a manual re-pick with
  the same sha256 check, so the capability-persistence risk doesn't exist on
  those browsers by construction.
- **The streaming pipeline's one full-buffer read is a deliberate, disclosed
  trade-off, not an oversight.** `crypto.subtle.digest` has no incremental/
  streaming form, so computing a real sha256 requires one full read of the
  input. A hand-rolled streaming hash was considered and rejected: a wrong
  hash in an integrity tool is a worse failure than a slower one. Everything
  downstream of that one read — compression, base64 encoding, output — is
  genuinely streamed (chunk-by-chunk, never fully materialized), which is
  what changed from the pre-streaming implementation. *Verified against a
  real 600MB synthetic file in headless Chrome: encode succeeded, correct
  sha256, no crash — with the caveat that this test methodology is
  conservative/pessimistic relative to a real disk-sourced file (see
  CHANGELOG.md's web v5.4 entry for the exact reasoning). Not verified: an
  actual mobile browser on physical hardware.*

## macOS app

- **Secrets in Keychain only.** API keys are stored as Keychain generic
  passwords (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in
  `UserDefaults`/plist, logs, argv, or shell history.
- **argv execution.** The app runs `smash` with an argument array; no shell.
- **User-level helper only.** The optional MCP "network layer" installs a
  user-level binary and registers it with the AI client; no system daemon, no
  platform-server change.
- **Code signing.** The bundle is signed (ad-hoc in the build environment;
  Developer ID where the cert is present). Notarization is **not** performed
  here — see BUILD.md for the honest status. A self-hash alone is not treated
  as anti-tamper; OS code signing is the boundary.

## What smash does NOT claim

- It is not encryption. `--ai-api` sends content to whatever provider you
  configure; that is an explicit, user-chosen network action.
- Minification/obfuscation are not security.
- A generated file existing is not proof it works; see the evidence report.
