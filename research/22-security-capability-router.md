# Research 22 — Unified security/reverse capability router

## Question

How can every agent receive the full catalog of reverse engineering and security
capabilities without loading dozens of skills at once or forcing the user to
choose a specialization manually?

## Context and source

The design is based on version 1.0.1 of the `zhaoxuya520/reverse-skill`
repository at commit `71acc8e3115f76bad7a914c36466c1086232288c`, reviewed on
2026-08-31. Its routing data lives in one structured source,
`skills/config/routing.json`; the root skill acts as the controller, while 43
routes are selectable executors.

Source:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Evidence

- The router evaluates each route's regex rules: `must`, optionally `mustAll`,
  and negative `exclude` conditions.
- PRIMARY is the route with the highest number of matched rules; ties are won
  by the earlier item in `priority`; R0 is used when nothing matches.
- `routing.json` is the SSoT, while Markdown tables are derived views.
- The upstream benchmark contains 173 requests; the local run of
  `bash skills/scripts/test-routing.sh` produced `173/173` and passed the caller
  root detection regression.
- Structural Graphify analysis of the executable portion produced 570 nodes and
  1,139 edges without dangling, self-loop, or collapsed edges.

## Complete option catalog

| ID | PRIMARY capability |
|---|---|
| R0 | General reverse engineering; also the fallback |
| R1 | APK reverse |
| R2 | Mobile reverse: Android and iOS |
| R3 | JavaScript/frontend reverse |
| R4 | DSL/custom VM reverse |
| R5 | .NET reverse |
| R6 | IDA reverse |
| R7 | radare2 |
| R8 | Firmware pentest |
| R9 | Malware analysis |
| R10 | Attack chain |
| R11 | Pentest tools |
| R12 | API security |
| R13 | Supply-chain security |
| R14 | LLM/Agent security |
| R15 | Binary diff and symbol migration |
| R16 | Patch diff/N-day analysis |
| R17 | Pwn chain |
| R18 | EDR/AV defensive reverse analysis |
| R19 | Browser/desktop automation |
| R20 | Docs generator |
| R21 | Protocol reverse |
| R22 | Ghidra reverse |
| R23 | Cloud/Kubernetes security |
| R24 | Windows/Active Directory |
| R25 | Digital forensics |
| R26 | Code audit/SAST |
| R27 | Threat hunting/detection engineering |
| R28 | OT/ICS |
| R29 | Wi-Fi/wireless |
| R30 | Browser-extension reverse |
| R31 | macOS/Mach-O reverse |
| R32 | Thick-client security |
| R33 | Go/Rust reverse |
| R34 | Hardware/debug interfaces |
| R35 | Database security |
| R36 | Email/phishing analysis |
| R37 | Identity federation: SAML/OIDC/OAuth2/SSO |
| R38 | RF/SDR research |
| R39 | Diagram generation |
| R40 | Case evidence review |
| R41 | CTF sandbox orchestrator |
| R44 | Threat intelligence/OSINT |

The upstream priority order is preserved as the reference collision-resolution
rule:
`R4, R1, R2, R3, R30, R31, R33, R5, R9, R21, R22, R6, R7, R8, R34,
R28, R17, R16, R18, R24, R37, R23, R35, R25, R44, R36, R29, R38, R32,
R26, R27, R10, R11, R12, R13, R14, R15, R19, R40, R20, R39, R41, R0`.

## Options considered

1. Load every skill at every startup. This provides complete coverage but
   consumes substantial context, introduces conflicting instructions, and
   reduces routing accuracy.
2. Require the user to name a skill. This is economical, but the user must know
   the internal taxonomy in advance.
3. Use a deterministic router and one PRIMARY. This preserves the full catalog
   while loading only the relevant operating contour.
4. Let the LLM choose freely without an SSoT. This is flexible but difficult to
   test and cannot guarantee the same choice across runtimes.

## Decision

The startup prompt stores only the existence of the shared security/reverse
contour and the rule to choose one PRIMARY. The complete map lives in this
research document. The agent:

1. classifies the current task;
2. chooses the narrowest PRIMARY;
3. attaches a secondary route only at a genuine domain boundary or blocker;
4. explains the selected branch to the owner when ambiguity remains;
5. uses R0 as a fallback, not as a reason to skip a more precise route.

Routing selects a methodology; it neither grants authority nor confirms tool
availability. Availability is checked against `research/24`, while active scope
is governed by `research/23` and `security-posture.md`.

## Risks and deviations from upstream

- We do not transfer the aggressive `agent-obedience-engineering`
  instructions: they can suppress justified clarification and approval.
- We do not require a report, diagram, journal, and community question after
  every task: deliverables are determined by the request and scope.
- Upstream `README_AI.md` refers to steps 0–14, while canonical `RULES.md`
  contains 12 steps. We use the structured router rather than a contradictory
  textual chain.
- A new capability is added only with a unique ID, a route, collision tests,
  and an index update.

## Revisit when

- A stable native runtime router appears that can be tested at least as well as
  the structured SSoT.
- Request collisions routinely require a secondary route instead of one
  PRIMARY.
- The upstream map or benchmark changes and new routes become relevant to our
  work.
- The route map noticeably degrades the startup prompt; in that case the full
  catalog remains only in research/artifacts and the prompt retains a short
  pointer.
