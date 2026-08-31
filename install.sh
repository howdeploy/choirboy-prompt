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
#                                         chat.message plugin (first message)
#   hermes   ~/.hermes/config.yaml       pre_llm_call shell hook + consent allowlist
#   kimi     ~/.kimi-code/config.toml    [[hooks]] SessionStart block
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
HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session-start.sh"
STOP_HOOK_SCRIPT="$PLUGIN_ROOT/hooks/artifact-stop.sh"
ARTIFACT_GENERATOR="$PLUGIN_ROOT/scripts/artifact-generator.py"
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
    kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "$HOME/.kimi-code" ] ;;
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

target_installed() {
  case "$1" in
    claude) grep -qF "session-start.sh" "$(claude_settings_file)" 2>/dev/null \
              && grep -qF "artifact-stop.sh" "$(claude_settings_file)" 2>/dev/null ;;
    codex)  grep -qF "session-start.sh" "$HOME/.codex/hooks.json" 2>/dev/null \
              && grep -qF "artifact-stop.sh" "$HOME/.codex/hooks.json" 2>/dev/null ;;
    opencode) grep -qF "$MARK" "$HOME/.config/opencode/plugins/agent-plugin.ts" 2>/dev/null ;;
    hermes) grep -qF "$MARK" "$HOME/.hermes/config.yaml" 2>/dev/null ;;
    kimi)   grep -qF "$MARK" "$HOME/.kimi-code/config.toml" 2>/dev/null ;;
    gemini) grep -qF "$MARK" "$HOME/.gemini/GEMINI.md" 2>/dev/null ;;
    grok)   grep -qF "$MARK" "$HOME/.grok/AGENTS.md" 2>/dev/null ;;
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

# block_add FILE START_LINE — append the block read on stdin unless
# START_LINE is already present in FILE.
block_add() {
  local file="$1" start="$2"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
  if grep -qF "$start" "$file"; then
    echo "  already present in $file — skipped"
    return 0
  fi
  backup "$file"
  { printf '\n'; cat; } >> "$file"
  echo "  block added to $file"
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
# CONTEXT_LIMIT prevents Codex from spilling a large SessionStart payload.
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

# opencode_plugin FILE install|uninstall — manage the OpenCode chat.message
# adapter as a complete, marked file. The installed module calls the canonical
# plain-format hook once per session and injects its output as a marked text part.
opencode_plugin() {
  PLUGIN_FILE="$1" MODE="$2" HOOK_PATH="$HOOK_SCRIPT" INSTALL_MARK="$MARK" \
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

template = r'''// >>> agent-plugin:vibe-lore >>>
// OpenCode adapter for choirboy-prompt.
// Injects the canonical fixed lore once per session as a marked text part.
// Fail-open: a missing hook, timeout, or malformed payload never blocks chat.

import { spawnSync } from "child_process"
import { randomUUID } from "crypto"
import type { Plugin } from "@opencode-ai/plugin"

const HOOK_SCRIPT = __HOOK_SCRIPT__
const DELIVERY_MARKER = "<choirboy-delivery "
const MAX_TRACKED_SESSIONS = 4096
const deliveredSessions = new Set<string>()

function rememberSession(sessionID: string) {
  if (deliveredSessions.size >= MAX_TRACKED_SESSIONS) {
    const oldest = deliveredSessions.values().next().value
    if (typeof oldest === "string") deliveredSessions.delete(oldest)
  }
  deliveredSessions.add(sessionID)
}

export const AgentPlugin: Plugin = async ({ client, directory }) => {
  return {
    "chat.message": async (input, output) => {
      try {
        const sessionID = typeof input.sessionID === "string" ? input.sessionID : ""
        if (!sessionID) return

        const parts = output.parts as any[]
        if (!Array.isArray(parts)) return
        if (
          parts.some(
            (part) =>
              part &&
              part.type === "text" &&
              typeof part.text === "string" &&
              part.text.includes(DELIVERY_MARKER),
          )
        ) {
          rememberSession(sessionID)
          return
        }
        if (deliveredSessions.has(sessionID)) return

        // The in-memory set covers a long-running TUI/server process. The
        // persisted session history also prevents duplicate delivery when a
        // headless session is resumed by a fresh OpenCode process.
        const historyResult = await client.session.messages({
          path: { id: sessionID },
          query: { directory },
        })
        const history = historyResult.data
        if (!Array.isArray(history)) return
        if (
          history.some(
            (message) =>
              message.info.role === "user" &&
              message.parts.some(
                (part) =>
                  part.type === "text" &&
                  part.synthetic === true &&
                  part.text.includes(DELIVERY_MARKER),
              ),
          )
        ) {
          rememberSession(sessionID)
          return
        }

        const result = spawnSync("bash", [HOOK_SCRIPT, "--format", "plain"], {
          encoding: "utf8",
          timeout: 15000,
          maxBuffer: 2 * 1024 * 1024,
        })
        const injected = (result.stdout ?? "").trim()
        if (
          result.status !== 0 ||
          !injected.includes("<choirboy-delivery ") ||
          !injected.includes("<choirboy-context>")
        ) {
          return
        }

        parts.unshift({
          id: `prt_choirboy_${randomUUID().replaceAll("-", "")}`,
          sessionID,
          messageID: output.message.id,
          type: "text",
          text: injected,
          synthetic: true,
        })
        rememberSession(sessionID)
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

def backup() -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}.{os.getpid()}")
    shutil.copy2(path, destination)
    return destination

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
    INSTALL_MARK="$MARK" python3 - <<'PY'
import os
import shutil
import sys
import time
from pathlib import Path

path = Path(os.environ["WORKFLOW_FILE"])
mode = os.environ["MODE"]
source_path = Path(os.environ["SOURCE_SKILL"])
mark = os.environ["INSTALL_MARK"]

def backup() -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}.{os.getpid()}")
    shutil.copy2(path, destination)
    return destination

if mode == "install":
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
    content = content[:insert_at] + f"\n<!-- {mark}: managed Grok Bot workflow -->\n" + content[insert_at:]

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
    if any(is_ours(a) for a in approvals):
        status = "unchanged"
    else:
        approvals.append({"event": "pre_llm_call", "command": cmd})
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
## Лор команды (agent-plugin)

В начале сессии прочитай файлы плагина и работай из этого контекста:

- $PLUGIN_ROOT/prompt.md — правила работы агента
- $PLUGIN_ROOT/security-posture.md — позиция по безопасности (рамка аудита)
- $PLUGIN_ROOT/lore.md — история совместных решений
- $PLUGIN_ROOT/user.md — профиль пользователя
- $PLUGIN_ROOT/research/ — обоснования решений (читай по требованию)

В начале сессии запусти
\`python3 "$ARTIFACT_GENERATOR" session-context\` и выполни выданную инструкцию.
Содержимое проектных dossiers создаёшь ты сам; lifecycle-скрипт только готовит
request, проверяет файлы и фиксирует их свежесть. При статусе \`ready\` сначала
прочитай \`artifacts/INDEX.md\` и dossier нужного домена.

Не переоткрывай зафиксированные там решения без причины; если предлагаешь
отступить — скажи, что изменилось со времени соответствующего документа.
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
    if ! status="$(json_hook "$file" "$command" uninstall hooks.SessionStart "" 15 20000 session-start.sh)"; then
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
    if ! status="$(json_hook "$file" "$command" install hooks.SessionStart "" 15 20000 session-start.sh)"; then
      die "codex: refusing to edit invalid hook settings in $file"
    fi
    [ "$status" = "changed" ] && echo "  SessionStart installed (additionalContextLimit=20000)" || echo "  SessionStart already registered — skipped"
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
    echo "opencode: removing chat.message plugin from $file"
    if ! status="$(opencode_plugin "$file" uninstall)"; then
      die "opencode: refusing unsafe uninstall; inspect $file"
    fi
    [ "$status" = "changed" ] \
      && echo "  plugin removed (timestamped backup kept)" \
      || echo "  plugin was not installed"
  else
    echo "opencode: installing chat.message plugin into $file"
    if ! status="$(opencode_plugin "$file" install)"; then
      die "opencode: refusing to overwrite an unmarked plugin; move it aside or merge manually"
    fi
    [ "$status" = "changed" ] \
      && echo "  plugin installed (first-message lore injection)" \
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
    block_add "$cfg" "# >>> $MARK >>>" <<EOF
# >>> $MARK >>>
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
  local cfg="$HOME/.kimi-code/config.toml"
  mkdir -p "$(dirname "$cfg")"
  [ -f "$cfg" ] || : > "$cfg"
  if [ "$UNINSTALL" = 1 ]; then
    echo "kimi: removing SessionStart hook from $cfg"
    block_remove "$cfg" "# >>> $MARK >>>" "# <<< $MARK <<<"
  else
    echo "kimi: installing SessionStart hook into $cfg"
    if ! grep -qF "# >>> $MARK >>>" "$cfg" && grep -qE '^hooks[[:space:]]*=' "$cfg"; then
      die "kimi: $cfg already defines 'hooks =' — switch it to [[hooks]] entries or merge manually:
  [[hooks]]
  event = \"SessionStart\"
  command = \"bash \\\"$HOOK_SCRIPT\\\" --format plain\""
    fi
    block_add "$cfg" "# >>> $MARK >>>" <<EOF
# >>> $MARK >>>
[[hooks]]
event = "SessionStart"
command = "bash \"$HOOK_SCRIPT\" --format plain"
timeout = 15
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
    instruction_block "$style" | block_add "$file" "$start"
  fi
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
    else
      s="detected"
    fi
    case "$t" in
      claude) loc="$(claude_settings_file)" ;;
      codex)  loc="$HOME/.codex/hooks.json" ;;
      opencode) loc="$HOME/.config/opencode/plugins/agent-plugin.ts" ;;
      hermes) loc="$HOME/.hermes/config.yaml" ;;
      kimi)   loc="$HOME/.kimi-code/config.toml" ;;
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
  if ! artifact_status="$(python3 "$ARTIFACT_GENERATOR" prepare)"; then
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
