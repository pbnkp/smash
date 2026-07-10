#!/usr/bin/env python3
# Conservative, parser-free JS compaction for the smash SPA.
# SAFE-BY-CONSTRUCTION: operates line-by-line and only removes tokens that
# cannot appear inside code lines of this source:
#   - whole-line comments (a line whose FIRST non-space chars are // or /* or *)
#   - block-comment continuation lines while inside a leading /* ... */ block
#   - leading indentation and trailing whitespace
#   - blank lines
# It never touches intra-line content, so string/regex literals (which may
# contain //, /*, etc.) are preserved byte-for-byte.
# NOTE: minification is a SIZE optimization, NOT a security boundary. The
# integrity boundary is SRI + the service-worker hash check.
import sys, re

src = open(sys.argv[1], encoding="utf-8").read()
out = []
in_block = False
for line in src.split("\n"):
    s = line.strip()
    if in_block:
        if "*/" in s:
            in_block = False
        continue
    if s == "":
        continue
    if s.startswith("//"):
        continue
    if s.startswith("/*"):
        if "*/" not in s:      # opens a multi-line block
            in_block = True
        continue
    if s.startswith("*"):      # block-comment body/closer that leaked through
        continue
    out.append(s)

text = "\n".join(out) + "\n"
sys.stdout.write(text)
sys.stderr.write("minify: %d -> %d bytes\n" % (len(src), len(text)))
