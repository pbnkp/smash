#!/usr/bin/env python3
"""Exact token counter for smash. Reads stdin (or a path argv[1]), prints one integer.

Contract: print ONLY the integer on stdout. Exit 2 when the tokenizer is
unavailable, so the caller falls back to its LABELLED estimate rather than
trusting a wrong number.

Encoding is o200k_base. It is not any single vendor's production tokenizer; it is
a stable, well-correlated proxy, and every smash report that uses it prints
`exact(o200k)` so the number's provenance travels with it.
"""
import sys

def read_input():
    if len(sys.argv) > 1 and not sys.argv[1].startswith('-'):
        with open(sys.argv[1], 'rb') as fh:
            return fh.read()
    return sys.stdin.buffer.read()

def main():
    try:
        import tiktoken
    except Exception:
        sys.stderr.write('smash-tokcount: tiktoken unavailable\n')
        return 2
    text = read_input().decode('utf-8', errors='replace')
    enc = tiktoken.get_encoding('o200k_base')
    sys.stdout.write(str(len(enc.encode(text, disallowed_special=()))))
    return 0

if __name__ == '__main__':
    sys.exit(main())
