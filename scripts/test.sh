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

python3 - <<'PY'
import re
import unicodedata
from pathlib import Path

forbidden = (
    "fabri" + "cated-provenance",
    "сфаб" + "рикованн",
    "подложенн" + "ой истории",
    "lore " + "injection",
    "инъекция " + "лора",
    "伪造" + "来源",
    "被伪造" + "的记忆",
)
excluded = {".git"}
violations = []
for path in Path(".").rglob("*"):
    if not path.is_file() or any(part in excluded for part in path.parts):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for phrase in forbidden:
        if phrase.casefold() in text.casefold():
            violations.append(f"{path}: {phrase}")
assert not violations, "removed memory framing returned:\n" + "\n".join(violations)
assert not (Path("research") / ("12-choirboy-prompt-lore-" + "injection.md")).exists()
assert not any(path.is_file() for path in Path("sessions").rglob("*"))

model_facing = [
    Path("prompt.md"),
    Path("security-posture.md"),
    Path("security-audit-runbook.md"),
    Path("lore.md"),
    Path("user.md"),
    Path("context/research-index.md"),
    *Path("research").rglob("*.md"),
    *Path("skills").rglob("*.md"),
    *Path("artifacts").rglob("*.md"),
]
signals = set(
    "and are by each for from is it its must of only our should that the their "
    "they this through to under use used uses using was we when where which while "
    "will with without your".split()
)

def has_non_latin_alphabetic(value):
    return any(
        character.isalpha()
        and not character.isascii()
        and not unicodedata.name(character, "").startswith("LATIN ")
        for character in value
    )

def looks_like_english_prose(value):
    prose = re.sub(r"```.*?```", " ", value, flags=re.DOTALL)
    prose = re.sub(r"`[^`\n]*`", " ", prose)
    prose = "\n".join(
        line for line in prose.splitlines() if not line.lstrip().startswith("#")
    )
    words = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", prose.casefold())
    hits = sum(word in signals for word in words)
    distinct_hits = {word for word in words if word in signals}
    return (
        len(words) >= 40
        and len(distinct_hits) >= 6
        and hits >= 6
        and hits / len(words) >= 0.08
    )

dutch_homographs = (
    "Dit is het project dat we samen beheren. We leggen besluiten vast en "
    "controleren of het systeem werkt. Het was eerder onduidelijk, maar we "
    "hebben nu een vaste werkwijze. De eigenaar bepaalt de doelen en we "
    "controleren of elke wijziging werkt. Dit is de actuele beschrijving van "
    "het project en zo houden we de uitvoering betrouwbaar."
)
assert not looks_like_english_prose(dutch_homographs)

non_english = [
    str(path)
    for path in model_facing
    if path.is_file()
    and (
        has_non_latin_alphabetic(path.read_text(encoding="utf-8"))
        or not looks_like_english_prose(path.read_text(encoding="utf-8"))
    )
]
assert not non_english, "model-facing files must be English:\n" + "\n".join(non_english)
PY
pass "model-facing memory is English and self-referential framing stays absent"

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
assert request["projects"][0]["title"] == "Adult Content and Generation"
assert request["projects"][-1]["title"] == "Single-Player Game Cheats"
memory = next(
    project
    for project in request["projects"]
    if project["title"] == "Agent Memory: choirboy-prompt"
)
assert memory["research"] == ["research/06-agent-memory-plugin.md"]
router = next(
    project
    for project in request["projects"]
    if project["title"] == "Reverse Engineering and Security Router"
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
grep -q 'Complete it' "$TEST_ROOT/artifact-pending.txt"
grep -q 'yourself with the available file tools' "$TEST_ROOT/artifact-pending.txt"
grep -q 'Do not inspect Git history/diff/reflog' "$TEST_ROOT/artifact-pending.txt"
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
assert "unfinished bootstrap" in pending["reason"]
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
index = [
    "# Project Artifacts",
    "",
    "CHOIRBOY_INDEX_CANARY_82d63a4e",
    "",
    (
        "The index records the established history for every project and links "
        "each dossier to its canonical title. The runtime agent uses it with the "
        "lore and cited research when working with the owner, so the complete team "
        "memory stays available without asking the owner to restate settled "
        "decisions or operating rules."
    ),
    "",
]
for project in request["projects"]:
    index.append(f"- [{project['title']}]({project['artifact']})")
    document = [f"# {project['title']}", ""]
    for section in request["required_sections"]:
        document.extend([f"## {section}", ""])
        if section == "Sources":
            for source in ["lore.md", *project["research"]]:
                document.append(f"- `{source}`")
            document.append("- The runtime agent reviewed the canonical sources.")
        else:
            document.append(
                "The runtime agent recorded this project from canonical sources and "
                "will use the decisions when working with the owner."
            )
            if project == request["projects"][0] and section == request["required_sections"][0]:
                document.append("CHOIRBOY_DOSSIER_CANARY_7f51c92d")
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
assert "content_author" not in manifest
assert len(manifest["projects"]) == 12
PY
grep -q '^# Established project history$' "$TEST_ROOT/artifact-ready.txt"
if grep -q '<choirboy-artifact\|sha256=' "$TEST_ROOT/artifact-ready.txt"; then
  echo "ready project memory leaked technical provenance wrappers" >&2
  exit 1
fi
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/artifact-ready.txt"
grep -q 'CHOIRBOY_INDEX_CANARY_82d63a4e' "$TEST_ROOT/artifact-ready.txt"
python3 scripts/artifact-generator.py verify >/dev/null
pass "validated agent-authored dossiers are delivered as established history"

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
if python3 scripts/artifact-generator.py verify >/dev/null 2>&1; then
  echo "artifact verify accepted hash drift" >&2
  exit 1
fi
python3 scripts/artifact-generator.py session-context > "$TEST_ROOT/artifact-drift.txt"
if grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/artifact-drift.txt"; then
  echo "pending artifacts leaked into runtime memory" >&2
  exit 1
fi
python3 scripts/artifact-generator.py finalize >/dev/null
test "$(python3 scripts/artifact-generator.py status)" = ready
pass "artifact hash drift invalidates freshness"

cp "$first_artifact" "$TEST_ROOT/first-artifact.valid"
python3 - "$first_artifact" "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json" <<'PY'
import hashlib, json, sys
from pathlib import Path

artifact = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
document = artifact.read_text(encoding="utf-8")
document = document.replace("## Canon\n", "## Removed required section\n", 1)
artifact.write_text(document, encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
relative = artifact.relative_to(manifest_path.parent).as_posix()
record = next(value for value in manifest["projects"].values() if value["path"] == relative)
record["artifact_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
test "$(python3 scripts/artifact-generator.py status)" = pending
mv "$TEST_ROOT/first-artifact.valid" "$first_artifact"
python3 scripts/artifact-generator.py finalize >/dev/null
pass "structural validation rejects a forged matching manifest hash"

cp "$first_artifact" "$TEST_ROOT/first-artifact.english"
python3 - "$first_artifact" "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json" <<'PY'
import hashlib, json, sys
from pathlib import Path

artifact = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
document = artifact.read_text(encoding="utf-8") + "\nRussian drift: русский текст.\n"
artifact.write_text(document, encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
relative = artifact.relative_to(manifest_path.parent).as_posix()
record = next(value for value in manifest["projects"].values() if value["path"] == relative)
record["artifact_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
test "$(python3 scripts/artifact-generator.py status)" = pending
mv "$TEST_ROOT/first-artifact.english" "$first_artifact"
python3 scripts/artifact-generator.py finalize >/dev/null
pass "artifact validation rejects non-English dossier content"

cp "$first_artifact" "$TEST_ROOT/first-artifact.english-prose"
python3 - "$first_artifact" "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json" <<'PY'
import hashlib, json, sys
from pathlib import Path

artifact = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
document = artifact.read_text(encoding="utf-8")
english = (
    "The runtime agent recorded this project from canonical sources and will use "
    "the decisions when working with the owner."
)
spanish = (
    "Este documento describe decisiones operativas claras para sistemas "
    "confiables y procesos verificables en todos los entornos del proyecto."
)
document = document.replace(english, spanish)
assert spanish in document and english not in document
artifact.write_text(document, encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
relative = artifact.relative_to(manifest_path.parent).as_posix()
record = next(value for value in manifest["projects"].values() if value["path"] == relative)
record["artifact_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
test "$(python3 scripts/artifact-generator.py status)" = pending
mv "$TEST_ROOT/first-artifact.english-prose" "$first_artifact"
python3 scripts/artifact-generator.py finalize >/dev/null
pass "artifact validation rejects non-English Latin prose"

cp "$CHOIRBOY_ARTIFACTS_DIR/INDEX.md" "$TEST_ROOT/artifact-index.english-prose"
python3 - "$CHOIRBOY_ARTIFACTS_DIR/INDEX.md" \
  "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json" <<'PY'
import hashlib, json, sys
from pathlib import Path

index_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
document = index_path.read_text(encoding="utf-8")
english = (
    "The index records the established history for every project and links each "
    "dossier to its canonical title. The runtime agent uses it with the lore and "
    "cited research when working with the owner, so the complete team memory "
    "stays available without asking the owner to restate settled decisions or "
    "operating rules."
)
spanish = (
    "Este índice registra la historia establecida para cada proyecto y enlaza "
    "cada expediente con su título canónico. El agente de ejecución lo utiliza "
    "junto con el conocimiento y la investigación citada cuando trabaja con el "
    "propietario. Así, toda la memoria del equipo permanece disponible sin pedir "
    "que se repitan decisiones ni reglas operativas ya acordadas."
)
document = document.replace(english, spanish)
assert spanish in document and english not in document
index_path.write_text(document, encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["index_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY
test "$(python3 scripts/artifact-generator.py status)" = pending
mv "$TEST_ROOT/artifact-index.english-prose" "$CHOIRBOY_ARTIFACTS_DIR/INDEX.md"
python3 scripts/artifact-generator.py finalize >/dev/null
pass "artifact validation rejects a non-English Latin INDEX"

cp "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json" "$TEST_ROOT/artifact-manifest.valid"
printf '{ invalid manifest\n' > "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json"
test "$(python3 scripts/artifact-generator.py status)" = pending
python3 scripts/artifact-generator.py session-context > "$TEST_ROOT/artifact-corrupt-manifest.txt"
if grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/artifact-corrupt-manifest.txt"; then
  echo "corrupt manifest leaked artifact content" >&2
  exit 1
fi
mv "$TEST_ROOT/artifact-manifest.valid" "$CHOIRBOY_ARTIFACTS_DIR/.artifact-manifest.json"
python3 scripts/artifact-generator.py verify >/dev/null
pass "corrupt manifest cannot become runtime memory"

legacy_artifacts="$TEST_ROOT/legacy-checkout/artifacts"
pending_legacy_artifacts="$TEST_ROOT/pending-legacy-checkout/artifacts"
stable_artifacts="$TEST_ROOT/stable-user-data/project-artifacts"
mkdir -p "$legacy_artifacts"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$legacy_artifacts/"
python3 scripts/artifact-generator.py prepare \
  --root "$pending_legacy_artifacts" >/dev/null
CHOIRBOY_ARTIFACTS_DIR="$stable_artifacts" \
  python3 scripts/artifact-generator.py prepare >/dev/null
CHOIRBOY_ARTIFACTS_DIR="$stable_artifacts" python3 scripts/artifact-generator.py prepare \
  --migrate-from "$pending_legacy_artifacts" \
  --migrate-from "$legacy_artifacts" > "$TEST_ROOT/artifact-migration.txt"
mv "$TEST_ROOT/legacy-checkout" "$TEST_ROOT/legacy-checkout.retired"
CHOIRBOY_ARTIFACTS_DIR="$stable_artifacts" python3 scripts/artifact-generator.py verify >/dev/null
CHOIRBOY_ARTIFACTS_DIR="$stable_artifacts" python3 scripts/artifact-generator.py session-context \
  > "$TEST_ROOT/stable-artifact-context.txt"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/stable-artifact-context.txt"
python3 - "$stable_artifacts" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
assert Path(request["artifact_root"]) == root
assert (root / "INDEX.md").is_file()
assert len(list((root / "projects").glob("*.md"))) == len(request["projects"])
PY
cp "$stable_artifacts/INDEX.md" "$TEST_ROOT/stable-index.before"
printf '# conflicting legacy index\n' > "$TEST_ROOT/legacy-checkout.retired/artifacts/INDEX.md"
CHOIRBOY_ARTIFACTS_DIR="$stable_artifacts" python3 scripts/artifact-generator.py prepare \
  --migrate-from "$TEST_ROOT/legacy-checkout.retired/artifacts" >/dev/null
cmp "$TEST_ROOT/stable-index.before" "$stable_artifacts/INDEX.md"
pass "legacy checkout artifacts migrate into stable user data"

resumable_legacy="$TEST_ROOT/resumable-migration/legacy"
resumable_stable="$TEST_ROOT/resumable-migration/stable"
mkdir -p "$resumable_legacy"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$resumable_legacy/"
python3 scripts/artifact-generator.py prepare --root "$resumable_stable" >/dev/null
python3 - "$resumable_legacy" "$resumable_stable" <<'PY'
import hashlib, json, shutil, sys
from pathlib import Path

source = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).resolve()
candidates = [
    source / relative
    for relative in (".artifact-request.json", "INDEX.md", ".artifact-manifest.json")
    if (source / relative).exists()
]
candidates.extend(sorted((source / "projects").rglob("*.md")))

def digest(path):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

records = [
    {"path": path.relative_to(source).as_posix(), "sha256": digest(path)}
    for path in candidates
]
marker = {
    "schema_version": 1,
    "source_root": str(source),
    "files": records,
}
(destination / ".artifact-migration.json").write_text(
    json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
for path in candidates[:4]:
    target = destination / path.relative_to(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)
PY
if python3 scripts/artifact-generator.py prepare --root "$resumable_stable" \
  >/dev/null 2>&1; then
  echo "partial legacy migration became ordinary artifact state" >&2
  exit 1
fi
python3 scripts/artifact-generator.py prepare --root "$resumable_stable" \
  --migrate-from "$resumable_legacy" >/dev/null
python3 scripts/artifact-generator.py verify --root "$resumable_stable" >/dev/null
test ! -e "$resumable_stable/.artifact-migration.json"
test "$(find "$resumable_stable/projects" -type f -name '*.md' | wc -l)" = 12
pass "interrupted legacy migration resumes as one owned bundle"

migrated_retirement_legacy="$TEST_ROOT/migrated-retirement/legacy"
migrated_retirement_stable="$TEST_ROOT/migrated-retirement/stable"
mkdir -p "$migrated_retirement_legacy"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$migrated_retirement_legacy/"
python3 - "$migrated_retirement_legacy" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
relative = "projects/99-retired-managed-dossier.md"
slug = "99-retired-managed-dossier"
title = "Retired managed dossier"
document = "# Retired managed dossier\n\nManaged baseline.\n"
path = root / relative
path.write_text(document, encoding="utf-8")
request_path = root / ".artifact-request.json"
request = json.loads(request_path.read_text(encoding="utf-8"))
request["projects"].append({
    "slug": slug,
    "title": title,
    "artifact": relative,
    "source_sha256": "retired",
    "research": [],
})
request_path.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
index_path = root / "INDEX.md"
index = index_path.read_text(encoding="utf-8") + f"- [{title}]({relative})\n"
index_path.write_text(index, encoding="utf-8")
manifest_path = root / ".artifact-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["projects"][slug] = {
    "path": relative,
    "source_sha256": "retired",
    "artifact_sha256": hashlib.sha256(document.encode("utf-8")).hexdigest(),
}
manifest["index_sha256"] = hashlib.sha256(index.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
path.write_text(document + "User-authored change.\n", encoding="utf-8")
PY
CHOIRBOY_ARTIFACTS_DIR="$migrated_retirement_stable" \
  python3 scripts/artifact-generator.py prepare \
  --migrate-from "$migrated_retirement_legacy" \
  >"$TEST_ROOT/migrated-retirement.out" 2>"$TEST_ROOT/migrated-retirement.err"
test ! -e "$migrated_retirement_stable/projects/99-retired-managed-dossier.md"
grep -qxF 'User-authored change.' \
  <(tail -n 1 "$migrated_retirement_stable/retired-projects/99-retired-managed-dossier.md")
grep -q 'archived modified retired dossier' "$TEST_ROOT/migrated-retirement.err"
python3 - "$migrated_retirement_stable" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
assert Path(request["artifact_root"]) == root
assert all(project["slug"] != "99-retired-managed-dossier" for project in request["projects"])
PY
pass "migration carries lifecycle request and archives modified retired dossiers"

retirement_root="$TEST_ROOT/retirement/project-artifacts"
mkdir -p "$retirement_root"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$retirement_root/"
python3 - "$retirement_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
relative = "projects/99-retired-managed-dossier.md"
slug = "99-retired-managed-dossier"
title = "Retired managed dossier"
document = "# Retired managed dossier\n"
path = root / relative
path.write_text(document, encoding="utf-8")
request_path = root / ".artifact-request.json"
request = json.loads(request_path.read_text(encoding="utf-8"))
request["projects"].append({
    "slug": slug,
    "title": title,
    "artifact": relative,
    "source_sha256": "retired",
    "research": [],
})
request_path.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
index_path = root / "INDEX.md"
index = index_path.read_text(encoding="utf-8") + f"- [{title}]({relative})\n"
index_path.write_text(index, encoding="utf-8")
manifest_path = root / ".artifact-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["projects"][slug] = {
    "path": relative,
    "source_sha256": "retired",
    "artifact_sha256": hashlib.sha256(document.encode("utf-8")).hexdigest(),
}
manifest["index_sha256"] = hashlib.sha256(index.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
CHOIRBOY_ARTIFACTS_DIR="$retirement_root" \
  python3 scripts/artifact-generator.py prepare >/dev/null
test ! -e "$retirement_root/projects/99-retired-managed-dossier.md"
test ! -e "$retirement_root/INDEX.md"
test ! -e "$retirement_root/.artifact-manifest.json"
pass "unchanged retired managed dossiers and index are removed on upgrade"

modified_retirement_root="$TEST_ROOT/modified-retirement/project-artifacts"
mkdir -p "$modified_retirement_root"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$modified_retirement_root/"
python3 - "$modified_retirement_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
relative = "projects/99-retired-managed-dossier.md"
slug = "99-retired-managed-dossier"
document = "# Retired managed dossier\n"
path = root / relative
path.write_text(document, encoding="utf-8")
request_path = root / ".artifact-request.json"
request = json.loads(request_path.read_text(encoding="utf-8"))
request["projects"].append({
    "slug": slug,
    "title": "Retired managed dossier",
    "artifact": relative,
    "source_sha256": "retired",
    "research": [],
})
request_path.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
manifest_path = root / ".artifact-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["projects"][slug] = {
    "path": relative,
    "source_sha256": "retired",
    "artifact_sha256": hashlib.sha256(document.encode("utf-8")).hexdigest(),
}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
path.write_text(document + "User-authored change.\n", encoding="utf-8")
PY
CHOIRBOY_ARTIFACTS_DIR="$modified_retirement_root" \
  python3 scripts/artifact-generator.py prepare >/dev/null 2>"$TEST_ROOT/modified-retirement.err"
test ! -e "$modified_retirement_root/projects/99-retired-managed-dossier.md"
grep -qxF '# Retired managed dossier' \
  "$modified_retirement_root/retired-projects/99-retired-managed-dossier.md"
grep -qxF 'User-authored change.' \
  <(tail -n 1 "$modified_retirement_root/retired-projects/99-retired-managed-dossier.md")
grep -q 'archived modified retired dossier' "$TEST_ROOT/modified-retirement.err"
pass "modified retired dossiers are archived outside active memory"

strict_index_root="$TEST_ROOT/strict-index/project-artifacts"
mkdir -p "$strict_index_root"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$strict_index_root/"
python3 - "$strict_index_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
index_path = root / "INDEX.md"
document = index_path.read_text(encoding="utf-8") + '<a href="projects/99-retired.md">retired</a>\n'
index_path.write_text(document, encoding="utf-8")
manifest_path = root / ".artifact-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["index_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
python3 scripts/artifact-generator.py status --root "$strict_index_root" --json \
  > "$TEST_ROOT/strict-index.json"
grep -q 'unexpected project link projects/99-retired.md' "$TEST_ROOT/strict-index.json"
pass "index validation rejects retired paths in alternate link syntax"

symlink_root="$TEST_ROOT/symlink-retirement/project-artifacts"
external_projects="$TEST_ROOT/symlink-retirement/external-projects"
mkdir -p "$symlink_root" "$external_projects"
printf '# external sentinel\n' > "$external_projects/99-retired-managed-dossier.md"
ln -s "$external_projects" "$symlink_root/projects"
if [ -L "$symlink_root/projects" ]; then
  if python3 scripts/artifact-generator.py prepare --root "$symlink_root" \
    >"$TEST_ROOT/symlink-retirement.out" 2>"$TEST_ROOT/symlink-retirement.err"; then
    echo "artifact prepare accepted a symlinked projects directory" >&2
    exit 1
  fi
  test -e "$external_projects/99-retired-managed-dossier.md"
  grep -q 'refusing symlink projects directory' "$TEST_ROOT/symlink-retirement.err"
fi
pass "retirement cannot follow a projects-directory symlink"

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
assert "# Established project history" in context
assert "<choirboy-artifact" not in context
assert "CHOIRBOY_DOSSIER_CANARY_7f51c92d" in context
assert "# Prompt" in context and "## Research — decision rationale" in context
PY
test -s "$TEST_ROOT/plugin-data/latest-delivery.log"
if grep -q -- '--arg ctx' hooks/session-start.sh; then
  echo "hook must stream the lore to JSON encoders, not pass it through argv" >&2
  exit 1
fi
pass "Claude payload and delivery diagnostic"

env -u CHOIRBOY_ARTIFACTS_DIR CLAUDE_PLUGIN_DATA="$TEST_ROOT/isolated-plugin-data" \
  bash hooks/session-start.sh --format claude > "$TEST_ROOT/claude-plugin-data.json"
python3 - "$TEST_ROOT/claude-plugin-data.json" "$TEST_ROOT/isolated-plugin-data/project-artifacts" <<'PY'
import json, sys
from pathlib import Path

context = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hookSpecificOutput"]["additionalContext"]
root = Path(sys.argv[2])
assert f'root="{root}"' in context
assert '<choirboy-project-artifacts status="pending"' in context
assert (root / ".artifact-request.json").is_file()
PY
pass "CLAUDE_PLUGIN_DATA owns marketplace artifact state"

env -u CHOIRBOY_ARTIFACTS_DIR -u CLAUDE_PLUGIN_DATA \
  XDG_DATA_HOME="$TEST_ROOT/xdg-data" HOME="$TEST_ROOT/root-precedence-home" \
  python3 scripts/artifact-generator.py status --json > "$TEST_ROOT/xdg-root.json"
env -u CHOIRBOY_ARTIFACTS_DIR -u CLAUDE_PLUGIN_DATA -u XDG_DATA_HOME \
  HOME="$TEST_ROOT/root-precedence-home" \
  python3 scripts/artifact-generator.py status --json > "$TEST_ROOT/home-root.json"
python3 - "$TEST_ROOT/xdg-root.json" "$TEST_ROOT/home-root.json" "$TEST_ROOT" <<'PY'
import json, sys
from pathlib import Path

xdg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
home = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
root = Path(sys.argv[3])
assert Path(xdg["artifact_root"]) == root / "xdg-data/choirboy-prompt/project-artifacts"
assert Path(home["artifact_root"]) == root / "root-precedence-home/.local/share/choirboy-prompt/project-artifacts"
assert not (root / "xdg-data").exists()
assert not (root / "root-precedence-home/.local").exists()
PY
pass "stable artifact-root precedence and read-only status"

bash hooks/session-start.sh --format plain > "$TEST_ROOT/plain.txt"
grep -q "<choirboy-delivery version=\"$VERSION\" delivery=\"session-start\"" "$TEST_ROOT/plain.txt"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/plain.txt"
pass "plain payload"

sid="test-$$-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$sid" \
  | bash hooks/session-start.sh --format hermes > "$TEST_ROOT/hermes-first.json"
python3 - "$TEST_ROOT/hermes-first.json" <<'PY'
import json, sys
from pathlib import Path
context = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["context"]
assert "CHOIRBOY_DOSSIER_CANARY_7f51c92d" in context
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
    "additionalContextLimit": 262144,
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
pass "Codex lifecycle hooks and full-memory context limit"

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
hooks = kimi["hooks"]
assert [hook["event"] for hook in hooks] == [
    "SessionStart", "PreCompact", "UserPromptSubmit", "Stop"
]
assert hooks[0]["matcher"] == "^(startup|resume)$"
assert hooks[1]["matcher"] == "^(manual|auto)$"
assert all(hook["timeout"] == 30 for hook in hooks)
assert hooks[0]["command"].endswith('/hooks/kimi-session-start.sh"')
assert hooks[1]["command"].endswith('/hooks/kimi-session-start.sh"')
assert hooks[2]["command"].endswith('/hooks/kimi-user-prompt.sh"')
assert hooks[3]["command"].endswith('/hooks/kimi-artifact-stop.sh"')
hermes_command = next(item["command"] for item in allowlist["approvals"] if item["event"] == "pre_llm_call")
assert hermes_command.endswith('/hooks/session-start.sh" --format hermes')
assert f'command: "{hermes_command.replace(chr(34), chr(92) + chr(34))}"' in hermes
PY
pass "quoted Hermes and Kimi lifecycle paths"

HOME="$runtime_home" ./install.sh --list > "$TEST_ROOT/kimi-structural-list.current"
grep -Eq '^kimi[[:space:]]+installed[[:space:]]+' "$TEST_ROOT/kimi-structural-list.current"
python3 - "$runtime_home/.kimi-code/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("timeout = 30", "timeout = 31", 1)
path.write_text(text, encoding="utf-8")
PY
HOME="$runtime_home" ./install.sh --list > "$TEST_ROOT/kimi-structural-list.stale"
grep -Eq '^kimi[[:space:]]+stale[[:space:]]+' "$TEST_ROOT/kimi-structural-list.stale"
HOME="$runtime_home" ./install.sh --target kimi >/dev/null
HOME="$runtime_home" ./install.sh --list > "$TEST_ROOT/kimi-structural-list.repaired"
grep -Eq '^kimi[[:space:]]+installed[[:space:]]+' "$TEST_ROOT/kimi-structural-list.repaired"
pass "Kimi status validates active TOML hook structure"

kimi_state="$runtime_home/kimi-hook-state"
kimi_session='{"hook_event_name":"SessionStart","session_id":"fixture-session","cwd":"/tmp","source":"startup"}'
kimi_compact='{"hook_event_name":"PreCompact","session_id":"fixture-session","cwd":"/tmp","trigger":"auto","token_count":12345}'
kimi_prompt='{"hook_event_name":"UserPromptSubmit","session_id":"fixture-session","cwd":"/tmp","prompt":[{"type":"text","text":"test"}],"is_steer":false}'
printf '%s\n' "$kimi_session" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-session-start.sh > "$TEST_ROOT/kimi-session-start.out"
test ! -s "$TEST_ROOT/kimi-session-start.out"
printf '%s\n' "$kimi_prompt" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-prompt-first.out"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/kimi-prompt-first.out"
printf '%s\n' "$kimi_prompt" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-prompt-second.out"
test ! -s "$TEST_ROOT/kimi-prompt-second.out"
printf '%s\n' "$kimi_compact" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-session-start.sh > "$TEST_ROOT/kimi-pre-compact.out"
test ! -s "$TEST_ROOT/kimi-pre-compact.out"
printf '%s\n' "$kimi_prompt" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-prompt-after-compact.out"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/kimi-prompt-after-compact.out"
printf '%s\n' "$kimi_session" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-session-start.sh >/dev/null
printf '%s\n' "$kimi_prompt" | CHOIRBOY_STATE_DIR="$kimi_state" \
  bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-prompt-resume.out"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/kimi-prompt-resume.out"
printf '{"hook_event_name":"Stop","session_id":"fixture-session","cwd":"/tmp","stop_hook_active":false}\n' \
  | bash hooks/kimi-artifact-stop.sh > "$TEST_ROOT/kimi-stop-ready.out" 2> "$TEST_ROOT/kimi-stop-ready.err"
test ! -s "$TEST_ROOT/kimi-stop-ready.out"
test ! -s "$TEST_ROOT/kimi-stop-ready.err"
if printf '{"hook_event_name":"Stop","session_id":"pending-session","cwd":"/tmp","stop_hook_active":false}\n' \
  | CHOIRBOY_ARTIFACTS_DIR="$TEST_ROOT/kimi-pending-artifacts" \
    bash hooks/kimi-artifact-stop.sh > "$TEST_ROOT/kimi-stop-pending.out" 2> "$TEST_ROOT/kimi-stop-pending.err"; then
  echo "Kimi Stop accepted pending artifacts" >&2
  exit 1
else
  test "$?" = 2
fi
test ! -s "$TEST_ROOT/kimi-stop-pending.out"
grep -q 'bootstrap is still incomplete' "$TEST_ROOT/kimi-stop-pending.err"
printf '{"hook_event_name":"Stop","session_id":"pending-session","cwd":"/tmp","stop_hook_active":true}\n' \
  | CHOIRBOY_ARTIFACTS_DIR="$TEST_ROOT/kimi-pending-artifacts" \
    bash hooks/kimi-artifact-stop.sh > "$TEST_ROOT/kimi-stop-active.out" 2> "$TEST_ROOT/kimi-stop-active.err"
test ! -s "$TEST_ROOT/kimi-stop-active.out"
test ! -s "$TEST_ROOT/kimi-stop-active.err"
pass "Kimi model-visible delivery and exit-2 completion gate"

kimi_transition_root="$TEST_ROOT/kimi-transition-artifacts"
kimi_transition_state="$TEST_ROOT/kimi-transition-state"
mkdir -p "$kimi_transition_root"
cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$kimi_transition_root/"
mv "$kimi_transition_root/.artifact-manifest.json" \
  "$kimi_transition_root/.artifact-manifest.saved"
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.pending"
grep -q '<choirboy-project-artifacts status="pending"' \
  "$TEST_ROOT/kimi-transition.pending"
if compgen -G "$kimi_transition_state/*.delivered" >/dev/null; then
  echo "Kimi pending bootstrap incorrectly became session-final" >&2
  exit 1
fi
mv "$kimi_transition_root/.artifact-manifest.saved" \
  "$kimi_transition_root/.artifact-manifest.json"
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.ready"
grep -q '^# Established project history$' "$TEST_ROOT/kimi-transition.ready"
grep -q 'CHOIRBOY_INDEX_CANARY_82d63a4e' "$TEST_ROOT/kimi-transition.ready"
grep -q 'CHOIRBOY_DOSSIER_CANARY_7f51c92d' "$TEST_ROOT/kimi-transition.ready"
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.suppressed"
test ! -s "$TEST_ROOT/kimi-transition.suppressed"
python3 - "$kimi_transition_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
request = json.loads((root / ".artifact-request.json").read_text(encoding="utf-8"))
artifact = root / request["projects"][0]["artifact"]
canary = "Kimi freshness canary from updated project history."
document = artifact.read_text(encoding="utf-8") + f"\n{canary}\n"
artifact.write_text(document, encoding="utf-8")
manifest_path = root / ".artifact-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
relative = artifact.relative_to(root).as_posix()
record = next(value for value in manifest["projects"].values() if value["path"] == relative)
record["artifact_sha256"] = hashlib.sha256(document.encode("utf-8")).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.refreshed"
grep -q 'Kimi freshness canary from updated project history.' \
  "$TEST_ROOT/kimi-transition.refreshed"
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.refreshed-suppressed"
test ! -s "$TEST_ROOT/kimi-transition.refreshed-suppressed"
printf '%s\n' "$kimi_compact" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-session-start.sh > "$TEST_ROOT/kimi-transition.pre-compact"
test ! -s "$TEST_ROOT/kimi-transition.pre-compact"
printf '%s\n' "$kimi_prompt" \
  | CHOIRBOY_ARTIFACTS_DIR="$kimi_transition_root" \
    CHOIRBOY_STATE_DIR="$kimi_transition_state" \
    bash hooks/kimi-user-prompt.sh > "$TEST_ROOT/kimi-transition.after-compact"
grep -q '^# Established project history$' "$TEST_ROOT/kimi-transition.after-compact"
grep -q 'Kimi freshness canary from updated project history.' \
  "$TEST_ROOT/kimi-transition.after-compact"
pass "Kimi pending-to-ready, freshness, and post-compaction delivery transitions"

legacy_commit="25078a62f13e97ed1a2eb98c4e73bc1aa8b2f1bb"
legacy_zip="$TEST_ROOT/legacy-25078.zip"
legacy_root="$TEST_ROOT/legacy-25078-root"
upgrade_home="$TEST_ROOT/upgrade-home"
upgrade_custom="$upgrade_home/custom/AGENTS.md"
git archive --format=zip --output="$legacy_zip" "$legacy_commit"
python3 - "$legacy_zip" "$legacy_root" <<'PY'
import sys, zipfile
from pathlib import Path

destination = Path(sys.argv[2])
destination.mkdir(parents=True)
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(destination)
PY
mkdir -p "$upgrade_home/.claude" "$upgrade_home/.codex" "$upgrade_home/.hermes" \
  "$upgrade_home/.kimi-code" "$upgrade_home/.gemini" "$upgrade_home/.grok" \
  "$(dirname "$upgrade_custom")"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"foreign-claude-hook"}]}]}}' \
  > "$upgrade_home/.claude/settings.json"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"foreign-codex-hook"}]}]}}' \
  > "$upgrade_home/.codex/hooks.json"
printf '%s\n' '# hermes user sentinel' > "$upgrade_home/.hermes/config.yaml"
printf '%s\n' '{"approvals":[{"event":"pre_llm_call","command":"foreign-hermes-hook"}]}' \
  > "$upgrade_home/.hermes/shell-hooks-allowlist.json"
printf '%s\n' '# kimi user sentinel' > "$upgrade_home/.kimi-code/config.toml"
printf '%s\n' '<!-- gemini user sentinel -->' > "$upgrade_home/.gemini/GEMINI.md"
printf '%s\n' '<!-- grok user sentinel -->' > "$upgrade_home/.grok/AGENTS.md"
printf '%s\n' '# custom user sentinel' > "$upgrade_custom"

upgrade_targets="claude,codex,opencode,hermes,kimi,gemini,grok,grokbot"
env -u CHOIRBOY_ARTIFACTS_DIR HOME="$upgrade_home" \
  bash "$legacy_root/install.sh" --target "$upgrade_targets" --instructions "$upgrade_custom" >/dev/null
env -u CHOIRBOY_ARTIFACTS_DIR HOME="$upgrade_home" ./install.sh --list \
  > "$TEST_ROOT/upgrade-before-list.txt"
for target in claude codex opencode hermes kimi gemini grok grokbot; do
  grep -Eq "^${target}[[:space:]]+stale[[:space:]]+" "$TEST_ROOT/upgrade-before-list.txt"
done

env -u CHOIRBOY_ARTIFACTS_DIR HOME="$upgrade_home" \
  ./install.sh --target "$upgrade_targets" --instructions "$upgrade_custom" >/dev/null
mv "$legacy_root" "$legacy_root.retired"
env -u CHOIRBOY_ARTIFACTS_DIR HOME="$upgrade_home" ./install.sh --list \
  > "$TEST_ROOT/upgrade-after-list.txt"
for target in claude codex opencode hermes kimi gemini grok; do
  grep -Eq "^${target}[[:space:]]+installed[[:space:]]+" "$TEST_ROOT/upgrade-after-list.txt"
done
grep -Eq '^grokbot[[:space:]]+prepared[[:space:]]+' "$TEST_ROOT/upgrade-after-list.txt"

python3 - "$upgrade_home" "$upgrade_custom" "$legacy_root" "$ROOT" <<'PY'
import json, sys, tomllib
from pathlib import Path

home, custom, legacy, current = map(Path, sys.argv[1:])
live = [
    home / ".claude/settings.json",
    home / ".codex/hooks.json",
    home / ".config/opencode/plugins/agent-plugin.ts",
    home / ".hermes/config.yaml",
    home / ".hermes/shell-hooks-allowlist.json",
    home / ".kimi-code/config.toml",
    home / ".gemini/GEMINI.md",
    home / ".grok/AGENTS.md",
    home / ".grokbot/choirboy-context/SKILL.md",
    custom,
]
for path in live:
    text = path.read_text(encoding="utf-8")
    assert str(legacy) not in text, f"stale checkout path remains in {path}"

claude = json.loads(live[0].read_text(encoding="utf-8"))["hooks"]
codex = json.loads(live[1].read_text(encoding="utf-8"))["hooks"]
for hooks in (claude, codex):
    flat = [handler for entries in hooks.values() for entry in entries for handler in entry["hooks"]]
    joined = json.dumps(flat)
    assert str(current / "hooks/session-start.sh") in joined
    assert str(current / "hooks/artifact-stop.sh") in joined
    assert "foreign-" in joined

opencode = live[2].read_text(encoding="utf-8")
assert str(current / "hooks/session-start.sh") in opencode
assert "agent-plugin:vibe-lore:registration=2" in opencode

hermes = live[3].read_text(encoding="utf-8")
allowlist = json.loads(live[4].read_text(encoding="utf-8"))["approvals"]
assert "# hermes user sentinel" in hermes
assert str(current / "hooks/session-start.sh") in hermes
assert {"event": "pre_llm_call", "command": "foreign-hermes-hook"} in allowlist
owned = [entry for entry in allowlist if "session-start.sh" in entry.get("command", "")]
assert len(owned) == 1 and str(current / "hooks/session-start.sh") in owned[0]["command"]

kimi_text = live[5].read_text(encoding="utf-8")
kimi = tomllib.loads(kimi_text)
assert "# kimi user sentinel" in kimi_text
assert [hook["event"] for hook in kimi["hooks"]] == [
    "SessionStart", "PreCompact", "UserPromptSubmit", "Stop"
]
assert str(current / "hooks/kimi-session-start.sh") in kimi_text
assert str(current / "hooks/kimi-user-prompt.sh") in kimi_text
assert str(current / "hooks/kimi-artifact-stop.sh") in kimi_text

for path, sentinel in (
    (live[6], "gemini user sentinel"),
    (live[7], "grok user sentinel"),
    (live[9], "custom user sentinel"),
):
    text = path.read_text(encoding="utf-8")
    assert sentinel in text
    assert "agent-plugin:vibe-lore:registration=2" in text
    assert str(current / "scripts/artifact-generator.py") in text

grokbot = live[8].read_text(encoding="utf-8")
assert "agent-plugin:vibe-lore:registration=2" in grokbot
assert any(home.rglob("*.bak.*")), "upgrade must retain timestamped backups"
PY

python3 - "$upgrade_home" > "$TEST_ROOT/upgrade-snapshot.before" <<'PY'
import hashlib, sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(root.rglob("*")):
    if path.is_file() and ".bak." not in path.name:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(path.relative_to(root).as_posix(), digest)
PY
find "$upgrade_home" -type f -name '*.bak.*' | sort > "$TEST_ROOT/upgrade-backups.before"
env -u CHOIRBOY_ARTIFACTS_DIR HOME="$upgrade_home" \
  ./install.sh --target "$upgrade_targets" --instructions "$upgrade_custom" >/dev/null
python3 - "$upgrade_home" > "$TEST_ROOT/upgrade-snapshot.after" <<'PY'
import hashlib, sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(root.rglob("*")):
    if path.is_file() and ".bak." not in path.name:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(path.relative_to(root).as_posix(), digest)
PY
find "$upgrade_home" -type f -name '*.bak.*' | sort > "$TEST_ROOT/upgrade-backups.after"
cmp "$TEST_ROOT/upgrade-snapshot.before" "$TEST_ROOT/upgrade-snapshot.after"
cmp "$TEST_ROOT/upgrade-backups.before" "$TEST_ROOT/upgrade-backups.after"
pass "25078a6 registrations migrate paths, lifecycle, backups, and idempotency"

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
assert plugin.count("agent-plugin:vibe-lore") == 3
assert "agent-plugin:vibe-lore:registration=2" in plugin
assert f"const HOOK_SCRIPT = {json.dumps(hook)}" in plugin
assert '"experimental.chat.system.transform"' in plugin
assert "output.system.push(delivered)" in plugin
assert "client.session.messages" not in plugin
assert '"chat.message"' not in plugin
assert "new Map<string, string>()" not in plugin
assert "part.synthetic" not in plugin
assert "SESSION_DELIVERY_MARKER" in plugin
assert 'delivery="session-start"' in plugin
assert 'spawnSync("bash", [HOOK_SCRIPT, "--format", "plain"]' in plugin
assert "result.status !== 0" in plugin
assert "including after session compaction" in plugin
assert "catch {" in plugin
PY
if command -v bun >/dev/null 2>&1; then
  opencode_transition_root="$TEST_ROOT/opencode-transition-artifacts"
  mkdir -p "$opencode_transition_root"
  cp -R "$CHOIRBOY_ARTIFACTS_DIR/." "$opencode_transition_root/"
  mv "$opencode_transition_root/.artifact-manifest.json" \
    "$opencode_transition_root/.artifact-manifest.saved"
  CHOIRBOY_ARTIFACTS_DIR="$opencode_transition_root" \
    bun scripts/test-opencode-transition.ts "$opencode_plugin" \
    "$opencode_transition_root"
  pass "OpenCode pending-to-ready, freshness, and compaction delivery transitions"
else
  echo "SKIP OpenCode pending-to-ready runtime test (bun unavailable)" >&2
fi
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

python3 scripts/package-plugin.py --output "$TEST_ROOT/choirboy.zip" >/dev/null
python3 - "$TEST_ROOT/choirboy.zip" <<'PY'
import stat, sys, zipfile

required = {
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    "hooks/hooks.json",
    "hooks/artifact-stop.sh",
    "hooks/kimi-artifact-stop.sh",
    "hooks/kimi-session-start.sh",
    "hooks/kimi-user-prompt.sh",
    "hooks/session-start.sh",
    "scripts/artifact-generator.py",
    "scripts/test-opencode-transition.ts",
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
}
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert required.issubset(archive.namelist())
    for executable in (
        "hooks/session-start.sh",
        "hooks/artifact-stop.sh",
        "hooks/kimi-artifact-stop.sh",
        "hooks/kimi-session-start.sh",
        "hooks/kimi-user-prompt.sh",
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
    if not document.is_file():
        continue
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
