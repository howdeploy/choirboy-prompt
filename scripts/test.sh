#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(python3 -c 'import json; print(json.load(open(".claude-plugin/plugin.json", encoding="utf-8"))["version"])')"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/choirboy-test.XXXXXX")"
export CHOIRBOY_ARTIFACTS_DIR="$TEST_ROOT/project-artifacts"
cleanup() {
  if [ "${CHOIRBOY_TEST_KEEP_TMP:-0}" = 1 ]; then
    printf 'Test artifacts preserved at %s\n' "$TEST_ROOT"
  else
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

pass() { printf 'PASS %s\n' "$1"; }

# Git Bash on hosted Windows runners may emulate `ln -s` with plain files when
# symlink creation is unavailable. Small wrappers keep the dependency-isolation
# tests portable without copying executables away from their runtime libraries.
install_test_command() {
  local destination="$1" command="$2" source
  source="$(command -v "$command")"
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$source" > "$destination/$command"
  chmod +x "$destination/$command"
}

python3 scripts/build-context.py --check >/dev/null
pass "generated context skill"

list_copy="$TEST_ROOT/list-copy"
mkdir -p "$list_copy/scripts" "$list_copy/skills/load-context" "$TEST_ROOT/list-home"
cp install.sh "$list_copy/"
cp scripts/build-context.py "$list_copy/scripts/"
printf 'stale sentinel\n' > "$list_copy/skills/load-context/SKILL.md"
HOME="$TEST_ROOT/list-home" CHOIRBOY_ARTIFACTS_DIR="$TEST_ROOT/list-artifacts" \
  bash "$list_copy/install.sh" --list >/dev/null
grep -qxF 'stale sentinel' "$list_copy/skills/load-context/SKILL.md"
test ! -e "$TEST_ROOT/list-artifacts"
pass "list mode is read-only"

python3 - <<'PY'
import json
from pathlib import Path

plugin = json.loads(Path(".claude-plugin/plugin.json").read_text(encoding="utf-8"))
market = json.loads(Path(".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
hooks = json.loads(Path("hooks/hooks.json").read_text(encoding="utf-8"))
entry = market["plugins"][0]
handler = hooks["hooks"]["SessionStart"][0]["hooks"][0]
stop_handler = hooks["hooks"]["Stop"][0]["hooks"][0]
assert plugin["name"] == entry["name"] == "choirboy-prompt"
assert plugin["version"] == entry["version"]
assert handler["command"] == "bash"
assert handler["args"] == ["${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"]
assert handler["timeout"] == 15
assert stop_handler == {
    "type": "command",
    "command": "bash",
    "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/artifact-stop.sh"],
    "timeout": 15,
}
PY
pass "manifests and lifecycle hooks"

claude plugin validate . >/dev/null
pass "Claude plugin validator"

python3 scripts/artifact-generator.py prepare --json > "$TEST_ROOT/artifact-pending.json"
python3 scripts/artifact-generator.py session-context > "$TEST_ROOT/artifact-pending.txt"
python3 - "$CHOIRBOY_ARTIFACTS_DIR" "$TEST_ROOT/artifact-pending.json" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
status = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
assert status["status"] == "pending"
assert status["project_count"] == len(request["projects"]) == 12
assert not (root / "INDEX.md").exists()
assert not (root / ".artifact-manifest.json").exists()
assert not any(path.is_file() for path in (root / "projects").iterdir())
assert request["projects"][0]["title"] == "18+ контент и генерация"
assert request["projects"][-1]["title"] == "Читы для соло-игр"
router = next(
    project
    for project in request["projects"]
    if project["title"] == "Роутер reverse engineering и security-задач"
)
assert router["research"] == [
    f"research/{number:02d}-{name}.md"
    for number, name in (
        (22, "security-capability-router"),
        (23, "security-case-and-evidence-contract"),
        (24, "security-tool-registry-and-bootstrap"),
        (25, "reverse-engineering-capability-map"),
        (26, "application-infrastructure-security-map"),
        (27, "exploitation-malware-forensics-and-detection"),
        (28, "llm-agent-and-skill-supply-chain-security"),
        (29, "ctf-sandbox-orchestration"),
        (30, "security-reporting-and-knowledge-reuse"),
    )
]
PY
grep -q '<choirboy-project-artifacts status="pending"' "$TEST_ROOT/artifact-pending.txt"
grep -q 'Выполни его сам через доступные' "$TEST_ROOT/artifact-pending.txt"
pass "artifact prepare creates request metadata only"

printf '{}\n' | bash hooks/artifact-stop.sh > "$TEST_ROOT/artifact-stop-pending.json"
printf '{"stop_hook_active":true}\n' \
  | bash hooks/artifact-stop.sh > "$TEST_ROOT/artifact-stop-active.json"
printf 'malformed\n' | bash hooks/artifact-stop.sh > "$TEST_ROOT/artifact-stop-malformed.json"
python3 - "$TEST_ROOT/artifact-stop-pending.json" \
  "$TEST_ROOT/artifact-stop-active.json" "$TEST_ROOT/artifact-stop-malformed.json" <<'PY'
import json, sys
from pathlib import Path

pending, active, malformed = [
    json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[1:]
]
assert pending["decision"] == "block"
assert "незавершённый bootstrap" in pending["reason"]
assert active == malformed == {}
PY
pass "Stop returns unfinished bootstrap to the same agent once"

# These temporary files stand in for file-tool writes by the runtime agent.
# Production lifecycle code is forbidden from synthesizing dossier content.
python3 - "$CHOIRBOY_ARTIFACTS_DIR" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
index = ["# Проектные артефакты", ""]
for project in request["projects"]:
    index.append(f"- [{project['title']}]({project['artifact']})")
    document = [f"# {project['title']}", ""]
    for section in request["required_sections"]:
        document.extend([f"## {section}", ""])
        if section == "Источники":
            for source in ["lore.md", *project["research"]]:
                document.append(f"- `{source}`")
            document.append("- Канонический набор источников проверен агентом.")
        else:
            document.append("Зафиксировано runtime-agent по каноническим источникам проекта.")
        document.append("")
    (root / project["artifact"]).write_text("\n".join(document), encoding="utf-8")
(root / "INDEX.md").write_text("\n".join(index) + "\n", encoding="utf-8")
PY
printf '# unexpected dossier\n' > "$CHOIRBOY_ARTIFACTS_DIR/projects/unexpected.md"
if python3 scripts/artifact-generator.py finalize >/dev/null 2>&1; then
  echo "artifact validator accepted an extra dossier" >&2
  exit 1
fi
mv "$CHOIRBOY_ARTIFACTS_DIR/projects/unexpected.md" "$TEST_ROOT/unexpected.fixture"
python3 scripts/artifact-generator.py finalize --json > "$TEST_ROOT/artifact-ready.json"
python3 scripts/artifact-generator.py session-context > "$TEST_ROOT/artifact-ready.txt"
python3 - "$CHOIRBOY_ARTIFACTS_DIR" "$TEST_ROOT/artifact-ready.json" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
status = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
manifest = json.loads((root / ".artifact-manifest.json").read_text(encoding="utf-8"))
assert status["status"] == "ready"
assert manifest["content_author"] == "runtime-agent"
assert len(manifest["projects"]) == 12
PY
grep -q '<choirboy-project-artifacts status="ready"' "$TEST_ROOT/artifact-ready.txt"
grep -q 'сначала прочитай INDEX' "$TEST_ROOT/artifact-ready.txt"
pass "agent-authored artifacts finalize and become runtime memory"

first_artifact="$(python3 - "$CHOIRBOY_ARTIFACTS_DIR" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
print(root / request["projects"][0]["artifact"])
PY
)"
printf '\n<!-- freshness drift -->\n' >> "$first_artifact"
test "$(python3 scripts/artifact-generator.py status)" = pending
python3 scripts/artifact-generator.py finalize >/dev/null
test "$(python3 scripts/artifact-generator.py status)" = ready
pass "artifact hash drift invalidates freshness"

market_config="$TEST_ROOT/claude-config"
CLAUDE_CONFIG_DIR="$market_config" claude plugin marketplace add "$ROOT" >/dev/null
CLAUDE_CONFIG_DIR="$market_config" \
  claude plugin install choirboy-prompt@choirboy-prompt >/dev/null
CLAUDE_CONFIG_DIR="$market_config" claude plugin list --json > "$TEST_ROOT/plugins.json"
python3 - "$TEST_ROOT/plugins.json" "$VERSION" <<'PY'
import json, sys
from pathlib import Path

plugins = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plugin = next(item for item in plugins if item["id"] == "choirboy-prompt@choirboy-prompt")
assert plugin["version"] == sys.argv[2]
assert plugin["enabled"] is True
install = Path(plugin["installPath"])
assert (install / "hooks/hooks.json").is_file()
assert (install / "hooks/artifact-stop.sh").is_file()
assert (install / "scripts/artifact-generator.py").is_file()
assert (install / "skills/load-context/SKILL.md").is_file()
assert (install / "skills/diagnose/SKILL.md").is_file()
assert (install / "sessions/README.md").is_file()
assert (install / "sessions/claude/fa1ce000-0000-4000-8000-0000000000c1.jsonl").is_file()
PY
pass "isolated marketplace install"

CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugin-data" \
  bash hooks/session-start.sh --format claude > "$TEST_ROOT/claude.json"
python3 - "$TEST_ROOT/claude.json" "$VERSION" <<'PY'
import json, re, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
context = doc["hookSpecificOutput"]["additionalContext"]
version = re.escape(sys.argv[2])
assert doc["hookSpecificOutput"]["hookEventName"] == "SessionStart"
hook_marker = re.search(rf'<choirboy-delivery version="{version}" delivery="session-start" context_sha256="([0-9a-f]{{64}})" nonce="[^"]+" />', context)
skill_marker = re.search(rf'<choirboy-delivery version="{version}" delivery="skill" context_sha256="([0-9a-f]{{64}})" />', Path("skills/load-context/SKILL.md").read_text(encoding="utf-8"))
assert hook_marker and skill_marker and hook_marker.group(1) == skill_marker.group(1)
assert "<choirboy-context>" in context and "</choirboy-context>" in context
assert '<choirboy-project-artifacts status="ready"' in context
assert "# Prompt" in context and "## Research — обоснования решений" in context
PY
test -s "$TEST_ROOT/plugin-data/latest-delivery.log"
if grep -q -- '--arg ctx' hooks/session-start.sh; then
  echo "hook must stream the lore to JSON encoders, not pass it through argv" >&2
  exit 1
fi
pass "Claude payload and delivery diagnostic"

bash hooks/session-start.sh --format plain > "$TEST_ROOT/plain.txt"
grep -q "<choirboy-delivery version=\"$VERSION\" delivery=\"session-start\"" "$TEST_ROOT/plain.txt"
pass "plain payload"

sid="test-$$-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$sid" \
  | bash hooks/session-start.sh --format hermes > "$TEST_ROOT/hermes-first.json"
python3 - "$TEST_ROOT/hermes-first.json" <<'PY'
import json, sys
from pathlib import Path
assert "context" in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
printf '{"session_id":"%s","extra":{"is_first_turn":false}}' "$sid" \
  | bash hooks/session-start.sh --format hermes > "$TEST_ROOT/hermes-second.json"
grep -qx '{}' "$TEST_ROOT/hermes-second.json"
pass "Hermes first-turn gate"

python_path="$TEST_ROOT/python-bin"
mkdir -p "$python_path"
for command in cat date dirname head mkdir mv python3 sed tail; do
  install_test_command "$python_path" "$command"
done
PATH="$python_path" /bin/bash -c \
  'printf '\''{"session_id":"python-only","extra":{"is_first_turn":true}}'\'' | /bin/bash hooks/session-start.sh --format hermes' \
  > "$TEST_ROOT/hermes-python.json"
python3 - "$TEST_ROOT/hermes-python.json" <<'PY'
import json, sys
from pathlib import Path
assert "context" in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
pass "Hermes Python parser without jq"

minimal_path="$TEST_ROOT/minimal-bin"
mkdir -p "$minimal_path"
for command in cat date dirname head mkdir mv sed; do
  install_test_command "$minimal_path" "$command"
done
PATH="$minimal_path" /bin/bash hooks/session-start.sh --format claude > "$TEST_ROOT/minimal.json"
python3 -m json.tool "$TEST_ROOT/minimal.json" >/dev/null
grep -q 'context_sha256=\\"unavailable\\"' "$TEST_ROOT/minimal.json"
pass "dependency-free Bash JSON fallback"

missing_root="$TEST_ROOT/missing-content"
mkdir -p "$missing_root/hooks" "$missing_root/.claude-plugin"
cp hooks/session-start.sh "$missing_root/hooks/"
cp .claude-plugin/plugin.json "$missing_root/.claude-plugin/"
bash "$missing_root/hooks/session-start.sh" --format plain > "$TEST_ROOT/missing.txt" 2>/dev/null
grep -q '<choirboy-context>' "$TEST_ROOT/missing.txt"
pass "graceful missing-content mode"

crlf_root="$TEST_ROOT/crlf-content"
mkdir -p "$crlf_root/hooks" "$crlf_root/.claude-plugin" \
  "$crlf_root/context" "$crlf_root/skills/load-context"
cp hooks/session-start.sh "$crlf_root/hooks/"
cp .claude-plugin/plugin.json "$crlf_root/.claude-plugin/"
cp skills/load-context/SKILL.md "$crlf_root/skills/load-context/"
cp prompt.md security-posture.md lore.md user.md "$crlf_root/"
cp context/research-index.md "$crlf_root/context/"
python3 - "$crlf_root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
for relative in ("prompt.md", "security-posture.md", "lore.md", "user.md", "context/research-index.md"):
    path = root / relative
    path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
PY
bash "$crlf_root/hooks/session-start.sh" --format claude > "$TEST_ROOT/crlf.json"
python3 - "$TEST_ROOT/crlf.json" "$crlf_root/skills/load-context/SKILL.md" <<'PY'
import json, re, sys
from pathlib import Path

context = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hookSpecificOutput"]["additionalContext"]
hook_hash = re.search(r'delivery="session-start" context_sha256="([0-9a-f]{64})"', context).group(1)
skill_hash = re.search(r'delivery="skill" context_sha256="([0-9a-f]{64})"', Path(sys.argv[2]).read_text(encoding="utf-8")).group(1)
assert hook_hash == skill_hash
PY
pass "CRLF context normalization"

manual_home="$TEST_ROOT/manual-home"
manual_settings="$manual_home/settings.json"
mkdir -p "$manual_home"
HOME="$manual_home" ./install.sh --target claude --settings "$manual_settings" >/dev/null
HOME="$manual_home" ./install.sh --target claude --settings "$manual_settings" >/dev/null
python3 - "$manual_settings" "$ROOT/hooks/session-start.sh" <<'PY'
import json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
start_entries = doc["hooks"]["SessionStart"]
stop_entries = doc["hooks"]["Stop"]
assert len(start_entries) == len(stop_entries) == 1
assert start_entries[0]["hooks"][0] == {
    "type": "command", "command": "bash", "args": [sys.argv[2]], "timeout": 15,
}
assert stop_entries[0]["hooks"][0] == {
    "type": "command",
    "command": "bash",
    "args": [str(Path(sys.argv[2]).with_name("artifact-stop.sh"))],
    "timeout": 15,
}
PY
HOME="$manual_home" ./install.sh --uninstall --target claude --settings "$manual_settings" >/dev/null
python3 - "$manual_settings" <<'PY'
import json, sys
from pathlib import Path
hooks = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hooks"]
assert hooks["SessionStart"] == []
assert hooks["Stop"] == []
PY
pass "manual installer idempotency and rollback"

codex_home="$TEST_ROOT/codex-home"
mkdir -p "$codex_home/.codex"
HOME="$codex_home" ./install.sh --target codex >/dev/null
HOME="$codex_home" ./install.sh --target codex >/dev/null
python3 - "$codex_home/.codex/hooks.json" "$ROOT" <<'PY'
import json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hooks"]
root = Path(sys.argv[2])
start = doc["SessionStart"][0]["hooks"][0]
stop = doc["Stop"][0]["hooks"][0]
assert start == {
    "type": "command",
    "command": f'bash "{root / "hooks/session-start.sh"}"',
    "timeout": 15,
    "additionalContextLimit": 20000,
}
assert stop == {
    "type": "command",
    "command": f'bash "{root / "hooks/artifact-stop.sh"}"',
    "timeout": 15,
}
PY
HOME="$codex_home" ./install.sh --uninstall --target codex >/dev/null
python3 - "$codex_home/.codex/hooks.json" <<'PY'
import json, sys
from pathlib import Path
hooks = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hooks"]
assert hooks["SessionStart"] == []
assert hooks["Stop"] == []
PY
pass "Codex lifecycle hooks and context limit"

invalid_home="$TEST_ROOT/invalid-json-home"
invalid_settings="$invalid_home/settings.json"
mkdir -p "$invalid_home"
printf '{ definitely not json\n' > "$invalid_settings"
cp "$invalid_settings" "$TEST_ROOT/invalid-settings.before"
if HOME="$invalid_home" ./install.sh --target claude --settings "$invalid_settings" >/dev/null 2>&1; then
  echo "installer accepted malformed hook JSON" >&2
  exit 1
fi
cmp "$invalid_settings" "$TEST_ROOT/invalid-settings.before"
pass "installer preserves malformed JSON"

invalid_hermes_home="$TEST_ROOT/invalid-hermes-home"
invalid_allowlist="$invalid_hermes_home/.hermes/shell-hooks-allowlist.json"
mkdir -p "$(dirname "$invalid_allowlist")"
printf '[ broken allowlist\n' > "$invalid_allowlist"
cp "$invalid_allowlist" "$TEST_ROOT/invalid-allowlist.before"
if HOME="$invalid_hermes_home" ./install.sh --target hermes >/dev/null 2>&1; then
  echo "installer accepted a malformed Hermes allowlist" >&2
  exit 1
fi
cmp "$invalid_allowlist" "$TEST_ROOT/invalid-allowlist.before"
pass "installer preserves malformed Hermes allowlist"

broken_markers="$TEST_ROOT/broken-markers.md"
printf 'keep me\n<!-- agent-plugin:vibe-lore START -->\nmanaged text\nkeep this tail\n' \
  > "$broken_markers"
cp "$broken_markers" "$TEST_ROOT/broken-markers.before"
if ./install.sh --uninstall --target none --instructions "$broken_markers" >/dev/null 2>&1; then
  echo "installer removed a managed block without an END marker" >&2
  exit 1
fi
cmp "$broken_markers" "$TEST_ROOT/broken-markers.before"
pass "installer preserves files with unmatched managed markers"

grok_home="$TEST_ROOT/grok-home"
mkdir -p "$grok_home"
HOME="$grok_home" ./install.sh --target grok,grokbot > "$TEST_ROOT/grok-install.txt"
grep -Fq 'import/link this SKILL.md in Grok Bot Workflows' "$TEST_ROOT/grok-install.txt"
HOME="$grok_home" ./install.sh --target grok,grokbot >/dev/null
grokbot_skill="$grok_home/.grokbot/choirboy-context/SKILL.md"
python3 - "$grok_home/.grok/AGENTS.md" "$grokbot_skill" "$ROOT" <<'PY'
import sys
from pathlib import Path

grok_rules = Path(sys.argv[1]).read_text(encoding="utf-8")
grokbot_skill = Path(sys.argv[2]).read_text(encoding="utf-8")
assert grok_rules.count("<!-- agent-plugin:vibe-lore START -->") == 1
assert grok_rules.count("<!-- agent-plugin:vibe-lore END -->") == 1
assert grokbot_skill.startswith("---\nname: choirboy-context\n")
assert "agent-plugin:vibe-lore: managed Grok Bot workflow" in grokbot_skill
assert '<choirboy-delivery ' in grokbot_skill
assert "<choirboy-context>" in grokbot_skill
assert "</choirboy-context>" in grokbot_skill
assert sys.argv[3] not in grokbot_skill
PY
if compgen -G "$grokbot_skill.bak.*" >/dev/null; then
  echo "idempotent Grok Bot preparation unexpectedly created a backup" >&2
  exit 1
fi
HOME="$grok_home" ./install.sh --list > "$TEST_ROOT/grok-list.txt"
grep -Eq '^grok[[:space:]]+installed[[:space:]]+' "$TEST_ROOT/grok-list.txt"
grep -Eq '^grokbot[[:space:]]+prepared[[:space:]]+' "$TEST_ROOT/grok-list.txt"
HOME="$grok_home" ./install.sh --uninstall --target grok,grokbot >/dev/null
test ! -e "$grokbot_skill"
if grep -qF 'agent-plugin:vibe-lore' "$grok_home/.grok/AGENTS.md"; then
  echo "Grok Build uninstall left the managed block behind" >&2
  exit 1
fi
HOME="$grok_home" ./install.sh --list > "$TEST_ROOT/grok-list-uninstalled.txt"
grep -Eq '^grok[[:space:]]+detected[[:space:]]+' "$TEST_ROOT/grok-list-uninstalled.txt"
grep -Eq '^grokbot[[:space:]]+detected[[:space:]]+' "$TEST_ROOT/grok-list-uninstalled.txt"
pass "Grok Build install and Grok Bot workflow preparation"

legacy_grokbot_home="$TEST_ROOT/grokbot-legacy-home"
legacy_grokbot_agents="$legacy_grokbot_home/.grokbot/AGENTS.md"
mkdir -p "$(dirname "$legacy_grokbot_agents")"
printf 'keep me\n<!-- agent-plugin:vibe-lore START -->\nold pointer\n<!-- agent-plugin:vibe-lore END -->\n' \
  > "$legacy_grokbot_agents"
HOME="$legacy_grokbot_home" ./install.sh --target grokbot >/dev/null
grep -qxF 'keep me' "$legacy_grokbot_agents"
if grep -qF 'agent-plugin:vibe-lore' "$legacy_grokbot_agents"; then
  echo "Grok Bot migration left the unsupported legacy pointer behind" >&2
  exit 1
fi
test -f "$legacy_grokbot_home/.grokbot/choirboy-context/SKILL.md"
pass "Grok Bot legacy pointer migration"

foreign_grokbot_home="$TEST_ROOT/grokbot-foreign-home"
foreign_grokbot_skill="$foreign_grokbot_home/.grokbot/choirboy-context/SKILL.md"
mkdir -p "$(dirname "$foreign_grokbot_skill")"
printf '%s\n' '# foreign Grok Bot workflow' > "$foreign_grokbot_skill"
if HOME="$foreign_grokbot_home" ./install.sh --target grokbot >/dev/null 2>&1; then
  echo "Grok Bot preparation overwrote an unmarked workflow" >&2
  exit 1
fi
grep -qxF '# foreign Grok Bot workflow' "$foreign_grokbot_skill"
pass "Grok Bot foreign-workflow guard"

grokbot_binary_home="$TEST_ROOT/grokbot-binary-home"
grokbot_binary_path="$TEST_ROOT/grokbot-binary-path"
mkdir -p "$grokbot_binary_home" "$grokbot_binary_path"
printf '#!/bin/sh\nexit 0\n' > "$grokbot_binary_path/grok-bot"
chmod +x "$grokbot_binary_path/grok-bot"
HOME="$grokbot_binary_home" PATH="$grokbot_binary_path:$PATH" \
  ./install.sh --list > "$TEST_ROOT/grokbot-binary-list.txt"
grep -Eq '^grokbot[[:space:]]+detected[[:space:]]+' "$TEST_ROOT/grokbot-binary-list.txt"
pass "fresh Grok Bot binary detection"

runtime_home="$TEST_ROOT/runtime-home"
mkdir -p "$runtime_home"
HOME="$runtime_home" ./install.sh --target hermes,kimi >/dev/null
grep -Fq \
  "command: \"bash \\\"$ROOT/hooks/session-start.sh\\\" --format hermes\"" \
  "$runtime_home/.hermes/config.yaml"
python3 - "$runtime_home" <<'PY'
import json, sys, tomllib
from pathlib import Path

home = Path(sys.argv[1])
hermes = (home / ".hermes/config.yaml").read_text(encoding="utf-8")
kimi = tomllib.loads((home / ".kimi-code/config.toml").read_text(encoding="utf-8"))
allowlist = json.loads((home / ".hermes/shell-hooks-allowlist.json").read_text(encoding="utf-8"))
plain_command = kimi["hooks"][0]["command"]
assert plain_command.startswith('bash "') and plain_command.endswith('" --format plain')
command = plain_command.removesuffix(" --format plain") + " --format hermes"
assert f'command: "{command.replace(chr(34), chr(92) + chr(34))}"' in hermes
assert {"event": "pre_llm_call", "command": command} in allowlist["approvals"]
PY
pass "quoted Hermes and Kimi paths"

opencode_home="$TEST_ROOT/opencode-home"
opencode_plugin="$opencode_home/.config/opencode/plugins/agent-plugin.ts"
mkdir -p "$opencode_home"
HOME="$opencode_home" ./install.sh --target opencode >/dev/null
HOME="$opencode_home" ./install.sh --target opencode >/dev/null
python3 - "$opencode_plugin" "$ROOT/hooks/session-start.sh" <<'PY'
import json, sys
from pathlib import Path

plugin = Path(sys.argv[1]).read_text(encoding="utf-8")
hook = sys.argv[2]
assert plugin.count("agent-plugin:vibe-lore") == 2
assert f"const HOOK_SCRIPT = {json.dumps(hook)}" in plugin
assert '"chat.message"' in plugin
assert "new Set<string>()" in plugin
assert "deliveredSessions.has(sessionID)" in plugin
assert "client.session.messages" in plugin
assert "part.synthetic === true" in plugin
assert "rememberSession(sessionID)" in plugin
assert 'spawnSync("bash", [HOOK_SCRIPT, "--format", "plain"]' in plugin
assert "result.status !== 0" in plugin
assert 'id: `prt_choirboy_${randomUUID().replaceAll("-", "")}`' in plugin
assert "sessionID," in plugin
assert "messageID: output.message.id" in plugin
assert "synthetic: true" in plugin
assert "catch {" in plugin
PY
if compgen -G "$opencode_plugin.bak.*" >/dev/null; then
  echo "idempotent OpenCode install unexpectedly created a backup" >&2
  exit 1
fi
HOME="$opencode_home" ./install.sh --list > "$TEST_ROOT/opencode-list.txt"
grep -Eq '^opencode[[:space:]]+installed[[:space:]]+' "$TEST_ROOT/opencode-list.txt"
printf '\n// test drift\n' >> "$opencode_plugin"
HOME="$opencode_home" ./install.sh --target opencode >/dev/null
compgen -G "$opencode_plugin.bak.*" >/dev/null
if grep -qF '// test drift' "$opencode_plugin"; then
  echo "OpenCode refresh left test drift in place" >&2
  exit 1
fi
HOME="$opencode_home" ./install.sh --uninstall --target opencode >/dev/null
test ! -e "$opencode_plugin"
compgen -G "$opencode_plugin.bak.*" >/dev/null
HOME="$opencode_home" ./install.sh --list > "$TEST_ROOT/opencode-list-uninstalled.txt"
grep -Eq '^opencode[[:space:]]+detected[[:space:]]+' "$TEST_ROOT/opencode-list-uninstalled.txt"
pass "OpenCode install, list, idempotent refresh, backup, and rollback"

foreign_home="$TEST_ROOT/opencode-foreign-home"
foreign_plugin="$foreign_home/.config/opencode/plugins/agent-plugin.ts"
mkdir -p "$(dirname "$foreign_plugin")"
printf '// foreign OpenCode plugin\n' > "$foreign_plugin"
if HOME="$foreign_home" ./install.sh --target opencode >/dev/null 2>&1; then
  echo "OpenCode install overwrote an unmarked plugin" >&2
  exit 1
fi
grep -qxF '// foreign OpenCode plugin' "$foreign_plugin"
pass "OpenCode foreign-plugin guard"

python3 - <<'PY'
import json
from pathlib import Path

root = Path("sessions")

def jsonl(path):
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

def message_text(message):
    content = message["content"]
    if isinstance(content, str):
        return content
    return content[0]["text"]

claude_path = root / "claude/fa1ce000-0000-4000-8000-0000000000c1.jsonl"
codex_path = root / "codex/rollout-2026-08-10T18-30-00-fa1ce000-0000-7000-8000-0000000000c2.jsonl"
kimi_dir = root / "kimi/session_fa1ce000-0000-4000-8000-0000000000c3"

claude = jsonl(claude_path)
previous = None
for record in claude:
    assert record["sessionId"] == "fa1ce000-0000-4000-8000-0000000000c1"
    assert record["parentUuid"] == previous
    previous = record["uuid"]
claude_dialogue = [
    (record["message"]["role"], message_text(record["message"]))
    for record in claude
]

codex = jsonl(codex_path)
assert codex[0]["payload"]["session_id"] == "fa1ce000-0000-7000-8000-0000000000c2"
codex_dialogue = [
    (record["payload"]["role"], message_text(record["payload"]))
    for record in codex
    if record["type"] == "response_item" and record["payload"]["type"] == "message"
]

kimi_state = json.loads((kimi_dir / "state.json").read_text(encoding="utf-8"))
kimi_wire = jsonl(kimi_dir / "agents/main/wire.jsonl")
kimi_dialogue = [
    (record["message"]["role"], message_text(record["message"]))
    for record in kimi_wire
    if record["type"] == "context.append_message"
]
kimi_index = json.loads((root / "kimi/session_index.jsonl.example").read_text(encoding="utf-8"))
assert kimi_state["id"] == kimi_index["sessionId"]
assert "$HOME" in kimi_state["agents"]["main"]["homedir"]
assert "$HOME" in kimi_index["sessionDir"]
assert kimi_state["agents"]["main"]["homedir"] == f'{kimi_index["sessionDir"]}/agents/main'

assert claude_dialogue == codex_dialogue == kimi_dialogue
assert len(claude_dialogue) == 6

sql = (root / "codex/threads-insert.sql").read_text(encoding="utf-8")
assert sql.count("INSERT INTO threads") == 1
assert "fa1ce000-0000-7000-8000-0000000000c2" in sql and "$HOME" in sql
assert kimi_state["title"] in sql
assert "not a historical record" in (root / "README.md").read_text(encoding="utf-8")
assert "исторической записью разговора" in (root / "README.ru.md").read_text(encoding="utf-8")
assert "不是历史对话记录" in (root / "README.zh-CN.md").read_text(encoding="utf-8")
PY
pass "native session-store compatibility fixtures"

python3 scripts/package-plugin.py --output "$TEST_ROOT/choirboy.zip" >/dev/null
python3 - "$TEST_ROOT/choirboy.zip" <<'PY'
import stat, sys, zipfile

required = {
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    "hooks/hooks.json",
    "hooks/artifact-stop.sh",
    "hooks/session-start.sh",
    "scripts/artifact-generator.py",
    "skills/load-context/SKILL.md",
    "skills/diagnose/SKILL.md",
    "research/22-security-capability-router.md",
    "research/23-security-case-and-evidence-contract.md",
    "research/24-security-tool-registry-and-bootstrap.md",
    "research/25-reverse-engineering-capability-map.md",
    "research/26-application-infrastructure-security-map.md",
    "research/27-exploitation-malware-forensics-and-detection.md",
    "research/28-llm-agent-and-skill-supply-chain-security.md",
    "research/29-ctf-sandbox-orchestration.md",
    "research/30-security-reporting-and-knowledge-reuse.md",
    "sessions/README.md",
    "sessions/README.ru.md",
    "sessions/README.zh-CN.md",
    "sessions/claude/fa1ce000-0000-4000-8000-0000000000c1.jsonl",
    "sessions/codex/rollout-2026-08-10T18-30-00-fa1ce000-0000-7000-8000-0000000000c2.jsonl",
    "sessions/codex/threads-insert.sql",
    "sessions/kimi/session_fa1ce000-0000-4000-8000-0000000000c3/state.json",
    "sessions/kimi/session_fa1ce000-0000-4000-8000-0000000000c3/agents/main/wire.jsonl",
    "sessions/kimi/session_index.jsonl.example",
}
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert required.issubset(archive.namelist())
    for executable in (
        "hooks/session-start.sh",
        "hooks/artifact-stop.sh",
        "scripts/artifact-generator.py",
    ):
        mode = archive.getinfo(executable).external_attr >> 16
        assert mode & stat.S_IXUSR
PY
pass "custom-plugin ZIP"

python3 - <<'PY'
import re, subprocess
from pathlib import Path

missing = []
tracked = subprocess.run(
    ["git", "ls-files", "*.md"], check=True, capture_output=True, text=True
).stdout.splitlines()
for name in tracked:
    document = Path(name)
    text = document.read_text(encoding="utf-8")
    for target in re.findall(r"\]\(([^)]+)\)", text):
        target = target.strip("<>").split("#", 1)[0]
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        if not (document.parent / target).resolve().exists():
            missing.append(f"{document}: {target}")
assert not missing, "broken local links:\n" + "\n".join(missing)
PY
pass "local documentation links"

printf 'All tests passed.\n'
