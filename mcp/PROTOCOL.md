# smash MCP — Protocol & Integration Guide

`smash-mcp` is the communication layer between MCP-speaking AI applications
(Claude Code, Claude Desktop, agent frameworks) and the `smash` CLI. The model
never runs a shell: it calls typed tools, and the server shells out to the
canonical `smash` binary with **argv** (never a shell string), returning
artifact **paths + metadata** — never raw content.

- Version: `smash-mcp v1.2`
- MCP protocol: `2025-06-18`
- Engine: the `smash` CLI (v5.2) is the single source of truth. The server
  produces byte-identical artifacts to the CLI because it *is* the CLI.
- Language: Go, written to the **Go 1.13** language level (`io/ioutil`, no
  generics, no post-1.13 stdlib). Builds clean on go1.22 (macOS arm64 +
  FreeBSD amd64).

## Why MCP (and not "let the model run smash")

MCP gives the model a **typed, bounded** surface. It can encode/decode/verify,
but it cannot pass arbitrary flags, cannot execute arbitrary commands, cannot
write outside approved roots, and never receives raw file bytes back — only
paths, sizes, hashes, and manifests. That containment is the point.

## Tools

| Tool | Lossy? | Purpose |
|---|---|---|
| `smash_capabilities` | — | version, engine, modes, artifact format, transports, limits |
| `smash_health` | — | liveness/readiness: `ok` / `degraded` / `down` |
| `smash_encode` | no | lossless compress+encode files/dirs/text → artifact paths + sha256 |
| `smash_ai_compress` | **yes** | semantic compression (`native` offline, or `api` via provider env) |
| `smash_decode` | no | restore artifacts → paths + sha256 |
| `smash_manifest` | — | parse an artifact's in-file manifest; report base64 validity |
| `smash_verify` | — | full decode-verify; for lossless, compare restored sha256 to source |
| `smash_batch` | mixed | many encode/ai/decode/verify jobs in one call; cancellation-aware |

Lossless (`smash_encode`/`decode`/`verify`) and lossy (`smash_ai_compress`)
are deliberately separate tools so a client can never confuse the two. Every
result carries an `evidence` field (`CREATED`, `RUNTIME_VERIFIED`,
`RUNTIME_VERIFIED_LOSSY`, `MISMATCH`, `FAILED`, `OBSERVED`).

### Result shape (example: `smash_encode`)
```json
{ "ok": true, "lossy": false, "evidence": "CREATED",
  "artifacts": [ { "artifact": "/path/x.smash.txt", "bytes": 780,
                   "sha256": "9f2a…c41d" } ] }
```

### `smash_verify` (integrity)
```json
{ "artifact": "…", "verified": true, "restoredSha256": "…",
  "sourceSha256": "…", "match": true, "lossy": false,
  "evidence": "RUNTIME_VERIFIED" }
```
For lossless artifacts, `match` compares the restored bytes' sha256 to the
manifest's recorded source sha256 (constant-time). For lossy artifacts, byte
identity is not expected — decode success is the evidence
(`RUNTIME_VERIFIED_LOSSY`).

## Transports

### stdio (default)
Newline-delimited JSON-RPC 2.0 on stdin/stdout. This is what Claude Code /
Claude Desktop use. No network, no auth needed — the AI app spawns the server
as a child process under the same user.

```
smash-mcp
```

### HTTP (optional, local)
```
smash-mcp -http 127.0.0.1:7461
```
- **Loopback only by default.** A non-loopback bind is refused unless
  `-allow-remote` **and** `-tls-cert`/`-tls-key` are supplied (TLS mandatory
  off-loopback).
- **Bearer auth required.** Token from `-token` or `SMASH_MCP_TOKEN`, else one
  is generated and printed to stderr at startup. Compared in **constant time**
  (over SHA-256 digests, so length is not leaked).
- **CORS disabled** (no `Access-Control-Allow-*` headers) → browsers can't call
  it cross-origin.
- Request-size cap (64 MiB), concurrency cap (8 in-flight), fixed-window rate
  limit (120 req / 10 s), per-op timeouts, `GET`→405.
- **Compression proxy:** requests may use `Content-Encoding: gzip`; clients
  that send `Accept-Encoding: gzip` receive gzip for responses of at least
  1 KiB. The 64 MiB cap is enforced after decompression. stdio remains plain
  newline JSON-RPC because custom compressed framing would break MCP clients.

One JSON-RPC request per POST to `/mcp`. `/health` returns a plain-text
liveness line.

## Configuration reference

| Flag / env | Default | Meaning |
|---|---|---|
| `-http host:port` | (off) | enable HTTP transport (loopback unless `-allow-remote`) |
| `-token` / `SMASH_MCP_TOKEN` | auto | HTTP bearer token |
| `-allow-remote` | false | permit non-loopback bind (requires TLS) |
| `-tls-cert` / `-tls-key` | — | TLS material for off-loopback bind |
| `-smash path` | PATH → `~/bin/smash` | smash engine binary |
| `-roots a:b` / `SMASH_MCP_ROOTS` | HTTP: `$HOME`+tempdir | approved path roots (containment) |
| `-V` | — | print version |

**Approved roots.** In HTTP mode, every input path and output dir must resolve
(after symlink evaluation) inside an approved root; traversal (`..`) and
symlink escapes are rejected. stdio inherits the same check when `-roots` is
set.

## Client setup

### Claude Code
```
claude mcp add -s user smash ~/bin/smash-mcp
```

### Claude Desktop (`claude_desktop_config.json`)
```json
{ "mcpServers": { "smash": { "command": "/Users/you/bin/smash-mcp" } } }
```

### Any MCP client over HTTP
```
smash-mcp -http 127.0.0.1:7461 -token "$SMASH_MCP_TOKEN"
curl -s http://127.0.0.1:7461/mcp \
  -H "Authorization: Bearer $SMASH_MCP_TOKEN" \
  -H "Accept-Encoding: gzip" --compressed \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"smash_capabilities","arguments":{}}}'
```

## Security model

See `SECURITY.md` and `THREAT-MODEL.md`. In one paragraph: argv-only execution
(no shell), typed tools (no arbitrary flags), path containment (approved roots,
traversal + symlink-escape rejected), no payload logging, sanitized structured
errors (control bytes stripped so a hostile filename can't inject terminal
escapes through the protocol), constant-time auth on HTTP, loopback-default
with TLS-required-off-loopback, and results that are paths + metadata rather
than content dumps.

## Evidence (this build)

- Protocol battery includes 8 tools, stdio + HTTP, gzip request/response,
  decompressed-size enforcement, auth (401 on
  missing/wrong token), 405 on GET, no CORS, non-loopback refused, token not
  logged, path traversal rejected, malformed JSON-RPC → parse error, unknown
  method → -32601, unknown tool → isError, duplicate id both answered,
  notification-only stays silent, no content dumps in the protocol channel.
- In-client: `smash_capabilities` answers through standard MCP clients against
  `smash v5.2`; no custom client codec is required.
