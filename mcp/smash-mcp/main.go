// smash-mcp — MCP (Model Context Protocol) server exposing smash to AI apps.
// Sole author: pbnkp. MIT.
//
// The communication layer between any MCP-speaking AI application
// (Claude Code, Claude Desktop, agent frameworks) and the smash CLI. The AI
// model never runs a shell: it calls typed tools; this server shells out to
// the canonical `smash` binary with argv (never a shell string) and returns
// artifact paths + metadata, never raw content.
//
// Transports:
//
//	stdio (default)            — newline-delimited JSON-RPC 2.0 (MCP stdio)
//	-http 127.0.0.1:PORT       — loopback JSON-RPC over HTTP POST /mcp.
//	                             Requires a bearer token (constant-time
//	                             compare). Non-loopback bind is refused
//	                             unless -allow-remote AND TLS are supplied.
//
// Go 1.13-compatible: uses io/ioutil, no generics, no post-1.13 stdlib APIs.
// Target parity with bernie's Go 1.13.7.
package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const version = "1.3"
const protocolVersion = "2025-06-18"

// ---- limits (per-operation + transport) ----
const (
	maxHTTPBody     = 64 << 20 // 64 MiB request cap
	maxConcurrent   = 8        // in-flight tool calls
	rateWindow      = 10 * time.Second
	rateMax         = 120 // requests per window (HTTP)
	encodeTimeout   = 120 * time.Second
	aiAPITimeout    = 300 * time.Second
	maxBatchItems   = 256
	maxInlineText   = 8 << 20 // 8 MiB inline text via temp file
	minGzipResponse = 1024    // avoid expanding tiny JSON-RPC responses
)

var (
	smashBin     string
	allowedRoots []string
	startTime    = time.Now()
)

// ================= JSON-RPC =================

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}
type rpcError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}
type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

// ================= MCP shapes =================

type toolDef struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	InputSchema interface{} `json:"inputSchema"`
}
type textContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}
type toolResult struct {
	Content []textContent `json:"content"`
	IsError bool          `json:"isError,omitempty"`
}

func obj(kv ...interface{}) map[string]interface{} {
	m := map[string]interface{}{}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i].(string)] = kv[i+1]
	}
	return m
}
func schema(props map[string]interface{}, required ...string) map[string]interface{} {
	s := map[string]interface{}{"type": "object", "properties": props}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}

var tools = []toolDef{
	{"smash_capabilities", "List smash version, engine binary, compression modes, artifact format, transports, and per-operation limits.", schema(map[string]interface{}{})},
	{"smash_health", "Liveness/readiness: confirm the smash engine binary is present and executes. Returns ok|degraded|down with detail.", schema(map[string]interface{}{})},
	{"smash_encode", "Losslessly compress+encode files/directories (or inline text) into readable .smash.txt artifacts (ASCII manifest + base64 payload). Returns artifact paths, sizes, sha256 of source; never raw content.",
		schema(map[string]interface{}{
			"paths":  obj("type", "array", "items", obj("type", "string"), "description", "files or directories to encode"),
			"text":   obj("type", "string", "description", "inline text to encode instead of paths"),
			"mode":   obj("type", "string", "enum", []string{"xz", "gz", "zstd"}, "description", "lossless mode (default xz)"),
			"outdir": obj("type", "string", "description", "output dir (must be inside an approved root)"),
		})},
	{"smash_ai_compress", "LOSSY semantic compression of text (mode 'native' = offline dictionary, ~25-40%; mode 'api' = LLM via smash's provider env). Returns artifact paths + sizes.",
		schema(map[string]interface{}{
			"paths":  obj("type", "array", "items", obj("type", "string")),
			"text":   obj("type", "string"),
			"mode":   obj("type", "string", "enum", []string{"native", "api"}, "description", "default native"),
			"outdir": obj("type", "string"),
		})},
	{"smash_decode", "Decode smash artifacts back to original files/directories. Returns restored paths (sha256 for files; directories are extracted and reported by kind). Decode is NOT verification — use smash_verify to check integrity.",
		schema(map[string]interface{}{
			"artifacts": obj("type", "array", "items", obj("type", "string")),
			"outdir":    obj("type", "string"),
		}, "artifacts")},
	{"smash_manifest", "Parse a v5 artifact's in-file manifest (source, kind, bytes, sha256, encoding, lossy). Reports base64 validity and payload size. Does not decode unless smash_verify is used.",
		schema(map[string]interface{}{"artifact": obj("type", "string")}, "artifact")},
	{"smash_verify", "Full integrity verification: runs the engine's --verify, which decodes the artifact to its DECOMPRESSED payload (no extraction) and compares that sha256 to the manifest — correct for files AND directories. Returns match=true/false with evidence RUNTIME_VERIFIED | MISMATCH; a lossy (--ai) artifact reports RUNTIME_VERIFIED_LOSSY (decodes cleanly; source sha is pre-compaction, not comparable).",
		schema(map[string]interface{}{"artifact": obj("type", "string")}, "artifact")},
	{"smash_batch", "Run many encode/ai/decode/verify jobs in ONE call (minimizes round-trips). Each item {op, paths?/text?/artifacts?/artifact?, mode?, outdir?}. Sequential; per-item ok/error.",
		schema(map[string]interface{}{
			"items": obj("type", "array", "items", schema(map[string]interface{}{
				"op":        obj("type", "string", "enum", []string{"encode", "ai", "decode", "verify"}),
				"paths":     obj("type", "array", "items", obj("type", "string")),
				"text":      obj("type", "string"),
				"artifacts": obj("type", "array", "items", obj("type", "string")),
				"artifact":  obj("type", "string"),
				"mode":      obj("type", "string"),
				"outdir":    obj("type", "string"),
			}, "op")),
		}, "items")},
}

// ================= path containment =================

// pathAllowed resolves p to an absolute, symlink-evaluated form and checks it
// is inside one of allowedRoots. For a not-yet-existing target (e.g. output
// dir), it resolves the nearest existing ancestor. Blocks traversal + symlink
// escape. If allowedRoots is empty (stdio same-user trust), only reject NUL.
func pathAllowed(p string) (string, error) {
	if strings.IndexByte(p, 0) >= 0 {
		return "", errors.New("invalid path (NUL)")
	}
	ap, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	// resolve symlinks on the longest existing prefix
	resolved := ap
	probe := ap
	for {
		if r, err := filepath.EvalSymlinks(probe); err == nil {
			rest := strings.TrimPrefix(ap, probe)
			resolved = filepath.Join(r, rest)
			break
		}
		parent := filepath.Dir(probe)
		if parent == probe {
			break
		}
		probe = parent
	}
	resolved = filepath.Clean(resolved)
	if len(allowedRoots) == 0 {
		return resolved, nil
	}
	for _, root := range allowedRoots {
		rr, err := filepath.EvalSymlinks(root)
		if err != nil {
			rr = filepath.Clean(root)
		}
		if resolved == rr || strings.HasPrefix(resolved, rr+string(os.PathSeparator)) {
			return resolved, nil
		}
	}
	return "", fmt.Errorf("path outside approved roots: %s", filepath.Base(resolved))
}

// ================= smash exec =================

func runSmash(ctx context.Context, timeout time.Duration, args ...string) (string, string, error) {
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(cctx, smashBin, args...)
	var ob, eb bytes.Buffer
	cmd.Stdout = &ob
	cmd.Stderr = &eb
	err := cmd.Run()
	if cctx.Err() == context.DeadlineExceeded {
		return ob.String(), eb.String(), fmt.Errorf("smash timed out after %s", timeout)
	}
	if cctx.Err() == context.Canceled {
		return ob.String(), eb.String(), errors.New("cancelled")
	}
	return ob.String(), eb.String(), err
}

func parseOutputs(stderr string) []string {
	var out []string
	prefixes := []string{"encoded: ", "decoded: ", "decoded+extracted: ",
		"decoded (ai-compacted, lossy): ", "decoded+extracted (ai-compacted, lossy): "}
	for _, line := range strings.Split(stderr, "\n") {
		line = strings.TrimSpace(line)
		for _, p := range prefixes {
			if strings.HasPrefix(line, p) {
				out = append(out, strings.TrimPrefix(line, p))
			}
		}
	}
	return out
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) == 0 {
		return ""
	}
	return sanitizeErr(lines[len(lines)-1])
}

// sanitizeErr strips control bytes so a hostile filename/provider body in an
// error message cannot inject terminal escapes through the protocol channel.
func sanitizeErr(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= 0x20 && r != 0x7f {
			b.WriteRune(r)
		}
	}
	out := b.String()
	if len(out) > 400 {
		out = out[:400] + "…"
	}
	return out
}

func fileSize(p string) int64 {
	if st, err := os.Stat(p); err == nil {
		return st.Size()
	}
	return -1
}

// sha256File shas a FILE via openssl reading stdin — matches the engine's own
// sha256_file (portable across mac/FreeBSD openssl builds), avoids passing the
// path as an argv operand (a leading-dash path could be read as a flag), and
// drops `-r` (absent on older/FreeBSD openssl). A directory yields an error.
func sha256File(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	cmd := exec.Command("openssl", "dgst", "-sha256")
	cmd.Stdin = f
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return "", errors.New("no digest")
	}
	return fields[len(fields)-1], nil
}

func stageText(text string) (string, error) {
	if len(text) > maxInlineText {
		return "", fmt.Errorf("inline text exceeds %d bytes", maxInlineText)
	}
	f, err := ioutil.TempFile("", "smash-mcp-*.txt")
	if err != nil {
		return "", err
	}
	if _, err := f.WriteString(text); err != nil {
		f.Close()
		os.Remove(f.Name())
		return "", err
	}
	f.Close()
	return f.Name(), nil
}

// ================= tool args =================

type encodeArgs struct {
	Paths  []string `json:"paths"`
	Text   string   `json:"text"`
	Mode   string   `json:"mode"`
	Outdir string   `json:"outdir"`
}
type decodeArgs struct {
	Artifacts []string `json:"artifacts"`
	Outdir    string   `json:"outdir"`
}
type oneArtifactArgs struct {
	Artifact string `json:"artifact"`
}
type batchItem struct {
	Op        string   `json:"op"`
	Paths     []string `json:"paths"`
	Text      string   `json:"text"`
	Artifacts []string `json:"artifacts"`
	Artifact  string   `json:"artifact"`
	Mode      string   `json:"mode"`
	Outdir    string   `json:"outdir"`
}
type batchArgs struct {
	Items []batchItem `json:"items"`
}

func orEmpty(r json.RawMessage) []byte {
	if len(r) == 0 {
		return []byte("{}")
	}
	return r
}

// ================= tool impls =================

func doEncode(ctx context.Context, a encodeArgs, ai string) (interface{}, error) {
	var args []string
	switch a.Mode {
	case "", "xz":
	case "gz":
		args = append(args, "-g")
	case "zstd":
		args = append(args, "-z")
	default:
		if ai == "" {
			return nil, fmt.Errorf("unknown mode: %s", sanitizeErr(a.Mode))
		}
	}
	timeout := encodeTimeout
	lossy := false
	switch ai {
	case "native":
		args = append(args, "--ai")
		lossy = true
	case "api":
		args = append(args, "--ai-api")
		lossy = true
		timeout = aiAPITimeout
	}
	if a.Outdir != "" {
		od, err := pathAllowed(a.Outdir)
		if err != nil {
			return nil, err
		}
		args = append(args, "-o", od+string(os.PathSeparator))
	}

	var cleanup []string
	defer func() {
		for _, f := range cleanup {
			os.Remove(f)
		}
	}()

	if a.Text != "" {
		if len(a.Paths) > 0 {
			return nil, errors.New("pass paths OR text, not both")
		}
		t, err := stageText(a.Text)
		if err != nil {
			return nil, err
		}
		cleanup = append(cleanup, t)
		args = append(args, "--", t)
	} else {
		if len(a.Paths) == 0 {
			return nil, errors.New("need paths or text")
		}
		args = append(args, "--")
		for _, p := range a.Paths {
			ap, err := pathAllowed(p)
			if err != nil {
				return nil, err
			}
			args = append(args, ap)
		}
	}

	_, stderr, err := runSmash(ctx, timeout, args...)
	if err != nil {
		return nil, fmt.Errorf("%v: %s", err, lastLine(stderr))
	}
	arts := parseOutputs(stderr)
	res := []map[string]interface{}{}
	for _, p := range arts {
		sum, _ := sha256File(p)
		res = append(res, map[string]interface{}{"artifact": p, "bytes": fileSize(p), "sha256": sum})
	}
	return map[string]interface{}{"ok": true, "lossy": lossy, "evidence": "CREATED", "artifacts": res}, nil
}

func doDecode(ctx context.Context, a decodeArgs) (interface{}, error) {
	if len(a.Artifacts) == 0 {
		return nil, errors.New("need artifacts")
	}
	args := []string{"-d"}
	if a.Outdir != "" {
		od, err := pathAllowed(a.Outdir)
		if err != nil {
			return nil, err
		}
		args = append(args, "-o", od+string(os.PathSeparator))
	}
	args = append(args, "--")
	for _, p := range a.Artifacts {
		ap, err := pathAllowed(p)
		if err != nil {
			return nil, err
		}
		args = append(args, ap)
	}
	_, stderr, err := runSmash(ctx, encodeTimeout, args...)
	if err != nil {
		return nil, fmt.Errorf("%v: %s", err, lastLine(stderr))
	}
	restored := parseOutputs(stderr)
	res := []map[string]interface{}{}
	for _, p := range restored {
		entry := map[string]interface{}{"path": p}
		// A dir-tar restores to a DIRECTORY: sha of a directory is meaningless
		// (openssl errors), so report kind instead of a bogus empty sha. For a
		// file, sha it and surface any sha failure rather than swallowing it.
		if st, e := os.Stat(p); e == nil && st.IsDir() {
			entry["kind"] = "directory"
		} else {
			entry["kind"] = "file"
			entry["bytes"] = fileSize(p)
			if sum, se := sha256File(p); se == nil {
				entry["sha256"] = sum
			} else {
				entry["sha256"] = ""
				entry["shaError"] = sanitizeErr(se.Error())
			}
		}
		res = append(res, entry)
	}
	// Decode is restoration, not verification. Labeling it RUNTIME_VERIFIED
	// would be a false evidence claim (it compares nothing to the manifest).
	return map[string]interface{}{"ok": true, "evidence": "DECODED", "restored": res}, nil
}

// parseManifest reads the `#` header lines of an artifact and counts the
// payload's non-whitespace bytes. The payload is a SINGLE base64 line that can
// exceed any Scanner token cap (a >256 MiB artifact used to fail here while
// decode still worked), so headers are read line-by-line (all short) and the
// payload is STREAMED with a fixed buffer — bounded memory at any artifact size.
func parseManifest(path string) (map[string]string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer f.Close()
	man := map[string]string{}
	br := bufio.NewReaderSize(f, 256*1024)
	// Header: every line starts with '#'. Peek so the huge payload line is
	// never pulled into a buffer.
	for {
		b, perr := br.Peek(1)
		if perr != nil || b[0] != '#' {
			break
		}
		line, rerr := br.ReadString('\n')
		body := strings.TrimSpace(strings.TrimPrefix(strings.TrimRight(line, "\n"), "#"))
		for _, field := range strings.Split(body, "|") {
			kv := strings.SplitN(field, ":", 2)
			if len(kv) == 2 {
				k := strings.TrimSpace(kv[0])
				v := strings.TrimSpace(kv[1])
				if k != "" && v != "" && k != "safety" && k != "restore" {
					man[k] = v
				}
			}
		}
		if rerr != nil {
			break
		}
	}
	// Payload: stream the rest, counting non-whitespace bytes only.
	var payload int64
	buf := make([]byte, 64*1024)
	for {
		n, rerr := br.Read(buf)
		for _, c := range buf[:n] {
			if c != ' ' && c != '\t' && c != '\r' && c != '\n' {
				payload++
			}
		}
		if rerr != nil {
			break
		}
	}
	return man, payload, nil
}

func doManifest(a oneArtifactArgs) (interface{}, error) {
	ap, err := pathAllowed(a.Artifact)
	if err != nil {
		return nil, err
	}
	man, payloadChars, err := parseManifest(ap)
	if err != nil {
		return nil, err
	}
	// validate base64 by streaming the non-# lines through the decoder
	f, ferr := os.Open(ap)
	if ferr != nil {
		return nil, ferr
	}
	defer f.Close()
	valid := true
	dec := base64.NewDecoder(base64.StdEncoding, filteredReader(f))
	if _, err := io.Copy(ioutil.Discard, dec); err != nil {
		valid = false
	}
	return map[string]interface{}{
		"artifact":     ap,
		"bytes":        fileSize(ap),
		"manifest":     man,
		"hasManifest":  len(man) > 0,
		"base64Valid":  valid,
		"payloadChars": payloadChars,
		"evidence":     "OBSERVED",
	}, nil
}

// parseVerifyLine extracts the engine's `SMASH-VERIFY key=value ...` machine
// line (printed on stdout by `smash --verify`). Values are space-free tokens.
func parseVerifyLine(stdout string) map[string]string {
	for _, line := range strings.Split(stdout, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "SMASH-VERIFY") {
			continue
		}
		kv := map[string]string{}
		for _, tok := range strings.Fields(strings.TrimPrefix(line, "SMASH-VERIFY")) {
			if p := strings.SplitN(tok, "=", 2); len(p) == 2 {
				kv[p[0]] = p[1]
			}
		}
		return kv
	}
	return nil
}

func atoiSafe(s string) int64 {
	if n, err := strconv.ParseInt(s, 10, 64); err == nil {
		return n
	}
	return -1
}

// doVerify checks integrity via the engine's `smash --verify`, which decodes
// the artifact to its DECOMPRESSED payload (the tar for a dir, the file bytes
// for a file) with NO extraction and compares that sha256 to the manifest.
// Correct for BOTH kinds — the old extract-then-sha path shaed a restored
// directory (impossible) and reported every directory artifact as MISMATCH.
func doVerify(ctx context.Context, a oneArtifactArgs) (interface{}, error) {
	ap, err := pathAllowed(a.Artifact)
	if err != nil {
		return nil, err
	}
	stdout, stderr, runErr := runSmash(ctx, encodeTimeout, "--verify", "--", ap)
	kv := parseVerifyLine(stdout)
	if len(kv) == 0 {
		// No machine line: the engine errored before emitting a verdict (usage,
		// exec, timeout). Surface it as FAILED rather than fabricating a result.
		detail := lastLine(stderr)
		if detail == "" && runErr != nil {
			detail = sanitizeErr(runErr.Error())
		}
		return map[string]interface{}{"artifact": ap, "verified": false, "evidence": "FAILED", "error": detail}, nil
	}
	matchStr := kv["match"]
	lossy := kv["lossy"] == "yes"
	verified := matchStr == "true"
	out := map[string]interface{}{
		"artifact":       ap,
		"kind":           kv["kind"],
		"lossy":          lossy,
		"verified":       verified,
		"match":          verified,
		"restoredSha256": kv["decoded_sha256"],
		"restoredBytes":  atoiSafe(kv["bytes"]),
	}
	if ms := kv["manifest_sha256"]; ms != "" && ms != "none" {
		out["sourceSha256"] = ms
	}
	switch {
	case matchStr == "true" && lossy:
		out["evidence"] = "RUNTIME_VERIFIED_LOSSY"
		out["note"] = "lossy artifact: decodes cleanly; source sha is pre-compaction and not comparable"
	case matchStr == "true":
		out["evidence"] = "RUNTIME_VERIFIED"
	case matchStr == "unknown":
		out["evidence"] = "INDETERMINATE"
		out["note"] = "artifact carries no manifest sha256 (pre-v5); it decodes cleanly but integrity is not comparable"
	default:
		out["evidence"] = "MISMATCH"
		if r := kv["reason"]; r != "" {
			out["error"] = r
		}
	}
	return out, nil
}

func doCapabilities() (interface{}, error) {
	modes := []string{"xz", "gz"}
	if _, err := exec.LookPath("zstd"); err == nil {
		modes = append(modes, "zstd")
	}
	modes = append(modes, "ai")
	if os.Getenv("B64_AI_URL") != "" || os.Getenv("ANTHROPIC_API_KEY") != "" || os.Getenv("OPENAI_API_KEY") != "" {
		modes = append(modes, "ai-api")
	}
	sv, _, _ := runSmash(context.Background(), 10*time.Second, "-V")
	return map[string]interface{}{
		"mcp":            "smash-mcp v" + version,
		"proto":          protocolVersion,
		"engine":         strings.TrimSpace(sv),
		"binary":         smashBin,
		"losslessModes":  modes,
		"artifactFormat": "<source>.smash.txt (ASCII self-describing manifest + base64 payload)",
		"transports":     []string{"stdio", "http-loopback", "http-gzip"},
		"transportCompression": map[string]interface{}{
			"http":                 "gzip request/response negotiation",
			"stdio":                "identity (MCP-compatible)",
			"minimumResponseBytes": minGzipResponse,
		},
		"limits": map[string]interface{}{
			"maxBatchItems": maxBatchItems, "maxInlineTextBytes": maxInlineText,
			"encodeTimeoutSec": int(encodeTimeout / time.Second), "aiApiTimeoutSec": int(aiAPITimeout / time.Second),
			"maxHTTPBodyBytes": maxHTTPBody, "maxConcurrent": maxConcurrent,
			"rateMaxPerWindow": rateMax, "rateWindowSec": int(rateWindow / time.Second),
		},
		"approvedRoots": allowedRoots,
	}, nil
}

func doHealth() (interface{}, error) {
	if _, err := os.Stat(smashBin); err != nil {
		return map[string]interface{}{"status": "down", "detail": "smash binary missing", "evidence": "FAILED"}, nil
	}
	sv, _, err := runSmash(context.Background(), 10*time.Second, "-V")
	if err != nil {
		return map[string]interface{}{"status": "degraded", "detail": lastLine(err.Error()), "evidence": "FAILED"}, nil
	}
	return map[string]interface{}{
		"status": "ok", "engine": strings.TrimSpace(sv), "binary": smashBin,
		"uptimeSec": int(time.Since(startTime) / time.Second), "evidence": "RUNTIME_VERIFIED",
	}, nil
}

// filteredReader strips `#` comment lines and whitespace, yielding bare base64.
type fr struct {
	sc   *bufio.Scanner
	buf  []byte
	done bool
}

func filteredReader(f io.Reader) io.Reader {
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 256*1024*1024)
	return &fr{sc: sc}
}
func (r *fr) Read(p []byte) (int, error) {
	for len(r.buf) == 0 {
		if r.done {
			return 0, io.EOF
		}
		if !r.sc.Scan() {
			r.done = true
			return 0, io.EOF
		}
		line := r.sc.Text()
		if strings.HasPrefix(line, "#") {
			continue
		}
		r.buf = []byte(strings.Map(func(rn rune) rune {
			if rn == ' ' || rn == '\t' || rn == '\r' || rn == '\n' {
				return -1
			}
			return rn
		}, line))
	}
	n := copy(p, r.buf)
	r.buf = r.buf[n:]
	return n, nil
}

func callTool(ctx context.Context, name string, argsRaw json.RawMessage) (interface{}, error) {
	switch name {
	case "smash_capabilities":
		return doCapabilities()
	case "smash_health":
		return doHealth()
	case "smash_encode":
		var a encodeArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		return doEncode(ctx, a, "")
	case "smash_ai_compress":
		var a encodeArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		mode := a.Mode
		a.Mode = ""
		switch mode {
		case "", "native":
			return doEncode(ctx, a, "native")
		case "api":
			return doEncode(ctx, a, "api")
		default:
			return nil, fmt.Errorf("unknown ai mode: %s (use 'native' or 'api')", sanitizeErr(mode))
		}
	case "smash_decode":
		var a decodeArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		return doDecode(ctx, a)
	case "smash_manifest":
		var a oneArtifactArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		return doManifest(a)
	case "smash_verify":
		var a oneArtifactArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		return doVerify(ctx, a)
	case "smash_batch":
		var a batchArgs
		if err := json.Unmarshal(orEmpty(argsRaw), &a); err != nil {
			return nil, errors.New("invalid arguments")
		}
		if len(a.Items) == 0 || len(a.Items) > maxBatchItems {
			return nil, fmt.Errorf("items: need 1-%d", maxBatchItems)
		}
		results := []interface{}{}
		for i, it := range a.Items {
			if ctx.Err() != nil { // batch cancellation
				results = append(results, map[string]interface{}{"index": i, "op": it.Op, "ok": false, "error": "cancelled"})
				continue
			}
			var r interface{}
			var err error
			switch it.Op {
			case "encode":
				r, err = doEncode(ctx, encodeArgs{Paths: it.Paths, Text: it.Text, Mode: it.Mode, Outdir: it.Outdir}, "")
			case "ai":
				switch it.Mode {
				case "", "native":
					r, err = doEncode(ctx, encodeArgs{Paths: it.Paths, Text: it.Text, Outdir: it.Outdir}, "native")
				case "api":
					r, err = doEncode(ctx, encodeArgs{Paths: it.Paths, Text: it.Text, Outdir: it.Outdir}, "api")
				default:
					err = fmt.Errorf("unknown ai mode: %s (use 'native' or 'api')", sanitizeErr(it.Mode))
				}
			case "decode":
				r, err = doDecode(ctx, decodeArgs{Artifacts: it.Artifacts, Outdir: it.Outdir})
			case "verify":
				r, err = doVerify(ctx, oneArtifactArgs{Artifact: it.Artifact})
			default:
				err = fmt.Errorf("unknown op: %s", sanitizeErr(it.Op))
			}
			entry := map[string]interface{}{"index": i, "op": it.Op}
			if err != nil {
				entry["ok"] = false
				entry["error"] = sanitizeErr(err.Error())
			} else {
				entry["ok"] = true
				entry["result"] = r
			}
			results = append(results, entry)
		}
		return map[string]interface{}{"results": results, "count": len(results)}, nil
	}
	return nil, fmt.Errorf("unknown tool: %s", sanitizeErr(name))
}

// ================= dispatch =================

func handle(ctx context.Context, req *rpcRequest) *rpcResponse {
	resp := &rpcResponse{JSONRPC: "2.0", ID: req.ID}
	switch req.Method {
	case "initialize":
		resp.Result = map[string]interface{}{
			"protocolVersion": protocolVersion,
			"capabilities":    map[string]interface{}{"tools": map[string]interface{}{}},
			"serverInfo":      map[string]interface{}{"name": "smash-mcp", "version": version},
			"instructions":    "smash compresses/encodes any content into terminal-safe, LLM-readable .txt artifacts and restores them. Results are paths + metadata, never content dumps. Lossless: smash_encode/decode/verify. Lossy: smash_ai_compress. Use smash_batch for many jobs in one call.",
		}
	case "notifications/initialized", "initialized", "notifications/cancelled":
		return nil
	case "ping":
		resp.Result = map[string]interface{}{}
	case "tools/list":
		resp.Result = map[string]interface{}{"tools": tools}
	case "tools/call":
		var p struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err := json.Unmarshal(orEmpty(req.Params), &p); err != nil {
			resp.Error = &rpcError{Code: -32602, Message: "invalid params"}
			break
		}
		out, err := callTool(ctx, p.Name, p.Arguments)
		if err != nil {
			resp.Result = toolResult{Content: []textContent{{Type: "text", Text: "error: " + sanitizeErr(err.Error())}}, IsError: true}
			break
		}
		blob, _ := json.Marshal(out)
		resp.Result = toolResult{Content: []textContent{{Type: "text", Text: string(blob)}}}
	default:
		if req.ID == nil {
			return nil
		}
		resp.Error = &rpcError{Code: -32601, Message: "method not found"}
	}
	return resp
}

// ================= stdio transport =================

func serveStdio() {
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1024*1024), maxHTTPBody)
	enc := json.NewEncoder(os.Stdout)
	var mu sync.Mutex
	for sc.Scan() {
		line := bytes.TrimSpace(sc.Bytes())
		if len(line) == 0 {
			continue
		}
		var req rpcRequest
		if err := json.Unmarshal(line, &req); err != nil {
			mu.Lock()
			enc.Encode(rpcResponse{JSONRPC: "2.0", Error: &rpcError{Code: -32700, Message: "parse error"}})
			mu.Unlock()
			continue
		}
		if resp := handle(context.Background(), &req); resp != nil {
			mu.Lock()
			enc.Encode(resp)
			mu.Unlock()
		}
	}
}

// ================= HTTP transport =================

type rateLimiter struct {
	mu     sync.Mutex
	count  int
	window time.Time
}

func acceptsGzip(r *http.Request) bool {
	for _, part := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
		name := strings.TrimSpace(strings.SplitN(part, ";", 2)[0])
		if strings.EqualFold(name, "gzip") {
			return true
		}
	}
	return false
}

// readRPCBody accepts identity or gzip HTTP bodies and applies the size cap to
// the decompressed JSON, preventing a small compressed request from expanding
// past the MCP request limit.
func readRPCBody(r *http.Request) ([]byte, int, error) {
	var reader io.Reader = r.Body
	encoding := strings.TrimSpace(strings.ToLower(r.Header.Get("Content-Encoding")))
	switch encoding {
	case "", "identity":
	case "gzip":
		zr, err := gzip.NewReader(r.Body)
		if err != nil {
			return nil, http.StatusBadRequest, errors.New("invalid gzip request")
		}
		defer zr.Close()
		reader = zr
	default:
		return nil, http.StatusUnsupportedMediaType, errors.New("unsupported content encoding")
	}
	body, err := ioutil.ReadAll(io.LimitReader(reader, maxHTTPBody+1))
	if err != nil {
		return nil, http.StatusBadRequest, errors.New("read error")
	}
	if len(body) > maxHTTPBody {
		return nil, http.StatusRequestEntityTooLarge, errors.New("request too large")
	}
	return body, 0, nil
}

// writeRPC negotiates standard HTTP gzip without changing MCP JSON-RPC
// semantics. stdio remains uncompressed because arbitrary framing there would
// be incompatible with normal MCP clients.
func writeRPC(w http.ResponseWriter, status int, value interface{}, useGzip bool) {
	body, err := json.Marshal(value)
	if err != nil {
		status = http.StatusInternalServerError
		body = []byte(`{"jsonrpc":"2.0","error":{"code":-32603,"message":"encode error"}}`)
	}
	body = append(body, '\n')
	w.Header().Set("Content-Type", "application/json")
	w.Header().Add("Vary", "Accept-Encoding")
	if useGzip && len(body) >= minGzipResponse {
		w.Header().Set("Content-Encoding", "gzip")
		w.WriteHeader(status)
		zw := gzip.NewWriter(w)
		_, _ = zw.Write(body)
		_ = zw.Close()
		return
	}
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func (r *rateLimiter) allow() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	if now.Sub(r.window) > rateWindow {
		r.window = now
		r.count = 0
	}
	r.count++
	return r.count <= rateMax
}

func serveHTTP(addr, token string, allowRemote bool, certFile, keyFile string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("bad -http address: %v", err)
	}
	ip := net.ParseIP(host)
	loopback := ip != nil && ip.IsLoopback()
	if !loopback && !allowRemote {
		return errors.New("-http refuses non-loopback bind (pass -allow-remote AND -tls-cert/-tls-key to expose beyond loopback)")
	}
	if !loopback && (certFile == "" || keyFile == "") {
		return errors.New("non-loopback bind requires TLS (-tls-cert/-tls-key)")
	}
	if token == "" {
		b := make([]byte, 24)
		if _, err := rand.Read(b); err != nil {
			return err
		}
		token = hex.EncodeToString(b)
		fmt.Fprintf(os.Stderr, "smash-mcp: generated bearer token (set Authorization: Bearer <token>):\n%s\n", token)
	}
	tokenBytes := []byte(token)
	rl := &rateLimiter{window: time.Now()}
	sem := make(chan struct{}, maxConcurrent)

	authOK := func(r *http.Request) bool {
		h := r.Header.Get("Authorization")
		const p = "Bearer "
		if !strings.HasPrefix(h, p) {
			return false
		}
		got := []byte(strings.TrimPrefix(h, p))
		// constant-time; length-independent by comparing fixed-size digests
		return subtle.ConstantTimeCompare(sha(got), sha(tokenBytes)) == 1
	}

	writeErr := func(w http.ResponseWriter, r *http.Request, code int, rpcCode int, msg string) {
		writeRPC(w, code, rpcResponse{JSONRPC: "2.0", Error: &rpcError{Code: rpcCode, Message: msg}}, acceptsGzip(r))
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "smash-mcp v%s ok\n", version)
	})
	mux.HandleFunc("/mcp", func(w http.ResponseWriter, r *http.Request) {
		// CORS disabled by default: no Access-Control-Allow-* headers emitted.
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.Method != http.MethodPost {
			writeErr(w, r, http.StatusMethodNotAllowed, -32600, "POST only")
			return
		}
		if !authOK(r) {
			writeErr(w, r, http.StatusUnauthorized, -32001, "unauthorized")
			return
		}
		if !rl.allow() {
			writeErr(w, r, http.StatusTooManyRequests, -32002, "rate limit exceeded")
			return
		}
		if r.ContentLength > maxHTTPBody {
			writeErr(w, r, http.StatusRequestEntityTooLarge, -32003, "request too large")
			return
		}
		body, bodyStatus, err := readRPCBody(r)
		if err != nil {
			writeErr(w, r, bodyStatus, -32700, err.Error())
			return
		}
		var req rpcRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeErr(w, r, http.StatusOK, -32700, "parse error")
			return
		}
		select {
		case sem <- struct{}{}:
			defer func() { <-sem }()
		case <-time.After(30 * time.Second):
			writeErr(w, r, http.StatusServiceUnavailable, -32004, "server busy")
			return
		}
		resp := handle(r.Context(), &req)
		if resp == nil {
			w.WriteHeader(http.StatusAccepted)
			return
		}
		writeRPC(w, http.StatusOK, resp, acceptsGzip(r))
	})

	srv := &http.Server{
		Addr: addr, Handler: mux,
		ReadTimeout: 30 * time.Second, WriteTimeout: 600 * time.Second, IdleTimeout: 120 * time.Second,
		ReadHeaderTimeout: 10 * time.Second,
	}
	if !loopback {
		fmt.Fprintf(os.Stderr, "smash-mcp v%s https on %s (TLS, remote)\n", version, addr)
		return srv.ListenAndServeTLS(certFile, keyFile)
	}
	fmt.Fprintf(os.Stderr, "smash-mcp v%s http on %s (loopback, bearer-auth)\n", version, addr)
	return srv.ListenAndServe()
}

// sha returns a fixed 32-byte digest so the bearer-token ConstantTimeCompare
// is length-independent (comparing digests, not raw tokens).
func sha(b []byte) []byte {
	h := sha256.Sum256(b)
	return h[:]
}

func main() {
	httpAddr := flag.String("http", "", "serve HTTP JSON-RPC on host:port (loopback only unless -allow-remote)")
	token := flag.String("token", os.Getenv("SMASH_MCP_TOKEN"), "bearer token for HTTP (auto-generated if empty)")
	allowRemote := flag.Bool("allow-remote", false, "permit non-loopback bind (requires TLS)")
	certFile := flag.String("tls-cert", "", "TLS cert for non-loopback bind")
	keyFile := flag.String("tls-key", "", "TLS key for non-loopback bind")
	bin := flag.String("smash", "", "path to smash binary (default: PATH lookup then ~/bin/smash)")
	rootsFlag := flag.String("roots", os.Getenv("SMASH_MCP_ROOTS"), "colon-separated approved path roots (default: $HOME + tempdir)")
	showVer := flag.Bool("V", false, "print version and exit")
	flag.Parse()

	if *showVer {
		fmt.Printf("smash-mcp v%s (proto %s)\n", version, protocolVersion)
		return
	}

	smashBin = *bin
	if smashBin == "" {
		if p, err := exec.LookPath("smash"); err == nil {
			smashBin = p
		} else if home, err := os.UserHomeDir(); err == nil {
			smashBin = filepath.Join(home, "bin", "smash")
		}
	}
	if smashBin == "" {
		fmt.Fprintln(os.Stderr, "smash-mcp: cannot locate smash binary (use -smash)")
		os.Exit(2)
	}
	if _, err := os.Stat(smashBin); err != nil {
		fmt.Fprintf(os.Stderr, "smash-mcp: smash binary not found at %s\n", smashBin)
		os.Exit(2)
	}

	// approved roots (containment for HTTP; stdio same-user is trusted but still
	// benefits from the same checks when roots are set).
	if *rootsFlag != "" {
		for _, r := range strings.Split(*rootsFlag, ":") {
			if r != "" {
				if abs, err := filepath.Abs(r); err == nil {
					allowedRoots = append(allowedRoots, filepath.Clean(abs))
				}
			}
		}
	} else {
		// Default containment for BOTH stdio and HTTP: home + tempdir. The AI
		// model chooses the paths it passes, so confine reads/writes to the
		// user's own trees — an unconfined stdio server could be steered into
		// e.g. ~/.ssh. Override with -roots / SMASH_MCP_ROOTS.
		if home, err := os.UserHomeDir(); err == nil {
			allowedRoots = append(allowedRoots, filepath.Clean(home))
		}
		allowedRoots = append(allowedRoots, filepath.Clean(os.TempDir()))
	}

	if *httpAddr != "" {
		if err := serveHTTP(*httpAddr, *token, *allowRemote, *certFile, *keyFile); err != nil {
			fmt.Fprintf(os.Stderr, "smash-mcp: %v\n", err)
			os.Exit(1)
		}
		return
	}
	serveStdio()
}
