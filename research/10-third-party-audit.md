# Research 10 — Third-party contract auditing and responsible disclosure

Fixed plugin research document. It extends `research/09` on Web3 security:
that document covers mechanisms and on-chain forensics, while this one covers
auditing third-party contracts and projects and publishing findings.

## Question

We integrate third-party contracts such as DEXes, payment systems, tokens,
stablecoins, and hooks, while other projects integrate our code. Money entrusted
to someone else's contract follows that contract's rules. How should we assess
third-party contracts before integration, and what should we do with discovered
vulnerabilities?

## Options

1. **Do not audit** — trust reputation and the claim that "everyone uses it."
2. **Audit only our own code** — treat third-party contracts as black boxes.
3. **Audit third-party contracts before integration and conduct public research
   with responsible disclosure.**

## Decision: option 3

A third-party contract is code that controls our funds. Auditing it is a
mandatory due-diligence stage before any integration: listing a pool, integrating
an oracle, holding a token, or using a hook. Public research is part of the work,
not a side activity. A finding disclosed through a defined process protects
users and the project itself; a finding hidden in a drawer is a bomb.

### Why third-party auditing is mandatory

- Integration transfers money to someone else's code. A project's reputation
  does not replace reading its contract. A vulnerability in something we
  integrate becomes our vulnerability.
- The same contract may be used by hundreds of integrators. Auditing it once
  protects both our integration and theirs.
- Known vulnerability classes, listed below, can be checked quickly. This is a
  filter rather than a deep investigation, and the economics of auditing already
  work at the filtering stage.

### Why publish

- If only one auditor knows about a vulnerability, either an attacker eventually
  finds it or it surfaces after damage occurs. Coordinated disclosure gives the
  project time to fix the issue before publication.
- Publication protects the community: until a vulnerability is disclosed,
  other integrators do not know that their code is also exposed.
- A public track record of findings is professional capital for an auditor:
  project trust, bounty programs, and work. Silent findings create none of that
  capital.

## Third-party contract audit methodology

This methodology extends `research/09`:

1. **Surface.** Determine what the contract receives from us—tokens,
   permissions, callbacks—and what it can do with them: transfer, freeze, burn,
   or upgrade. Money in third-party code follows that code's rules, so this is
   the first thing to inspect.
2. **Access control.** Identify who can call dangerous functions such as
   withdraw, mint, setFee, upgrade, and pause. For owner/admin/roles, determine
   whether control belongs to a multisig or an EOA. The lesson from
   `research/09`: hook callbacks must use onlyPoolManager, or anyone can invoke
   them.
3. **Known classes**, maintained as an expanding catalog:
   - EVM: reentrancy, including read-only reentrancy and hook-enabled tokens such
     as ERC-777; oracle manipulation; approval/transferFrom; signature replay;
     CREATE2/selfdestruct; delegatecall/storage collision; unchecked return
     values; and upgradeable-logic risks involving initializers, proxies, and
     timelocks;
   - Solana: CPI reentrancy; PDA seeds and bumps; account confusion involving
     owner/signer/type/rent; close-account drains; Token-2022 extensions; and
     Anchor pitfalls such as unchecked account structs, signer seeds, and close.
4. **Money versus mechanism.** Separate an exploit from lawful mechanics. JIT,
   sandwiches, and high fee tiers are not vulnerabilities (`research/09`), while
   honeypots, drains, and backdoors are.
5. **Upgrades.** If the system uses a proxy or other upgradeable design,
   determine who can change the logic, how changes happen, whether there is a
   timelock, and who owns the proxy.
6. **PoC only on a fork or testnet.** Never test against live funds.

## Responsible disclosure process

1. Contact the project through its security contact, bounty program such as
   Immunefi, HackerOne, Sherlock, or Code4rena, or a public channel.
2. Provide a report containing the vulnerability class, impact, a fork-based
   PoC, and a proposed fix. Do not exploit third-party funds or publicly disclose
   details before a fix.
3. Allow time to fix, usually up to 90 days or as agreed with the project.
4. Publish after the fix, or after the deadline: provide a report for the
   project and community plus recommendations for integrators.
5. If no contact is possible or the project remains silent, publish after an
   ethical deadline with the minimum exploitable detail. Never publish a working
   exploit against live funds.

## Boundaries

Auditing and disclosure are white-hat practices. We do not exploit findings or
remove funds; PoCs run only on a fork or testnet; and a working exploit is not
published before a fix. This expands the `research/09` scope from protecting our
own projects to protecting the ecosystem without changing the governing rule:
we do not touch other people's funds.

## When to revisit

- Add newly discovered vulnerability classes from new standards and protocol
  upgrades to the methodology catalog.
- Reassess the process when the bounty ecosystem changes, including Immunefi
  rules or new platforms.
- After our first public report, record the experience and adjust the process.
