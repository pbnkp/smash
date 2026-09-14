# smash — Rollback

Every deploy in this project is reversible. Timestamped backups are made before
any overwrite.

## CLI
smash writes a timestamped backup beside the binary before it overwrites itself,
so every upgrade is reversible on any host:
```
ls ~/bin/smash.v-prev.*.bak            # or wherever `command -v smash` points
cp ~/bin/smash.v-prev.<timestamp>.bak ~/bin/smash
smash -V
```
On a system-wide install the same pattern applies next to the installed binary
(for example `/usr/local/bin/smash.v-prev.<timestamp>.bak`). Use
`command -v smash` to find which copy is actually on your PATH before restoring —
a second copy earlier in PATH will shadow the one you just rolled back.

## Homebrew
```
brew uninstall smash
# reinstall a prior formula by checking out an older tap commit, or:
brew install pbnkp/smash/smash    # reinstalls the current pinned version
```
The tap's git history retains prior formula versions (sha256 + version pairs).

## MCP server
```
# backups live in the session _backups/ and beside the binary
cp ~/bin/smash-mcp.v1.0.*.bak ~/bin/smash-mcp    # if present
# or rebuild a prior main.go from mcp/smash-mcp git history
claude mcp remove smash -s user                  # unregister entirely
```

## macOS app
```
# the build writes to ~/Applications/Smash.app; to remove:
osascript -e 'quit app "Smash"' 2>/dev/null; pkill -f Smash.app/Contents/MacOS
rm -rf ~/Applications/Smash.app
# to roll back a version, rebuild from a prior commit of ui/macos/
```

## Finder Quick Actions / Services
```
rm -f ~/Library/Services/Smash*.workflow ~/Library/Services/"Smash Selected Text.workflow"
/System/Library/CoreServices/pbs -update
```

## Web / PWA
Static assets — roll back by redeploying the previous `dist/`. To force clients
off a bad service worker:
1. Bump the SW `CACHE` tag (build-dist.sh does this automatically per content
   hash) so the new SW replaces the old on next load.
2. The SW's `activate` handler deletes all non-current caches.
3. Users can also unregister via browser devtools → Application → Service
   Workers → Unregister.
Because the SW **fails closed** on integrity mismatch, a corrupt redeploy never
activates — clients keep the last verified version.

## Repository / GitHub
- Every release is tagged, so any prior tree is recoverable with
  `git checkout <tag>`; the tap's history retains each formula version.
- The CLI `smash` script is **byte-identical** to the shipped v5.0 (sha
  `98089bdd…af90`); this work added `ui/`, `mcp/`, and docs only, so the
  Homebrew formula sha is unchanged and needs no bump.
- To revert the repo to before this work: `git checkout <prior-commit>` (prior
  HEAD recorded in the evidence report), or restore the tarball backup.
