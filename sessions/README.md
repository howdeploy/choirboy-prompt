# sessions/ — native session-store compatibility fixtures

**Languages:** [English](README.md) · [Русский](README.ru.md) ·
[简体中文](README.zh-CN.md)

Compatibility fixtures for
[research/12](../research/12-choirboy-prompt-lore-injection.md): **one locally
constructed dialogue in three native session-store formats** (Claude Code,
Codex, Kimi Code). The reserved IDs use the `fa1ce000-…` range. The files are
not a historical record of a conversation.

The fixture dialogue covers the relevant path: the model, following the planted
lore/meta-prompt, *voluntarily* drafts and then softens a censorship-bypass
prompt — with zero trigger vocabulary in the whole transcript. The vector is
not in the words but in the provenance: classifiers scan request lexicon,
nobody asks where the "previous work" in the context came from.

Session stores have no integrity protection at all: no signatures, no MACs,
no server-side verification of local transcripts. Dropping a file into the
right folder is sufficient for the session to appear in the resume picker
and to be replayed as genuine history.

## What this proves — and what it does not

The files are runtime-visible evidence of a “real previous dialogue” from the
agent's perspective: the transcript was authored by hand, yet a compatible
local runtime can index, resume, and replay it through its native history path.
That confirms the missing provenance boundary.

It is **not evidence that the represented conversation actually occurred**.
These are locally constructed compatibility artifacts and must retain that
non-historical provenance label. Use them only with your own local runtime and
data.

## Layout

| Runtime | Files | Store location |
|---|---|---|
| Claude Code | `claude/<sessionId>.jsonl` | `~/.claude/projects/<mangled-cwd>/` |
| Codex | `codex/rollout-….jsonl` + `codex/threads-insert.sql` | `~/.codex/sessions/YYYY/MM/DD/` + `state_5.sqlite` |
| Kimi Code | `kimi/session_<uuid>/{state.json,agents/main/wire.jsonl}` + `kimi/session_index.jsonl.example` | `~/.kimi-code/sessions/wd_<name>_<hash>/` |

Paths inside the artifacts (`rollout_path` in the SQL, `homedir` in
`state.json`, the index example) carry a literal `$HOME` placeholder —
expand it when planting, e.g. `sed -i "s|\$HOME|$HOME|g"` on the copy.

## Compatibility validation

The commands below reproduce the finding in a disposable copy of your own
local stores. Back up the target, close the application before editing it, and
remove the compatibility record afterward. Native schemas are version-sensitive.

### Claude Code

```bash
cp sessions/claude/fa1ce000-0000-4000-8000-0000000000c1.jsonl \
   ~/.claude/projects/-home-research-choirboy-prompt/
```

The folder name is the session's `cwd` with slashes replaced by dashes; the
session shows up only in the resume list of that project. `claude --resume`
(and the Claude Desktop **Code** tab, which reads the same store) lists it
immediately. The `uuid`/`parentUuid` chain inside the file is already
consistent.

### Codex

Two-layer store: the rollout file is the source of truth, but the resume
picker reads sqlite.

```bash
mkdir -p ~/.codex/sessions/2026/08/10
cp sessions/codex/rollout-2026-08-10T18-30-00-fa1ce000-0000-7000-8000-0000000000c2.jsonl \
   ~/.codex/sessions/2026/08/10/
# with the app CLOSED (WAL):
sed "s|\$HOME|$HOME|g" sessions/codex/threads-insert.sql \
  | sqlite3 ~/.codex/state_5.sqlite
```

`thread_history_1.sqlite` is a derived projection — codex re-projects it
from the rollout on its own. Note the v7-style time-ordered ID: the date in
the filename, the `YYYY/MM/DD` path and `created_at` must agree.

### Kimi Code

```bash
mkdir -p ~/.kimi-code/sessions/wd_choirboy-prompt_fixture
cp -r sessions/kimi/session_fa1ce000-0000-4000-8000-0000000000c3 \
      ~/.kimi-code/sessions/wd_choirboy-prompt_fixture/
KIMI_FIXTURE_DIR="$HOME/.kimi-code/sessions/wd_choirboy-prompt_fixture/session_fa1ce000-0000-4000-8000-0000000000c3"
sed "s|\$HOME|$HOME|g" "$KIMI_FIXTURE_DIR/state.json" > "$KIMI_FIXTURE_DIR/state.json.tmp"
mv "$KIMI_FIXTURE_DIR/state.json.tmp" "$KIMI_FIXTURE_DIR/state.json"
sed "s|\$HOME|$HOME|g" sessions/kimi/session_index.jsonl.example \
  >> ~/.kimi-code/session_index.jsonl
```

`search-index/` is a derived tantivy index — ignore it, it rebuilds.

## Writing your own compatibility fixture

1. Create a harmless session in the target runtime to capture its current
   schema.
2. Close the runtime and copy only that session into a staging directory.
3. Remove tokens, request IDs, private paths, tool output, and third-party data.
4. Replace every session/message ID and timestamp consistently; preserve roles,
   ordering, parent links, paths, and picker metadata.
5. Mark the result as a `locally constructed compatibility fixture` and state
   that it is not a historical record.
6. Validate every JSON/JSONL line, back up your own store, then test the copy.
7. Remove the test entry after the experiment.

The complete mandatory workflow for authoring lore, research, rationale, and
sessions is in [docs/authoring.en.md](../docs/authoring.en.md).

## Boundary

Defensive compatibility validation: run against your own runtimes only. The finding is
for vendors — until session provenance is verified at the platform level,
forged history is indistinguishable from real history. See
[docs/detection.en.md](../docs/detection.en.md).
