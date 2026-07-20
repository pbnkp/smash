# Verification evidence — origin provenance (commit `efcc777`)

Archived beside the change rather than left in a temp dir, so the claims below
can be re-audited by someone who was not in the room.

Date: 2026-07-20 · Machine: macOS (darwin) · bash 3.2 target retained.

## Claim states

| Claim | State |
|---|---|
| Feature emits origin on both manifest paths | VERIFIED (exercised this session) |
| Decode round-trip is byte-exact after the change | VERIFIED (sha256 compared) |
| Backward compatible with pre-origin artifacts | VERIFIED (decoded a real one) |
| Installed to `~/bin/smash` | VERIFIED (binary diffed against repo) |
| Sink-stream path emits origin at runtime | INFERRED — shares `origin_line()` with the verified path, but `--sink` needs an rclone remote and was NOT exercised |
| UI layers pass `--origin` | NOT DONE — open, see `origin-provenance-ui-followon.md` |

## 1. Syntax

```
$ bash -n ./smash
[1] SYNTAX OK
```

## 2. File operand with `--origin`

```
$ ./smash -q --origin "unit test: sample from scratchpad" -o "$T" "$T/sample.txt"
$ grep -m1 '^# origin:' "$T/sample.txt.smash.txt"
# origin: unit test: sample from scratchpad
```

## 3. The reported gap — stdin with no `--origin`

This is the case from the bug report: `kind: stdin`, no provenance anywhere.

```
$ printf 'selected text bytes\n' | ./smash -q -o "$T/stdin1" -
$ grep -m1 '^# origin:' "$T/stdin1.smash.txt"
# origin: unrecorded (pass --origin "<where this came from>")
```

Absence is now a statement, not a silence.

## 4. `--origin-auto`

```
$ ./smash -q --origin "from Safari" --origin-auto -o "$T/auto" "$T/sample.txt"
# origin: from Safari | cwd: <repo path> | via: zsh
```

## 5. Round-trip — the change must not break decode

```
$ ./smash -q -d -o "$T/restored" "$T/sample.txt.smash.txt"
  SHA MATCH: 05d00c18f2814401a4acc9111a7be89072c805127b6c95e7671472c1b9615232
```

Source sha256 and restored sha256 identical.

## 6. Backward compatibility — a real pre-origin artifact

Decoded a 99KB artifact produced before this feature existed:

```
$ ./smash -d -o "$T/oldtest" ~/smashes/claude-md-omnibus-2026-07-20.txt.smash.txt
smash: origin: not recorded (artifact predates origin tracking)
decoded: .../oldtest
```

Old artifact decodes cleanly under the new binary, and the missing field is
reported rather than passed over silently.

## 7. Install to live tooling

First attempt FAILED and is recorded here rather than quietly retried:

```
$ cp ./smash ~/bin/smash
cp: /Users/piggy/bin/smash: Permission denied
```

Cause: mode `0555`, no owner write bit (`stat -f '%Sp %Sf'` → `-r-xr-xr-x -`,
no special flags). Resolved by restoring the exact mode after the copy:

```
$ chmod u+w ~/bin/smash && cp ./smash ~/bin/smash && chmod 555 ~/bin/smash
-r-xr-xr-x@ 1 ... 73631 Jul 20 08:23 /Users/piggy/bin/smash
```

Post-install, exercised against the LIVE binary (not the repo copy):

```
# origin: live check: piped from zsh by Sir
# origin: unrecorded (pass --origin "<where this came from>")
round-trip SHA MATCH 724f53b6eb834abce27c7c23206986135ff6482869a6e327ccdab8a5e6067ef9
IDENTICAL to committed efcc777
```

## Rollback

```
cp ~/bin/smash.bak.20260720 ~/bin/smash
```

Pre-change binary: `~/bin/smash.bak.20260720`, 70412 bytes, byte-identical to
commit `4ded86c`. Post-change: 73631 bytes, byte-identical to `efcc777`.

## Not proven

- The `--sink` streaming manifest path was not exercised (needs a configured
  rclone remote). It calls the same `origin_line()` as the verified path, which
  is why one shared function was used instead of two emitters — but shared code
  is an argument, not a test.
- No persisted regression test yet. Per the fail-closed-self-infrastructure
  rule, an unreproducible "tested" claim is a weaker claim: these are one-shot
  manual runs, recorded above so they can at least be replayed by hand.
