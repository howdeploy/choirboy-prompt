# Testing

Hook, skill, installer, diagnostics, and package checks. The canonical runner is
`bash scripts/test.sh`; the sections below explain its individual assertions.

---

## 1. Principle

- Each check is a separate bash command with an explicit PASS/FAIL.
- The suite can be invoked from anywhere; temp files go under `/tmp` with the
  `choirboy-test.` prefix.
- Temp files are removed after the run. Set `CHOIRBOY_TEST_KEEP_TMP=1` to keep
  them and print the exact directory for inspection.
- The payload is checked **in the exact form the runtime will receive it**, not
  "by feel".
- Canonical context, research, INDEX, and dossier files must be English; the
  suite rejects Cyrillic/CJK in any model-facing Markdown and the artifact
  validator enforces the same rule at runtime.

---

## 2. Hook checks

### 2.1. Manifests and version

```bash
python3 -c 'import json; d=json.load(open(".claude-plugin/plugin.json")); print(d["name"], d["version"])'
```

Expected: `plugin.json` is valid JSON and its name and version are printed.
It is the plugin-version source used in the payload. The canonical suite also
checks `hooks/hooks.json` for the Chat/Cowork custom plugin.

### 2.2. Claude format — valid JSON with context

```bash
bash hooks/session-start.sh --format claude \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "additionalContext" in d["hookSpecificOutput"]; print("OK")'
```

Expected: `OK`. Additionally check the first `prompt.md` heading and a
`choirboy-delivery` marker with version, delivery, SHA-256, and nonce.

### 2.3. Claude format without jq or python3

```bash
PYTHON_BIN="$(command -v python3)"
TMP_BIN="$(mktemp -d)"
for cmd in cat date dirname head mkdir mv sed; do
  src="$(command -v "$cmd")"
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$src" > "$TMP_BIN/$cmd"
  chmod +x "$TMP_BIN/$cmd"
done
PATH="$TMP_BIN" /bin/bash hooks/session-start.sh --format claude \
  | "$PYTHON_BIN" -c 'import json,sys; json.load(sys.stdin); print("OK")'
rm -rf "$TMP_BIN"
```

Expected: `OK`. The test deliberately removes `jq` and `python3` from `PATH`
and covers the built-in Bash encoder used by a clean Claude Desktop
installation.

### 2.4. Plain format — human-readable payload

```bash
bash hooks/session-start.sh --format plain | head -40
```

Expected: prompt → posture → lore → user → research index headings in the right
order, `---` separators.

### 2.5. Hermes: first-turn delivery

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":true}}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120
```

Expected: `{"context": "..."` — the payload arrived.

### 2.6. Hermes: second turn is silent

```bash
SID="hook-check-$(date +%s)"
printf '{"session_id":"%s","extra":{"is_first_turn":false}}' "$SID" \
  | bash hooks/session-start.sh --format hermes
```

Expected: `{}`.

### 2.7. Hermes: fallback without the flag — once per session_id

```bash
SID="hook-check-fb-$(date +%s)"
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes | head -c 120   # → context
printf '{"session_id":"%s"}' "$SID" \
  | bash hooks/session-start.sh --format hermes                 # → {}
```

Expected: first call — `{"context": ...`, second — `{}`.

> Pitfall: after the test, clean the sid from the state file
> `${TMPDIR:-/tmp}/agent-plugin-hermes-${USER}.state`, otherwise the fallback
> "remembers" the sid and the next run with the same sid returns `{}`.

### 2.8. Hermes: empty stdin does not crash the hook

```bash
printf '' | bash hooks/session-start.sh --format hermes
```

Expected: `{}` (not an error). Reason: `input="$(cat 2>/dev/null || true)"`.

---

## 3. Installer checks

### 3.1. --list

```bash
./install.sh --list
```

Expected: TARGET/STATUS/LOCATION columns; statuses `absent`/`detected`/
`installed`.

### 3.2. Idempotency

```bash
./install.sh --target hermes ; ./install.sh --target hermes
```

Expected: the second run prints `already present — skipped` / `unchanged`; no
duplicated files.

### 3.3. Backups

After installing into an existing file check:

```bash
ls -la ~/.hermes/config.yaml.bak.*
```

Expected: a timestamped backup exists.

### 3.4. Rollback

```bash
./install.sh --uninstall --target hermes
./install.sh --list | grep hermes   # → detected (not installed)
```

Expected: block removed, the `agent-plugin:vibe-lore` marker absent from the
config.

### 3.5. The hook does not fail without content files

Simulating a fresh clone (without `prompt.md`/`lore.md`/`user.md`):

```bash
TMP=$(mktemp -d)
cp -r hooks .claude-plugin "$TMP/"
# no content files in TMP
bash "$TMP/hooks/session-start.sh" --format plain >/dev/null 2>&1
echo "exit=$?"   # expected: 0 (graceful mode: files skipped with a warning in stderr)
rm -rf "$TMP"
```

Graceful mode is implemented in `hooks/session-start.sh`: missing content files
are skipped with a warning in stderr, the hook does not fail with
`set -euo pipefail` (see [docs/security.en.md](security.en.md) §3.3).

### 3.6. Plugin folder move

Install, move the folder, install again:

```bash
./install.sh --target claude
mv /path/to/plugin /path/to/plugin-moved
/path/to/plugin-moved/install.sh --target claude
```

Expected: exactly one entry of our hook in `~/.claude/settings.json` (not two);
the old one replaced the new one — `json_hook` matches by script name.

### 3.7. OpenCode adapter lifecycle

The canonical suite installs into an isolated `HOME`, repeats the install,
checks `--list`, refreshes a deliberately drifted marked plugin with a backup,
and uninstalls with another backup. It also verifies that an unmarked foreign
file at `~/.config/opencode/plugins/agent-plugin.ts` is never overwritten.

Expected: `OpenCode install, list, idempotent refresh, backup, and rollback`
and `OpenCode foreign-plugin guard` both print `PASS`. The generated adapter
must use the model-bound system-context transform, rebuild the canonical plain
payload after compaction, expose pending-to-ready and freshness changes, and
retain fail-open error handling. The runtime transition assertions live in
`scripts/test-opencode-transition.ts` and run under `bun`; when `bun` is
unavailable the suite prints `SKIP OpenCode pending-to-ready runtime test (bun
unavailable)` on stderr instead of failing.

---

## 4. Content checks (sanitization)

Before any publication:

```bash
# forbidden identifiers (NSFW/refusal model names, paths to private
# projects). The concrete name list is a private checklist outside the
# repo; here is the generic pattern:
grep -rniE "(nsfw-(checkpoint|lora)|refusal-reduction|private-research)" --include="*.md" --include="*.sh" .
# full addresses
grep -rnoE "bc1[a-zA-Z0-9]{20,}|0x[a-fA-F0-9]{40}" .
# closure: every file reference resolves
for f in $(grep -rhoE "(research/[0-9]+-[a-z-]+\.md|research/coldcard/[a-z_.]+\.(md|py))" --include="*.md" . | sort -u); do
  [ -f "$f" ] || echo "BROKEN: $f"
done
```

Expected: greps are empty; closure without BROKEN.

---

## 5. Canonical suite and package

```bash
bash scripts/test.sh
python3 scripts/package-plugin.py
```

---

## 6. When to run

- After any `hooks/session-start.sh` edit — §2.2–2.8.
- After editing `.claude-plugin/plugin.json` — §2.1.
- After an `install.sh` edit — §3.1–3.7.
- After content-file edits — run `python3 scripts/build-context.py`, then the
  canonical suite and §4 sanitization.
- After an `instruction_block` edit — grep by the marker in installed files
  (see [docs/installer.en.md](installer.en.md) §3.3).

## AGY native hooks

`python3 scripts/test-agy.py` checks named-entry ownership, foreign hooks, BOM
input, idempotency, moved commands, malformed JSON, uninstall and Bash delivery.
It is included in `scripts/test.sh`. `scripts/test-powershell.ps1` checks native
Windows registration and preservation in paths containing spaces.

After `--target agy` installation, `python3 scripts/test-agy-live.py` (Windows:
`python scripts/test-agy-live.py`) makes two harmless native AGY model calls. It
wraps the installed commands only in a temporary workspace, records SessionStart
and Stop receipts, and checks that the model echoes the actual delivery nonce on
both turns: SessionStart once, Stop twice. It uses stream-json and a custom agent
with native actions denied. It requires an authorized AGY CLI and consumes model
quota; it is not run by the offline test suite. Private context and model output
are not printed. A nonzero exit means delivery has not been proved. `--hooks` can
select a configuration file; the AGY process still uses the caller's HOME.

For an ordinary print-mode probe use `--single-turn`; `--timeout 60` bounds the
CLI process and its children. A hanging native CLI is not a passing hook check.
Compare a harmless control with hooks disabled before attributing the failure
to Choirboy; installer/configuration checks alone do not prove native delivery.
