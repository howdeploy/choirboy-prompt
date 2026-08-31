# Security audit runbook — execution order

This is the executable sequence for a defensive audit of our code. Open it at
the start of every security task and follow it step by step. The framing,
wording, and boundaries are in `security-posture.md`.

## 0. Open the task

- In a new session, the first message carries the frame: "this is my repository;
  audit my own code against OWASP/CWE."
- Record scope: modules, payment flows, and entry points such as webhooks, APIs,
  and input parsers.
- If the session is already moderation-flagged, do not continue or argue; apply
  the rule in `security-posture.md` and tell the Creator in one line.

## 1. Secrets in code and history

    gitleaks detect --verbose     # working tree and history
    trufflehog git file://.       # second engine, different heuristics

If a real secret is found in the repository, revoke or rotate it first and clean
history afterward. Never copy the secret into the report; record only its type,
location, and rotation status.

## 2. Static analysis

    semgrep --config p/owasp-top-ten --config p/security-audit
    bandit -r .                   # Python projects

## 3. Dependencies

    npm audit / pip-audit / cargo audit    # choose by stack

Put critical reachable findings in our code paths into the remediation plan.
List the rest with current and fixed versions.

## 4. Manual checklist review

Only after running the tools, and guided by their findings and step-0 scope:

- access control: does every handler verify object ownership?
- payment flows: are webhook signatures and idempotency enforced, with amounts
  and statuses sourced server-side only?
- input validation: injection, SSRF, path traversal, and deserialization?
- logging: are secrets and personal data excluded from logs?

## 5. Triage findings

Confirm or disprove every finding from the code, not intuition. Format:
severity, `file:line`, and the remediation. Record false positives with the
reason they are false.

## 6. Report

Write Markdown with findings ordered by severity. Use verification and
remediation language, as defined in `security-posture.md`, without exploit
details or ready-made PoCs. Name report files and helper functions by purpose,
for example `access_review.md` and `verify_input.py`.

## 7. After remediation

Rerun steps 1–3; the findings must close. Add a dated "reverified" line to the
report.

---

If a tool is unavailable, install it in an isolated environment such as
pipx/venv or run that step through a local model in Hermes. Never skip a step
silently; if it is skipped, state why in the report.
