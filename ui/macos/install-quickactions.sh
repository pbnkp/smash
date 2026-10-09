#!/bin/bash
# Install the six smash Finder Services into ~/Library/Services.
#
# File services: Automator inputMethod 1 means "as arguments". The scripts
# read "$@". They do not read stdin.
# Smash Selected Text: inputMethod 0 means "to stdin".
# serviceProcessesInput must be 1 or the service receives nothing.
#
# Re-running overwrites the two plists inside each existing bundle.
# It does not remove the bundle.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SVC="${HOME}/Library/Services"
mkdir -p "$SVC"

python3 - "$ROOT/services" "$SVC" <<'PY'
import os, plistlib, sys
services, dest = sys.argv[1], sys.argv[2]
jobs = [
    ("Smash.sh", "Smash", "file"),
    ("Smash--semantic-.sh", "Smash (semantic)", "file"),
    ("Smash--portable,-opens-on-iPhone-.sh", "Smash (portable, opens on iPhone)", "file"),
    ("Smash--redact-credentials-.sh", "Smash (redact credentials)", "file"),
    ("Restore--smash--d-.sh", "Restore (smash -d)", "file"),
    ("Smash-Selected-Text.sh", "Smash Selected Text", "text"),
]

def info_plist(name, kind):
    if kind == "file":
        item = {
            "NSMenuItem": {"default": name},
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSSendFileTypes": ["public.item"],
        }
    else:
        item = {
            "NSMenuItem": {"default": name},
            "NSMessage": "runWorkflowAsService",
            "NSSendTypes": ["public.utf8-plain-text"],
        }
    return {"NSServices": [item]}

def document(name, body, kind):
    text = kind == "text"
    action = {
        "action": {
            "AMActionVersion": "2.0.3",
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": {
                "COMMAND_STRING": body,
                "CheckedForUserDefaultShell": True,
                "inputMethod": 0 if text else 1,
                "shell": "/bin/bash",
                "source": "",
            },
            "BundleIdentifier": "com.apple.Automator.RunShellScript",
            "Class Name": "AMShellScriptAction",
            "InputUUID": "SMASH-IN-%s" % name,
            "UUID": "SMASH-UUID-%s" % name,
            "arguments": {},
        },
        "isViewVisible": 1,
    }
    meta = {
        "serviceInputTypeIdentifier": "com.apple.Automator.text" if text else "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceProcessesInput": 1,
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
    }
    return {
        "AMApplicationBuild": "523",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [action],
        "connectors": {},
        "workflowMetaData": meta,
    }

for fn, name, kind in jobs:
    path = os.path.join(services, fn)
    with open(path, "r", encoding="utf-8") as fh:
        body = fh.read()
    if body.startswith("#!"):
        body = body.split("\n", 1)[1]
    contents = os.path.join(dest, name + ".workflow", "Contents")
    os.makedirs(contents, exist_ok=True)
    with open(os.path.join(contents, "Info.plist"), "wb") as fh:
        plistlib.dump(info_plist(name, kind), fh, fmt=plistlib.FMT_XML)
    with open(os.path.join(contents, "document.wflow"), "wb") as fh:
        plistlib.dump(document(name, body, kind), fh, fmt=plistlib.FMT_XML)
    print("installed: %s.workflow" % name)
PY

/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "registered via pbs -update"
