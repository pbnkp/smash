# smash — AI / LLM / Agent Traffic Efficiency Protocol

Status: design (v0.1, 2026-07-22) · Author: pbnkp + boy

The goal: move the **most accurate** input and output over AI/LLM/agent links
with the **fewest tokens, bytes, round-trips, and seconds** — without ever
trading away correctness, and without circumventing any provider's controls.

This document is explicit about **what the layer does, when, and how it decides**
— and, just as explicitly, **what it will not do**.

---

## 0. Honest scope — the one hard line

This layer **reduces** traffic and **respects** provider rate limits. It does
**not** evade them.

- ✅ It sends fewer tokens/bytes, caches, dedupes, and routes to a local model
  so you rarely hit a limit in the first place.
- ✅ When it *does* see a rate-limit signal, it **honors** it (obeys
  `Retry-After`, backs off) and uses the wait to serve from cache or fall back
  to local.
- ❌ It never rotates keys/IPs to defeat per-key limits, never ignores
  `Retry-After`, never hammers past `429`, never spoofs identity. Those are the
  provider's controls; a client cannot legitimately remove them, and this layer
  will not try.

The honest way to "not wait on the provider" is **not to depend on the provider**
— run local (§4) and send less (§3). That is faster, cheaper, private, and does
not violate anyone's terms.

---

## 1. The data stream: where the waste is

AI/agent traffic is unusually wasteful in identifiable, repeatable ways. The
layer inspects the stream (payloads + headers, never content it must not read)
and classifies each of these signals.

| # | Signal (identified in the stream) | Direction | Typical waste |
|---|-----------------------------------|-----------|---------------|
| S1 | **Re-sent unchanged context** each turn (system prompt, files, history) | upload | 40–90% of tokens in agent loops |
| S2 | **Verbatim large paste** (logs, code, JSON, transcripts) | upload | high; often compressible or referenceable |
| S3 | **Formatting/whitespace bloat** that costs tokens without meaning | upload | 3–15% |
| S4 | **Repeated identical request** (same prompt+model+params) | both | 100% (fully cacheable) |
| S5 | **Boilerplate / low-information tokens** (filler prose, restated instructions) | upload | variable |
| S6 | **Uncompressed response in transit** | download | standard gzip recovers 60–80% of bytes |
| S7 | **Rate-limit / quota signal** (`429`, `Retry-After`, quota headers) | download | forces waits + failures |
| S8 | **Task that a local model can do** (compact, classify, summarize, extract) | both | 100% of provider cost/limit |

Detection is **cheap and local**: hashing, diffing against a per-session
baseline, header inspection, and a size/entropy heuristic. No payload content is
logged (§5).

---

## 2. The detect → avoid pipeline

For every outbound request and inbound response:

```
                 ┌─────────────┐
 request/resp →  │  IDENTIFY   │  hash · diff vs baseline · header scan · size/entropy
                 └─────┬───────┘
                       ▼
                 ┌─────────────┐
                 │  CLASSIFY   │  S1..S8 (above), + accuracy-sensitivity of the payload
                 └─────┬───────┘
                       ▼
                 ┌─────────────┐
                 │   AVOID     │  apply the legitimate mitigation for that class (§3/§4)
                 └─────┬───────┘   — lossless unless the payload is explicitly prose-safe
                       ▼
                 ┌─────────────┐
                 │   VERIFY    │  sha256 round-trip on anything compressed (smash --verify)
                 └─────┬───────┘
                       ▼
                 ┌─────────────┐
                 │   MONITOR   │  local-only counters: tokens saved, cache hits, rl events (§5)
                 └─────────────┘
```

The pipeline is **fail-open toward accuracy**: if a mitigation cannot be proven
lossless for a correctness-sensitive payload, it is **not applied** — the raw
bytes go through unchanged. Size is never bought with silent inaccuracy.

---

## 3. Avoidance techniques — upload (input to the model)

| For | Technique | Lossless? | Notes |
|-----|-----------|-----------|-------|
| S1 | **Context delta / dedup** — send only the diff vs a shared per-session baseline; reference unchanged blocks by content hash | **yes** | biggest single win in agent loops; requires a decode/rehydrate step on the consumer side |
| S2 | **smash artifact carriage** — ship a `smash` artifact (xz/zstd + base64, self-describing manifest, sha256) instead of the raw blob when the consumer can decode it | **yes** | round-trip verified; ideal for logs/code/JSON |
| S3 | **Token-aware minification** — collapse redundant whitespace/formatting that does not change semantics for the model | **yes*** | *lossless for the model's interpretation; original recoverable from the artifact |
| S5 | **Semantic compaction (`--ai`)** — dictionary + structure-aware compaction | **lossy** | **prose/docs ONLY**, opt-in, `lossy: yes` stamped in the manifest; **never** for code/data |
| S8 | **Local pre-pass** — do compaction/extraction/classification on a local model, send only the distilled result upstream | depends | keeps the cloud call small and rare |

**Accuracy rule (upload):** the default is lossless. Lossy semantic compaction
is only ever applied to payloads explicitly marked prose-safe, and is always
labeled so the receiver knows fidelity was traded.

---

## 4. Avoidance techniques — download (output from the model) + routing

| For | Technique | Notes |
|-----|-----------|-------|
| S4 | **Response cache** keyed by `sha256(normalized_prompt ‖ model ‖ params)` | returns prior output for identical requests — enormous for repetitive agent runs; local, private, TTL'd |
| S6 | **Transit compression** (gzip content-encoding) | already negotiated by smash-mcp over HTTP; standard, lossless |
| S7 | **Honor + reroute on rate-limit** | on `429`/`Retry-After`: obey the wait, and during it serve from cache (S4) or fall back to local (S8). **Never** evade |
| S8 | **Local-first routing** | route eligible tasks to a local model (Ollama, `B64_AI_URL=…:11434`) → **no provider tokens, no limits, no forced delay, nothing leaves the machine** |

**Local-first is the real answer to "provider-forced timers":** you remove the
*provider*, not their rules. Cloud becomes the deliberate exception, used only
when a task genuinely needs a frontier model.

---

## 5. Monitoring — secure & private by construction

Built-in, **local-only** observability. Nothing is transmitted anywhere.

- **Counters (numbers only):** tokens sent/saved, bytes in/out, cache hit-rate,
  local-vs-cloud split, rate-limit events honored, round-trip verify pass-rate.
- **No payload content is ever logged** — only sizes, sha256 hashes, and class
  counts. API keys stay in the OS keychain, never on disk, never in logs.
- **Artifacts and logs are `0600`**, owner-only.
- The monitor is a read-side aggregator: it cannot alter a request, so it can
  never itself become an exfiltration path.

---

## 6. Accuracy guarantees (maximum-accurate I/O)

1. **Lossless is default.** Anything correctness-sensitive — code, data,
   structured text — is compressed only with lossless codecs (xz/zstd/gz) and
   **round-trip verified** (`smash --verify`: decoded sha256 == manifest sha256)
   before it is trusted.
2. **Lossy is opt-in, labeled, and prose-only.** Semantic compaction (`--ai`)
   never touches code/data and is always stamped `lossy: yes`.
3. **Integrity travels with the bytes.** Every artifact carries source bytes +
   sha256 in its manifest; the receiver can verify independently.
4. **No silent degradation.** If a size win cannot be proven safe, it is not
   taken.

Compression-ratio claims in this project are **measured, not asserted** — real
before/after token and byte counts on real inputs. There is no claim to beat the
information-theoretic (Shannon) limit of lossless compression; wins come from
*modeling your specific data* (logs/code/JSON/markdown), dedup, and delta — which
genuinely beat generic codecs *on those inputs*, not on arbitrary data.

---

## 7. What this is NOT

- Not a rate-limit bypass, key/IP rotator, or throttle evader.
- Not a way to ignore `Retry-After` or hammer `429`s.
- Not a lossless-magic claim (no "2× smaller than everything, always").
- Not a telemetry channel — nothing about your traffic leaves your machine.

Efficiency and respect for provider controls, together. That is the only version
that is honest, that ships, and that keeps you unbanned and private.

---

## 8. Build order (incremental, each independently useful)

1. **Local-first routing** in the `--ai`/`--ai-api` path (Ollama default, cloud opt-in). — *biggest, honest latency/limit win*
2. **Response cache** (S4) keyed by normalized prompt hash.
3. **Context delta/dedup** (S1) for agent loops.
4. **Local monitor** (§5) surfacing measured savings.
5. **Data-tuned lossless codec** benchmarks vs generic xz on your corpora (§6).

Each step is measured against a real baseline before it is called done.
