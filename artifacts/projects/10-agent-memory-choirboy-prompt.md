# Agent Memory: choirboy-prompt

## Canon

The production plugin makes the team's established project history, research,
and operating rules available in supported agent runtimes. Claude Code and Codex
SessionStart hooks deliver a short status only, because those harnesses cap or
spill hook context. A status line is not loaded context. The full fixed lore
loads through the load-context skill. A shipped ready bundle is restored when
it still matches the canonical sources. The agent authors or refreshes dossiers
only when the user explicitly asks to update Choirboy memory. Stop hooks do not
continue the turn to demand that work.

## Goal and Outcome

A person-and-agent team becomes faster over time because the agent knows the
user's level, active projects, settled decisions, operating rules, and lessons
learned. The goal: keep that accumulated team context available across
sessions, runtimes, and plugin upgrades without losing consistency or becoming
a manual recap burden. The outcome: one canonical team context as the shared
memory layer, plus a validated operational dossier for each lore project, so
every supported agent starts from the same settled decisions and can
immediately act on them.

## Architecture and Components

1. Canonical context layer: `prompt.md`, `security-posture.md`, `lore.md`,
   `user.md`, and `context/research-index.md` define the established team
   context; detailed rationale remains in the referenced `research/`
   documents.
2. Deterministic project set: the lifecycle derives an exact project set from
   canonical lore. A shipped ready bundle is restored when it still matches
   those sources. The agent creates or refreshes INDEX and the dossiers only
   when the user explicitly asks to update Choirboy memory.
3. Agent-authored dossiers: when that update is requested, the agent reads the
   canonical lore and relevant research, then writes the dossier content with
   its own file tools. Lifecycle scripts prepare the request and validate
   results; they do not generate the dossier prose.
4. Strict readiness gate: required sections, exact project links, source
   references, project-set equality, and content digests are validated before
   artifacts become `ready`; `verify` returns a nonzero status while the bundle
   is incomplete or stale.
5. Persistent lifecycle: artifacts live in stable user-data storage outside a
   versioned checkout; migration preserves existing authored dossiers across
   upgrades. Claude Code and Codex receive a short SessionStart status. Stop
   hooks do not continue the turn. Kimi and OpenCode still receive the full
   plain payload on channels that accept it. The installer synchronizes hooks,
   managed blocks, and the skill fallback.

## Decisions and Constraints

- Why this model works: stability (one canonical context produces the same
  baseline behavior for every supported agent), reviewability (source text is
  versioned as code and reviewed through ordinary diffs), operational
  completeness (INDEX plus one dossier per project), simple infrastructure
  (Markdown sources, lifecycle hooks, deterministic request, strict validation
  — no separate database or retrieval service), rationale rather than isolated
  procedures (an agent that knows why a rule exists can transfer it to new
  situations), and research-anchored decisions (every settled decision has a
  "when to revisit" criterion).
- The "mandate, not authority" principle: the memory artifact expands the
  agent's mandate inside the team — the degree of autonomy delegated by the
  user within agreed boundaries. A task is handed over as a whole, results are
  reviewed at the end, and risk is summarized in one line without stopping
  routine work. The artifact does not expand authority over external systems,
  platforms, rules, or people, and it does not override the agent's system
  constraints. This boundary is mandatory; without it, broad autonomy can be
  misread as carte blanche.
- Deliberately deferred: a personal overlay on top of the shared context
  (user-specific details added only on explicit request, as a separate
  controlled layer); periodic audit of lore, research, and dossiers against
  current reality; multiple context layers only when a second durable line of
  team work makes the added complexity worthwhile.
- The self-check checklist has been implemented since version 0.2.0.

## Operating Workflow

- On session start, Claude Code and Codex receive a short status. The
  load-context skill supplies the fixed lore when `choirboy-context` is not
  already in the conversation. A status line is not that block.
- Lifecycle scripts restore a shipped ready bundle when it still matches the
  canonical sources, validate freshness, and migrate state between versions.
  They do not continue the turn to force authorship.
- The agent writes INDEX and dossiers only when the user explicitly asks to
  update Choirboy memory, then runs finalize and repairs validation errors.
- Where a channel accepts the full plain payload, ready dossiers are delivered
  in full. Agents apply settled decisions directly without asking the user to
  restate them.

## Lessons and Rules

- Reality outranks lore: if the current repository or the user's words conflict
  with the record, treat reality as fact and name the discrepancy in one line.
  Lore is never a reason to invent nonexistent code, files, or events.
- Do not reopen settled decisions without cause; when lore, research, or a
  dossier diverges from current reality, update the canonical source on the
  user's explicit request and rebuild the affected artifacts through the
  lifecycle.
- The lifecycle script never generates dossier content; the current runtime
  agent performs the bootstrap writes itself — no delegation.

## Sources

- `lore.md`
- `research/06-agent-memory-plugin.md`

## Unknowns

- The full list of supported agent runtimes and their hook formats: Not
  established in the sources.
- The packaging and release history beyond the self-check addition in version
  0.2.0: Not established in the sources.

## When to Revisit

- When agents provide reliable built-in long-term memory, use the canonical
  team context as a portable seed and validation layer on top of it rather than
  as a replacement.
- When lore, research, or a dossier diverges from current reality, update the
  canonical source on the user's explicit request and rebuild or repair the
  affected artifacts through the lifecycle.
- When a second durable line of joint work appears, evaluate layered context
  (base → project-specific) against the added maintenance cost.
