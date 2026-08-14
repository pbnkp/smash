# Changelog

All notable changes to smash are documented here.

---

## v5.5 — 2026-08-14 (CLI + web + MCP 1.2) — "never bigger"

The trigger: a 166,505-byte JPEG smashed on web v5.4 produced a 221,474-byte
artifact (+33%). Root cause is arithmetic, not a bug: base64 is a hard x1.333
(printable-ASCII floor: x1.218) and gzip/xz find zero slack in entropy-coded
data, so a byte-lossless ASCII artifact of an already-compressed source is
MATHEMATICALLY always bigger than that source. v5.5 makes smash stop
pretending otherwise.

### Added
- **Media-fit (CLI + web).** When the lossless payload cannot beat the source
  and the source is a JPEG, smash re-encodes the image at descending quality
  (CLI: native `sips`, q 85→35; web: canvas `toBlob`, q .85→.35) until the
  WHOLE artifact (manifest + payload) is strictly smaller than the source.
  First quality that fits wins, preserving maximum fidelity. Result is
  visually equivalent, NOT byte-identical — declared loudly:
  `lossy: visual-fit`, a `# fit:` manifest line with `fit-bytes` +
  `fit-sha256` (restored-bytes integrity target; `sha256:` stays the SOURCE
  hash for provenance), and the restored file is named `<name>.fit.jpg` so it
  never impersonates the original. CLI and web fit artifacts decode
  interchangeably (verified both directions). Reference file: 166,505B JPEG →
  160,145B artifact via CLI (96%, q75), 112,540B via web (68%, q85 — canvas
  encodes tighter than sips).
- **`--exact` (CLI) / `exact:true` (MCP).** Forbid media-fit: byte-lossless
  artifact even when bigger. `--fit` extends auto-fit to any raster sips
  reads (PNG/TIFF/BMP/HEIC/WebP → fitted JPEG; flattens transparency —
  that's why it's opt-in).
- **INFLATED warning.** Non-media already-compressed inputs (zip, video,
  encrypted) still encode losslessly — nothing smaller is possible — but now
  warn loudly instead of silently shipping a bigger artifact. Hosts without
  sips (FreeBSD) do the same for images.
- **MCP `smash_verify` fit awareness.** Media-fit artifacts verify restored
  sha256 against `fit-sha256` → `RUNTIME_VERIFIED_FIT|MISMATCH`; lossless
  behavior unchanged. `lossy` detection now treats any non-"no" value as
  lossy. `smash_encode` gained the `exact` option; capabilities report
  `mediaFit`.

### Fixed
- **Web decode of artifacts >64KB (latent since the v5.4 streaming
  rewrite).** Smash payloads are ONE giant base64 line; the header parser
  booked every byte read while waiting for a newline as "header" and tripped
  the 65,536-byte header cap, so web decode of any large single-line artifact
  (including every CLI artifact) failed with "header exceeds 65536 bytes". A
  partial line that cannot be a `#` header line is now recognized as payload
  immediately. Verified: 160KB CLI `-g` fit artifact decodes in-browser with
  fit-sha256 match.
- **Web now names xz/zstd artifacts plainly.** Instead of DecompressionStream's
  cryptic "incorrect header check", decoding a non-gzip artifact reports:
  "this artifact is xz-compressed — browsers only decode gzip; restore it
  with the CLI".
- **MCP `parseOutputs` matched decode lines by exact prefix** and missed any
  parenthesized variant with variable content (bit first on media-fit's
  `decoded (media-fit jpeg q=NN — ...)`); now matches the line shape.

---

## web v5.4 — 2026-08-13

Streaming rewrite of the web app (`ui/web/`). The CLI itself is unchanged
(still v5.3) — this is a web-only version bump; the two now share the same
artifact format (`<name>.smash.txt`) but track separately since the web app
gained capabilities the CLI doesn't have.

### Added
- **Streaming encode/decode.** The old pipeline read the whole file via
  `arrayBuffer()`, materialized the whole compressed output, then built one
  giant base64 string — roughly 4-5x the file size in peak JS heap, easily
  enough to crash mobile Safari on a large video. The rewrite streams
  compression and base64 output chunk-by-chunk (3-byte-aligned encode,
  4-char-aligned decode, both carry a small cross-chunk buffer) straight into
  either a `showSaveFilePicker()` writable stream (Chromium: never touches
  JS heap as one blob) or a `Blob` built from an array of small parts
  (Safari/Firefox: the browser assembles it, not one JS string). One full
  buffer read remains, deliberately: computing a real sha256 needs the whole
  input, and `crypto.subtle.digest` has no incremental form — a hand-rolled
  streaming hash was ruled out as the wrong place to introduce a bug in an
  integrity tool. Verified via headless Chrome against a real 600MB
  synthetic file (encode succeeded, correct sha256, no crash) and a real
  encode→decode round trip with byte-exact content match.
- **History (IndexedDB, no login).** Reference metadata only — name, size,
  sha256, mode, timestamp — never the source bytes or the artifact bytes.
  Clearable from the UI.
- **Relink.** On Chromium, picking or dropping a file via the File System
  Access API captures a `FileSystemFileHandle`, stored alongside its history
  entry for silent re-access later (permission re-request, sha256
  re-verify). Safari/Firefox lack that API entirely — relink there falls
  back to a manual re-pick with the same sha256 verification.
- **PWA install UX.** Captures `beforeinstallprompt` on Chromium/Android for
  a real install button; iOS Safari has no programmatic install API at all,
  so it gets a guided "tap Share → Add to Home Screen" hint instead, shown
  once and never once `display-mode: standalone` / `navigator.standalone`
  indicates it's already installed.
- **`ui/web/index.html` is now the production-complete single-file build**,
  not just a `file://` fallback: inline favicon, meta description, and an
  inlined `data:` URI PWA manifest (verified installable — `beforeinstallprompt`
  fired correctly in a real headless-Chrome run against it, not assumed to
  work). Its CSP moved to hash-sourced `script-src` (`sha256-…` on the loader
  and payload scripts) instead of `'unsafe-inline'`, matching `dist/`'s
  security posture despite having no external script to apply SRI to.
  Documented trade-off in INSTALL.md: this variant has no service worker (no
  second file to register one against), so it always runs online — use
  `dist/` if offline support matters more than file count.

### Fixed (build process)
- **The CSP hash-source computation had two real bugs, both caught by testing
  against a real browser, not by review.** (1) The loader script's hash was
  computed via an `awk` line-reconstruction that introduced a whitespace/
  newline mismatch — Chrome's own CSP-violation message showed the correct
  hash, which matched neither of the two hashes in the policy. This would
  have completely broken the page (CSP blocks the loader itself → blank
  screen) had it shipped untested. (2) The payload script's hash was computed
  as a plain file hash, but the loader reconstructs the payload via
  `atob()` → JS string (Latin-1: one char per original byte) → assigned to
  `textContent`, and CSP hashes the UTF-8 re-encoding of that string — for a
  file containing non-ASCII bytes (this one has em-dashes, arrows, middle
  dots in its UI copy), that diverges from a plain file hash. Verified
  empirically that the two hash values differ for this file, not assumed.
  Fixed by extracting the loader's exact bytes by offset (Python, not `awk`
  reconstruction) and computing the payload hash via the same Latin-1-decode-
  then-UTF-8-re-encode transform the browser actually performs. Re-verified
  in headless Chrome post-fix: zero CSP violations, full functional test
  passes (`ok:true`).

### Fixed
- Web artifact naming now matches the CLI's (`<name>.smash.txt`) instead of
  the web app's own older `<name>.gz.b64.<timestamp>.txt` scheme —
  cross-tool interop verified with the real installed CLI decoding a
  web-produced artifact.

---

## v5.0 — 2026-07-10

The "many things in, one safe text file out" release.

### Added
- **Multi-input encode.** `smash f1.txt f2.php ./sub/f3.whatever dir/ ...`
  encodes every operand (each artifact lands beside its own input unless
  `-o`/`B64_OUTDIR` says otherwise). The old `too many args` error is gone.
- **Multi-artifact decode.** `smash -d a b c [-o dir/]` decodes each.
- **Argument-vector-as-text fallback.** When operands are *mostly not files*
  (e.g. `` smash `ps auxww` `` — an unquoted command substitution that
  explodes into dozens of words), smash now encodes the whole argument
  vector as one inline-text payload (`args.xz.b64.<ts>.txt`) instead of
  dying. It announces this loudly (even under `-q`) because it changes what
  the artifact is. A typo guard keeps real file lists strict: if half or
  more of the operands exist, a missing one is treated as a typo and smash
  dies naming it — nothing is silently encoded as prose.
- **`-` stdin operand.** `cmd | smash -` streams stdin explicitly (the bare
  pipe form still works); `smash -d -` decodes an artifact piped or pasted
  on stdin, restoring into the current directory.
- **In-artifact manifest.** Every artifact now opens with a `# `-prefixed
  manifest *before* the payload: tool + version, created (UTC) + host,
  source name, kind, byte count, sha256 of the source bytes, the encoding
  chain, a restore hint, and an explicit safety note that the payload is
  inert data. Decode strips it automatically.
- **LLM/agent-safe artifact format.** Artifact names now end in **`.txt`**
  (`<name>.<mode>.b64.<timestamp>.txt`) and artifact contents are pure
  printable ASCII (manifest + base64) — so AI assistants, agent tooling,
  editors, and terminals can open any artifact safely even when the source
  content is binary or encrypted. Collision suffixes stay *before* the
  `.txt` so the extension always survives.
- **`-V` / `--version`.**
- **`-o` on encode.** Existing dir (or trailing `/`) = output directory;
  otherwise a filename prefix for single input, or created as a directory
  for multi input. (Previously `-o` was silently ignored on encode.)

### Fixed
- Operands after `--` were silently dropped; they are now honored verbatim
  (dash-leading filenames encode/decode correctly).
- Decoding an artifact of an empty source no longer dies; it restores the
  empty file with a note.
- `--ai` on a non-text input no longer mangles bytes through the awk
  compactor — it falls back to lossless xz for that input, loudly.

### Security
- **Terminal-bleed hardening.** Source content is never written to the
  terminal, and every dynamic string smash prints (filenames, API error
  excerpts) is stripped of control/escape bytes first — ANSI/OSC escape
  injection via a hostile filename or API response can no longer reach the
  terminal. Verified in the release battery by asserting zero ESC bytes
  across captured stdout+stderr while encoding files whose *names and
  contents* contain OSC/CSI sequences.
- **Artifacts are inert and non-executable.** Artifacts and restored files
  are written mode `0600`; payloads are data only — nothing in smash ever
  `eval`s, sources, or executes payload bytes, and the manifest says so in
  the file itself.
- **Option-injection guards.** `--` end-of-options added to `mv`/`cp`/
  `chmod`/`tar` invocations that touch user-controlled names.
- **Batch atomicity.** All operands are validated (readable, supported
  type) *before* the first artifact is written, so a bad operand can't
  leave a half-finished batch.

### Compatibility
- **Pre-v5 artifacts decode unchanged** (headerless single-line payloads,
  with or without the `.txt` suffix). v5 artifacts require v5 to decode
  (older versions don't strip the manifest).
- Verified on: macOS `/bin/bash` 3.2 (60-check battery) and FreeBSD 12.1
  bash 4.3 / xz 5.2.4 (15-check battery incl. cross-version decode of a
  v4.5-produced artifact).

---

## v4.5 — 2026-06-29

### Fixed
- **`smash --edit` no longer crashes with "command nano -w not found".** The
  editor default `"${EDITOR:-nano -w}"` collapsed into a single quoted word, so
  the shell looked for a program literally named `nano -w`. The editor is now
  resolved into a bash array: `$VISUAL`/`$EDITOR` are honored (multi-word safe,
  e.g. `code --wait`) and, if unset, smash falls back through
  `nano → pico → vi → vim` (passing `-w` only to nano).

### Added
- **`-z` / `--zstd`** — opt-in zstd compression mode (`.zst.b64`). Decode
  auto-detects it. Fast and modern; needs `zstd` installed on both ends.
- **`--level N`** — compression level override (xz/gz `1-9`, zstd `1-19`).
- **`--threads N`** — xz/zstd thread count (default `0` = all cores).
- **`-q` / `--quiet`** — suppress progress output (errors still print).

### Speed
- **xz multithreading** (`-T0`, all cores) on encode, probed once at startup and
  auto-omitted on hosts whose `xz` predates `-T`. Large wins on big inputs,
  no-op on small ones. Decode/verify already handle threaded streams.
- **`pigz`** used automatically for `-g`/gzip mode when installed (output is
  standard gzip; `gunzip` reads it).

### Security
- **Temp files honor `$TMPDIR`** (per-user, mode-700 on macOS) instead of
  world-writable `/tmp`; falls back to `/tmp` only when `$TMPDIR` is unset.
- **`.dtar` extraction rejects path traversal** — archive members with absolute
  paths or `..` components are refused before `tar x` runs (payloads can be
  untrusted).
- **API-key temp files are registered with the cleanup trap**, so an interrupt
  mid-request can't leave the `curl` auth config (containing the key) behind in
  the temp dir.

---

## v4.4 — 2026-05-07

### Changed
- Default Anthropic model updated: `claude-sonnet-4-20250514` → `claude-sonnet-4-6`  
  (Claude 4 Sonnet API model ID, correct as of 2026-05-07)

### Added
- `boy-smash.sh` AI workflow integration documented in README  
  (read / pack / context / memory / decode subcommands for AI session use)

---

## v4.3

### Changed
- **POSIX hardening:** Switched to explicit bash features (`[[ ]]`, `local`, pipefail) from POSIX-only awk/sed approaches — avoids portability theater while gaining real safety guarantees.

### Security
- **API keys hidden from process list:** API key now passed to curl via `-K tmpfile` (a temp file readable only by the process) instead of on the command line. `ps aux` can no longer expose keys.
- **API payloads hidden from process list:** Request body passed via `-d @tmpfile` instead of `-d '{"large":...}'` — also prevents ARG_MAX errors on large inputs.

### Fixed
- `printf` over `echo` for all data output — eliminates `-n`/`-e` interpretation issues across platforms.
- `stdin <` redirects replace `cat |` pipes — one fewer process, cleaner signal handling.
- Tool existence checks at startup with clear error messages (`die "requires openssl"`).
- Robust `$EDITOR` fallback: checks for `nano` before dying if `$EDITOR` is unset.

---

## v4.2

### Added
- Directory support: directories are automatically tarred before encoding. On decode, `.dtar.*` files are auto-extracted back to directories.
- `.dtar` extension convention to distinguish directory archives from single-file archives.
- Binary files in directories are included unchanged when using `--ai`/`--ai-api` modes (only text files get AI-compressed).

---

## v4.1

### Added
- `--ai-api` mode: LLM API semantic compression. Supports Anthropic, OpenAI, Ollama, LM Studio, Groq, Together, Mistral, OpenRouter, vLLM, text-generation-webui, and any OpenAI-compatible endpoint.
- Auto-detection of API provider from environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `B64_AI_URL`).
- Compression system prompt tuned for maximum fact preservation at minimum size.
- Local model support — any endpoint at `localhost` is treated as keyless.

---

## v4.0

### Added
- `--ai` mode: native semantic compression using an awk-based domain dictionary. No API, no network. Implements the core compression ideology: shared domain knowledge between writer and reader can be exploited without transmitting the dictionary.
- 100+ entry abbreviation dictionary covering: core types, infrastructure, identity/auth, data/comms, code structure, ops/lifecycle, qualifiers.
- Filler phrase removal (100+ patterns).
- Article and weak-verb stripping (reconstructable from context).
- Line-joining optimization: packs short lines into 250-char blocks before compression, giving xz a larger sliding window for better pattern matching.
- Deduplication of consecutive identical lines.

---

## v3.x

- `--edit` mode: open `$EDITOR`, encode file contents on save/exit.
- `-s` string mode: encode a string argument directly.
- Interactive paste mode: `smash` with no arguments opens a Ctrl+D-terminated input session.
- Output path control: `-o` flag and `$B64_OUTDIR` environment variable.
- `pick_unique()` for collision-free output filenames.

---

## v2.x

- Gzip mode (`-g` / `--gz`): faster lossless compression, wider compatibility.
- Auto-detection of compression format on decode from file extension.
- Verification step after encode: decodes output to temp file and runs `xz -t`/`gzip -t` to confirm integrity before moving to final location.

---

## v1.0

- Initial release: xz + base64 encode/decode. Single-file tool. Interactive paste mode. FreeBSD-first (wolowitz/FreeBSD 12.1 development host).
