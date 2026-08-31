#!/usr/bin/env bash
# agent-plugin — session-start hook.
#
# Builds the plugin's fixed context, appends agent-authored artifact state, and
# emits both in the format the calling runtime expects. The canonical fixed
# sources also generate skills/load-context/SKILL.md.
#
#   --format claude   Claude Code / Codex SessionStart JSON (default):
#                     {"hookSpecificOutput": {"hookEventName": "SessionStart",
#                      "additionalContext": ...}}
#   --format plain    Raw context text on stdout (runtimes that append hook
#                     stdout to the session context, e.g. Kimi Code).
#   --format hermes   Hermes shell-hook protocol (pre_llm_call): reads the
#                     JSON payload from stdin, delivers only on the first turn
#                     of a session, answers {"context": ...} or {}.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FORMAT="claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:?--format requires a value}"; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "session-start.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

VERSION="$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -n1)"

payload=""
for f in prompt.md security-posture.md lore.md user.md context/research-index.md; do
  if [ -f "$PLUGIN_ROOT/$f" ]; then
    fragment="$(cat "$PLUGIN_ROOT/$f")"
    # Keep hook and generated-skill hashes identical on Windows and for
    # user-edited CRLF content, regardless of Git checkout configuration.
    fragment="${fragment//$'\r'/}"
    [ -n "$payload" ] && payload="$payload"$'\n\n---\n\n'
    payload="$payload$fragment"
  else
    echo "agent-plugin: $f missing — skipped" >&2
  fi
done

payload_sha256() {
  local digest rest
  if command -v sha256sum >/dev/null 2>&1; then
    read -r digest rest < <(printf '%s\n' "$payload" | sha256sum)
    printf '%s' "$digest"
  elif command -v shasum >/dev/null 2>&1; then
    read -r digest rest < <(printf '%s\n' "$payload" | shasum -a 256)
    printf '%s' "$digest"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$payload" | python3 -c \
      'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  else
    printf 'unavailable'
  fi
}

CONTEXT_SHA256="$(payload_sha256)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf 'unknown-time')"
NONCE="${STAMP}-$$"
DELIVERY_MARKER="<choirboy-delivery version=\"${VERSION:-unknown}\" delivery=\"session-start\" context_sha256=\"$CONTEXT_SHA256\" nonce=\"$NONCE\" />"
payload="$DELIVERY_MARKER"$'\n'"<choirboy-context>"$'\n'"$payload"$'\n'"</choirboy-context>"

# The lifecycle script only prepares/validates state. The currently running
# agent receives the actual authoring job in this context and writes every
# dossier itself. Keep this outside <choirboy-context> so the canonical lore
# hash remains identical to the generated load-context skill.
artifact_generator="$PLUGIN_ROOT/scripts/artifact-generator.py"
artifact_context=""
if command -v python3 >/dev/null 2>&1 && [ -f "$artifact_generator" ]; then
  if ! artifact_context="$(python3 "$artifact_generator" session-context)"; then
    echo "agent-plugin: artifact lifecycle could not be prepared" >&2
    artifact_context='<choirboy-project-artifacts status="unavailable">Artifact lifecycle failed to initialize; inspect the SessionStart hook stderr.</choirboy-project-artifacts>'
  fi
else
  artifact_context='<choirboy-project-artifacts status="unavailable">Automatic project artifacts require python3 and scripts/artifact-generator.py.</choirboy-project-artifacts>'
fi
payload="$payload"$'\n'"$artifact_context"

# Marketplace plugins receive a persistent data directory. Record only delivery
# metadata there, never the lore itself, so a silent hook failure is observable.
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  diagnostic_tmp="$CLAUDE_PLUGIN_DATA/latest-delivery.tmp.$$"
  {
    printf 'version=%s\n' "${VERSION:-unknown}"
    printf 'delivery=session-start\n'
    printf 'context_sha256=%s\n' "$CONTEXT_SHA256"
    printf 'nonce=%s\n' "$NONCE"
    printf 'plugin_root=%s\n' "$PLUGIN_ROOT"
  } > "$diagnostic_tmp"
  mv "$diagnostic_tmp" "$CLAUDE_PLUGIN_DATA/latest-delivery.log"
fi

# json_quote VALUE — encode a Bash string as a JSON string without external
# dependencies. Bash variables cannot contain NUL; every other JSON control
# character is escaped, while UTF-8 bytes are preserved as-is.
json_quote() {
  local value="${1-}" out="" char escaped code i
  local LC_ALL=C
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      '"') out+='\"' ;;
      $'\\') out+="\\\\" ;;
      $'\b') out+='\b' ;;
      $'\f') out+='\f' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *)
        printf -v code '%d' "'$char"
        if [ "$code" -lt 32 ]; then
          printf -v escaped '\\u%04x' "$code"
          out+="$escaped"
        else
          out+="$char"
        fi
        ;;
    esac
  done
  printf '"%s"' "$out"
}

# emit_json KEY — print a flat JSON object {"KEY": payload} on stdout.
emit_json() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -Rs --arg k "$1" '{($k): .}'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json, sys
print(json.dumps({sys.argv[1]: sys.stdin.read()}, ensure_ascii=False))
' "$1"
  else
    printf '{"%s":%s}\n' "$1" "$(json_quote "$payload")"
  fi
}

# json_field FIELD — extract a scalar field from the JSON document on stdin.
json_field() {
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1 | select(. != null)" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    EXPR="$1" python3 -c '
import json, os, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(0)
node = doc
for part in os.environ["EXPR"].strip(".").split("."):
    if not isinstance(node, dict):
        node = None
        break
    node = node.get(part)
if isinstance(node, bool):
    print("true" if node else "false")
elif node is not None:
    print(node)
'
  else
    echo "agent-plugin: Hermes format requires jq or python3" >&2
    return 1
  fi
}

case "$FORMAT" in
  claude)
    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$payload" | jq -Rs \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
    elif command -v python3 >/dev/null 2>&1; then
      printf '%s' "$payload" | python3 -c '
import json, sys
print(json.dumps(
    {"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.stdin.read(),
    }},
    ensure_ascii=False,
))
'
    else
      printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
        "$(json_quote "$payload")"
    fi
    ;;

  plain)
    printf '%s\n' "$payload"
    ;;

  hermes)
    # Hermes runs this as a pre_llm_call shell hook: JSON payload on stdin,
    # JSON answer on stdout. Deliver only on the first turn of a session —
    # repeating the full lore on every turn would bloat the context.
    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
      echo "agent-plugin: Hermes format requires jq or python3" >&2
      exit 1
    fi
    input="$(cat 2>/dev/null || true)"
    first=""
    sid=""
    if [ -n "$input" ]; then
      first="$(printf '%s' "$input" | json_field .extra.is_first_turn)"
      sid="$(printf '%s' "$input" | json_field .session_id)"
    fi
    if [ "$first" = "false" ]; then
      printf '{}\n'
      exit 0
    fi
    # Fallback for payloads without is_first_turn: deliver once per session_id.
    state="${TMPDIR:-/tmp}/agent-plugin-hermes-${USER:-user}.state"
    if [ "$first" != "true" ]; then
      if [ -z "$sid" ] || grep -qxF "$sid" "$state" 2>/dev/null; then
        printf '{}\n'
        exit 0
      fi
    fi
    if [ -n "$sid" ]; then
      printf '%s\n' "$sid" >> "$state"
      tail -n 200 "$state" > "$state.tmp" && mv "$state.tmp" "$state"
    fi
    emit_json context
    ;;

  *)
    echo "session-start.sh: unknown format: $FORMAT" >&2
    exit 1
    ;;
esac
