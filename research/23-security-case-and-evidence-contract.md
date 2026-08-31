# Research 23 — Case scope and evidence chain

## Question

How can security/reverse work remain reproducible without allowing a route or
tool to expand the authorized scope implicitly?

## Context and constraints

The architecture is adapted from `reverse-skill` at commit
`71acc8e3115f76bad7a914c36466c1086232288c`. We carry over the file contracts
and quality gate while retaining the stricter frame in `security-posture.md`:
active testing is limited to owned, integrated, or explicitly authorized
environments.

Primary sources:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/scope-contract.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/evidence-finding-path.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/timeline-workitem.md

## Case package

Long-running or active work uses one directory:

```text
work/<case>/
  scope.md
  timeline.md
  workitems.md
  evidence/
  notes/
  report/
```

`scope.md` records:

- `auth.status`: `granted`, `pending`, or `denied`;
- the basis: an owned system, laboratory, offline sample, written agreement,
  bug bounty scope, or public CTF;
- exact in-scope assets, surfaces, and permitted activities;
- out-of-scope assets and actions;
- network profile: `offline`, `lab_only`, `authorized_target_only`, or
  `unrestricted_lab`;
- deliverables, data-handling constraints, and `ready_for_act`.

Until `auth.status=granted` and `ready_for_act=true`, reading, local
classification, and scope preparation are allowed, but active interaction with
the target is not. A `--force` flag must not bypass this gate.

## Evidence → Finding → Path

### Evidence

`E-nnn` is an observation: time, source type, path or command, file SHA-256,
exact reproduction command, minimal sanitized excerpt, and its associated work
item. An old observation is never rewritten; a correction or new result becomes
a separate record with `supersedes`.

### Finding

`F-nnn` is an interpretation with severity, category, status, location, impact,
confidence, reproduction, and remediation. It must reference at least one
existing Evidence record. A `validated` finding should preferably have two
independent confirmations, usually static and dynamic; a single weak source
keeps the Finding in `candidate` or requires an explicit residual risk.

### Path

`P-nnn` connects the route from input to result. Its type depends on the task:

- `callflow` — calls and transformations in reverse engineering;
- `solve` — a laboratory/CTF solution;
- `attack` — only an authorized test path within scope.

Every material step points to Evidence and, when necessary, a Finding.

## Timeline and workitems

`timeline.md` is append-only. Each entry contains an action,
command/reference, result, artifacts, evidence IDs, `decision_delta`, links to
unchanged state, and the next step. Old entries are not edited; a correction is
a new entry with `corrects`.

`workitems.md` stores coverage and the statuses `pending`, `in_progress`,
`blocked`, `done`, and `cancelled`. This separates "the tool ran" from "the
surface was actually tested and confirmed by Evidence."

## Handoff review

Upstream `case-review` uses only the Python standard library and checks:

- scope readiness;
- Findings/Paths/workitems/timeline references to existing Evidence;
- valid statuses and confidence values;
- absence of orphaned Evidence;
- optionally, SHA-256 of case-local artifacts and prevention of path escape
  outside the case root.

The local upstream test run produced `8/8`. Review is read-only unless its
output is explicitly saved under `report/`.

## Important limitation

A Markdown gate is a procedural control, not a capability sandbox. An agent or
user can technically write `granted` by hand; an external CLI/MCP is not
required to read `scope.md`. Therefore:

1. the textual gate remains a mandatory operational check;
2. dangerous tools must also validate allowlists/scope in their own code;
3. audit logs and limits must live at the tool boundary;
4. the absence of such a check is reported as a risk, not hidden behind the
   phrase "hard gate."

## Decision

Use a lightweight case package for multi-step reverse/security tasks and always
separate observations from conclusions. A short read-only audit may use an
equivalent compact report without a `work/` directory if it preserves scope,
Evidence, and verifiable references. The format must not create bureaucracy for
its own sake; it is warranted when it helps the owner reproduce and continue
the work.

## Revisit when

- An executable policy engine binds scope to every MCP/CLI operation.
- Case packages become too large for Markdown and require a database or signed
  evidence store.
- A legal or organizational process requires formal chain of custody.
- Tests show that two independent Evidence records do not fit a particular
  type of static conclusion; the exception must be documented.
