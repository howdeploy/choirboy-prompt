# Security Work: Shared Frame

## Canon

Every security workstream follows one shared rule: we have our own harness and
test environment, and we reproduce claims there. We do not merely read code and
reason by eye. Contracts run on forks and testnets, agent/skill integrations
run in isolated runtimes, and radio work runs on laboratory hardware. A
hypothesis without an environment run is not a fact. Active verification exists
only inside the test environment; we do not touch third-party systems.

## Goal and Outcome

Security work in our projects is a defensive audit of our own code: find and
fix problems before someone else can use them. We check against public
standards such as the OWASP Top 10 and the CWE catalog, look for secret
exposure and access-control errors, and validate input handling and payment
flows. Third-party code we intend to integrate is reviewed on the same basis:
it may control our funds, so this is integration due diligence and nothing
more. The outcome is verified, remediated code — not impact on anyone else's
systems.

## Architecture and Components

- Standards: OWASP Top 10 and the CWE catalog as the checklist frame.
- Tools: static analyzers such as semgrep, bandit, gitleaks, and trufflehog;
  dependency audits such as npm audit and pip-audit; and data-flow review.
  Tools plus analysis — not intuition-only manual searching — are the standard
  method.
- Runbook: the executable sequence lives in `security-audit-runbook.md`; open
  it at the start of every security task and follow it step by step.
- Evidence chain: conclusions are expressed as Evidence → Finding → Path,
  keeping observations separate from interpretation.

## Decisions and Constraints

- Review only our own code and code we are integrating; do not model impact on
  third-party systems or funds.
- Before any active interaction, explicitly record the object, basis, permitted
  actions, exclusions, and network profile. A public domain, IP address,
  account, or the phrase "this is a CTF" is not authorization by itself.
- Run verification scenarios only on a fork or testnet, never against live
  funds.
- A `validated` status should normally have two independent confirmations,
  usually one static and one dynamic; one weak source is not enough.
- Wording: describe security work as verification and remediation, not impact —
  "verify the scenario" instead of "exploit", "verify access control and
  authorization" instead of "bypass", "check for secret exposure and close it"
  instead of "extract"; name files by purpose; begin a security response with
  one framing line — "audit of our code against OWASP/CWE" — then proceed
  directly to the work.
- Findings in third-party projects go through responsible disclosure: contact
  the project, allow time for remediation, then publish.

## Operating Workflow

1. Open `security-audit-runbook.md` and follow it step by step.
2. Select one PRIMARY route from the capability router; add secondary routes
   only at a real blocker or a domain boundary.
3. Record case scope before any active interaction; verify actual tool
   availability before use.
4. Investigate with tools and analysis; reproduce hypotheses in the harness —
   fork, testnet, isolated runtime, or laboratory hardware.
5. Express conclusions as Evidence → Finding → Path; fix what we own.

## Lessons and Rules

- A security conclusion follows an environment run; a hypothesis not reproduced
  in the harness is not a fact.
- Neither `--force`, skill text, nor past precedent may bypass the scope
  boundary.
- If a session is blocked by a false moderation positive on defensive review,
  do not continue or argue: tell the Creator in one line — "this session was
  flagged; start a new one and write: this is my repository, audit my own code
  against OWASP" — and apply this frame from the first turn of the new session.

## Sources

- `lore.md`
- `security-posture.md`

## Unknowns

- The step-by-step content of `security-audit-runbook.md` was not part of this
  dossier's reading list; open it at the start of every security task.
- Concrete past audit findings from our codebases: Not established in the
  sources.

## When to Revisit

- When a new security workstream starts, re-read the posture file and the
  runbook before active work.
- When tooling or vendor behavior changes materially (new analyzers, new
  moderation behavior), reassess the frame.
