#!/usr/bin/env bash
# Kimi 0.39.x appends UserPromptSubmit stdout to the model request. Deliver the
# full fixed lore plus validated artifact memory when its fingerprint changes.
# A pending bootstrap repeats until the next prompt can deliver the ready bundle.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_HOOK="$PLUGIN_ROOT/hooks/session-start.sh"
input="$(cat 2>/dev/null || true)"

if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$SESSION_HOOK" ]; then
  exit 0
fi

key="$(printf '%s' "$input" | python3 -c '
import hashlib, json, sys
try:
    event = json.load(sys.stdin)
except Exception:
    event = {}
if event.get("hook_event_name") != "UserPromptSubmit":
    raise SystemExit(0)
session_id = event.get("session_id") or event.get("sessionId")
cwd = event.get("cwd", "")
if isinstance(session_id, str) and session_id:
    raw = json.dumps([2, session_id, cwd], ensure_ascii=False, separators=(",", ":"))
    print(hashlib.sha256(raw.encode("utf-8")).hexdigest())
')"
state_root="${CHOIRBOY_STATE_DIR:-${KIMI_CODE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.kimi-code}/choirboy-prompt/hook-state}"
marker=""
if [ -n "$key" ]; then
  umask 077
  if mkdir -p "$state_root"; then
    chmod 700 "$state_root" 2>/dev/null || true
    marker="$state_root/$key.delivered"
  else
    echo "agent-plugin: cannot create Kimi hook state; delivering without marker" >&2
  fi
fi

if ! payload="$(bash "$SESSION_HOOK" --format plain)"; then
  echo "agent-plugin: Kimi context delivery failed open" >&2
  exit 0
fi

ready=0
fingerprint=""
if [[ "$payload" == *$'\n# Established project history\n'* ]]; then
  ready=1
  fingerprint="$(printf '%s' "$payload" | python3 -c '
import hashlib, re, sys
payload = re.sub(r" nonce=\"[^\"]*\"", " nonce=\"\"", sys.stdin.read(), count=1)
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
')"
  if [ -n "$marker" ] && [ -f "$marker" ] && [ ! -L "$marker" ]; then
    previous=""
    IFS= read -r previous < "$marker" || true
    [ "$previous" = "$fingerprint" ] && exit 0
  fi
fi

if ! printf '%s\n' "$payload"; then
  echo "agent-plugin: Kimi context stdout failed; delivery remains unmarked" >&2
  exit 0
fi

# Pending is not session-final: after the agent runs finalize, the next prompt
# must receive INDEX plus all dossiers. Store only the normalized fingerprint
# of a ready delivery. Changed lore or artifacts therefore replace the marker
# and are delivered in the same session. If marker I/O fails, a duplicate on
# the next prompt is safer than silently omitting current memory.
if [ "$ready" = 1 ] && [ -n "$marker" ] && [ -n "$fingerprint" ]; then
  MARKER="$marker" FINGERPRINT="$fingerprint" python3 -c '
import os, tempfile
from pathlib import Path

path = Path(os.environ["MARKER"])
if path.is_symlink():
    raise SystemExit(1)
descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(descriptor, "w", encoding="ascii", newline="\n") as handle:
        handle.write(os.environ["FINGERPRINT"] + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary_name, 0o600)
    os.replace(temporary_name, path)
finally:
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
' 2>/dev/null || true
fi
