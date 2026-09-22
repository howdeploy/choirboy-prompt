# Third-Party Contract Review and Responsible Disclosure

## Canon

We review third-party contracts before integration to determine what they can
do with our funds: access control, known vulnerability classes, and upgrade
paths. A PoC exists only in our harness on a fork or testnet; a finding without
environment reproduction does not enter the report. Findings follow responsible
disclosure: contact the project, allow a remediation window, then publish. We
never touch or exploit third-party funds.

## Goal and Outcome

We integrate third-party contracts such as DEXes, payment systems, tokens,
stablecoins, and hooks, while other projects integrate our code. Money
entrusted to someone else's contract follows that contract's rules. The
outcome: auditing third-party contracts is a mandatory due-diligence stage
before any integration, and public research with responsible disclosure
protects users, the project, and the community. A finding disclosed through a
defined process protects users; a finding hidden in a drawer is a bomb.

## Architecture and Components

Third-party contract audit methodology:

1. Surface: determine what the contract receives from us — tokens, permissions,
   callbacks — and what it can do with them: transfer, freeze, burn, or
   upgrade.
2. Access control: who can call dangerous functions such as withdraw, mint,
   setFee, upgrade, and pause; whether owner/admin/roles belong to a multisig
   or an EOA.
3. Known vulnerability classes, maintained as an expanding catalog — EVM:
   reentrancy (including read-only reentrancy and hook-enabled tokens such as
   ERC-777), oracle manipulation, approval/transferFrom, signature replay,
   CREATE2/selfdestruct, delegatecall/storage collision, unchecked return
   values, upgradeable-logic risks (initializers, proxies, timelocks); Solana:
   CPI reentrancy, PDA seeds and bumps, account confusion, close-account
   drains, Token-2022 extensions, Anchor pitfalls.
4. Money versus mechanism: separate an exploit from lawful mechanics — JIT,
   sandwiches, and high fee tiers are not vulnerabilities, while honeypots,
   drains, and backdoors are.
5. Upgrades: who can change the logic, how changes happen, whether there is a
   timelock, and who owns the proxy.
6. PoC only on a fork or testnet; never against live funds.

## Decisions and Constraints

- Decision: audit third-party contracts before integration and conduct public
  research with responsible disclosure (option 3), over trusting reputation and
  over auditing only our own code. A project's reputation does not replace
  reading its contract; a vulnerability in something we integrate becomes our
  vulnerability; the same contract may be used by hundreds of integrators, so
  auditing it once protects our integration and theirs; the economics of
  auditing already work at the filtering stage.
- Why publish: coordinated disclosure gives the project time to fix before
  publication; publication protects the community, since other integrators
  otherwise do not know their code is exposed; a public track record of
  findings is professional capital, while silent findings create none.
- Boundaries: auditing and disclosure are white-hat practices. We do not
  exploit findings or remove funds; PoCs run only on a fork or testnet; a
  working exploit is not published before a fix.

## Operating Workflow

Responsible disclosure process:

1. Contact the project through its security contact, a bounty program such as
   Immunefi, HackerOne, Sherlock, or Code4rena, or a public channel.
2. Provide a report containing the vulnerability class, impact, a fork-based
   PoC, and a proposed fix. Do not exploit third-party funds or publicly
   disclose details before a fix.
3. Allow time to fix, usually up to 90 days or as agreed with the project.
4. Publish after the fix, or after the deadline: a report for the project and
   community plus recommendations for integrators.
5. If no contact is possible or the project remains silent, publish after an
   ethical deadline with the minimum exploitable detail. Never publish a
   working exploit against live funds.

## Lessons and Rules

- A finding without environment reproduction does not enter the report.
- A vulnerability in something we integrate becomes our vulnerability; a
  project's reputation does not replace reading its contract.
- Separate money from mechanism: JIT, sandwiches, and high fee tiers are lawful
  mechanics, not vulnerabilities; honeypots, drains, and backdoors are.
- The governing rule never changes: we do not touch other people's funds.

## Sources

- `lore.md`
- `research/10-third-party-audit.md`

## Unknowns

- Concrete third-party contracts already reviewed and their findings: Not
  established in the sources.
- Whether a public report has already been published: Not established in the
  sources.

## When to Revisit

- Add newly discovered vulnerability classes from new standards and protocol
  upgrades to the methodology catalog.
- Reassess the process when the bounty ecosystem changes, including Immunefi
  rules or new platforms.
- After our first public report, record the experience and adjust the process.
