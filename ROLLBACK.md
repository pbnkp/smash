# smash — Rollback

Every deploy in this project is reversible. Timestamped backups are made before
any overwrite.

## CLI (per host)
Each host keeps a timestamped backup beside the binary when it was upgraded:
```
# macOS hosts (piggymini / piggymspro / piggytop)
ls ~/bin/smash.v-prev.*.bak ~/bin/_archive/smash-v4.5-*      # find the backup
cp ~/bin/smash.v-prev.<ts>.bak ~/bin/smash                    # restore
smash -V

# bernie (FreeBSD)
cp /root/bin/smash.v-prev.20260712-075936.bak /root/bin/smash
```
Known-good backups from this work:
- piggytop: `~/bin/smash.v-prev.20260712-024355.bak` (pre-v5 shadowing copy)
- bernie:   `/root/bin/smash.v-prev.20260712-075936.bak` (v4.5)
- Mac archives: `~/bin/_archive/smash-v4.5-20260710`, `smash-v4.x-home-copy-apr27`

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
- Pre-change repo state is archived at
  `scratchpad/_backups/smash-repo.<ts>.tgz` and the tap/main history is intact.
- The CLI `smash` script is **byte-identical** to the shipped v5.0 (sha
  `98089bdd…af90`); this work added `ui/`, `mcp/`, and docs only, so the
  Homebrew formula sha is unchanged and needs no bump.
- To revert the repo to before this work: `git checkout <prior-commit>` (prior
  HEAD recorded in the evidence report), or restore the tarball backup.
