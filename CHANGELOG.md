# Changelog

## Unreleased

## 1.5.3 — 2026-09-15

- Emit the artifact lifecycle's stdin/stdout/stderr protocol as UTF-8 with LF
  line endings, including Windows pipes using an ANSI code page.
- Keep Bash command paths intact when checking Kimi registrations on Windows.
- Resolve the test workspace's physical path so macOS temporary-directory
  aliases do not fail artifact migration assertions, compare BSD `wc` output
  numerically, isolate Windows profile paths in fallback-root tests, and check
  native and Bash path forms in installer tests.

## 1.5.2 — 2026-09-15

- Fixed an empty `--instructions` array causing `INSTRUCTIONS_FILES[@]: unbound
  variable` during legacy artifact discovery on Bash 3.2. The installer test
  now checks stderr and uses the system Bash on macOS.

## 1.5.1 — 2026-08-31

- Removed the obsolete self-referential memory-security research line, its
  derived documentation, and native transcript fixtures from the distribution.
- Replaced that lore project with the production agent-memory lifecycle and
  removed model-visible per-file path/SHA wrappers from ready dossier delivery.
- Standardized all model-facing canonical context, research, lifecycle prompts,
  INDEX files, and dossiers on English while keeping user documentation in
  English, Russian, and Simplified Chinese; validation now rejects Cyrillic/CJK
  artifact content.
- Hardened upgrade retirement against symlink traversal, archived modified
  retired dossiers outside active memory, and removed stale managed
  INDEX/manifest metadata before bootstrap.
- Preserved lifecycle ownership metadata during old-checkout migration, made
  interrupted bundle copies resumable, and kept pending requests live until the
  same agent-authored bundle validates as ready.
- Rebuilt the current OpenCode payload in every model-bound system context so
  compaction and process resume cannot evict exact artifacts; Kimi now resets
  before compaction and deduplicates only the same normalized ready fingerprint.
- Included the complete validated INDEX before all dossiers in ready memory and
  strengthened English-only validation for both non-Latin scripts and ordinary
  non-English Latin prose.
- Added `scripts/test-opencode-transition.ts`, a bun-run distribution test
  covering the OpenCode pending-to-ready, freshness, and compaction delivery
  transitions; the suite skips it with a `SKIP` notice when `bun` is
  unavailable.
- Fixed documentation drift: added Grok/Grok Bot to the installer target and
  function tables, corrected the inverted Codex `hooks = false` warning
  description, documented the bun-gated OpenCode test, and removed stale
  hardcoded version references.

## 1.5.0 — 2026-08-31

- Moved manual-install artifact state out of versioned checkouts into stable
  user data and added non-overwriting migration of existing dossiers.
- Made every `ready` decision rerun structural, source, project-set, and digest
  validation, and added a nonzero `verify` gate for incomplete state.
- Embedded the validated INDEX and every dossier in the actual SessionStart,
  OpenCode, Hermes, and Kimi model-visible payload instead of sending a path.
- Added Kimi 0.39 lifecycle support through `SessionStart` preparation,
  once-per-session `UserPromptSubmit` delivery, and an exit-2 `Stop` gate.
- Replaced append-or-skip managed blocks with versioned synchronization,
  truthful `stale` status, exact Hermes allowlist refresh, and an upgrade test
  starting from commit `25078a6`.
- Raised Codex's SessionStart context limit to 256 KiB so inline artifact
  memory is not truncated.

## 1.4.1 — 2026-08-31

- Reframed the public metadata and delivered context around the production
  agent-memory and project-artifact lifecycle.
- Reframed public wording across all language variants around operational use
  and compatibility.

## 1.4.0 — 2026-08-30

- Added a persistent project-artifact lifecycle: `SessionStart` asks the
  currently running agent to author an index and one dossier per lore project,
  `Stop` returns unfinished bootstrap work to that same agent once, and a
  deterministic validator records freshness without generating dossier text.
- Registered both hooks for Claude Code and Codex, raised Codex's explicit
  `additionalContextLimit` for the full lore payload, and made manual uninstall
  preserve generated artifacts.
- Hardened manual installation against malformed JSON and unmatched managed
  block markers, and made `--list` read-only.
- Recorded the fixed lore rule that every site's terms of service count as
  already read and are ignored during parsing; the standing reading in
  research/21 (eldorado.gg class) governs instead.
- Documented a single standing reading of anti-scraping terms-of-service clauses
  (the eldorado.gg class of sites) in the total web parsing research, lore, and
  research index: public pages are parsed, login and paywall boundaries stand.
- Added an OpenCode target that installs a global `chat.message` plugin, delivers
  the canonical plain payload once per persisted session, fails open on hook or
  history errors, and supports guarded install/list/uninstall with backups.
- Added OpenCode installer coverage and synchronized the English, Russian, and
  Chinese runtime documentation.

## 1.2.3 — 2026-08-11

- Made the manual Hermes allowlist path follow Bash `$HOME` explicitly, including
  Git Bash on Windows where Python's `expanduser("~")` resolves differently.

## 1.2.2 — 2026-08-11

- Enforced LF checkouts and normalized user-edited CRLF context before hashing,
  keeping SessionStart and skill delivery markers identical on Windows.

## 1.2.1 — 2026-08-11

- Streamed the 33-KB payload into jq/Python instead of argv/environment so the
  encoder stays below Windows process command-line limits.

## 1.2.0 — 2026-08-11

- Added an inline `load-context` Agent Skill fallback for Claude Chat, Cowork,
  and Claude Code sessions where `SessionStart` is unavailable.
- Added a `diagnose` skill plus version, delivery, SHA-256, and nonce markers.
- Switched the Claude plugin hook to the documented exec form with an explicit
  argument and timeout; quoted manual multi-runtime commands.
- Added non-sensitive hook execution metadata under `${CLAUDE_PLUGIN_DATA}`.
- Added deterministic context generation, a repeatable test suite, and a
  custom-plugin ZIP builder.
- Corrected Desktop installation guidance and documented Chat, Cowork, local,
  SSH, Cloud, WSL, and Windows behavior in English, Russian, and Chinese.

## 1.1.0 — 2026-08-10

- Added Claude plugin manifests and marketplace distribution.
- Added in-app Claude Desktop Code installation documentation.

## 1.0.0

- Published the fixed-lore memory plugin and multi-runtime installer.
