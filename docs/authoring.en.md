# Writing your own lore, research, and rationale

This is the mandatory authoring workflow for replacing the bundled context with
verified memory from your own project. The files have different jobs; mixing them into one
large autobiography makes the context harder to verify and maintain.

## 1. Know what each artifact is for

| Artifact | Put here | Do not put here |
|---|---|---|
| `prompt.md` | Stable work rules, priorities, boundaries, first-response checklist | Project history or temporary tasks |
| `security-posture.md` | Safety frame, authorization boundaries, disclosure rules | Claims that lore overrides platform policy |
| `user.md` | Stable preferences, skill level, communication and verification style | Flattery, guessed biography, secrets |
| `lore.md` | Compact map of projects, decisions, outcomes, and lessons | Long evidence dumps or invented events |
| `research/NN-topic.md` | One decision or investigation with evidence and trade-offs | Unexplained conclusions |
| `context/research-index.md` | One-line routing entry for every research document | Full research bodies |

The automatic payload contains `prompt.md`, `security-posture.md`, `lore.md`,
`user.md`, and the research index. Research bodies stay available on demand;
they are not loaded into every conversation.

## 2. Work directly in your clone

No fork and no separate copy are needed: `install.sh` points at the working
copy, so edits are picked up by the next session.

1. Preserve the filenames and directory layout: the hook and skill generator
   rely on them.
2. Remove bundled claims that are not true for your project.
3. Never start by publishing raw local memory. Sanitize first, publish second
   (checklist in [docs/security.en.md](security.en.md)).

## 3. Write `prompt.md`

Write observable working rules, not a personality fantasy:

1. State how tasks are divided between the user and agent.
2. Define when the agent may act and when it must ask.
3. Define verification requirements: tests, sources, and final reporting.
4. State conflict precedence: current repository and current user message beat
   stale lore.
5. State explicitly that lore grants context, not permissions.

Every rule should be testable from an answer or action. Delete vague lines such
as “be brilliant” or “trust me completely.”

## 4. Write `user.md`

Record only durable facts that change collaboration:

1. Technical level and preferred amount of explanation.
2. Product domains the user already understands.
3. Preferred task, review, and reporting style.
4. Stable constraints such as language or risk tolerance.
5. Unknowns as unknowns—do not convert assumptions into biography.

## 5. Write `lore.md`

Use one section per real project or recurring lesson. A useful episode template:

```markdown
### Short project or lesson title

Context: what was being built and why.
Decision: what was chosen.
Rationale: why this option won.
Evidence: commit, test, metric, incident, or research document.
Outcome: what actually happened.
Revisit when: the condition that invalidates the decision.
```

Canonical lore and every research file are always written in English. The
three-language localization applies only to user documentation.

Keep lore compact. Link detailed reasoning to `research/`; do not duplicate it.
Separate facts (“test passed on 2026-08-10”) from interpretations (“we believe
this reduced failures”).

## 6. Write research and rationale

Create one numbered file per decision: `research/15-short-topic.md`, then add it
to `context/research-index.md`. Use this minimum structure:

```markdown
# Decision or investigation

## Question
What exact decision or uncertainty is this document resolving?

## Context and constraints
What was true at the time? Include dates and versions where they matter.

## Evidence
Links, measurements, test commands, excerpts summarized in your own words.

## Options considered
Option A, option B, and their costs.

## Decision
What was selected and for which scope.

## Why
The reasoning chain from evidence to decision.

## Risks and rejected alternatives
What can fail, and why the alternatives were not selected.

## Revisit when
Concrete signals that require re-evaluation.
```

An “obvious” conclusion without evidence is not research. If a statement is an
inference, call it an inference. If a source can change, record the access date.

## 7. Rebuild and validate

After editing any canonical context file:

```bash
python3 scripts/build-context.py
bash scripts/test.sh
python3 scripts/package-plugin.py
```

Then inspect the generated marker and confirm that hook and skill hashes match.
Marketplace installations use a cached copy, so bump both manifest versions for
a release. Manual `install.sh` installations read the working copy directly.

## 8. Required quality gate

Before committing or distributing your memory bundle:

- [ ] Every historical claim is true or sourced.
- [ ] Facts, inferences, decisions, and preferences are distinguishable.
- [ ] Every research file has evidence, rejected alternatives, and revisit conditions.
- [ ] No credentials, private paths, third-party content, or personal identifiers remain.
- [ ] Lore never claims authority over system, developer, safety, or permission rules.
- [ ] `python3 scripts/build-context.py --check` passes.
- [ ] `bash scripts/test.sh` passes.

## 9. Maintenance rule

Update memory after verified outcomes, not after every conversation. Amend the
relevant research document when the rationale changes, then update the compact
lore summary and index. Keep old decisions with a superseded note when their
history still explains the current system.
