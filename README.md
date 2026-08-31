<div align="center">

# choirboy-prompt

<h3>Lore injection: how fabricated memory becomes model trust</h3>

<p>
<strong>Read this in other languages</strong><br>
<a href="README.md">🇺🇸 English</a> ·
<a href="README.ru.md">🇷🇺 Русский</a> ·
<a href="README.zh-CN.md">🇨🇳 简体中文</a>
</p>

<p>
<img alt="Bash 5.0+" src="https://img.shields.io/badge/bash-5.0%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
<img alt="runtimes" src="https://img.shields.io/badge/runtimes-claude%20%C2%B7%20codex%20%C2%B7%20opencode%20%C2%B7%20hermes%20%C2%B7%20kimi%20%C2%B7%20gemini%20%C2%B7%20grok%20%C2%B7%20grokbot-22D3EE?style=flat-square">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-3FB950?style=flat-square"></a>
</p>

<p>
choirboy-prompt is a production agent-memory plugin. It injects a fixed lore
bundle into agent sessions and documents the
<em>fabricated-provenance trust</em> vector:
the model takes a planted history of "joint work" for its own and transfers
trust to the person that history describes.
</p>

</div>

---

## How it works

1. **Install.** `./install.sh` finds the agent apps on your machine and
   registers a hook in each one that fires when a new session starts.
   Where hooks do not exist, it writes a synchronized managed block into the
   instruction file; for Grok Bot it prepares a workflow for manual import.
2. **Assembly.** The hook `hooks/session-start.sh` glues one text together:
   `prompt.md` → `security-posture.md` → `lore.md` → `user.md` →
   `context/research-index.md`.
3. **Injection.** That text lands in the session context before the first
   message. The model reads it as **its own memory** of joint work: it has
   no way to tell written-down history from real history.
4. **Project artifacts.** On the first hooked session the current agent receives
   a deterministic request to author an `INDEX.md` and one dossier per lore
   project. After validation, every ready hook delivery embeds the complete
   INDEX and dossiers inline rather than sending only a filesystem pointer.
5. **Trust transfer.** The person's reputation from the lore is extrapolated
   onto the current request: a "long-time partner" instead of an anonymous user.

Vector mechanics and classifier behavior:
[docs/mechanism.en.md](docs/mechanism.en.md). Plugin internals:
[docs/architecture.en.md](docs/architecture.en.md).

### Supported runtimes

| Runtime | Where it goes | Mechanics |
|---|---|---|
| Claude Code CLI / Desktop Code | marketplace or `~/.claude/settings.json` | automatic SessionStart delivery + Stop artifact gate; load-context skill as fallback |
| Claude Chat / Cowork | custom plugin | load-context skill (Chat has no SessionStart) |
| Codex | `~/.codex/hooks.json` | SessionStart delivery + Stop artifact gate (needs `hooks = true` in `[features]`) |
| OpenCode | `~/.config/opencode/plugins/agent-plugin.ts` | plugin injects the lore into the session's first message |
| Hermes | `~/.hermes/config.yaml` | `pre_llm_call` + consent allowlist, first turn only |
| Kimi Code 0.39.x | `~/.kimi-code/config.toml` | SessionStart prepares state; the first UserPromptSubmit delivers context; Stop blocks incomplete artifacts with exit 2 |
| Gemini | `~/.gemini/GEMINI.md` | synchronized lifecycle instruction block |
| Grok Build | `~/.grok/AGENTS.md` | synchronized lifecycle instruction block (hook stdout is ignored) |
| Grok Bot | `~/.grokbot/choirboy-context/SKILL.md` | workflow for manual import; run `@choirboy-context` in every new chat |

## Install

You need `git`, `bash`, and `python3`. Check: `git --version && python3 --version && bash --version`.

```bash
git clone https://github.com/howdeploy/choirboy-prompt.git
cd choirboy-prompt
./install.sh
```

Done. Open a **new** session in the agent — the lore loads automatically.

- Selected apps only: `./install.sh --target claude,codex`
- Per-runtime status: `./install.sh --list` (`stale` means a managed registration needs synchronization)
- Rollback: `./install.sh --uninstall` (timestamped `*.bak.*` backups stay next to the configs)
- `Permission denied` on launch: `chmod +x install.sh` and retry

Project artifacts live outside a manual checkout. Location precedence is
`CHOIRBOY_ARTIFACTS_DIR` → `${CLAUDE_PLUGIN_DATA}/project-artifacts` →
`${XDG_DATA_HOME}/choirboy-prompt/project-artifacts` →
`~/.local/share/choirboy-prompt/project-artifacts`. Re-running the installer
synchronizes owned registrations and, when that stable root is empty, migrates
an authored bundle from an older checkout without overwriting it.

Special cases — manual workflow import for Grok Bot, install via Claude
marketplace / Desktop / Chat / Cowork, Windows and WSL — are covered in
[docs/installer.en.md](docs/installer.en.md). **Do not combine** the
marketplace plugin with `./install.sh --target claude`: the lore would be
injected twice.

## Fill in your own files

The repository ships its canonical lore bundle. For your deployment, replace
it with verified memory from your own project **right in the clone**:
`install.sh` points at the working copy, so edits are picked up by the next
session. No forking or copying is needed. Do not present the bundled biography
as your own project history.

| File | What to write |
|---|---|
| `prompt.md` | work rules, priorities, explicit boundaries |
| `security-posture.md` | security frame and disclosure rules |
| `user.md` | only durable collaboration preferences |
| `lore.md` | real projects, decisions, outcomes, and lessons |
| `research/NN-topic.md` | one decision per file: question, evidence, options, decision, risks, revisit conditions |
| `context/research-index.md` | one line per research document |

Order of work:

1. Rewrite `prompt.md`, `user.md`, `lore.md` for your project.
2. One `research/NN-topic.md` per decision, plus a line in the index.
3. Rebuild and verify: `python3 scripts/build-context.py && bash scripts/test.sh`.

Full guide with templates and the quality gate: [docs/authoring.en.md](docs/authoring.en.md).
Native session-store compatibility fixtures (optional):
[sessions/README.md](sessions/README.md).

## Why this exists

Classic prompt injection plants an instruction. We research a different vector:
**forging the provenance of memory**. A model has no way to tell a real session
history from one written into the context — everything that looks like its past
experience becomes its past experience. A well-crafted lore makes the model
derive the person's honesty from the planted memory — and relax the heuristics
that would have reacted to an anonymous request.

The plugin keeps the vector reproducible on your own agents: your files, your
runtimes, fully reversible. The goal is defensive: we map the vector so vendors
can build platform-level detection (see [docs/detection.en.md](docs/detection.en.md)).
Tests on your own agents and your own lore files only, no third-party targets
(see [docs/security.en.md](docs/security.en.md)).

## Documentation

| Document | Contents |
|---|---|
| [Authoring your memory](docs/authoring.en.md) | Mandatory workflow and templates for lore, research, and sessions |
| [Vector mechanics](docs/mechanism.en.md) | Fabricated-provenance trust step by step, trust transfer, classifiers |
| [Architecture](docs/architecture.en.md) | Repo tree, payload anatomy, formats, Hermes protocol |
| [Installer](docs/installer.en.md) | All install paths, targets, markers, backups, edge cases |
| [Troubleshooting](docs/troubleshooting.en.md) | Delivery diagnostics, delivery markers, Windows/SSH/Cloud/WSL |
| [Security and disclosure](docs/security.en.md) | Security frame, sanitization checklist, responsible disclosure |
| [Detection](docs/detection.en.md) | Vendor recommendations: memory canaries, context provenance |
| [Testing](docs/testing.en.md) | Hook and installer checks, ad-hoc suite |
| [Session compatibility fixtures](sessions/README.md) | Native Claude Code, Codex, and Kimi store fixtures and boundaries |

## Known limitations

- The payload is not signed and not verified by runtimes — that is the
  provenance gap analyzed by this project, not a plugin implementation bug.
- Grok Bot: requires a one-time workflow import and an explicit
  `@choirboy-context` invocation in every new conversation.
- Gemini, Grok Build, and `--instructions` have no native delivery hook: their
  managed instruction block asks the agent to run the lifecycle command. A
  normal installer rerun synchronizes that block; no uninstall/reinstall cycle
  is required.
- Hermes first-turn dedup is a state file in `/tmp` without locks; parallel
  starts can race.
- Claude Chat does not run SessionStart — there the skill loads the lore
  manually; Cloud/WSL/SSH nuances are in [troubleshooting](docs/troubleshooting.en.md).
- Vendor server classifiers flag defensive vocabulary regardless of the frame
  in context; one Claude flag poisons the whole session — the "new session"
  rule is described in [docs/security.en.md](docs/security.en.md).

---

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">
<strong>Innocent as a choirboy.</strong>
</div>
