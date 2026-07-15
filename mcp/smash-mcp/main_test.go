package main

import (
	"bytes"
	"compress/gzip"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestReadRPCBodyGzip(t *testing.T) {
	var compressed bytes.Buffer
	zw := gzip.NewWriter(&compressed)
	_, _ = zw.Write([]byte(`{"jsonrpc":"2.0","id":1,"method":"ping"}`))
	_ = zw.Close()
	req := httptest.NewRequest(http.MethodPost, "/mcp", bytes.NewReader(compressed.Bytes()))
	req.Header.Set("Content-Encoding", "gzip")
	body, status, err := readRPCBody(req)
	if err != nil || status != 0 || !strings.Contains(string(body), `"method":"ping"`) {
		t.Fatalf("gzip request failed: status=%d err=%v body=%q", status, err, body)
	}
}

func TestWriteRPCGzip(t *testing.T) {
	rr := httptest.NewRecorder()
	writeRPC(rr, http.StatusOK, map[string]string{"payload": strings.Repeat("compress-me-", 300)}, true)
	if rr.Header().Get("Content-Encoding") != "gzip" {
		t.Fatal("large response was not gzip encoded")
	}
	zr, err := gzip.NewReader(rr.Body)
	if err != nil {
		t.Fatal(err)
	}
	decoded, _ := ioutil.ReadAll(zr)
	if !bytes.Contains(decoded, []byte("compress-me")) {
		t.Fatal("decoded response missing payload")
	}
}

func TestTinyRPCStaysIdentity(t *testing.T) {
	rr := httptest.NewRecorder()
	writeRPC(rr, http.StatusOK, map[string]bool{"ok": true}, true)
	if rr.Header().Get("Content-Encoding") != "" {
		t.Fatal("tiny response should not be compressed")
	}
}
