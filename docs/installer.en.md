# Installer

Full breakdown of `install.sh`: targets, markers, idempotency, backups,
`--instructions`, edge cases. If architecture is "what is installed", this
document is "how it gets installed and removed".

---

## 0. Claude plugin installation

The repository is a versioned Claude marketplace through
`.claude-plugin/marketplace.json`. The installed package contains both the
Claude Code `SessionStart` and `Stop` hooks plus skills for Chat and Cowork.

### 0.1. Claude Code CLI

```text
/plugin marketplace add howdeploy/choirboy-prompt
/plugin install choirboy-prompt@choirboy-prompt
```

Start a new session after installation. Update or remove from the CLI with:

```text
/plugin marketplace update choirboy-prompt
/plugin update choirboy-prompt@choirboy-prompt
/plugin uninstall choirboy-prompt@choirboy-prompt
/plugin marketplace remove choirboy-prompt
```

### 0.2. Claude Desktop Code

Desktop does not expose the terminal `/plugin` dialog. Add
`https://github.com/howdeploy/choirboy-prompt` under **Customize → Plugins →
Personal plugins → + → Add marketplace**. In a local Code session choose
**+ → Plugins → Add plugin → choirboy-prompt**, then start a new session.

The marketplace cache supplies `${CLAUDE_PLUGIN_ROOT}`. `hooks/hooks.json` uses
the documented exec form (`command: bash`, one path in `args`) so spaces and
shell metacharacters in the cache path are not tokenized. A 15-second timeout
prevents a stuck hook from blocking session startup.

### 0.3. Claude Chat and Cowork

Install the repository as a custom plugin under **Customize → Plugins**, or
upload the ZIP produced by `python3 scripts/package-plugin.py`. Chat does not
run `SessionStart`: invoke the **load-context** skill. Cowork may use the hook
where supported; the skill is its fallback. The **diagnose** skill proves
delivery from a `choirboy-delivery` marker instead of relying on model wording.

### 0.4. Boundaries

- the automatic hook requires `bash`; the skill does not;
- Cloud Code sessions need project `enabledPlugins` and do not inherit a local
  Desktop installation;
- Desktop WSL plugins are unavailable, and SSH hook sync is currently
  unreliable; use the skill fallback;
- do not enable both the marketplace plugin and `./install.sh --target claude`:
  Claude would load the payload twice;
- publishing requires the same version bump in `plugin.json` and marketplace,
  followed by `python3 scripts/build-context.py` and the test suite.

---

## 1. General schema

```text
./install.sh [--target claude,opencode] [--uninstall] [--list]
             [--instructions FILE] [--project] [--settings PATH]
```

Three modes:

| Mode | What it does |
|---|---|
| install (default) | Registers hooks/blocks and prepares the artifact request |
| `--uninstall` | Removes registrations but preserves agent-authored artifacts |
| `--list` | Read-only status: `absent` / `detected` / `stale` / `installed` (`prepared` for Grok Bot) |

`install.sh` requires `python3` for JSON operations. The hook's `claude` and
`plain` formats run on Bash without `jq`/`python3`; the `hermes` format requires
one of those two JSON parsers. The automatic artifact lifecycle requires
`python3`: installation prepares metadata only, while the next session asks the
current agent to write dossiers and pass the validator. Artifact storage is
stable across checkout changes. The request and validator require English INDEX
and dossier content. Root precedence is
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`.

Before rewriting registrations, the installer inspects current and legacy hook
paths plus the current checkout's `artifacts/`. If the stable root has no
agent-authored payload, it copies the first legacy INDEX/manifest/dossier bundle
there. Existing stable artifacts are never overwritten, and uninstall preserves
them. A ready bundle is fully revalidated and embedded inline in hook context;
the runtime does not receive only an INDEX path.

---

## 2. Targets

Runtime detection — by binary or config-directory presence:

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "${KIMI_CODE_HOME:-$HOME/.kimi-code}" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
grok)   command -v grok   >/dev/null 2>&1 || [ -d "$HOME/.grok" ] ;;
grokbot) command -v grokbot >/dev/null 2>&1 || command -v grok-bot >/dev/null 2>&1 \
           || [ -d "$HOME/.grokbot" ] ;;
```

Target selection rules:

- `--target claude,opencode` — only the listed ones.
- `--target none` — empty list, useful with `--instructions`.
- Without `--target` — all detected runtimes.
- `--project` / `--settings PATH` imply the `claude` target.

Each target writes to its own file:

| Target | File | Mechanism |
|---|---|---|
| claude | `~/.claude/settings.json` (or `--settings`/`--project`) | JSON hooks `SessionStart` + `Stop` |
| codex | `~/.codex/hooks.json` | JSON hooks `SessionStart` + `Stop` |
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | model-bound system-context transform |
| hermes | `~/.hermes/config.yaml` | marked `hooks.pre_llm_call` block + consent allowlist |
| kimi | `${KIMI_CODE_HOME:-~/.kimi-code}/config.toml` | marked SessionStart + PreCompact + UserPromptSubmit + Stop hooks |
| gemini | `~/.gemini/GEMINI.md` | marked HTML lifecycle instruction block |
| grok | `~/.grok/AGENTS.md` | marked HTML lifecycle instruction block (Grok Build global rules) |
| grokbot | `~/.grokbot/choirboy-context/SKILL.md` | prepared importable workflow (not auto-loaded) |
| `--instructions FILE` | any file | marked lifecycle instruction block (HTML or `#`) |

---

## 3. Markers and idempotency

### 3.1. The marker

All blocks are marked `MARK="agent-plugin:vibe-lore"`. Marker forms:

- hash style (configs, TOML): `# >>> agent-plugin:vibe-lore >>>` /
  `# <<< agent-plugin:vibe-lore <<<`
- html style (markdown instructions): `<!-- agent-plugin:vibe-lore START -->` /
  `<!-- agent-plugin:vibe-lore END -->`

The marker is both the ownership identifier and the block boundary for removal.
Current generated blocks also carry
`agent-plugin:vibe-lore:registration=2`; `--list` uses that revision and exact
script paths to distinguish a current install from a `stale` one.

### 3.2. Idempotency

- `block_sync` appends a missing managed block or atomically replaces the one
  complete START/END block with the current generated text. Surrounding user
  content is preserved; malformed, duplicate, or nested markers are refused.
- `json_hook` matches entries by script name (`session-start.sh` or
  `artifact-stop.sh` in the
  command), not by absolute path: if the plugin folder moved, the stale
  registration is replaced, not duplicated.
- A marketplace hook lives in the plugin cache and is not written into the
  `settings.json` hook array. The marketplace and manual Claude hook are
  alternatives, not two layers to enable at once.
- The OpenCode target owns one complete marked plugin file. An identical
  reinstall is a no-op; an update is backed up and replaced atomically.
- Hermes consent entries, Kimi's four hooks, Gemini/Grok instruction blocks,
  and arbitrary `--instructions` blocks are synchronized on every installer
  run. Old absolute paths and old registration revisions are upgraded in place.

### 3.3. Managed-block upgrades

The old skip-only behavior is gone. Re-running install regenerates and replaces
an owned block when its script path, lifecycle text, or registration revision
changed, with a timestamped backup first. `--list` reports `stale` when an owned
registration exists but is not the exact current registration. Run the normal
install command to synchronize it; an uninstall/install cycle is not required.

---

## 4. Backups and rollback

Every edit of an existing file is preceded by a backup:

```bash
backup() {
  [ -f "$1" ] || return 0
  cp -p "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"
}
```

Files like `settings.json.bak.20260802-153000` remain after `--uninstall` —
removed manually once the user confirms everything is fine.

Rollback: `./install.sh --uninstall` removes exactly the marked blocks and our
JSON entries, does not touch foreign ones.

---

## 5. Function breakdown

| Function | Purpose | Key logic |
|---|---|---|
| `target_present` | Runtime detection | binary or config dir |
| `claude_settings_file` | Where to write the Claude hook | `--settings` > `--project` > `~/.claude/settings.json` |
| `target_installed` | Exact current install? | per-target revision/path/hook checks |
| `target_managed_present` | Older owned install? | ownership marker/script ids; drives `stale` |
| `backup` | Backup before edit | `cp -p` with timestamp |
| `block_sync` | Add or upgrade a marked block | exact START/END replacement, atomic write |
| `block_remove` | Remove a marked block | by START/END, cleans the trailing blank line |
| `json_hook` | Hook into Claude-shaped JSON | match by script name, `is_ours()`/`has_exact()` |
| `opencode_plugin` | Manage the OpenCode adapter | marked-file guard, atomic replace, timestamped backup |
| `hermes_allowlist` | Hermes consent allowlist | exact (event, command) pair |
| `instruction_block` | Lifecycle instruction text | HTML or `#` comments |
| `grokbot_workflow` | Manage the Grok Bot workflow file | `install`/`uninstall`/`status`, marked-file guard |
| `discover_legacy_artifact_roots` | Find old checkout-local bundles | inspect old managed absolute paths |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` / `do_grok` / `do_grokbot` | Target install | per-target logic |
| `do_instructions` | Install into an arbitrary file | style by extension |

### 5.1. `json_hook` — details

Works with Claude-shaped hook JSON files (`settings.json`, `hooks.json`). The
key — **matching by script name**, not by path:

```python
def is_ours(entry):
    return any(hook_id in
               (h.get("command", "") + " " + " ".join(h.get("args", [])))
               for h in entry.get("hooks", []))
```

- install: removes stale registrations of our script (folder moved), adds the
  exact handler if absent. Claude receives `command: bash`, one `args` path, and
  `timeout: 15`; Codex keeps its quoted command and sets
  `additionalContextLimit: 262144` so the fixed lore and inline artifact memory
  remain in the same startup context.
- uninstall: removes all `is_ours()` entries.
- Invalid JSON is never replaced; real changes are backed up and written
  atomically.

### 5.2. `hermes_allowlist` — details

Hermes requires explicit consent for a shell hook: the `(event, command)` pair
in `~/.hermes/shell-hooks-allowlist.json`. The function adds/removes the exact
pair `("pre_llm_call", "<session-start.sh> --format hermes")`, refuses malformed
JSON, and writes valid changes atomically.

### 5.3. `block_sync` / `block_remove` — details

Work with text configs (config.yaml, config.toml, GEMINI.md):

- sync: appends the block if absent; otherwise replaces exactly one complete
  START/END range, preserving all surrounding content. Identical text is a no-op.
- safety: malformed, duplicate, or nested markers stop the install instead of
  guessing ownership. A real update is backed up and written atomically.
- remove: cuts from START to END inclusive, removes one preceding blank line if
  it was left by add.

### 5.4. Kimi 0.39.x lifecycle hooks

Kimi 0.39.x discards `SessionStart` stdout, so the managed TOML block installs
four hooks:

- `SessionStart` (`startup|resume`) prepares artifact state and resets the
  delivery fingerprint;
- `PreCompact` (`manual|auto`) resets it synchronously before compaction;
- `UserPromptSubmit` runs the canonical plain delivery and emits pending
  bootstrap repeatedly, or a ready bundle whenever its fingerprint changes;
- `Stop` exits 2 with the continuation request on stderr while validation is
  pending, and exits 0 at `ready`.

The state markers live below
`${KIMI_CODE_HOME:-~/.kimi-code}/choirboy-prompt/hook-state` unless
`CHOIRBOY_STATE_DIR` overrides them. A normalized ready fingerprint is stored
only after stdout was emitted successfully.

---

## 6. Edge cases

1. **A top-level `hooks:` already exists in the Hermes config.** The installer
   refuses (`die`) with instructions to merge blocks manually — so it does not
   overwrite foreign hooks.
2. **`hooks =` already exists in the Kimi config.** Same: die with a hint to
   switch to `[[hooks]]`.
3. **Codex: hooks disabled.** A `hooks = false` line found in
   `~/.codex/config.toml` → warning (not a block).
4. **File absent.** `mkdir -p` + creating an empty `{}`/empty file.
5. **Plugin folder moved.** JSON hooks match by script name and managed text
   blocks are synchronized — old absolute paths are replaced, not duplicated.
6. **Re-run or upgrade.** Current registrations are no-ops; old owned ones are
   reported as `stale` and upgraded in place by normal install.
7. **`--uninstall` without an install.** `no block in file — skipped`, does not
   fail.
8. **`--target none` + `--instructions`.** Only managed lifecycle instruction
   blocks, no runtime-specific hooks.
9. **Parallel Hermes starts.** State file in `/tmp` without locks — races are
   possible (known limitation, see README).
10. **Foreign OpenCode plugin at the managed path.** Install and uninstall
    refuse to overwrite or remove a file without the ownership marker.

---

## 7. How to verify the install

```bash
./install.sh --list                    # statuses
./install.sh --target opencode         # install the global OpenCode adapter
python3 scripts/artifact-generator.py status
python3 scripts/artifact-generator.py verify  # exit 2 unless fully ready
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # payload
echo '{"session_id":"hook-check","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # first turn
echo '{"session_id":"hook-check","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

In `--list`, `stale` is actionable: rerun install for that target and verify it
becomes `installed` (or `prepared` for Grok Bot). For a ready artifact bundle,
`session-context` must contain `# Established project history` and the complete
dossier bodies; a path-only message is not a successful memory delivery.

The full ad-hoc suite — [docs/testing.en.md](testing.en.md).
