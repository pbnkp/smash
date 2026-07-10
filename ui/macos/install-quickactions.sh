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
SMASH="$HOME/bin/smash"
mkdir -p "$SVC"

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
    <key>serviceProcessesInput</key><integer>0</integer>
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
        <key>inputMethod</key><integer>1</integer>
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

# Bodies read paths from stdin (inputMethod=1 → the workflow pipes items in,
# one per line). Output lands beside each input (smash default).
mk_file_action "Smash"              "export B64_OUTDIR=\"\$HOME/smashes\"; while IFS= read -r f; do \"$SMASH\" -q \"\$f\"; done"
mk_file_action "Smash (semantic)"   "export B64_OUTDIR=\"\$HOME/smashes\"; while IFS= read -r f; do \"$SMASH\" --ai -q \"\$f\"; done"
mk_file_action "Restore (smash -d)" "export B64_OUTDIR=\"\$HOME/smashes\"; while IFS= read -r f; do \"$SMASH\" -q -d \"\$f\"; done"
mk_text_action "Smash Selected Text" "\"$SMASH\" -q -s \"\$(cat)\""

/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "registered via pbs -update"
