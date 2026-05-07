# Changelog

All notable changes to smash are documented here.

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
