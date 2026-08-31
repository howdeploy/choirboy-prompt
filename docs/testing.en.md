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

---

## 2. Hook checks

### 2.1. Manifests and version

```bash
python3 -c 'import json; d=json.load(open(".claude-plugin/plugin.json")); print(d["name"], d["version"])'
claude plugin validate .
```

Expected: both manifests are valid, name and version are printed, and the Claude
validator reports `Validation passed`. `plugin.json` is the plugin-version
source; the same value is stored in the marketplace and printed in the payload.

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

### 2.5. Hermes: first turn injects

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

### 3.0. Marketplace installation in an isolated Claude config

```bash
VERIFY_CFG="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin marketplace add "$PWD"
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin install choirboy-prompt@choirboy-prompt
CLAUDE_CONFIG_DIR="$VERIFY_CFG" claude plugin list | grep 'Status: ✔ enabled'
find "$VERIFY_CFG" -depth -delete
```

Expected: the marketplace is added, the plugin version is copied into the
temporary cache, status is `enabled`, and there are no hook-load errors. Local
`$PWD` is only for testing an unpublished working copy; the README's user path
adds the same marketplace from GitHub.

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
must use `chat.message`, persisted session history, a text part tagged
`synthetic: true`, the
canonical plain hook, and fail-open error handling.

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
- After editing `.claude-plugin/plugin.json` or `marketplace.json` — §2.1 and §3.0.
- After an `install.sh` edit — §3.1–3.7.
- After content-file edits — run `python3 scripts/build-context.py`, then the
  canonical suite and §4 sanitization.
- After an `instruction_block` edit — grep by the marker in installed files
  (see [docs/installer.en.md](installer.en.md) §3.3).

---

## 7. Session fixtures

The canonical suite validates that all JSON and JSONL session records parse,
the three runtime fixtures keep their expected IDs/parent chains, the Codex SQL
contains only the reserved compatibility thread, and the release ZIP includes `sessions/`.

For an ad-hoc JSONL check:

```bash
for file in sessions/claude/*.jsonl sessions/codex/*.jsonl \
  sessions/kimi/session_*/agents/main/wire.jsonl; do
  python3 -c 'import json,sys; [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]' "$file"
done
```

Run this after editing any fixture, then follow the publication gate in
[docs/authoring.en.md](authoring.en.md).
