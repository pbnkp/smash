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
