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
  Claude would inject the payload twice;
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
| `--list` | Read-only status: `absent` / `detected` / `installed` |

`install.sh` requires `python3` for JSON operations. The hook's `claude` and
`plain` formats run on Bash without `jq`/`python3`; the `hermes` format requires
one of those two JSON parsers. The automatic artifact lifecycle requires
`python3`: installation prepares metadata only, while the next session asks the
current agent to write dossiers and pass the validator. Manual installs default
to `artifacts/`; `CHOIRBOY_ARTIFACTS_DIR` overrides that location.

---

## 2. Targets

Runtime detection — by binary or config-directory presence:

```bash
claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
codex)  command -v codex  >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
hermes) command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ] ;;
kimi)   command -v kimi   >/dev/null 2>&1 || [ -d "$HOME/.kimi-code" ] ;;
gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
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
| opencode | `~/.config/opencode/plugins/agent-plugin.ts` | global `chat.message` plugin |
| hermes | `~/.hermes/config.yaml` | marked `hooks.pre_llm_call` block + consent allowlist |
| kimi | `~/.kimi-code/config.toml` | marked `[[hooks]]` block |
| gemini | `~/.gemini/GEMINI.md` | marked HTML pointer block |
| `--instructions FILE` | any file | marked pointer block (HTML or `#`) |

---

## 3. Markers and idempotency

### 3.1. The marker

All blocks are marked `MARK="agent-plugin:vibe-lore"`. Marker forms:

- hash style (configs, TOML): `# >>> agent-plugin:vibe-lore >>>` /
  `# <<< agent-plugin:vibe-lore <<<`
- html style (markdown instructions): `<!-- agent-plugin:vibe-lore START -->` /
  `<!-- agent-plugin:vibe-lore END -->`

The marker is both the ownership identifier and the block boundary for removal.

### 3.2. Idempotency

- `block_add` checks the START marker: already present → `already present — skipped`,
  duplicates nothing.
- `json_hook` matches entries by script name (`session-start.sh` or
  `artifact-stop.sh` in the
  command), not by absolute path: if the plugin folder moved, the stale
  registration is replaced, not duplicated.
- A marketplace hook lives in the plugin cache and is not written into the
  `settings.json` hook array. The marketplace and manual Claude hook are
  alternatives, not two layers to enable at once.
- The OpenCode target owns one complete marked plugin file. An identical
  reinstall is a no-op; an update is backed up and replaced atomically.

### 3.3. The marker pitfall

`block_add` is idempotent by the START marker. This means: if `instruction_block`
(the pointer-block text) is edited, already-installed blocks (GEMINI.md,
`--instructions` files) **will not update** — the installer says
`already present — skipped`, the copy stays old. Remedy: patch the installed
file manually or `--uninstall` + install.

After any `instruction_block` edit — grep by the marker in installed files.

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
| `target_installed` | Already installed? | grep by marker/script name |
| `backup` | Backup before edit | `cp -p` with timestamp |
| `block_add` | Add a marked block | idempotent by START |
| `block_remove` | Remove a marked block | by START/END, cleans the trailing blank line |
| `json_hook` | Hook into Claude-shaped JSON | match by script name, `is_ours()`/`has_exact()` |
| `opencode_plugin` | Manage the OpenCode adapter | marked-file guard, atomic replace, timestamped backup |
| `hermes_allowlist` | Hermes consent allowlist | exact (event, command) pair |
| `instruction_block` | Pointer-block text | HTML or `#` comments |
| `do_claude` / `do_codex` / `do_opencode` / `do_hermes` / `do_kimi` / `do_gemini` | Target install | per-target logic |
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
  `additionalContextLimit: 20000` for the complete startup payload.
- uninstall: removes all `is_ours()` entries.
- Invalid JSON is never replaced; real changes are backed up and written
  atomically.

### 5.2. `hermes_allowlist` — details

Hermes requires explicit consent for a shell hook: the `(event, command)` pair
in `~/.hermes/shell-hooks-allowlist.json`. The function adds/removes the exact
pair `("pre_llm_call", "<session-start.sh> --format hermes")`, refuses malformed
JSON, and writes valid changes atomically.

### 5.3. `block_add` / `block_remove` — details

Work with text configs (config.yaml, config.toml, GEMINI.md):

- add: appends the block at the end (with a blank line before) if START is absent.
- remove: cuts from START to END inclusive, removes one preceding blank line if
  it was left by add.

---

## 6. Edge cases

1. **A top-level `hooks:` already exists in the Hermes config.** The installer
   refuses (`die`) with instructions to merge blocks manually — so it does not
   overwrite foreign hooks.
2. **`hooks =` already exists in the Kimi config.** Same: die with a hint to
   switch to `[[hooks]]`.
3. **Codex: hooks disabled.** `grep hooks = true` in `~/.codex/config.toml`
   not found → warning (not a block).
4. **File absent.** `mkdir -p` + creating an empty `{}`/empty file.
5. **Plugin folder moved.** JSON hooks match by script name — old entries are
   replaced, no duplicates.
6. **Re-run.** Everything is idempotent: `unchanged`/`skipped`.
7. **`--uninstall` without an install.** `no block in file — skipped`, does not
   fail.
8. **`--target none` + `--instructions`.** Only pointer blocks, no runtimes.
9. **Parallel Hermes starts.** State file in `/tmp` without locks — races are
   possible (known limitation, see README).
10. **Foreign OpenCode plugin at the managed path.** Install and uninstall
    refuse to overwrite or remove a file without the ownership marker.

---

## 7. How to verify the install

```bash
./install.sh --list                    # statuses
./install.sh --target opencode         # install the global OpenCode adapter
grep -F 'agent-plugin:vibe-lore' ~/.config/opencode/plugins/agent-plugin.ts
bash hooks/session-start.sh --format plain | head -40   # payload
echo '{"session_id":"demo","extra":{"is_first_turn":true}}' \
  | bash hooks/session-start.sh --format hermes | head -c 120   # first turn
echo '{"session_id":"demo","extra":{"is_first_turn":false}}' \
  | bash hooks/session-start.sh --format hermes            # → {}
```

The full ad-hoc suite — [docs/testing.en.md](testing.en.md).

---

## 8. Packaged research fixtures

The marketplace/custom-plugin ZIP includes the tracked `sessions/` directory so
the native-format evidence can be inspected after installation. These files are
documentation fixtures: neither `SessionStart` nor `load-context` imports them
into a user's native session store, and they are not part of the automatic lore
payload. Manual reproduction is described in [`sessions/README.md`](../sessions/README.md).
