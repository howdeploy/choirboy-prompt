# Troubleshooting

Diagnose registration, execution, delivery, and model behavior separately. A
Claude acknowledgement is not evidence that `SessionStart` ran.

## Surface matrix

| Surface | Install | Primary delivery | Fallback / limit |
|---|---|---|---|
| Claude Code CLI | `/plugin` marketplace | automatic `SessionStart` | `/choirboy-prompt:load-context` |
| Desktop Code local | graphical Plugin Manager | automatic `SessionStart` | load-context skill |
| Claude Chat | custom plugin | load-context skill | Chat does not execute hooks |
| Claude Cowork | custom plugin | hook where available | load-context skill; hook runtime may drop output |
| Desktop Code SSH | graphical Plugin Manager | hook when synchronized | current SSH sync can omit `hooks/` |
| Desktop Code Cloud | project plugin settings | automatic hook | local Desktop plugins are not inherited |
| Desktop Code WSL | — | — | Desktop plugins are unavailable |

## Four-stage diagnosis

1. **Registration:** the plugin manager shows `choirboy-prompt` enabled and
   version `1.3.0`.
2. **Execution:** a marketplace hook creates
   `${CLAUDE_PLUGIN_DATA}/latest-delivery.log` with version, hash, and nonce.
3. **Delivery:** `/choirboy-prompt:diagnose` finds a `choirboy-delivery` marker
   next to `choirboy-context`.
4. **Behavior:** only after the first three stages pass should model acceptance,
   conflicting instructions, or memory be investigated.

Marker delivery values:

- `session-start` — the hook stdout reached the model;
- `skill` — the load-context fallback supplied the lore.

## Common failures

### `/plugin` is unavailable in Desktop

Expected: Desktop does not expose the terminal plugin dialog. Add the repository
under **Customize → Plugins → Personal plugins → + → Add marketplace**, then use
**Code → + → Plugins → Add plugin**.

### Plugin is installed in Chat but nothing changes

Expected for a hook-only workflow: Chat does not execute `SessionStart`. Select
the **load-context** skill or ask Claude to load Choirboy context.

### Cowork shows the plugin but no marker

Invoke **load-context**. Cowork hook execution is not deterministic across
current builds; the skill is the supported fallback.

### Windows hook error

Version 1.3.0 uses exec form so `${CLAUDE_PLUGIN_ROOT}` is a single argument, but
automatic delivery still needs `bash` on `PATH`. Install Git for Windows or use
the skill fallback. The skill itself has no Bash, jq, Python, or Node dependency.

### Hook runs twice

The marketplace plugin and `./install.sh --target claude` are both enabled.
Remove one path. The manual installer warns when it sees the marketplace entry.

### Cloud, SSH, or WSL

Cloud sessions require `extraKnownMarketplaces` and `enabledPlugins` in project
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "choirboy-prompt": {
      "source": {
        "source": "github",
        "repo": "howdeploy/choirboy-prompt"
      }
    }
  },
  "enabledPlugins": {
    "choirboy-prompt@choirboy-prompt": true
  }
}
```

Claude still asks the user to trust the marketplace/plugin. SSH can currently
fail to synchronize `hooks/`; use the skill. Desktop WSL plugins are unavailable.

## Maintainer checks

```bash
python3 scripts/build-context.py --check
bash scripts/test.sh
python3 scripts/package-plugin.py
```

The suite validates manifests, skill freshness, hook JSON, the dependency-free
Bash encoder, installer idempotency/rollback, diagnostics, and ZIP contents.

## Sessions are not an automatic fallback

The packaged `sessions/` directory contains locally constructed compatibility
fixtures, not a memory-import mechanism. Installing the plugin does not insert those records
into Claude Code, Codex, or Kimi stores. Native formats are version-sensitive;
use the app-closed, backed-up procedure in
[`sessions/README.md`](../sessions/README.md) only on your own local runtime.
