#!/usr/bin/env bash
# Kimi 0.39.x discards SessionStart stdout. Use this event to prepare artifact
# state and reset the once-per-session UserPromptSubmit delivery marker.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$PLUGIN_ROOT/scripts/artifact-generator.py"
input="$(cat 2>/dev/null || true)"

state_root="${CHOIRBOY_STATE_DIR:-${KIMI_CODE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.kimi-code}/choirboy-prompt/hook-state}"
umask 077
state_available=1
if ! mkdir -p "$state_root"; then
  echo "agent-plugin: cannot create Kimi hook state; context may repeat" >&2
  state_available=0
else
  chmod 700 "$state_root" 2>/dev/null || true
fi

if command -v python3 >/dev/null 2>&1; then
  key="$(printf '%s' "$input" | python3 -c '
import hashlib, json, sys
try:
    event = json.load(sys.stdin)
except Exception:
    event = {}
if event.get("hook_event_name") != "SessionStart":
    raise SystemExit(0)
session_id = event.get("session_id") or event.get("sessionId")
cwd = event.get("cwd", "")
if isinstance(session_id, str) and session_id:
    raw = json.dumps([2, session_id, cwd], ensure_ascii=False, separators=(",", ":"))
    print(hashlib.sha256(raw.encode("utf-8")).hexdigest())
')"
  if [ -n "$key" ] && [ "$state_available" = 1 ]; then
    MARKER="$state_root/$key.delivered" python3 -c '
import os
from pathlib import Path
try:
    Path(os.environ["MARKER"]).unlink()
except FileNotFoundError:
    pass
' 2>/dev/null || true
  fi
  if [ -f "$GENERATOR" ]; then
    python3 "$GENERATOR" prepare >/dev/null || \
      echo "agent-plugin: Kimi artifact preparation failed open" >&2
  fi
fi

exit 0
