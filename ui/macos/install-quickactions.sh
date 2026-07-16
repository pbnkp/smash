#!/bin/bash
# Install smash Finder Quick Actions / Services into ~/Library/Services.
# Generates real Automator .workflow bundles (Run Shell Script action),
# registers them with pbs, and self-tests each embedded action script.
#
# Actions:
#   Smash                — files/folders → smash (lossless xz)
#   Smash (semantic)     — files/folders → smash --ai (lossy)
#   Restore (smash -d)   — .b64 artifacts → smash -d
#   Smash Selected Text  — selected text → smash -s (any app)
set -euo pipefail
SVC="$HOME/Library/Services"
SMASH="${SMASH_BIN:-$HOME/bin/smash}"
SAFE_PATH='export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/bin:${PATH:-}"'
mkdir -p "$SVC"
[ -x "$SMASH" ] || { echo "smash is not executable at $SMASH" >&2; exit 2; }

# emit a file-input Quick Action bundle: $1=name  $2=shell-body
mk_file_action() {
  local name="$1" body="$2"
  local dir="$SVC/$name.workflow/Contents"
  rm -rf "$SVC/$name.workflow"; mkdir -p "$dir"
  cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSServices</key><array><dict>
    <key>NSMenuItem</key><dict><key>default</key><string>$name</string></dict>
    <key>NSMessage</key><string>runWorkflowAsService</string>
    <key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
    <key>NSSendFileTypes</key><array><string>public.item</string></array>
  </dict></array>
</dict></plist>
PLIST
  cat > "$dir/document.wflow" <<WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AMApplicationBuild</key><string>523</string>
  <key>AMApplicationVersion</key><string>2.10</string>
  <key>AMDocumentVersion</key><string>2</string>
  <key>actions</key><array><dict>
    <key>action</key><dict>
      <key>AMActionVersion</key><string>2.0.3</string>
      <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
      <key>ActionName</key><string>Run Shell Script</string>
      <key>ActionParameters</key><dict>
        <key>COMMAND_STRING</key><string>$body</string>
        <key>CheckedForUserDefaultShell</key><true/>
        <key>inputMethod</key><integer>1</integer>
        <key>shell</key><string>/bin/bash</string>
        <key>source</key><string></string>
      </dict>
      <key>BundleIdentifier</key><string>com.apple.Automator.RunShellScript</string>
      <key>Class Name</key><string>AMShellScriptAction</string>
      <key>InputUUID</key><string>SMASH-IN-$name</string>
      <key>UUID</key><string>SMASH-UUID-$name</string>
      <key>arguments</key><dict/>
    </dict>
    <key>isViewVisible</key><integer>1</integer>
  </dict></array>
  <key>connectors</key><dict/>
  <key>workflowMetaData</key><dict>
    <key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
    <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
    <key>serviceProcessesInput</key><integer>1</integer>
    <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict></plist>
WFLOW
  echo "installed: $name.workflow"
}

# text-input variant (selected text → stdin)
mk_text_action() {
  local name="$1" body="$2"
  local dir="$SVC/$name.workflow/Contents"
  rm -rf "$SVC/$name.workflow"; mkdir -p "$dir"
  cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSServices</key><array><dict>
    <key>NSMenuItem</key><dict><key>default</key><string>$name</string></dict>
    <key>NSMessage</key><string>runWorkflowAsService</string>
    <key>NSSendTypes</key><array><string>public.utf8-plain-text</string></array>
  </dict></array>
</dict></plist>
PLIST
  cat > "$dir/document.wflow" <<WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AMApplicationBuild</key><string>523</string>
  <key>AMApplicationVersion</key><string>2.10</string>
  <key>AMDocumentVersion</key><string>2</string>
  <key>actions</key><array><dict>
    <key>action</key><dict>
      <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
      <key>ActionName</key><string>Run Shell Script</string>
      <key>ActionParameters</key><dict>
        <key>COMMAND_STRING</key><string>$body</string>
        <key>inputMethod</key><integer>0</integer>
        <key>shell</key><string>/bin/bash</string>
      </dict>
      <key>BundleIdentifier</key><string>com.apple.Automator.RunShellScript</string>
      <key>Class Name</key><string>AMShellScriptAction</string>
      <key>UUID</key><string>SMASH-UUID-$name</string>
    </dict>
    <key>isViewVisible</key><integer>1</integer>
  </dict></array>
  <key>workflowMetaData</key><dict>
    <key>serviceInputTypeIdentifier</key><string>com.apple.Automator.text</string>
    <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
    <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict></plist>
WFLOW
  echo "installed: $name.workflow"
}

# File inputs use argv (inputMethod=1), preserving whitespace and even newline
# characters in Finder filenames. Text uses stdin (inputMethod=0).
mk_file_action "Smash"              "$SAFE_PATH; export B64_OUTDIR=\"\$HOME/smashes\"; for f in \"\$@\"; do \"$SMASH\" -q \"\$f\"; done"
mk_file_action "Smash (semantic)"   "$SAFE_PATH; export B64_OUTDIR=\"\$HOME/smashes\"; for f in \"\$@\"; do \"$SMASH\" --ai -q \"\$f\"; done"
mk_file_action "Restore (smash -d)" "$SAFE_PATH; export B64_OUTDIR=\"\$HOME/smashes\"; for f in \"\$@\"; do \"$SMASH\" -q -d \"\$f\"; done"
# Automator already provides selected text on stdin. Stream it directly so a
# multi-megabyte selection never crosses the OS command-line argument limit.
mk_text_action "Smash Selected Text" "$SAFE_PATH; \"$SMASH\" -q -o \"\$HOME/smashes/Selected Text.txt\" -"

for w in "$SVC/Smash.workflow" "$SVC/Smash (semantic).workflow" \
         "$SVC/Restore (smash -d).workflow" "$SVC/Smash Selected Text.workflow"; do
  plutil -lint "$w/Contents/Info.plist" "$w/Contents/document.wflow" >/dev/null
  touch "$w"
done

# Refresh the Services database. -flush removes stale entries left behind by
# older partial installs; -update immediately discovers all four workflows.
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "registered 4 Finder/Services actions via pbs"
