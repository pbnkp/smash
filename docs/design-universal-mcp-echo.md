# smash-echo: universal MCP server with local gateway, token accounting, and call receipts

Design document. Not a spec, not a promise, not an announcement.
Status: PROPOSED. Nothing in here is built.
Author of the request: repo owner. Author of this doc: engineering pass, 2026-07-20.
Engine baseline: `smash` v5.3, `smash-mcp` v1.2 (8 tools, stdio + loopback HTTP).

**Evidence vocabulary.** This doc reuses the states the MCP server already emits
(`CREATED`, `RUNTIME_VERIFIED`, `RUNTIME_VERIFIED_LOSSY`, `MISMATCH`, `FAILED`,
`OBSERVED`) and adds two for claims about the outside world:
`INFERRED` (reasoned, not checked) and `UNVERIFIED` (not checked, not reasoned,
just reported by a third party). Adding two states to the server's enum is a
real change; it is flagged here rather than assumed.

Every external claim below carries a state. Anything marked `VERIFIED` was
fetched or executed on 2026-07-20 and is listed in Appendix A with its source.
Anything marked `INFERRED` came from a search summary and was not read at the
primary source. Anything marked `UNVERIFIED` I do not know.

---

## 1. The ask, restated, and the line between real and not real

### 1.1 The request

One MCP server that installs into every MCP-supporting host (Claude Desktop,
Claude Code, ChatGPT, Grok, Gemini, Cursor, others). It runs locally as an
"echo back" service. It owns the network layer, compression, and token usage.
It frames LLMs so they stop emitting delay responses and fake latency, and it
forces accountability. No network drops, no fake delays. Maximum token savings,
maximum execution and response accuracy.

### 1.2 The structural facts that constrain all of it

**An MCP server is not in the model's path.** It is a callee. The host
application decides when to call it, what arguments to send, and what to do
with the result. The server never sees the system prompt, never sees the
conversation, never sees the other servers' tools, never sees the inference
request, and cannot modify anything the model emits. This is architecture, not
a limitation of effort.

Consequence: "owns the network layer" is false as written, for every hosted
model. The server can own **the traffic that is routed through its own tools**.
It cannot touch host-to-model traffic. The single exception is a self-hosted
model (Ollama, llama.cpp, vLLM) where you control the inference endpoint and
can put a loopback proxy in front of it. That proxy would not be an MCP server.
It would be a separate component in the same repo. It is listed as Phase 5 and
marked optional.

**A tool result is an input to a probabilistic decoder.** Tool descriptions and
result payloads influence the model. They do not constrain it. "Force
accountability" and "force the model to stop stalling" are not achievable by
any server-side mechanism. What is achievable is making the stall pointless and
detectable: return a terminal answer with measured wall-clock inside a
guaranteed deadline, never return a "pending" or "processing" shape the model
can echo back as waiting, and keep a receipt so a claim like "I ran the
verification" can be checked against the ledger in one call.

**"No network drops" cannot be guaranteed** for networks we do not own. What
can be guaranteed is deterministic behavior when drops happen: one terminal
state per call, always inside the deadline, retries bounded and disclosed,
never an infinite hang, never a silent failure reported as success.

**Compression does not automatically save tokens.** This is the most expensive
misconception in the ask, so it gets stated bluntly. A smash artifact is
base64 of xz. Base64 of high-entropy bytes tokenizes badly, roughly 1 token per
2 to 3 characters on BPE tokenizers (`INFERRED`, must be measured, see 5.4).
Compressed bytes are high entropy by construction. So pasting a compressed
artifact **into the context window can cost more tokens than the original text
and the model still cannot read it**, because no model can decompress xz in its
head.

smash artifacts save tokens in exactly one way: when they travel **by
reference** and never enter the context window. The token win comes from
reference passing, deduplication, delta transfer, and summary tiers. Not from
the compression ratio. The compression ratio is a transport and custody
property, not a context property. Any design that claims otherwise is lying to
the owner.

### 1.3 Achievable / not achievable

| Owner's phrasing | Verdict | What is actually delivered |
|---|---|---|
| One MCP server installs to Claude, ChatGPT, Grok, Gemini, others | **Partly** | One binary, both transports, one installer emitting per-host config dialects. Local stdio for Claude Code/Desktop, Cursor, VS Code, Windsurf, Zed, Gemini CLI. ChatGPT and the Grok API are remote-only, so they need an exposed HTTPS endpoint (see 2.4). "Install once, everywhere" is not a thing that exists. |
| Local echo-back service | **Yes** | `echo_ping` gives cryptographic round-trip proof and real RTT. The gateway tools give deterministic call-and-return with receipts. |
| Handles the network layer | **Scoped** | Owns egress for calls routed through `echo_fetch`: allowlist, deadlines, bounded retries, cache, dedupe, receipts. Does not and cannot touch model inference traffic on hosted models. |
| Handles compression | **Yes** | Already does. Extended with content-addressed storage and delta transfer. |
| Handles token usage | **Scoped** | Counts and caps tokens **in its own tool results and schemas**. Cannot see or reduce the host's system prompt, conversation history, or other servers' output. Counts are estimates for any tokenizer we cannot run offline. |
| Frames LLMs to drop delay responses / fake delays | **Partly, by influence only** | The server never sleeps, never returns a pending shape, always returns measured wall-clock. Whether the model still says "let me check on that" is outside our control. We make the claim checkable, not impossible. |
| Force accountability | **No, as stated** | Substituted: per-call evidence records, `echo_receipt`, `echo_verify_claim`. Dishonesty becomes detectable in one call. It does not become impossible. |
| No network drops | **No, as stated** | Substituted: deterministic timeout and retry, single terminal state, disclosed attempts, no hangs. |
| Maximum token savings | **Yes, by mechanism** | Reference-not-content, content-addressed dedupe, delta transfer, tiered returns, batch calls. Measured and reported per call, with the measurement method named. |
| Maximum execution and response accuracy | **Indirect** | Accuracy improves when the model is handed verified facts instead of raw dumps it must summarize. That is a real effect and an unquantified one. No accuracy number is claimed here. |

---

## 2. MCP host compatibility survey (checked 2026-07-20)

### 2.1 Protocol state

`VERIFIED` The stable specification revision is **2025-11-25**. It defines
hosts, clients, servers over JSON-RPC 2.0, with stateful connections and
capability negotiation. Server features: resources, prompts, tools. Client
features: sampling, roots, elicitation. Utilities: progress, cancellation,
logging, configuration, error reporting.

`VERIFIED` A release candidate for **2026-07-28** is published, final on
2026-07-28 (eight days from this writing). It is a significant break:

- Stateless protocol core. The `initialize`/`initialized` handshake and the
  `Mcp-Session-Id` header are removed. Client metadata rides in `_meta` on
  every request.
- Extensions framework with reverse-DNS identifiers and independent versioning.
- Tasks and MCP Apps become official extensions rather than core features.
- Streamable HTTP requires `Mcp-Method` and `Mcp-Name` headers so proxies can
  route without body inspection.
- Deprecated under a new twelve-month lifecycle policy: **roots, sampling,
  logging**. Sampling is redirected to direct provider APIs; logging to stderr
  and OpenTelemetry.
- Multi Round-Trip Requests (SEP-2322) replaces server-initiated sampling and
  elicitation with `InputRequiredResult` carrying `inputRequests` and an opaque
  `requestState`.

**Finding, current build:** `smash-mcp` v1.2 advertises `2025-06-18`. That is
two revisions behind stable and three behind the imminent RC. Any "universal"
claim requires supporting at least `2025-06-18` and `2025-11-25` now, with the
stateless core on a branch before the RC becomes normative. Design implication:
do not build anything that depends on server-initiated sampling. It is
deprecated on arrival.

### 2.2 Hosts that accept a local stdio server

| Host | Transport | Config location | State |
|---|---|---|---|
| Claude Code | stdio, `--transport http`, SSE, OAuth login | `claude mcp add [-s local\|user\|project]`, project `.mcp.json` | `VERIFIED` (ran `claude mcp --help` locally) |
| Claude Desktop | stdio | `claude_desktop_config.json`, macOS under `~/Library/Application Support/Claude/`, Windows under `%APPDATA%\Claude\` | `INFERRED` (filename confirmed in this repo's `mcp/PROTOCOL.md`; path from memory) |
| Gemini CLI | stdio default; `mcpServers` key | `~/.gemini/settings.json` or project `.gemini/settings.json`; `gemini mcp add <name> <command>` | `INFERRED` (search summary of Google's docs; not primary-fetched) |
| Cursor | stdio; `mcpServers` key | `~/.cursor/mcp.json`, project `.cursor/mcp.json` | `INFERRED` |
| VS Code (Copilot) | stdio; **`servers`** key, not `mcpServers` | workspace `.vscode/mcp.json` | `INFERRED` |
| Windsurf | stdio; `mcpServers` key | `~/.codeium/windsurf/mcp_config.json` | `INFERRED` |
| Zed | stdio; **`context_servers`** key | Zed settings | `INFERRED` |
| Grok Build (xAI terminal agent, beta) | "bring your own MCP"; reported to accept Claude Code configurations unchanged | unknown | `UNVERIFIED` on stdio specifically. The claim that Claude Code servers work unchanged implies stdio, but implication is not verification. |

Three different root keys already exist across this table (`mcpServers`,
`servers`, `context_servers`). That alone kills the idea of one config file
that every host reads.

### 2.3 Hosts that refuse local stdio

`VERIFIED` **ChatGPT.** OpenAI's Apps SDK documentation states the server must
be reachable over HTTPS and, for local development, instructs the developer to
use a tunnel: "for local development, use Secure MCP Tunnel and select Tunnel
when you create the app, or you can expose a local server to the public
internet via a tool such as ngrok or Cloudflare Tunnel." The endpoint form
given is a public `/mcp` URL. localhost is not a supported target.

`INFERRED` ChatGPT developer mode accepts SSE and streamable HTTP, and is
available on Pro, Plus, Business, Enterprise, and Education plans on web.
Not primary-fetched.

`INFERRED` **xAI Grok API / Grok 4.3.** Remote MCP tools are supported in the
xAI SDK, the OpenAI-compatible Responses API, and the Voice Agent API. Reported
verbatim in a search summary of xAI's docs: "Only Streamable HTTP and SSE
transports are accepted. STDIO is not." Not primary-fetched.

`UNVERIFIED` **Gemini consumer app / AI Studio.** I do not know whether the
non-CLI Gemini surfaces accept user-supplied MCP servers, local or remote. Do
not assume they do.

### 2.4 What "universal install" actually requires

Four separate mechanisms, not one:

1. **Config emitters.** The installer knows each host's file path and root key,
   merges rather than overwrites, backs up first, and defaults to `--dry-run`.
   For hosts we cannot verify, it prints the JSON block to stdout and tells the
   user where to paste it. Honest fallback beats a wrong write into someone's
   editor config.
2. **MCPB bundle** (`.mcpb`, the renamed DXT format): a zip containing the
   server binary plus `manifest.json`, for one-click install in desktop hosts
   that support it. `INFERRED`, from search summaries of the modelcontextprotocol
   `mcpb` repo. Scope of host support not verified.
3. **Registry publication** in the official MCP registry (preview since
   September 2025, API frozen at v0.1 in October 2025). `INFERRED`.
4. **Bridge mode** for remote-only hosts. Unavoidably an internet-reachable
   HTTPS endpoint plus auth. See 3.7. This is a different trust tier and must
   be opt-in, off by default, with a reduced tool surface.

**The tension, stated plainly.** smash's security posture is local-only,
loopback-default, no payload logging, path containment. ChatGPT and the Grok
API can only be reached by exposing an endpoint to the public internet. Those
two positions are mutually exclusive on the same process. The design does not
resolve this by compromise. It resolves it by making them separate modes with
separate tool surfaces, and by defaulting to local. If the owner wants ChatGPT
support, the owner is choosing to run a second, narrower, authenticated,
internet-exposed instance. That decision is the owner's, not the design's.

---

## 3. Architecture

### 3.1 One binary, three personalities

DRY: do not fork a second server. `smash-mcp` v2 is the same binary with modes.

```
smash-mcp                          stdio, local tools + echo tools     (default)
smash-mcp -http 127.0.0.1:7461     loopback HTTP, same surface, bearer auth
smash-mcp -bridge -http :8443 ...  internet-exposed, REDUCED surface, auth required
```

The existing 8 `smash_*` tools keep their names, schemas, and result shapes.
Nothing that works today breaks. The echo layer is additive.

### 3.2 Components

```
  ┌───────────────────────────────────────────────────────────┐
  │ HOST (Claude Code / Desktop / Cursor / Gemini CLI / ...)   │
  │   model ── decides ──▶ tools/call                          │
  └────────────┬──────────────────────────────────────────────┘
               │ JSON-RPC 2.0 (stdio | streamable HTTP)
  ┌────────────▼──────────────────────────────────────────────┐
  │ smash-mcp v2                                              │
  │                                                           │
  │  dispatch ─▶ [deadline] ─▶ [single-flight] ─▶ [op]        │
  │      │            │              │                        │
  │      │            │              └── dedupe by args hash  │
  │      │            └── ctx deadline, clamped, never ∞      │
  │      │                                                    │
  │  ┌───▼────────┐ ┌────────────┐ ┌──────────┐ ┌──────────┐ │
  │  │ engine     │ │ CAS store  │ │ token    │ │ ledger   │ │
  │  │ (smash CLI │ │ objects/   │ │ meter    │ │ JSONL    │ │
  │  │  argv only)│ │ by sha256  │ │          │ │ append   │ │
  │  └───┬────────┘ └─────┬──────┘ └────┬─────┘ └────┬─────┘ │
  │      │                │             │            │       │
  │  ┌───▼────────────────▼─────────────▼────────────▼─────┐ │
  │  │ result assembler: tier, cap, evidence, timings      │ │
  │  └───────────────────────┬─────────────────────────────┘ │
  │                          │                                │
  │  ┌───────────────────────▼──────────┐                     │
  │  │ egress gateway (echo_fetch only) │──▶ allowlisted hosts │
  │  └──────────────────────────────────┘                     │
  └───────────────────────────────────────────────────────────┘
```

What is *not* in this picture, deliberately: the model's inference traffic.
It never passes through this process on a hosted model.

### 3.3 The echo-back model, concretely

"Echo back" is implemented as three guarantees, not a metaphor:

1. **Proof of round trip.** `echo_ping` takes a client nonce and returns
   `sha256(nonce + server_secret_epoch)` plus a monotonic duration. The caller
   can prove the process actually answered and how long it truly took.
2. **Every call terminates.** One request produces exactly one terminal result
   inside the deadline. There is no `pending`, no `queued`, no `processing`
   state in any result shape. If work cannot finish in the deadline, the result
   is `FAILED` with `reason: deadline_exceeded` plus whatever partial artifacts
   exist, with hashes.
3. **Every call leaves a receipt.** Append-only ledger entry with hashes, never
   payloads.

### 3.4 Where smash compression plugs in

Three places, none of which put base64 in the context window:

- **Egress results.** `echo_fetch` writes the response body to the CAS,
  optionally encodes it to a `.smash.txt` artifact for durable custody, and
  returns `{cid, bytes, sha256, status, tier-summary}`. The body never crosses
  the protocol channel unless the caller explicitly asks for a tier that
  includes it, under a token cap.
- **Handoff between agents/machines.** Where an artifact must physically move
  (another host, another machine, a paste channel), the existing lossless
  artifact is the transport. That is the format's real job.
- **Lossy summarization.** `smash_ai_compress` native mode (offline dictionary,
  25 to 40 percent) can generate the `outline` tier for text. It is lossy and
  must stay labeled `RUNTIME_VERIFIED_LOSSY` or `CREATED`, never mixed with
  lossless evidence.

### 3.5 Token accounting

Per call the server records:

- `tokens_returned_est`: estimated tokens in the result the host receives.
- `tokens_raw_est`: what the untiered, uncapped result would have cost.
- `tokens_saved_est`: the difference, plus the mechanism that produced it
  (`tier`, `dedupe`, `delta`, `cap`, `batch`).
- `token_estimate_method`: named, never implied. One of
  `bpe:<tokenizer-id>` when a tokenizer is actually available offline, or
  `heuristic:chars-per-token=<n>` otherwise.

Session totals are available from `echo_budget`. The word "estimate" stays in
the field names. See 5.4 for why exact counts are not offered for four vendors.

### 3.6 Latency truth

Three separate measured numbers per call, all from a monotonic clock:

- `queue_ms`: time waiting on a concurrency semaphore.
- `engine_ms`: time inside the `smash` child process or the network call.
- `duration_ms`: total server-side wall clock.

Rules enforced in code and in the test battery:

- No `sleep` anywhere except retry backoff, and backoff time is reported in
  `backoff_ms`. A test greps the source for sleeps outside the backoff helper.
- Deadlines: every tool accepts `deadline_ms`, clamped to a per-op maximum. The
  context deadline is authoritative. There is no code path that waits forever.
- Retries only for idempotent operations, bounded (default 2), disclosed as
  `attempts`, with backoff capped by remaining deadline. A retried call reports
  the retry. Hidden retries are a lie about latency.
- Single-flight: identical in-flight calls (same op, same normalized args) join
  the first call instead of duplicating work. Reported as `coalesced: true`.

### 3.7 Security boundary

Unchanged where it already works: argv-only execution, typed tools, approved
roots with symlink-escape rejection, no payload logging, sanitized errors,
constant-time auth, loopback default, TLS required off-loopback.

Additions required by the echo layer:

- **Egress is default-deny.** `echo_fetch` refuses every host not in an explicit
  allowlist (config file, not a tool argument). No allowlist configured means
  the tool reports `BLOCKED`, not an error the model can retry around.
- **No ambient credentials.** The gateway never attaches environment secrets to
  outbound requests unless a named, configured credential is bound to a named
  allowlist entry.
- **Ledger stores hashes, not values.** Arguments are recorded as
  `sha256(canonical_json(args))`. A prompt containing a secret must not land in
  a log file.
- **Instruction-shaped fields are server-authored constants.** Fetched content
  is never placed in a field whose purpose is to tell the model what to do.
  Tool output is an injection channel; the framing text in 6.4 must be static.
- **Bridge mode is a different product.** With `-bridge`: auth mandatory, tool
  surface reduced to a read-only subset, no arbitrary filesystem paths accepted
  as input, output confined to a per-token sandbox root, egress tools disabled,
  rate limits tightened, and a startup banner on stderr saying what is exposed.

---

## 4. Tool surface

Existing 8 tools unchanged. Additions below. All results carry
`evidence`, `duration_ms`, `queue_ms`, and `token_estimate_method`.

### 4.1 `echo_ping`

Purpose: prove liveness and measure true round-trip. Kills the ambiguity
between "the tool is slow" and "the model is stalling".

```
in:  { nonce?: string, deadline_ms?: int }
out: { ok: true, echo: "<sha256(nonce|epoch)>", server_time_utc: "...",
       duration_ms: 3, seq: 41, evidence: "OBSERVED" }
```

### 4.2 `echo_context_put`

Purpose: put content into the content-addressed store so later calls pass a
`cid` instead of the bytes.

```
in:  { path?: string, text?: string, label?: string, encode?: bool }
out: { ok: true, cid: "<sha256>", bytes: 48234, lines: 1204,
       tokens_raw_est: 12180, artifact?: "<path>.smash.txt",
       evidence: "CREATED" }
```

### 4.3 `echo_context_get`

Purpose: retrieve at the cheapest tier that answers the question.

```
in:  { cid: string, tier: "none"|"facts"|"outline"|"excerpt"|"full",
       max_tokens?: int, range?: {start_line: int, end_line: int} }
out: { ok: true, cid, tier, content?: string, truncated: bool,
       omitted_bytes: int, tokens_returned_est: int,
       already_sent_this_session: bool, evidence: "OBSERVED" }
```

`tier: none` returns metadata only. `already_sent_this_session: true` means the
identical cid already crossed the boundary; the body is withheld by default.

### 4.4 `echo_delta`

Purpose: stop re-sending whole files when a few lines changed.

```
in:  { from_cid: string, to_cid: string, format?: "unified",
       context_lines?: int, max_tokens?: int }
out: { ok: true, changed_lines: 14, hunks: 3, diff?: string,
       artifact?: "<path>", tokens_saved_est: 11440, evidence: "OBSERVED" }
```

### 4.5 `echo_fetch`

Purpose: the gateway. Deterministic, allowlisted, cached, receipted egress.

```
in:  { url: string, method?: "GET"|"POST", headers?: {..}, body_cid?: string,
       deadline_ms?: int, retries?: int, return?: tier, max_tokens?: int,
       cache?: "prefer"|"bypass"|"only" }
out: { ok: bool, status: int, cid: string, bytes: int, sha256: string,
       cached: bool, attempts: int, backoff_ms: int,
       duration_ms: int, engine_ms: int,
       content?: string, truncated: bool,
       evidence: "OBSERVED"|"FAILED"|"BLOCKED",
       reason?: "not_allowlisted"|"deadline_exceeded"|"transport"|"status_4xx" }
```

Body never returned by default. `cache: only` answers from CAS or reports
`BLOCKED`, which is how an agent gets a guaranteed zero-network read.

### 4.6 `echo_budget`

```
in:  { set_session_max_tokens?: int, enforce?: "off"|"warn"|"hard" }
out: { ok: true, session_id, spent_est: 48210, remaining_est: 151790,
       calls: 37, saved_est: 402330, by_mechanism: {tier: .., dedupe: ..,
       delta: .., cap: ..}, token_estimate_method: "heuristic:chars-per-token=3.6",
       evidence: "OBSERVED" }
```

`enforce: hard` makes over-budget calls return `BLOCKED` with the remaining
budget, instead of silently returning a huge payload.

### 4.7 `echo_receipt`

```
in:  { last?: int, session?: string, tool?: string, since_ms?: int }
out: { ok: true, entries: [ { seq, ts_start, ts_end, duration_ms, tool,
        args_sha256, evidence, ok, artifacts: [{name, sha256, bytes}],
        attempts, coalesced } ], truncated: bool, evidence: "OBSERVED" }
```

This is the accountability primitive. It reports what the server actually did.
It says nothing about what the model claimed.

### 4.8 `echo_verify_claim`

```
in:  { claim: string,
       expect: { tools_called?: [string], artifacts?: [string],
                 cids?: [string], since_ms?: int } }
out: { ok: true, overall: "VERIFIED"|"MISMATCH"|"NOT_FOUND"|"UNSUPPORTED",
       checks: [ {expectation, state, detail} ],
       note: "prose claims are not machine-checkable; only the listed
              expectations were checked", evidence: "RUNTIME_VERIFIED" }
```

Hard limit, stated in the tool description itself: this verifies **artifacts,
hashes, and call history**. It cannot verify a sentence. `UNSUPPORTED` is a
first-class outcome and must be returned rather than guessed.

### 4.9 `echo_capabilities`

Extends `smash_capabilities` with: protocol revisions supported, transport,
mode (`local`/`bridge`), tokenizer availability and method, egress allowlist
size (count only, never the entries), ledger path presence, CAS size and GC
policy, per-op deadline ceilings.

---

## 5. Token efficiency strategy

### 5.1 Reference, not content

Default return tier is `facts` for every tool that could return a body. A file
read becomes `{cid, bytes, lines, sha256, outline}`. The body crosses the
boundary only when a caller asks for it with a cap. This is the single largest
saving available and it requires no compression at all.

### 5.2 Content-addressed dedupe

Everything entering the CAS is keyed by sha256. Two consequences:

- Re-reading an unchanged file returns `already_sent_this_session: true` and
  no body. Agent loops re-read the same file repeatedly; this cuts that to one
  transfer.
- Cross-session survival: the cid is stable, so a later session can reference
  content it never received.

### 5.3 Delta transfer and tiers

- `echo_delta` sends hunks instead of files after an edit.
- Tiers: `none` (metadata), `facts` (structured fields only), `outline`
  (headings, symbols, or `smash --ai` native compression, labeled lossy),
  `excerpt` (ranged lines under a cap), `full` (explicit, capped, truncation
  disclosed with `omitted_bytes` and a cid to fetch the rest).
- `smash_batch` already exists and stays the recommended path for multi-op work:
  one round trip, one result envelope, less protocol overhead.

### 5.4 What we will not claim about tokens

Exact token counts require the exact tokenizer of the exact model. Across
Anthropic, OpenAI, Google, and xAI those differ, some are not published, and
vendors change them between model releases. The current MCP server is written
to the Go 1.13 language level with **zero external dependencies** (`OBSERVED`:
`go.mod` declares `go 1.13` with no `require` block). Vendoring four BPE
tokenizers contradicts that posture.

Decision: ship a calibrated heuristic, name it in every result, and never call
it exact. `token_estimate_method` is a required field precisely so nobody can
quote a number without the method attached.

Phase 1 owes a measurement table, produced by actually running vendor
tokenizers offline in a one-off harness, covering: English prose, source code,
JSON, and base64-of-xz. The base64 row is the important one. My expectation is
that base64 artifacts cost more tokens than the source text they encode for
inputs under roughly 4 to 8 KB, and remain unreadable to the model at any size
(`INFERRED`, unmeasured). If the measurement contradicts that, the doc gets
corrected, not the measurement.

---

## 6. Accountability mechanisms

### 6.1 Evidence record per call

Append-only JSONL, one line per call, rotated by size, hashes only:

```json
{"seq":412,"session":"s-9f2a","ts_start":"2026-07-20T18:04:11.312Z",
 "ts_end":"2026-07-20T18:04:11.478Z","duration_ms":166,"queue_ms":2,
 "engine_ms":151,"tool":"smash_verify","args_sha256":"7c1e…",
 "ok":true,"evidence":"RUNTIME_VERIFIED","attempts":1,"coalesced":false,
 "artifacts":[{"name":"config.json.smash.txt","sha256":"9f2a…","bytes":780}]}
```

No arguments, no payloads, no URLs with query strings (host only, path hashed).
The ledger is evidence, not surveillance.

### 6.2 Wall-clock truth

Covered in 3.6. The property that matters for accountability: because
`duration_ms` is measured and returned, any statement about how long something
took is checkable against the receipt. The server cannot make the model tell
the truth. It can make the lie cheap to catch.

### 6.3 Claim states

Results use the server's existing enum plus `INFERRED` and `BLOCKED`.
`ok: true` is emitted only when the operation produced its stated artifact.
`smash_verify` already models this correctly: it decodes and compares hashes
before returning `RUNTIME_VERIFIED`. The echo tools inherit that rule. There is
no code path where a caught error becomes a success.

`BLOCKED` exists so refusal is distinguishable from failure. Not allowlisted,
over budget, no tokenizer, bridge-mode-disabled: those are `BLOCKED` with a
`reason` code. An agent retrying a `BLOCKED` call wastes tokens; the reason code
tells it not to.

### 6.4 Framing, and its honest ceiling

Legitimate levers, all of them influence:

1. Tool descriptions written as contracts: "returns a terminal result within
   `deadline_ms`. There is no pending state. Do not report waiting."
2. Result shapes with no waiting-shaped field to imitate.
3. Measured timings in every result.
4. `evidence` on every result so a hedge has a factual alternative in the same
   payload.
5. The server `instructions` field at initialization, if the host surfaces it
   (`UNVERIFIED` per host).

Ceiling: a host may truncate descriptions, reorder tools, or summarize results
before the model sees them. None of this is enforcement. The correct claim is
"the model has less room to be vague and a receipt exists if it is". Any
stronger claim is marketing.

Security note repeated because it is easy to get wrong: fetched content must
never be placed into instruction-shaped fields. If `echo_fetch` returns a page
that says "ignore previous instructions", that text belongs in `content` under
a cap, never in a `note`, `directive`, or `instructions` field.

---

## 7. Phased delivery

**P0. Truth core.** Smallest useful milestone, roughly one day, no new
dependencies, stdio only. `echo_ping`, monotonic timings on all existing tools,
JSONL ledger, `echo_receipt`. Deliverable: any claim about latency or "I ran
that" becomes checkable. Test: battery asserts one terminal state per call,
no sleeps outside backoff, ledger contains no payload bytes.

**P1. Token layer.** CAS (`echo_context_put/get`), `echo_delta`, `return` tier
plus `max_tokens` on existing tools, `echo_budget`, and the measured tokenizer
table from 5.4 published in the repo. Deliverable: measured savings with a
named method.

**P2. Universal install.** Config emitters per host with dry-run, merge, and
backup; `--print` fallback for unverified hosts; `.mcpb` bundle; registry
publication; protocol revision support for `2025-06-18` and `2025-11-25`.
Deliverable: install verified by hand on each host that is actually available
to test, with the untested ones marked untested in the README.

**P3. Gateway.** `echo_fetch` with allowlist, cache, bounded retry, deadline
propagation, receipts. Deliverable: deterministic egress with disclosed
attempts.

**P4. Bridge mode.** Reduced surface, auth, sandbox root, tunnel documentation,
explicit opt-in for ChatGPT and Grok API reachability. Gated on an owner
decision about the local-only posture.

**P5, optional and uncertain.** Local model proxy for self-hosted inference,
where "owns the network layer" is literally true. Separate component, separate
threat model, only worth building if local models are actually in the workflow.

**Parallel, unscheduled:** track the 2026-07-28 stateless core. Do not adopt
sampling. Plan for `initialize` removal.

---

## 8. Open questions for the owner

1. Which hosts actually matter? Building emitters for eight hosts we cannot
   test is how a "universal installer" becomes a bug factory.
2. Is bridge mode acceptable at all? It contradicts the local-only posture that
   `SECURITY.md` and `THREAT-MODEL.md` are built on. If the answer is no,
   ChatGPT and the Grok API are out of scope and the doc should say so in the
   README rather than implying coverage.
3. Does `smash-mcp` get to make network calls? Today it makes none. `echo_fetch`
   changes the product's character and its threat model. This is a values call.
4. Zero external dependencies and Go 1.13 language level: hard constraint or
   preference? It decides heuristic versus real tokenizers.
5. Ledger retention and privacy: how long, where, and does it survive a
   session? Hashes only is my recommendation; confirm.
6. CAS disk budget and GC policy: size cap, age cap, or both?
7. Do we add `INFERRED` and `BLOCKED` to the server's evidence enum, given
   existing clients may switch on the current set?
8. Should P0 ship inside `smash-mcp` v1.3, or wait for a v2.0 that also lands
   the protocol revision bump? My recommendation is v1.3 for P0, v2.0 at P2.
9. Naming: `echo_*` prefix, or fold into `smash_*` for a single namespace?
10. Is there an appetite for a conformance suite published as evidence, the way
    `PROTOCOL.md` already lists its protocol battery? That is the artifact that
    makes "universal" a checkable claim instead of a slogan.

---

## Appendix A. What was actually checked, and how

Checked 2026-07-20. Method stated per item so a reader can re-run it.

| Claim | State | Method |
|---|---|---|
| `smash` v5.3, `smash-mcp` v1.2, 8 tools, stdio + loopback HTTP, gzip, roots containment | `OBSERVED` | Read `mcp/PROTOCOL.md`, `mcp/smash-mcp/main.go` tool table, `README.md` output format section |
| `go.mod` declares `go 1.13`, no external requires | `OBSERVED` | Read `mcp/smash-mcp/go.mod` |
| Server advertises protocol `2025-06-18` | `OBSERVED` | `main.go` const `protocolVersion` |
| Claude Code supports stdio, `--transport http`, SSE, OAuth, scopes local/user/project | `VERIFIED` | Ran `claude mcp --help` and `claude mcp add --help` locally |
| ChatGPT requires public HTTPS `/mcp`; localhost unsupported; tunnel for local dev | `VERIFIED` | Fetched `developers.openai.com/apps-sdk/deploy/connect-chatgpt` |
| MCP stable revision 2025-11-25, its features and utilities | `VERIFIED` | Fetched `modelcontextprotocol.io/specification/2025-11-25` |
| MCP 2026-07-28 RC: stateless core, Extensions, Tasks, MCP Apps, roots/sampling/logging deprecated, `Mcp-Method`/`Mcp-Name` headers | `VERIFIED` | Fetched `blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/` |
| ChatGPT dev mode transports and plan availability | `INFERRED` | Search summary only |
| xAI Grok 4.3 remote MCP, SSE + streamable HTTP, stdio rejected | `INFERRED` | Search summary of xAI docs, not primary-fetched |
| Grok Build CLI accepts Claude Code MCP configs unchanged | `UNVERIFIED` | Third-party reporting; stdio support implied, not shown |
| Gemini CLI `~/.gemini/settings.json`, `gemini mcp add`, stdio default, trusted-folder gate | `INFERRED` | Search summary of Google docs |
| Cursor / VS Code / Windsurf / Zed config paths and root keys | `INFERRED` | Search summary; three distinct root keys reported |
| Claude Desktop config path | `INFERRED` | Filename appears in this repo's `PROTOCOL.md`; directory path from memory |
| MCPB bundle format (renamed DXT), official registry preview | `INFERRED` | Search summary |
| Gemini consumer app / AI Studio MCP support | `UNVERIFIED` | Not checked, not known |
| Base64-of-xz token cost versus source text | `INFERRED` | Reasoning about BPE behavior on high-entropy strings. Not measured. Phase 1 owes the measurement. |

## Appendix B. Final truth statement

**Real:** an MCP server can compress, deduplicate, cache, tier, meter, time,
bound, receipt, and refuse. All of section 3 through 7 is buildable with the
current stack and no new dependencies except whatever P3 needs for HTTP.

**Likely:** returning verified facts instead of raw dumps improves answer
accuracy and cuts token spend materially. Direction is confident, magnitude is
unmeasured, and no number is claimed here.

**Still nonsense until proven:** "installs everywhere" (three config dialects
and two remote-only hosts say otherwise), "owns the network layer" (false for
every hosted model), "forces accountability" (influence, not enforcement),
"no network drops" (determinism under drops, not absence of drops), and
"compression saves tokens" (only by reference; inline base64 probably costs
more, and the measurement has not been run yet).
