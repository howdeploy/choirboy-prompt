#!/usr/bin/env bash
# Kimi 0.39.x appends UserPromptSubmit stdout to the model request. Deliver the
# full fixed lore plus validated artifact memory once per startup/resume.
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
    [ -f "$marker" ] && exit 0
  else
    echo "agent-plugin: cannot create Kimi hook state; injecting without marker" >&2
  fi
fi

if ! payload="$(bash "$SESSION_HOOK" --format plain)"; then
  echo "agent-plugin: Kimi context delivery failed open" >&2
  exit 0
fi
if ! printf '%s\n' "$payload"; then
  echo "agent-plugin: Kimi context stdout failed; delivery remains unmarked" >&2
  exit 0
fi

# Mark only after a successful emission. If marker I/O fails, a duplicate on
# the next prompt is safer than silently omitting memory.
if [ -n "$marker" ]; then
  MARKER="$marker" python3 -c '
import os
path = os.environ["MARKER"]
try:
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    pass
else:
    os.close(descriptor)
' 2>/dev/null || true
fi
