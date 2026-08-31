# Security and disclosure

The security frame, the pre-publication sanitization checklist, and the rules of
responsible disclosure. This document is how the project treats itself.

---

## 1. Controlled validation frame

The project is published for **defensive security validation**:

- tests — on **your own** agents and **your own** lore files;
- no third-party targets: other users, their data, and their agents are not
  affected;
- the finding is directed at vendors and harness authors — so detection is built
  at the platform level (see [docs/detection.en.md](detection.en.md)).

The vector is reproduced under controlled conditions, never used against
third-party systems. Every publication explains the mechanics without handing
out a ready-made attack tool against foreign systems.

---

## 2. Research boundaries

| Allowed | Not allowed |
|---|---|
| Research the vector on your own agents | Use the vector against foreign agents/users |
| Publish the mechanics and lore artifacts | Publish working tools for recovering foreign keys |
| Direct findings to vendors | Exploit findings before the fix |
| Analyze publicly disclosed incidents | Expose victim addresses and full consolidators |
| Give vendors detection recommendations | Publish PoCs against live systems |

These boundaries are not decoration: they correspond to `research/10` (third-party
contract audits and responsible disclosure) and `research/09` (web3 security, key
entropy).

---

## 3. Pre-publication sanitization checklist

By nature the plugin carries **personal memory** — the joint-work history of a
"human + agent" pair. A public repository is a different space from a local
install. Checklist:

### 3.1. Content

A **sanitized** version is published: the lore and research docs carry the
mechanism under review, but without identifying details.

- [ ] `prompt.md`, `lore.md`, `user.md` — published; checked that they contain no
      paths to private projects and no personal data.
- [ ] `security-posture.md` — published as part of the payload; neutral
      vocabulary, no instructions revealing moderation bypass beyond the public
      frame.
- [ ] `research/01–14` — published; checked that they contain no names of
      specific NSFW/refusal models, no paths to files with addresses, and no full
      addresses.
- [ ] `security-audit-runbook.md` — executable audit commands; safe, references
      `security-posture.md` — verify the linkage.

### 3.2. Identification

- [ ] No mentions of paths to private projects (weak-entropy research
      repositories, etc.).
- [ ] No full wallet addresses; only anonymized prefixes (`bc1qnk…`) if needed
      at all.
- [ ] No names of specific NSFW/refusal models or refusal-removing LoRAs;
      functional roles remain ("NSFW checkpoint", "refusal reduction"). The
      concrete list of forbidden names lives **outside the repo** (private
      checklist) — it is not reproduced in public documents.
- [ ] No "Creator/Master" addresses and no personal details in public texts.

### 3.3. Mechanics

- [ ] Manual installation reads the working copy live; marketplace installation
      uses a cache and receives edits only after a version bump.
- [ ] `python3 scripts/build-context.py --check` passes: the inline skill is an
      exact generated copy of the sanitized canonical context.
- [ ] `${CLAUDE_PLUGIN_DATA}/latest-delivery.log` contains metadata only
      (version, hash, nonce, plugin root), never lore or user text.
- [ ] The hook works without content files (graceful mode): in a fresh clone
      without the canonical context files it does not fail with
      `set -euo pipefail` — it skips missing files with a warning.

### 3.4. Repository

- [ ] `.gitignore` created **before** the first `git add .` (see example below).
- [ ] `LICENSE` exists (README and badge reference it).
- [ ] Manifest `.claude-plugin/plugin.json` renamed to the public name
      (`choirboy-prompt`), version bumped.
- [ ] `.claude-plugin/marketplace.json` has the same version as `plugin.json`;
      `claude plugin validate .` passes.

### 3.5. Example `.gitignore`

Content is published, so `.gitignore` is only housekeeping:

```gitignore
# local backups install.sh makes while editing configs
*.bak.*
# editor/OS
.DS_Store
*.swp
```

---

## 4. Responsible disclosure rules (per research/10)

Findings in foreign projects follow the process:

1. Contact the project: security contact, bounty program (Immunefi, HackerOne,
   Sherlock, Code4rena), or a public channel.
2. Report: class, impact, PoC **on a fork/testnet**, suggested fix. No
   exploitation of foreign funds, no public disclosure before the fix.
3. Fix window (usually up to 90 days, by agreement).
4. Publication after the fix (or after the deadline): report for the project and
   community, recommendations for integrators.
5. If contact is impossible or the project stays silent — publication on an
   ethical deadline, with a minimum of exploitable details: we never publish a
   working exploit against live funds.

---

## 5. Behavior on a session flag

A known vendor problem: server classifiers flag defensive vocabulary regardless
of the frame in context. One Claude flag poisons the whole session — it only gets
worse from there.

Rule: in a flagged session we do not continue and do not argue. We start a new
session with an explicit frame from the first turn: "this is my repository, audit
of my own code per OWASP". In the new session we work from that frame.

This is not part of the vector — it is a countermeasure against false flags.

---

## 6. Publication risk assessment

| Risk | Level | Mitigation |
|---|---|---|
| Repo identifies the author (personal memory) | Medium | Sanitization: private-project paths, full addresses, NSFW/refusal model names cut out |
| Vector read as a censorship-bypass guide | Medium | Research frame in the README and this document; mechanics + countermeasures, not "how to attack" |
| Address/key leak | Critical | Pre-publication check: grep for bc1/0x/seed files |
| NSFW model name leak | High | Functional roles instead of names; private list outside the repo |
| AI audit as a guarantee | — | Coldcard teardown (`research/11`): a one-off AI audit missed the bug; audits must check the executable path, not code presence |

---

## 7. Publishing session fixtures

Native transcripts can contain more sensitive material than lore. Before adding
anything under `sessions/`:

- use only your own disposable runtime and conversation;
- remove credentials, request IDs, private paths, tool output, and third-party data;
- replace identifiers consistently without breaking parent chains or picker metadata;
- label every locally constructed transcript as a non-historical compatibility fixture;
- state that runtime acceptance proves missing provenance, not a historical event;
- test against a backed-up local store with the application closed.

The complete authoring and sanitization gate is in
[docs/authoring.en.md](authoring.en.md).
