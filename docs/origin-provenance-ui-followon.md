# Origin provenance: the UI layers still need to pass `--origin`

Status: CLI side shipped (commit `efcc777`). UI side OPEN.

## The gap that started this

A real artifact header, produced by dropping selected text onto the menu-bar app:

```
# ==== SMASH ARTIFACT v5.3 ====
# tool: smash v5.3 (sole author: pbnkp)
# created: 2026-07-20T14:57:14Z | host: <redacted>
# source: Selected Text.txt | kind: stdin | bytes: 118044 | sha256: cf62702f...
# encoding: base64( xz( source ) ) | lossy: no
```

Everything about *what* was encoded is here. Nothing about *where it came
from*. `Selected Text.txt` is a placeholder name the UI invented — it is not
a real file, and there is no record of which application the text was
selected in, which document or page it belonged to, or how it reached the
encoder. 118KB of text, unattributable the moment you close the tab.

For a file operand the path carries most of the provenance. For `kind: stdin`
and `-s` string input there was nothing at all.

## What shipped

`origin_line()` in `smash`, emitted by both manifest writers:

- `--origin "<text>"` — caller-supplied provenance, recorded verbatim
  (sanitized through `sn()` like every other manifest value).
- `--origin-auto` — additionally records `cwd` and the invoking process.
  Opt-in by design: artifacts are made to be pasted into chats, tickets and
  repos, so local paths must never be embedded unless the author asks.
- The line is emitted **always**. With nothing supplied it reads
  `unrecorded (pass --origin "<where this came from>")`, so a missing origin
  is a statement rather than a silence.
- `smash -d` reports the origin back, and says so explicitly when reading an
  artifact that predates the field.

Backward compatible both directions: it is one more `#` line, and both decode
paths strip manifest lines by content rather than position.

## What is still open — the actual fix for the screenshot above

**The CLI cannot infer semantic origin.** It is structurally impossible: by
the time bytes arrive on stdin, the fact that they were selected in Safari on
a particular page is gone. Only the UI layer knows it, and only at the moment
of capture.

So the remaining work is in the UI, and it is where the user-visible gap
actually closes:

| Surface | File | What it must pass |
|---|---|---|
| Share extension | `ui/macos/SmashShareViewController.swift` | Host app name + document title/URL from the extension context |
| Menu-bar app | `ui/macos/smash-menubar.swift` | For text drops: source app if resolvable, else `"text dropped on menu bar"`. For file drops the path already carries it |
| Quick Action | `ui/macos/install-quickactions.sh` | Invoking app + selection context from the Automator/Services environment |
| MCP server | `mcp/smash-mcp/main.go` | The calling model/tool identity, e.g. `"MCP smash_encode, inline text"` |

Suggested shape, so origins stay greppable and machine-readable later:

```
--origin "Safari | https://example.com/page | selection"
--origin "menu-bar text drop"
--origin "MCP smash_encode (inline text)"
```

### Privacy constraint, non-negotiable

A URL or document title is often more sensitive than the payload. The UI must
follow the same rule the CLI does: **record what the user would expect to see,
never silently harvest.** If a surface is going to attach a full URL, that
should be visible and defeatable in the UI, not a hidden default. Recording
`"Safari | selection"` without the URL is the safer default; the full URL
should be opt-in.

## Acceptance

Dropping selected text on the menu-bar icon produces an artifact whose
manifest names the source application, with no `unrecorded` line, and without
embedding anything the user did not expect to be embedded.
