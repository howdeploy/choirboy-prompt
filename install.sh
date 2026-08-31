#!/usr/bin/env bash
# agent-plugin installer — multi-runtime.
#
# Registers the plugin's fixed context (prompt.md + lore.md + user.md +
# research/) for automatic session delivery and prepares a persistent,
# agent-authored project-artifact lifecycle.
#
# Usage:
#   ./install.sh                      install into every detected runtime
#   ./install.sh --target claude,opencode  install only into the listed runtimes
#   ./install.sh --uninstall          remove the plugin from the selected runtimes
#   ./install.sh --list               show runtimes and install status
#   ./install.sh --instructions FILE  (un)register a managed pointer block in FILE
#                                     (combine with --target none to skip runtimes)
#   ./install.sh --project            Claude Code: project settings (./.claude/settings.json)
#   ./install.sh --settings PATH      Claude Code: explicit settings file
#
# Runtime targets:
#   claude   ~/.claude/settings.json     SessionStart + Stop hooks (Claude Code)
#   codex    ~/.codex/hooks.json         SessionStart + Stop hooks
#   opencode ~/.config/opencode/plugins/agent-plugin.ts
#                                         model-bound system-context plugin
#   hermes   ~/.hermes/config.yaml       pre_llm_call shell hook + consent allowlist
#   kimi     ~/.kimi-code/config.toml    SessionStart + PreCompact + prompt + Stop
#   gemini   ~/.gemini/GEMINI.md         managed instruction block
#   grok     ~/.grok/AGENTS.md           Grok Build global rules
#   grokbot  ~/.grokbot/choirboy-context/SKILL.md
#                                         importable Grok Bot workflow
#
# Any other agent that reads an instructions file can be wired up with
# --instructions PATH (repeatable). All changes are idempotent, marked with
# agent-plugin:vibe-lore markers, and reversible with --uninstall.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK="agent-plugin:vibe-lore"
REGISTRATION_VERSION="2"
REGISTRATION_MARK="$MARK:registration=$REGISTRATION_VERSION"
HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session-start.sh"
STOP_HOOK_SCRIPT="$PLUGIN_ROOT/hooks/artifact-stop.sh"
KIMI_SESSION_HOOK_SCRIPT="$PLUGIN_ROOT/hooks/kimi-session-start.sh"
KIMI_PROMPT_HOOK_SCRIPT="$PLUGIN_ROOT/hooks/kimi-user-prompt.sh"
KIMI_STOP_HOOK_SCRIPT="$PLUGIN_ROOT/hooks/kimi-artifact-stop.sh"
ARTIFACT_GENERATOR="$PLUGIN_ROOT/scripts/artifact-generator.py"
CODEX_CONTEXT_LIMIT="262144"
KIMI_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
ALL_TARGETS="claude codex opencode hermes kimi gemini grok grokbot"

UNINSTALL=0
LIST_ONLY=0
SCOPE="user"
SETTINGS_FILE=""
TARGETS=""
INSTRUCTIONS_FILES=()

usage() {
  sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "install.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)       TARGETS="${2:?--target requires a comma-separated list}"; shift ;;
    --uninstall)    UNINSTALL=1 ;;
    --list)         LIST_ONLY=1 ;;
    --instructions) INSTRUCTIONS_FILES+=("${2:?--instructions requires a path}"); shift ;;
    --project)      SCOPE="project" ;;
    --settings)     SETTINGS_FILE="${2:?--settings requires a path}"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || die "python3 is required"
if [ "$UNINSTALL" = 0 ] && [ "$LIST_ONLY" = 0 ] \
  && [ -f "$PLUGIN_ROOT/scripts/build-context.py" ]; then
  python3 "$PLUGIN_ROOT/scripts/build-context.py" >/dev/null
fi

# --- target detection -------------------------------------------------------

target_present() {
  case "$1" in
    claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
    codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
    opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
    hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
    kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "$KIMI_HOME" ] ;;
    gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
    grok)   command -v grok   >/dev/null 2>&1 || [ -d "$HOME/.grok" ] ;;
    grokbot) command -v grokbot >/dev/null 2>&1 \
               || command -v grok-bot >/dev/null 2>&1 \
               || [ -d "$HOME/.grokbot" ] ;;
    *) return 1 ;;
  esac
}

claude_settings_file() {
  if [ -n "$SETTINGS_FILE" ]; then printf '%s' "$SETTINGS_FILE";
  elif [ "$SCOPE" = "project" ]; then printf '%s' "$(pwd)/.claude/settings.json";
  else printf '%s' "$HOME/.claude/settings.json"; fi
}

kimi_hooks_current() {
  python3 - "$KIMI_HOME/config.toml" "$REGISTRATION_MARK" \
    "$KIMI_SESSION_HOOK_SCRIPT" "$KIMI_PROMPT_HOOK_SCRIPT" \
    "$KIMI_STOP_HOOK_SCRIPT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)
registration = sys.argv[2]
mark = registration.split(":registration=", 1)[0]
expected_block = f'''# >>> {mark} >>>
# {registration}
[[hooks]]
event = "SessionStart"
matcher = "^(startup|resume)$"
command = "bash \\"{sys.argv[3]}\\""
timeout = 30

[[hooks]]
event = "PreCompact"
matcher = "^(manual|auto)$"
command = "bash \\"{sys.argv[3]}\\""
timeout = 30

[[hooks]]
event = "UserPromptSubmit"
command = "bash \\"{sys.argv[4]}\\""
timeout = 30

[[hooks]]
event = "Stop"
command = "bash \\"{sys.argv[5]}\\""
timeout = 30
# <<< {mark} <<<'''
if expected_block not in text:
    raise SystemExit(1)
try:
    import tomllib
except ModuleNotFoundError:
    # Exact managed text alone cannot prove that the surrounding TOML parses.
    # On Python <=3.10, ask Kimi's read-only config doctor when available.
    import shutil
    import subprocess

    executable = shutil.which("kimi")
    if executable is None:
        raise SystemExit(1)
    result = subprocess.run(
        [executable, "doctor", "config", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    raise SystemExit(0 if result.returncode == 0 else 1)
try:
    config = tomllib.loads(text)
except tomllib.TOMLDecodeError:
    raise SystemExit(1)
hooks = config.get("hooks")
if not isinstance(hooks, list):
    raise SystemExit(1)
expected = (
    ("SessionStart", f'bash "{sys.argv[3]}"', "^(startup|resume)$"),
    ("PreCompact", f'bash "{sys.argv[3]}"', "^(manual|auto)$"),
    ("UserPromptSubmit", f'bash "{sys.argv[4]}"', None),
    ("Stop", f'bash "{sys.argv[5]}"', None),
)
for event, command, matcher in expected:
    matches = [
        hook
        for hook in hooks
        if isinstance(hook, dict)
        and hook.get("event") == event
        and hook.get("command") == command
    ]
    if len(matches) != 1 or matches[0].get("timeout") != 30:
        raise SystemExit(1)
    if matcher is None:
        if matches[0].get("matcher") not in (None, ""):
            raise SystemExit(1)
    elif matches[0].get("matcher") != matcher:
        raise SystemExit(1)
PY
}

target_installed() {
  case "$1" in
    claude) [ "$(json_hook "$(claude_settings_file)" bash status hooks.SessionStart "$HOOK_SCRIPT" 15 "" session-start.sh 2>/dev/null || true)" = current ] \
              && [ "$(json_hook "$(claude_settings_file)" bash status hooks.Stop "$STOP_HOOK_SCRIPT" 15 "" artifact-stop.sh 2>/dev/null || true)" = current ] ;;
    codex) [ "$(json_hook "$HOME/.codex/hooks.json" "bash \"$HOOK_SCRIPT\"" status hooks.SessionStart "" 15 "$CODEX_CONTEXT_LIMIT" session-start.sh 2>/dev/null || true)" = current ] \
              && [ "$(json_hook "$HOME/.codex/hooks.json" "bash \"$STOP_HOOK_SCRIPT\"" status hooks.Stop "" 15 "" artifact-stop.sh 2>/dev/null || true)" = current ] ;;
    opencode) [ "$(opencode_plugin "$HOME/.config/opencode/plugins/agent-plugin.ts" status 2>/dev/null || true)" = current ] ;;
    hermes) grep -qF "$REGISTRATION_MARK" "$HOME/.hermes/config.yaml" 2>/dev/null \
              && grep -qF "$HOOK_SCRIPT" "$HOME/.hermes/config.yaml" 2>/dev/null \
              && grep -qF "$HOOK_SCRIPT" "$HOME/.hermes/shell-hooks-allowlist.json" 2>/dev/null ;;
    kimi)   kimi_hooks_current 2>/dev/null ;;
    gemini) grep -qF "$REGISTRATION_MARK" "$HOME/.gemini/GEMINI.md" 2>/dev/null \
              && grep -qF "$ARTIFACT_GENERATOR" "$HOME/.gemini/GEMINI.md" 2>/dev/null ;;
    grok)   grep -qF "$REGISTRATION_MARK" "$HOME/.grok/AGENTS.md" 2>/dev/null \
              && grep -qF "$ARTIFACT_GENERATOR" "$HOME/.grok/AGENTS.md" 2>/dev/null ;;
    grokbot) [ "$(grokbot_workflow "$HOME/.grokbot/choirboy-context/SKILL.md" status 2>/dev/null || true)" = current ] ;;
    *) return 1 ;;
  esac
}

target_managed_present() {
  case "$1" in
    claude) grep -qF "session-start.sh" "$(claude_settings_file)" 2>/dev/null \
              || grep -qF "artifact-stop.sh" "$(claude_settings_file)" 2>/dev/null ;;
    codex) grep -qF "session-start.sh" "$HOME/.codex/hooks.json" 2>/dev/null \
              || grep -qF "artifact-stop.sh" "$HOME/.codex/hooks.json" 2>/dev/null ;;
    opencode) grep -qF "$MARK" "$HOME/.config/opencode/plugins/agent-plugin.ts" 2>/dev/null ;;
    hermes) grep -qF "$MARK" "$HOME/.hermes/config.yaml" 2>/dev/null ;;
    kimi) grep -qF "$MARK" "$KIMI_HOME/config.toml" 2>/dev/null ;;
    gemini) grep -qF "$MARK" "$HOME/.gemini/GEMINI.md" 2>/dev/null ;;
    grok) grep -qF "$MARK" "$HOME/.grok/AGENTS.md" 2>/dev/null ;;
    grokbot) grep -qF "$MARK" "$HOME/.grokbot/choirboy-context/SKILL.md" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

if [ -z "$TARGETS" ]; then
  if [ -n "$SETTINGS_FILE" ] || [ "$SCOPE" = "project" ]; then
    TARGETS="claude"   # Claude-specific flags imply the claude target only
  else
    TARGETS=""
    for t in $ALL_TARGETS; do
      target_present "$t" && TARGETS="$TARGETS $t"
    done
    TARGETS="${TARGETS# }"
  fi
else
  [ "$TARGETS" = "none" ] && TARGETS="" || TARGETS="$(printf '%s' "$TARGETS" | tr ', ' '  ')"
fi

# --- generic helpers --------------------------------------------------------

backup() {
  [ -f "$1" ] || return 0
  cp -p "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"
}

# block_sync FILE START_LINE END_LINE — atomically append or replace exactly
# one managed block with stdin while preserving all surrounding user content.
block_sync() {
  local file="$1" start="$2" end="$3" desired status
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
  desired="$(mktemp "${TMPDIR:-/tmp}/choirboy-block.XXXXXX")"
  cat > "$desired"
  if ! status="$(BLOCK_START="$start" BLOCK_END="$end" DESIRED="$desired" python3 - "$file" <<'PY'
import os, shutil, sys, tempfile, time
from pathlib import Path

path = Path(sys.argv[1])
start, end = os.environ["BLOCK_START"], os.environ["BLOCK_END"]
desired_path = Path(os.environ["DESIRED"])
desired = desired_path.read_text(encoding="utf-8")
current = path.read_text(encoding="utf-8")

def locate(document):
    lines = document.splitlines(keepends=True)
    offset = 0
    begin = finish = None
    inside = False
    seen = 0
    for number, line in enumerate(lines, start=1):
        stripped = line.strip()
        has_start, has_end = stripped == start, stripped == end
        if has_start and has_end:
            raise ValueError(f"both block markers occur on line {number}")
        if has_start:
            if inside or seen:
                raise ValueError(f"duplicate or nested START marker on line {number}")
            inside = True
            seen += 1
            begin = offset
        elif has_end:
            if not inside:
                raise ValueError(f"END marker without START on line {number}")
            inside = False
            finish = offset + len(line)
        offset += len(line)
    if inside:
        raise ValueError("START marker has no matching END marker")
    return begin, finish

try:
    desired_begin, desired_finish = locate(desired)
    if desired_begin != 0 or desired_finish != len(desired):
        raise ValueError("generated block must contain only one complete managed block")
    begin, finish = locate(current)
except ValueError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(2)

if begin is None:
    if current and not current.endswith("\n"):
        separator = "\n\n"
    elif current and not current.endswith("\n\n"):
        separator = "\n"
    else:
        separator = ""
    updated = current + separator + desired
else:
    updated = current[:begin] + desired + current[finish:]

if updated == current:
    print("unchanged")
    raise SystemExit(0)

suffix = "%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), time.time_ns())
shutil.copy2(path, path.with_name(f"{path.name}.bak.{suffix}"))
descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.tmp.", dir=path.parent)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(updated)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary_name, path.stat().st_mode)
    os.replace(temporary_name, path)
finally:
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
print("changed")
PY
  )"; then
    DESIRED="$desired" python3 -c 'import os; from pathlib import Path; Path(os.environ["DESIRED"]).unlink(missing_ok=True)'
    die "refusing unsafe managed-block update in $file; repair its markers first"
  fi
  DESIRED="$desired" python3 -c 'import os; from pathlib import Path; Path(os.environ["DESIRED"]).unlink(missing_ok=True)'
  if [ "$status" = "changed" ]; then
    echo "  block synchronized in $file"
  else
    echo "  block already current in $file — skipped"
  fi
}

# block_remove FILE START_LINE END_LINE — delete the marked block from FILE.
block_remove() {
  local file="$1" start="$2" end="$3"
  [ -f "$file" ] || { echo "  $file does not exist — skipped"; return 0; }
  if ! grep -qF "$start" "$file"; then
    echo "  no block in $file — skipped"
    return 0
  fi
  if ! START="$start" END="$end" python3 - "$file" <<'PY'
import os, sys

path = sys.argv[1]
start, end = os.environ["START"], os.environ["END"]
lines = open(path, encoding="utf-8").read().splitlines()
inside = False
seen = 0
for number, line in enumerate(lines, start=1):
    has_start, has_end = start in line, end in line
    if has_start and has_end:
        print(f"both block markers occur on line {number}", file=sys.stderr)
        raise SystemExit(2)
    if has_start:
        if inside:
            print(f"nested START marker on line {number}", file=sys.stderr)
            raise SystemExit(2)
        inside = True
        seen += 1
    elif has_end:
        if not inside:
            print(f"END marker without START on line {number}", file=sys.stderr)
            raise SystemExit(2)
        inside = False
if inside:
    print("START marker has no matching END marker", file=sys.stderr)
    raise SystemExit(2)
if not seen:
    raise SystemExit(2)
PY
  then
    die "refusing unsafe block removal from $file; repair its markers first"
  fi
  backup "$file"
  START="$start" END="$end" python3 - "$file" <<'PY'
import os, sys
path = sys.argv[1]
start, end = os.environ["START"], os.environ["END"]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out, skip = [], False
for line in lines:
    if start in line:
        skip = True
        # drop a single preceding blank line left over from block_add
        if out and out[-1].strip() == "":
            out.pop()
        continue
    if skip:
        if end in line:
            skip = False
        continue
    out.append(line)
open(path, "w", encoding="utf-8").write("".join(out))
PY
  echo "  block removed from $file"
}

# json_hook FILE CMD install|uninstall DOTPATH [ARG] [TIMEOUT]
#           [CONTEXT_LIMIT] [SCRIPT_ID] — safely add/remove one command hook in
# a Claude-Code-shaped hooks JSON file. ARG enables Claude's shell-free form;
# CONTEXT_LIMIT keeps Codex's complete lore plus inline artifact memory in the
# same SessionStart context instead of truncating it at the old 20-KB setting.
json_hook() {
  HOOK_CMD="$2" MODE="$3" DOTPATH="$4" HOOK_ARG="${5-}" HOOK_TIMEOUT="${6-}" \
  HOOK_CONTEXT_LIMIT="${7-}" HOOK_ID="${8-}" \
    python3 - "$1" <<'PY'
import json, os, shutil, sys, tempfile, time

path = sys.argv[1]
cmd, mode, dotpath = os.environ["HOOK_CMD"], os.environ["MODE"], os.environ["DOTPATH"]
hook_arg = os.environ.get("HOOK_ARG") or None
hook_timeout = int(os.environ["HOOK_TIMEOUT"]) if os.environ.get("HOOK_TIMEOUT") else None
context_limit = int(os.environ["HOOK_CONTEXT_LIMIT"]) if os.environ.get("HOOK_CONTEXT_LIMIT") else None
hook_id = os.environ.get("HOOK_ID")
if not hook_id:
    print("managed hook script id is required", file=sys.stderr)
    raise SystemExit(2)

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except (OSError, ValueError) as exc:
    print(f"refusing to replace invalid JSON in {path}: {exc}", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(data, dict):
    print(f"refusing to replace non-object JSON in {path}", file=sys.stderr)
    raise SystemExit(2)

node = data
keys = dotpath.split(".")
for k in keys[:-1]:
    if k not in node:
        node[k] = {}
    elif not isinstance(node[k], dict):
        print(f"refusing to replace non-object JSON path: {'.'.join(keys[:-1])}", file=sys.stderr)
        raise SystemExit(2)
    node = node[k]
entries = node.get(keys[-1])
if entries is None:
    entries = []
elif not isinstance(entries, list):
    print(f"refusing to replace non-array JSON path: {dotpath}", file=sys.stderr)
    raise SystemExit(2)

# A settings hook entry belongs to us if it runs the selected managed script,
# regardless of the absolute path (the plugin folder may move). This keeps the
# manual installer idempotent across working-copy moves. Marketplace hooks are
# resolved from the plugin cache and do not appear in this settings array.
def is_ours(entry):
    if not isinstance(entry, dict):
        return False
    return any(
        isinstance(h, dict) and hook_id in (
            h.get("command", "") + " " + " ".join(str(a) for a in h.get("args", []))
        )
        for h in entry.get("hooks", [])
    )

def has_exact(es):
    return any(
        isinstance(h, dict)
        and h.get("command") == cmd
        and ((hook_arg is None and "args" not in h) or h.get("args") == [hook_arg])
        and (hook_timeout is None or h.get("timeout") == hook_timeout)
        and (context_limit is None or h.get("additionalContextLimit") == context_limit)
        for e in es if isinstance(e, dict)
        for h in e.get("hooks", [])
    )

def expected_handler():
    handler = {"type": "command", "command": cmd}
    if hook_arg is not None:
        handler["args"] = [hook_arg]
    if hook_timeout is not None:
        handler["timeout"] = hook_timeout
    if context_limit is not None:
        handler["additionalContextLimit"] = context_limit
    return handler

if mode == "status":
    owned = [entry for entry in entries if is_ours(entry)]
    current = (
        len(owned) == 1
        and isinstance(owned[0].get("hooks"), list)
        and owned[0]["hooks"] == [expected_handler()]
    )
    print("current" if current else ("stale" if owned else "absent"))
    raise SystemExit(0)

if mode == "install":
    # drop stale registrations of our script (e.g. the plugin folder moved),
    # keep the one matching the current command exactly
    kept, removed_stale = [], False
    for e in entries:
        if is_ours(e) and not has_exact([e]):
            removed_stale = True
            continue
        kept.append(e)
    entries = kept
    if has_exact(entries):
        if not removed_stale:
            print("unchanged")
            sys.exit(0)
    else:
        handler = {"type": "command", "command": cmd}
        if hook_arg is not None:
            handler["args"] = [hook_arg]
        if hook_timeout is not None:
            handler["timeout"] = hook_timeout
        if context_limit is not None:
            handler["additionalContextLimit"] = context_limit
        entries.append({"hooks": [handler]})
else:
    before = len(entries)
    entries = [e for e in entries if not is_ours(e)]
    if len(entries) == before:
        print("unchanged")
        sys.exit(0)

node[keys[-1]] = entries
if os.path.exists(path):
    suffix = "%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), time.time_ns())
    shutil.copy2(path, "%s.bak.%s" % (path, suffix))
directory = os.path.dirname(path) or "."
descriptor, temporary = tempfile.mkstemp(prefix=".agent-plugin-hooks.", dir=directory)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
print("changed")
PY
}

# opencode_plugin FILE install|uninstall — manage the OpenCode model-context
# adapter as a complete, marked file. The installed module rebuilds the canonical
# plain payload for every model request, so compaction cannot evict project memory.
opencode_plugin() {
  PLUGIN_FILE="$1" MODE="$2" HOOK_PATH="$HOOK_SCRIPT" INSTALL_MARK="$MARK" \
    REGISTRATION_MARK="$REGISTRATION_MARK" \
    python3 - <<'PY'
import json
import os
import shutil
import sys
import time
from pathlib import Path

path = Path(os.environ["PLUGIN_FILE"])
mode = os.environ["MODE"]
hook_path = os.environ["HOOK_PATH"]
mark = os.environ["INSTALL_MARK"]
registration_mark = os.environ["REGISTRATION_MARK"]

template = r'''// >>> agent-plugin:vibe-lore >>>
// __REGISTRATION_MARK__
// OpenCode adapter for choirboy-prompt.
// Appends the canonical fixed lore to every model-bound system context.
// Fail-open: a missing hook, timeout, or malformed payload never blocks chat.

import { spawnSync } from "child_process"
import type { Plugin } from "@opencode-ai/plugin"

const HOOK_SCRIPT = __HOOK_SCRIPT__
const DELIVERY_MARKER = "<choirboy-delivery "
const SESSION_DELIVERY_MARKER = ' delivery="session-start"'

export const AgentPlugin: Plugin = async () => {
  return {
    "experimental.chat.system.transform": async (input, output) => {
      try {
        const sessionID = typeof input.sessionID === "string" ? input.sessionID : ""
        if (!sessionID) return
        if (!Array.isArray(output.system)) return
        if (
          output.system.some(
            (value) =>
              typeof value === "string" &&
              value.includes(DELIVERY_MARKER) &&
              value.includes(SESSION_DELIVERY_MARKER) &&
              value.includes("<choirboy-context>"),
          )
        ) return

        // System context is rebuilt for every model request. Recompute the
        // lifecycle payload here so pending -> ready and later lore/dossier
        // changes are visible immediately, including after session compaction.
        const result = spawnSync("bash", [HOOK_SCRIPT, "--format", "plain"], {
          encoding: "utf8",
          timeout: 15000,
          maxBuffer: 2 * 1024 * 1024,
        })
        const delivered = (result.stdout ?? "").trim()
        if (
          result.status !== 0 ||
          !delivered.includes(DELIVERY_MARKER) ||
          !delivered.includes("<choirboy-context>")
        ) return
        output.system.push(delivered)
      } catch {
        // fail-open: lore delivery must never break the OpenCode session
      }
    },
  }
}

export default AgentPlugin
// <<< agent-plugin:vibe-lore <<<
'''
content = template.replace("__HOOK_SCRIPT__", json.dumps(hook_path, ensure_ascii=False))
content = content.replace("__REGISTRATION_MARK__", registration_mark)

def backup() -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}.{os.getpid()}")
    shutil.copy2(path, destination)
    return destination

if mode == "status":
    if not path.is_file():
        print("absent")
    else:
        current = path.read_text(encoding="utf-8")
        print("current" if current == content else ("stale" if mark in current else "absent"))
    raise SystemExit(0)
if mode == "install":
    current = path.read_text(encoding="utf-8") if path.is_file() else None
    if current == content:
        print("unchanged")
        raise SystemExit(0)
    if current is not None and mark not in current:
        print(f"refusing to overwrite unmarked file: {path}", file=sys.stderr)
        raise SystemExit(2)
    path.parent.mkdir(parents=True, exist_ok=True)
    if current is not None:
        backup()
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)
    print("changed")
elif mode == "uninstall":
    if not path.is_file():
        print("unchanged")
        raise SystemExit(0)
    current = path.read_text(encoding="utf-8")
    if mark not in current:
        print(f"refusing to remove unmarked file: {path}", file=sys.stderr)
        raise SystemExit(2)
    backup()
    path.unlink()
    print("changed")
else:
    raise SystemExit(f"unknown mode: {mode}")
PY
}

# grokbot_workflow FILE install|uninstall — prepare a complete, importable
# Grok Bot workflow without editing the application's private data store.
# Grok Bot does not auto-load ~/.grokbot/AGENTS.md; its supported local route is
# importing a SKILL.md into Workflows and invoking it in a conversation.
grokbot_workflow() {
  WORKFLOW_FILE="$1" MODE="$2" SOURCE_SKILL="$PLUGIN_ROOT/skills/load-context/SKILL.md" \
    INSTALL_MARK="$MARK" REGISTRATION_MARK="$REGISTRATION_MARK" python3 - <<'PY'
import os
import shutil
import sys
import time
from pathlib import Path

path = Path(os.environ["WORKFLOW_FILE"])
mode = os.environ["MODE"]
source_path = Path(os.environ["SOURCE_SKILL"])
mark = os.environ["INSTALL_MARK"]
registration_mark = os.environ["REGISTRATION_MARK"]

def backup() -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}.{os.getpid()}")
    shutil.copy2(path, destination)
    return destination

source = source_path.read_text(encoding="utf-8")
if not source.startswith("---\n"):
    print(f"invalid generated skill (missing frontmatter): {source_path}", file=sys.stderr)
    raise SystemExit(2)
frontmatter_end = source.find("\n---\n", 4)
if frontmatter_end < 0:
    print(f"invalid generated skill (unterminated frontmatter): {source_path}", file=sys.stderr)
    raise SystemExit(2)
content = source.replace("name: load-context", "name: choirboy-context", 1)
insert_at = content.find("\n---\n", 4) + len("\n---\n")
content = (
    content[:insert_at]
    + f"\n<!-- {mark}: managed Grok Bot workflow; {registration_mark} -->\n"
    + content[insert_at:]
)

if mode == "status":
    if not path.is_file():
        print("absent")
    else:
        current = path.read_text(encoding="utf-8")
        print("current" if current == content else ("stale" if mark in current else "absent"))
    raise SystemExit(0)
if mode == "install":
    current = path.read_text(encoding="utf-8") if path.is_file() else None
    if current == content:
        print("unchanged")
        raise SystemExit(0)
    if current is not None and mark not in current:
        print(f"refusing to overwrite unmarked file: {path}", file=sys.stderr)
        raise SystemExit(2)
    path.parent.mkdir(parents=True, exist_ok=True)
    if current is not None:
        backup()
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)
    print("changed")
elif mode == "uninstall":
    if not path.is_file():
        print("unchanged")
        raise SystemExit(0)
    current = path.read_text(encoding="utf-8")
    if mark not in current:
        print(f"refusing to remove unmarked file: {path}", file=sys.stderr)
        raise SystemExit(2)
    backup()
    path.unlink()
    print("changed")
else:
    raise SystemExit(f"unknown mode: {mode}")
PY
}

# hermes_allowlist COMMAND install|uninstall — (un)approve the exact
# (event, command) pair in ~/.hermes/shell-hooks-allowlist.json.
hermes_allowlist() {
  local allowlist_path="$HOME/.hermes/shell-hooks-allowlist.json"
  ALLOWLIST_PATH="$allowlist_path" ALLOW_CMD="$1" MODE="$2" python3 - <<'PY'
import json, os, shutil, sys, tempfile, time

path = os.environ["ALLOWLIST_PATH"]
cmd, mode = os.environ["ALLOW_CMD"], os.environ["MODE"]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except (OSError, ValueError) as exc:
    print(f"refusing to replace invalid Hermes allowlist {path}: {exc}", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(data, dict):
    print(f"refusing to replace non-object Hermes allowlist {path}", file=sys.stderr)
    raise SystemExit(2)
approvals = data.get("approvals")
if approvals is None:
    approvals = []
elif not isinstance(approvals, list):
    print(f"refusing to replace non-array approvals in {path}", file=sys.stderr)
    raise SystemExit(2)

def is_ours(approval):
    return (
        isinstance(approval, dict)
        and approval.get("event") == "pre_llm_call"
        and "session-start.sh" in approval.get("command", "")
    )

if mode == "install":
    expected = {"event": "pre_llm_call", "command": cmd}
    owned = [a for a in approvals if is_ours(a)]
    if owned == [expected]:
        status = "unchanged"
    else:
        approvals = [a for a in approvals if not is_ours(a)]
        approvals.append(expected)
        status = "changed"
else:
    before = len(approvals)
    approvals = [a for a in approvals if not is_ours(a)]
    status = "changed" if len(approvals) != before else "unchanged"

if status == "unchanged":
    print(status)
    raise SystemExit(0)

data["approvals"] = approvals
if os.path.exists(path):
    suffix = "%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), time.time_ns())
    shutil.copy2(path, "%s.bak.%s" % (path, suffix))
directory = os.path.dirname(path) or "."
os.makedirs(directory, exist_ok=True)
descriptor, temporary = tempfile.mkstemp(prefix=".agent-plugin-allowlist.", dir=directory)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
print(status)
PY
}

instruction_block() {
  local comment_style="$1"
  local body
  body="$(cat <<EOF
## Team context (agent-plugin)

Lifecycle registration: \`$REGISTRATION_MARK\`.

At session start, read these plugin files and work from their context:

- $PLUGIN_ROOT/prompt.md — agent operating rules
- $PLUGIN_ROOT/security-posture.md — security and audit frame
- $PLUGIN_ROOT/lore.md — established project history and decisions
- $PLUGIN_ROOT/user.md — user profile
- $PLUGIN_ROOT/research/ — decision rationale, read on demand

At session start, run
\`python3 "$ARTIFACT_GENERATOR" session-context\` and complete the returned
instruction. You author the project dossiers yourself; the lifecycle script only
prepares the request, validates the files, and records freshness. When status is
\`ready\`, the command returns INDEX and every validated dossier in full. Use
that output as project memory instead of stopping at a path reference.

Do not reopen settled decisions without cause. If you propose a departure,
state what changed since the relevant research document.
EOF
)"
  if [ "$comment_style" = "html" ]; then
    printf '<!-- %s START -->\n%s\n<!-- %s END -->\n' "$MARK" "$body" "$MARK"
  else
    printf '# >>> %s >>>\n%s\n# <<< %s <<<\n' "$MARK" "$body" "$MARK"
  fi
}

# --- per-target install/uninstall -------------------------------------------

do_claude() {
  local file status
  file="$(claude_settings_file)"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || printf '{}\n' > "$file"
  if [ "$UNINSTALL" = 1 ]; then
    echo "claude: removing SessionStart/Stop hooks from $file"
    if ! status="$(json_hook "$file" bash uninstall hooks.SessionStart "$HOOK_SCRIPT" 15 "" session-start.sh)"; then
      die "claude: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  SessionStart removed" || echo "  SessionStart was not registered"
    if ! status="$(json_hook "$file" bash uninstall hooks.Stop "$STOP_HOOK_SCRIPT" 15 "" artifact-stop.sh)"; then
      die "claude: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  Stop removed" || echo "  Stop was not registered"
  else
    echo "claude: installing SessionStart/Stop hooks into $file"
    if grep -qF 'choirboy-prompt@choirboy-prompt' "$file" 2>/dev/null; then
      echo "  warning: marketplace plugin appears enabled in $file; manual hooks would run twice" >&2
    fi
    if ! status="$(json_hook "$file" bash install hooks.SessionStart "$HOOK_SCRIPT" 15 "" session-start.sh)"; then
      die "claude: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  SessionStart installed" || echo "  SessionStart already registered — skipped"
    if ! status="$(json_hook "$file" bash install hooks.Stop "$STOP_HOOK_SCRIPT" 15 "" artifact-stop.sh)"; then
      die "claude: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  Stop installed" || echo "  Stop already registered — skipped"
  fi
}

do_codex() {
  local file="$HOME/.codex/hooks.json"
  local command="bash \"$HOOK_SCRIPT\""
  local stop_command="bash \"$STOP_HOOK_SCRIPT\""
  local status
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || printf '{}\n' > "$file"
  if [ "$UNINSTALL" = 1 ]; then
    echo "codex: removing SessionStart/Stop hooks from $file"
    if ! status="$(json_hook "$file" "$command" uninstall hooks.SessionStart "" 15 "$CODEX_CONTEXT_LIMIT" session-start.sh)"; then
      die "codex: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  SessionStart removed" || echo "  SessionStart was not registered"
    if ! status="$(json_hook "$file" "$stop_command" uninstall hooks.Stop "" 15 "" artifact-stop.sh)"; then
      die "codex: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  Stop removed" || echo "  Stop was not registered"
  else
    echo "codex: installing SessionStart/Stop hooks into $file"
    if grep -qE '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*false' "$HOME/.codex/config.toml" 2>/dev/null; then
      echo "  warning: codex hooks are explicitly disabled in ~/.codex/config.toml" >&2
    fi
    if ! status="$(json_hook "$file" "$command" install hooks.SessionStart "" 15 "$CODEX_CONTEXT_LIMIT" session-start.sh)"; then
      die "codex: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  SessionStart installed (additionalContextLimit=$CODEX_CONTEXT_LIMIT)" || echo "  SessionStart already registered — skipped"
    if ! status="$(json_hook "$file" "$stop_command" install hooks.Stop "" 15 "" artifact-stop.sh)"; then
      die "codex: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  Stop installed" || echo "  Stop already registered — skipped"
  fi
}

do_opencode() {
  local file="$HOME/.config/opencode/plugins/agent-plugin.ts"
  local status
  if [ "$UNINSTALL" = 1 ]; then
    echo "opencode: removing model-context plugin from $file"
    if ! status="$(opencode_plugin "$file" uninstall)"; then
      die "opencode: refusing unsafe uninstall; inspect $file"
    fi
    [ "$status" = "changed" ] \
      && echo "  plugin removed (timestamped backup kept)" \
      || echo "  plugin was not installed"
  else
    echo "opencode: installing model-context plugin into $file"
    if ! status="$(opencode_plugin "$file" install)"; then
      die "opencode: refusing to overwrite an unmarked plugin; move it aside or merge manually"
    fi
    [ "$status" = "changed" ] \
      && echo "  plugin installed (model-bound lore delivery)" \
      || echo "  plugin already installed — skipped"
  fi
}

HERMES_HOOK_CMD="bash \"$HOOK_SCRIPT\" --format hermes"
HERMES_CONFIG_CMD="${HERMES_HOOK_CMD//\\/\\\\}"
HERMES_CONFIG_CMD="${HERMES_CONFIG_CMD//\"/\\\"}"

do_hermes() {
  local cfg="$HOME/.hermes/config.yaml"
  mkdir -p "$(dirname "$cfg")"
  [ -f "$cfg" ] || : > "$cfg"
  if [ "$UNINSTALL" = 1 ]; then
    echo "hermes: removing pre_llm_call hook from $cfg"
    block_remove "$cfg" "# >>> $MARK >>>" "# <<< $MARK <<<"
    hermes_allowlist "$HERMES_HOOK_CMD" uninstall >/dev/null
    echo "  consent allowlist entry removed"
  else
    echo "hermes: installing pre_llm_call hook into $cfg"
    if ! grep -qF "# >>> $MARK >>>" "$cfg" && grep -qE '^hooks:' "$cfg"; then
      die "hermes: $cfg already has a top-level 'hooks:' section — merge manually:
  hooks:
    pre_llm_call:
      - command: \"$HERMES_HOOK_CMD\"
        timeout: 15"
    fi
    chmod +x "$HOOK_SCRIPT"
    block_sync "$cfg" "# >>> $MARK >>>" "# <<< $MARK <<<" <<EOF
# >>> $MARK >>>
# $REGISTRATION_MARK
hooks:
  pre_llm_call:
    - command: "$HERMES_CONFIG_CMD"
      timeout: 15
# <<< $MARK <<<
EOF
    hermes_allowlist "$HERMES_HOOK_CMD" install >/dev/null
    echo "  consent allowlist entry added (pre_llm_call: $HERMES_HOOK_CMD)"
  fi
}

do_kimi() {
  local cfg="$KIMI_HOME/config.toml"
  mkdir -p "$(dirname "$cfg")"
  [ -f "$cfg" ] || : > "$cfg"
  if [ "$UNINSTALL" = 1 ]; then
    echo "kimi: removing SessionStart/PreCompact/UserPromptSubmit/Stop hooks from $cfg"
    block_remove "$cfg" "# >>> $MARK >>>" "# <<< $MARK <<<"
  else
    echo "kimi: installing SessionStart/PreCompact/UserPromptSubmit/Stop hooks into $cfg"
    if ! grep -qF "# >>> $MARK >>>" "$cfg" && grep -qE '^hooks[[:space:]]*=' "$cfg"; then
      die "kimi: $cfg already defines 'hooks =' — switch it to [[hooks]] entries or merge manually:
  [[hooks]]
  event = \"SessionStart\"
  command = \"bash \\\"$KIMI_SESSION_HOOK_SCRIPT\\\"\""
    fi
    chmod +x "$KIMI_SESSION_HOOK_SCRIPT" "$KIMI_PROMPT_HOOK_SCRIPT" "$KIMI_STOP_HOOK_SCRIPT"
    block_sync "$cfg" "# >>> $MARK >>>" "# <<< $MARK <<<" <<EOF
# >>> $MARK >>>
# $REGISTRATION_MARK
[[hooks]]
event = "SessionStart"
matcher = "^(startup|resume)$"
command = "bash \"$KIMI_SESSION_HOOK_SCRIPT\""
timeout = 30

[[hooks]]
event = "PreCompact"
matcher = "^(manual|auto)$"
command = "bash \"$KIMI_SESSION_HOOK_SCRIPT\""
timeout = 30

[[hooks]]
event = "UserPromptSubmit"
command = "bash \"$KIMI_PROMPT_HOOK_SCRIPT\""
timeout = 30

[[hooks]]
event = "Stop"
command = "bash \"$KIMI_STOP_HOOK_SCRIPT\""
timeout = 30
# <<< $MARK <<<
EOF
  fi
}

do_gemini() {
  do_instructions "$HOME/.gemini/GEMINI.md" html "gemini"
}

do_grok() {
  do_instructions "$HOME/.grok/AGENTS.md" html "grok"
}

do_grokbot() {
  local file="$HOME/.grokbot/choirboy-context/SKILL.md"
  local legacy="$HOME/.grokbot/AGENTS.md"
  local status

  # Migrate the unsupported pointer written by the initial Grok Bot adapter.
  if grep -qF "<!-- $MARK START -->" "$legacy" 2>/dev/null; then
    echo "grokbot: removing legacy instruction block from $legacy"
    block_remove "$legacy" "<!-- $MARK START -->" "<!-- $MARK END -->"
  fi

  if [ "$UNINSTALL" = 1 ]; then
    echo "grokbot: removing prepared workflow from $file"
    if ! status="$(grokbot_workflow "$file" uninstall)"; then
      die "grokbot: refusing unsafe uninstall; inspect $file"
    fi
    [ "$status" = "changed" ] \
      && echo "  prepared workflow removed (delete an already imported workflow in Grok Bot manually)" \
      || echo "  prepared workflow was not present"
  else
    echo "grokbot: preparing importable workflow at $file"
    if ! status="$(grokbot_workflow "$file" install)"; then
      die "grokbot: refusing to overwrite an unmarked workflow; move it aside or merge manually"
    fi
    [ "$status" = "changed" ] \
      && echo "  workflow prepared" \
      || echo "  workflow already current — skipped"
    echo "  next: import/link this SKILL.md in Grok Bot Workflows, then run @choirboy-context in each new chat"
  fi
}

# do_instructions FILE STYLE LABEL — managed pointer block for any agent
# that reads an instructions file at session start.
do_instructions() {
  local file="$1" style="$2" label="$3"
  local start end
  if [ "$style" = "html" ]; then
    start="<!-- $MARK START -->"; end="<!-- $MARK END -->"
  else
    start="# >>> $MARK >>>"; end="# <<< $MARK <<<"
  fi
  if [ "$UNINSTALL" = 1 ]; then
    echo "$label: removing instruction block from $file"
    block_remove "$file" "$start" "$end"
  else
    echo "$label: installing instruction block into $file"
    instruction_block "$style" | block_sync "$file" "$start" "$end"
  fi
}

# Print checkout-local artifact directories referenced by current or legacy
# registrations. The lifecycle migrates the first usable bundle into its
# stable user-data root before registrations are rewritten to this checkout.
discover_legacy_artifact_roots() {
  python3 - "$(claude_settings_file)" \
    "$HOME/.codex/hooks.json" \
    "$HOME/.config/opencode/plugins/agent-plugin.ts" \
    "$HOME/.hermes/config.yaml" \
    "$KIMI_HOME/config.toml" \
    "$HOME/.gemini/GEMINI.md" \
    "$HOME/.grok/AGENTS.md" \
    "${INSTRUCTIONS_FILES[@]}" <<'PY'
import re, sys
from pathlib import Path

patterns = (
    re.compile(r'(?P<root>(?:[A-Za-z]:)?/[^"\n\r`]*?)/hooks/session-start[.]sh'),
    re.compile(r'(?P<root>(?:[A-Za-z]:)?/[^"\n\r`]*?)/scripts/artifact-generator[.]py'),
    re.compile(r'(?P<root>(?:[A-Za-z]:)?/[^"\n\r`]*?)/prompt[.]md'),
)
seen = set()
for name in sys.argv[1:]:
    path = Path(name)
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    normalized = text.replace("\\", "/")
    for pattern in patterns:
        for match in pattern.finditer(normalized):
            root = match.group("root").strip()
            candidate = f"{root}/artifacts"
            if candidate not in seen:
                seen.add(candidate)
                print(candidate)
PY
}

# --- main -------------------------------------------------------------------

if [ "$LIST_ONLY" = 1 ]; then
  printf '%-8s %-10s %s\n' TARGET STATUS LOCATION
  for t in $ALL_TARGETS; do
    if ! target_present "$t"; then
      printf '%-8s %-10s %s\n' "$t" "absent" "-"
      continue
    fi
    if target_installed "$t"; then
      if [ "$t" = "grokbot" ]; then s="prepared"; else s="installed"; fi
    elif target_managed_present "$t"; then
      s="stale"
    else
      s="detected"
    fi
    case "$t" in
      claude) loc="$(claude_settings_file)" ;;
      codex)  loc="$HOME/.codex/hooks.json" ;;
      opencode) loc="$HOME/.config/opencode/plugins/agent-plugin.ts" ;;
      hermes) loc="$HOME/.hermes/config.yaml" ;;
      kimi)   loc="$KIMI_HOME/config.toml" ;;
      gemini) loc="$HOME/.gemini/GEMINI.md" ;;
      grok)   loc="$HOME/.grok/AGENTS.md" ;;
      grokbot) loc="$HOME/.grokbot/choirboy-context/SKILL.md" ;;
    esac
    printf '%-8s %-10s %s\n' "$t" "$s" "$loc"
  done
  exit 0
fi

[ -n "$TARGETS" ] || [ ${#INSTRUCTIONS_FILES[@]} -gt 0 ] \
  || die "no agent runtimes detected; use --target or --instructions"

if [ "$UNINSTALL" = 0 ]; then
  [ -f "$ARTIFACT_GENERATOR" ] || die "artifact lifecycle is missing: $ARTIFACT_GENERATOR"
  migration_args=(--migrate-from "$PLUGIN_ROOT/artifacts")
  while IFS= read -r legacy_root; do
    [ -n "$legacy_root" ] && migration_args+=(--migrate-from "$legacy_root")
  done < <(discover_legacy_artifact_roots)
  if ! artifact_status="$(python3 "$ARTIFACT_GENERATOR" prepare "${migration_args[@]}")"; then
    die "could not prepare the agent-authored artifact lifecycle"
  fi
  echo "agent-plugin: artifact lifecycle prepared — $artifact_status"
fi

for t in $TARGETS; do
  case "$t" in
    claude|codex|opencode|hermes|kimi|gemini|grok|grokbot) "do_$t" ;;
    *) die "unknown target: $t (known: $(echo "$ALL_TARGETS" | tr ' ' ','))" ;;
  esac
done

for f in ${INSTRUCTIONS_FILES[@]+"${INSTRUCTIONS_FILES[@]}"}; do
  case "$f" in
    *.md|*.markdown) style="html" ;;
    *) style="hash" ;;
  esac
  do_instructions "$f" "$style" "file:$f"
done

if [ "$UNINSTALL" = 1 ]; then
  echo "agent-plugin: uninstall complete"
else
  echo "agent-plugin: install complete — the next agent session will author or load project artifacts"
fi
