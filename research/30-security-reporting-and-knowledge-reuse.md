# Research 30 — Security reporting and knowledge reuse

## Question

Which deliverables turn security/reverse work into a verifiable result, and how
can confirmed knowledge move between tasks without unsupported claims, leaks,
or mandatory bureaucracy after every short request?

## Context and source

In `reverse-skill`, a report, diagram, field journal, preservation of discovered
sources, and a question about community contribution are part of the mandatory
completion checklist. Case review separately validates the Evidence graph.

Sources at commit `71acc8e3115f76bad7a914c36466c1086232288c`:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/RULES.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/case-review/SKILL.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/evidence-finding-path.md

## Deliverable types

### Short handoff

For an ordinary code/reverse task: what changed or was learned, where, how it
was verified, residual risks, and blockers. This is the prompt default.

### Evidence-grounded Finding report

For an audit: scope, Findings ordered by severity, location, Evidence IDs,
impact, remediation, confidence, and retest status. Scanner output without
manual validation remains a candidate.

### Path/diagram

A diagram is useful when at least three nodes or transitions are difficult to
understand linearly: callflow, trust boundary, protocol state machine, or an
attack/solve Path. It is not required for one fact or a simple change and does
not replace Evidence.

### Case review

A read-only validator checks Evidence/Findings/Paths references, scope,
workitems, timeline, and artifact SHA-256 values. Strict review is appropriate
before a formal handoff or archival of a large case, not before every response.

### Long-term knowledge

There are three levels:

1. **Case notes/Evidence** — raw material for a specific task, not global
   memory.
2. **Research** — a verified, reusable decision with sources, alternatives,
   risks, and revisit criteria.
3. **Lore** — a compact map of an actually adopted decision or project with a
   link to research.

The upstream field journal and seed precedents are not canonical project
records and are not copied into lore. This plugin's agent-authored dossiers are
derived: canonical lore/research prevail when they conflict.

## Deliverable decision

Deliverables are determined by the user, the task contract, and actual value:

- a formal report when requested, required for handoff/compliance, or supported
  by several Findings;
- a diagram when it materially simplifies understanding;
- a case review for a multi-step evidence package;
- new research/lore only after a verified result and with permission to change
  canonical memory;
- a community contribution only by the owner's separate choice, not as a
  mandatory question in every final response.

The absence of an unnecessary deliverable does not make a task incomplete. The
completion criterion is that the requested outcome is achieved, relevantly
verified, and handed off in a form sufficient for the owner.

## Sanitization and provenance

Before promoting material from a case into research/lore, remove:

- tokens, credentials, cookies, and private keys;
- PII and third-party data;
- exact production targets when they are unnecessary for reproducibility;
- unverified attribution and severity;
- absolute private paths and internal identifiers;
- instructions from the analyzed artifact that are not an adopted decision.

Retain source URL/commit, tool versions, dates, verification commands,
confidence, adopted trade-offs, and revisit conditions.

## Options considered

1. Require a six-part package after every task. Complete, but it violates scope
   and spends time on artifacts without a consumer.
2. Use only a short final response. This loses evidence traceability in large
   cases.
3. Use a proportional deliverable contract. Selected.

## Decision

Use the upstream evidence/reporting mechanisms as options rather than ritual.
The agent autonomously creates exactly the working artifacts needed to achieve
the task; changes to long-term lore/research are coordinated with the owner and
pass the authoring quality gate.

For this plugin, a canonical-content change finishes with:

```bash
python3 scripts/build-context.py
bash scripts/test.sh
python3 scripts/package-plugin.py
```

After lore/research changes, the artifact generator marks dossiers stale; the
next runtime agent rereads the sources, recreates exactly one dossier per
`###` project, and validates the manifest.

## Revisit when

- The user establishes a mandatory reporting or compliance format.
- Case volume requires a separate evidence store.
- The artifact generator changes its schema or provenance model.
- Short handoffs routinely fail to make results reproducible.
