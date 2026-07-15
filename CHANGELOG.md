# Changelog

All notable changes to smash are documented here.

---

## v5.2 — 2026-07-15

The readable-artifact and clipboard-drop release.

### Added
- Readable artifact names now use `<source>.smash.txt`, with `.2`, `.3`, etc.
  only for collisions. Compression, time, source kind, and checksums remain in
  the self-describing manifest; old timestamped `.b64` names still restore.
- The integrated macOS drop zone accepts dragged text as well as files and
  folders, and includes a **Smash Clipboard Text** button for large copied text.
  Clipboard content streams directly to Smash and is not staged as plaintext
  in a temporary file.

---

## v5.1 — 2026-07-15

The permission-safe restore and complete macOS integration release.

### Fixed
- Directory restores preserve ordinary source modes instead of flattening
  everything through the current umask. Extraction happens in a private
  staging directory; archived uid/gid values are never applied.
- Dangerous modes are narrowly sanitized: setuid/setgid regular files lose
  those bits, world-writable regular files lose `o+w`, and non-sticky
  world-writable directories lose `o+w`. Normal read/write/execute modes,
  executable tools, setgid/sticky directories, and mtimes are preserved.
- FreeBSD artifact hardening no longer relies on unsupported `chmod --`;
  artifacts are explicitly verified mode `0600` on macOS and FreeBSD.
- Menu-bar file drops use file-URL-only pasteboard reads and visible drag
  feedback. The app also accepts Finder Open With and a native NSServices
  provider instead of relying only on Automator.
- Finder installer registers and validates all four Quick Actions, clearing
  stale partial Service registrations first.
- macOS package/custom upgrades remove the obsolete standalone
  `com.boy.smash-dropzone` LaunchAgent now that dropping and restoring are
  integrated into the main Smash menu app.

### Added
- MCP v1.2 HTTP transport accepts gzip request bodies and negotiates gzip
  responses. The 64 MiB limit applies after decompression to block gzip bombs;
  stdio remains standard uncompressed MCP JSON-RPC.
- A sandboxed macOS Share extension, embedded in `Smash.app`, accepts files,
  media, URLs, and text from the system Share menu.
- Signed-app build, all-in-one `.pkg` builder, user-level custom installer,
  and clean uninstaller. Package/custom installs include the app, CLI, MCP
  helper, Share extension, and four Finder actions.

### Security
- Smash artifacts remain inert ASCII data: mode `0600`, never eval'd, sourced,
  or executed. This restriction applies to the artifact, not to safe original
  execute bits on a decoded directory tree.

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
