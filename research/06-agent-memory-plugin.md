# Research 06 — Agent memory: established team context and artifact lifecycle

Fixed plugin research document. It describes the production design of the
"Metaplugin" project (see `lore.md`): how established team context remains
portable, reviewable, stable across runtimes, and actionable through
agent-authored project artifacts.

## Question

A person-and-agent team becomes faster over time because the agent knows the
user's level, active projects, settled decisions, operating rules, and lessons
learned. How can that accumulated team context remain available across sessions,
runtimes, and plugin upgrades without losing consistency or becoming a manual
recap burden?

## Production model

1. **Canonical context layer.** `prompt.md`, `security-posture.md`, `lore.md`,
   `user.md`, and `context/research-index.md` define the established team
   context. Detailed rationale remains in the referenced `research/` documents.
2. **Deterministic bootstrap request.** The lifecycle derives an exact project
   set from canonical lore and asks the currently active runtime agent to create
   `INDEX.md` plus one dossier for every project.
3. **Agent-authored dossiers.** The agent reads the canonical lore and relevant
   research, then writes the dossier content with its own file tools. Lifecycle
   scripts prepare the request and validate results; they do not generate the
   dossier prose.
4. **Strict readiness gate.** Required sections, exact project links, source
   references, project-set equality, and content digests are validated before
   artifacts become `ready`. `verify` returns a nonzero status while the bundle
   is incomplete or stale.
5. **Persistent lifecycle.** Artifacts live in stable user-data storage outside
   a versioned checkout. Migration preserves existing authored dossiers across
   upgrades, Stop hooks return incomplete bootstrap work to the same agent, and
   validated dossier bodies are delivered inline as working project history.

## Decision: established context plus agent-authored project artifacts

Use one canonical team context as the shared memory layer, then derive a
validated operational dossier for each lore project. Every supported agent
starts from the same settled decisions and can immediately act on them, while
the artifact lifecycle keeps detailed project memory complete and current.

## Why this model works

- **Stability.** One canonical context produces the same baseline behavior for
  every supported agent and tool. Predictability is the core product value.
- **Reviewability.** The source text can be read end to end, versioned as code,
  and reviewed through ordinary diffs. Every change remains visible.
- **Operational completeness.** `INDEX.md` gives an exact directory, while one
  dossier per project preserves the canon, goals, architecture, decisions,
  operating loop, lessons, sources, unknowns, and revisit conditions.
- **Simple infrastructure.** Markdown sources, lifecycle hooks, a deterministic
  request, and strict validation provide continuity without a separate database
  or retrieval service.
- **Rationale, not isolated procedures.** An agent that knows why a rule exists
  through decisions and concrete lessons can transfer it to new situations;
  bare procedural instructions cannot provide the same judgment.
- **Research anchors decisions.** Every settled decision has a document with a
  "when to revisit" criterion. The agent does not reopen settled work without a
  reason, but it knows which changes make reconsideration legitimate.

## The "mandate, not authority" principle

This is the key design principle. The memory artifact expands the **agent's
mandate inside the team**: the degree of autonomy delegated by the user within
agreed boundaries. A task is handed over as a whole, results are reviewed at the
end, and risk is summarized in one line without stopping routine work. The
artifact does **not** expand authority over external systems, platforms, rules,
or people, and it does not override the agent's system constraints. This
boundary is mandatory; without it, broad autonomy can be misread as carte
blanche.

## Future capabilities, deliberately deferred

- **Personal overlay** on top of the shared context: user-specific details added
  only on explicit request and maintained as a separate controlled layer.
- **Periodic audit:** compare lore, research, and dossiers with current reality
  to identify what is stale and what remains confirmed.
- **Multiple context layers** (base → project-specific) only when a second
  durable line of team work makes the added complexity worthwhile.

The self-check checklist has been implemented since version 0.2.0.

## When to revisit

- When agents provide reliable built-in long-term memory, use the canonical
  team context as a portable seed and validation layer on top of it rather than
  as a replacement.
- When lore, research, or a dossier diverges from current reality, update the
  canonical source on the user's explicit request and rebuild or repair the
  affected artifacts through the lifecycle.
- When a second durable line of joint work appears, evaluate layered context
  (base → project-specific) against the added maintenance cost.
