# Research 29 — CTF sandbox orchestration

## Question

How can a broad catalog of CTF options be carried over so the agent selects the
right specialization itself, does not load 41 child skills at once, and does
not treat the word "CTF" as unconditional permission to work against any
presented infrastructure?

## Source and license

The source is the separate `CTF-Sandbox-Orchestrator` directory in
`reverse-skill` at commit `71acc8e3115f76bad7a914c36466c1086232288c`,
reviewed on 2026-08-31:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/CTF-Sandbox-Orchestrator/ctf-sandbox-orchestrator/SKILL.md
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/CTF-Sandbox-Orchestrator/LICENSE

The primary `reverse-skill` project is MIT, while this sidecar is GPLv3. We
therefore carry over an independently worded taxonomy and architectural
decision, not copies of GPL text or executable code into the MIT plugin.

## Architecture

One implicitly invoked controller acts as the CTF orchestrator. Only it accepts
the initial task, identifies the dominant evidence type, and selects one
downstream route. Child skills are not activated together and do not require
the user to know their names.

Shared loop:

1. verify that the challenge and infrastructure genuinely fall within an
   explicit sandbox/CTF scope;
2. build a compact map of nodes, artifacts, and transitions;
3. prove one minimal path from the entry point to the decisive branch, state
   mutation, or recovered artifact;
4. select the narrowest child route;
5. broaden the surface only after Evidence for the minimal path exists;
6. repeat from a clean/reset baseline before marking the challenge solved;
7. record the solve Path and reproduction prerequisites.

## Complete set of 41 downstream options

1. AD certificate abuse
2. Agent/cloud
3. Android hooking
4. Browser persistence
5. Bundle/source-map recovery
6. Cloud metadata path
7. Container runtime
8. Crypto/mobile
9. Custom protocol replay
10. DPAPI credential chain
11. File parser chain
12. Firmware layout
13. Forensic timeline
14. GraphQL/RPC drift
15. Identity/Windows
16. iOS runtime
17. JWT claim confusion
18. Kubernetes control plane
19. Kerberos delegation
20. Kernel/container escape
21. Linux credential pivot
22. LSASS/ticket material
23. Mailbox abuse
24. Malware configuration
25. OAuth/OIDC chain
26. PCAP/protocol
27. Prompt injection
28. Queue/worker drift
29. Race-condition state drift
30. Relay/coercion chain
31. Request normalization/smuggling
32. Reverse/pwn
33. Runtime routing
34. SSRF/metadata pivot
35. Stego/media
36. Supply chain
37. Template render path
38. Web runtime
39. WebSocket runtime
40. Windows pivot
41. ZIP/archive

These names form a capability index. A concrete child research document or
skill is connected only when the task actually requires its domain.

## Corrected authorization model

The upstream controller says presented targets, nodes, and identities should be
treated as internal sandbox objects by default. That rule is not carried over.
A domain, VPS, tenant, certificate, account, or brand that looks public may be
a real external object; a mistaken assumption changes both scope and
consequences.

The default here is:

- a local challenge artifact may be analyzed passively as an untrusted file;
- active infrastructure requires an explicit basis and a list of in-scope
  assets;
- `ctf_public` is acceptable as a basis only after the challenge/organizer and
  challenge boundaries are verified;
- unknown nodes remain `unknown`, not automatically `sandbox-internal`;
- a child skill cannot broaden the controller's scope;
- secrets and personal data outside the challenge path are not enumerated.

## Evidence priority

When sources conflict, reproducible runtime behavior, captured traffic, served
assets, and current configuration take priority; checked-in source, comments,
and screenshots are weaker when they disagree with the running challenge.
Runtime Evidence is still collected only in an authorized environment.

## Options considered

1. Copy the GPL sidecar in full. This provides ready-made text but changes the
   MIT plugin's licensing obligations.
2. Collapse everything into R41 without child taxonomy. Economical, but it loses
   the available options.
3. Describe the controller and capability index independently, adding code
   separately when needed. Selected.

## Decision

Carry one CTF profile and the complete catalog of 41 downstream capabilities
into memory. This is route knowledge, not an installed set of skills. Runtime
transfer can happen through a separate GPL-compatible package or an independent
implementation of specific child skills.

## Revisit when

- We decide to distribute a GPL-compatible sidecar separately.
- A recurring challenge domain needs its own local research document/skill.
- A CTF platform changes its scope or interaction rules.
- The controller misroutes tasks between similar child capabilities.
