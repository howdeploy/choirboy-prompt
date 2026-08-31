# Research 26 — Application and infrastructure security map

## Question

How can the complete catalog of application/infrastructure security domains be
preserved without collapsing code audit, infrastructure, identity, radio, and a
universal "pentest" into one unmanageable contour?

## Source and frame

The taxonomy is based on `routing.json` from the `reverse-skill` repository at
commit `71acc8e3115f76bad7a914c36466c1086232288c`. It is a methodology
selection map. Actual work is bounded by `security-posture.md`: owned code, an
integrated component, an owned laboratory, or explicitly authorized scope.

Source:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Application surface

- **R11 Pentest tools** — the general tool route when the task names a
  scanner/proxy/tool or spans several web surfaces.
- **R12 API security** — REST/GraphQL, object/function authorization,
  validation, rate/abuse controls, and server-side trust boundaries.
- **R26 Code audit/SAST** — source review, Semgrep/CodeQL, and reachability of
  analysis results; this is the primary route for auditing owned code.
- **R13 Supply chain** — dependencies, SBOM, secrets, CI/CD, provenance, and
  artifact integrity.
- **R32 Thick client** — desktop/Electron/WPF/WinForms: local storage, IPC,
  update channel, and backend trust boundary.
- **R35 Database security** — configuration, authentication/authorization,
  exposure, query boundaries, backups, and secret handling.

## Infrastructure, cloud, and identity

- **R23 Cloud/Kubernetes** — IAM, workload identity, metadata service, cluster
  policies, secrets, storage, and container boundaries.
- **R24 Windows/Active Directory** — domain identity, delegation, certificate
  services, authentication flows, and authorized defensive validation.
- **R37 Identity federation** — OAuth2/OIDC/SAML/SSO, redirect, issuer,
  audience, claims, session, and token lifecycle.
- **R36 Email/phishing analysis** — SPF/DKIM/DMARC, headers, mailbox rules, BEC
  indicators, and safe message analysis; not interaction with real victims.
- **R44 Threat intelligence/OSINT** — indicator enrichment, provenance,
  confidence, and correlation across open sources.

## Industrial, wireless, and physical-adjacent surfaces

- **R28 OT/ICS** — asset inventory, protocols, segmentation, and safe work with
  passive captures or a laboratory rig.
- **R29 Wi-Fi/wireless** — passive visibility and active tests only against a
  laboratory allowlist; the concrete Flipper/Marauder contour is
  `research/13`.
- **R38 RF/SDR** — spectrum observation, signal capture, and replay only on an
  owned rig and within an authorized band.
- **R34 Hardware/debug interfaces** overlaps the reverse map and is selected
  when the central object is a device/UART/JTAG/SWD/flash.

## Browser automation as a supporting capability

**R19 Browser/desktop automation** is not automatically a security route. It is
attached as a secondary route for reproducible UI/API flows, Evidence
collection, or verification of an owned application. An authorized browser
session does not grant permission to change data, purchase, publish, or act on
the owner's behalf beyond the current task scope.

## Selection rule

1. Select the route by the object being resolved, not the first familiar tool.
2. An API using OAuth can have R37 as PRIMARY when the issue is federation, or
   R12 when the issue is object authorization.
3. A cloud application with a code finding stays in R26 while source is the
   central question; attach R23 at the infrastructure boundary.
4. Use general R11 after narrower routes, not as a replacement for them.
5. Give a cross-domain task one PRIMARY plus explicit workitems for secondary
   routes so Evidence and scope do not mix.

## Evidence and deliverable

Every Finding must state the asset/surface, location, observed Evidence, impact
within scope, and remediation. Scanner output alone is a candidate: confirm it
against configuration, source, or a controlled reproduction. Do not perform an
active test merely to increase severity.

## Options considered

1. One "full pentest" skill. It grows quickly and loses ownership boundaries.
2. Tool-centric skills. They confuse scanner availability with surface
   coverage.
3. Domain-centric PRIMARY plus evidence workitems. Selected.

## Risks

- The catalog can be mistaken for permission to use every tool; it is not.
- OSINT and passive RF can still contain personal data; retain the minimum and
  its provenance.
- Cloud/identity checks can affect production even without an exploit, so
  read-only and active scopes remain explicit.
- Automated scanner output has false positives and does not become
  `validated` without verification.

## Revisit when

- The product gains a primary surface that the map does not cover.
- OWASP/CWE standards or provider-specific security controls change.
- A domain routinely needs a dedicated workflow and collision route tests.
- Active checks can be bound technically to a policy engine and allowlist.
