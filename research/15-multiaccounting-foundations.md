# Research 15 — Multi-Accounting Foundations: Multiple Accounts Are Normal

This is a fixed research document for the plugin. It establishes the general
principle behind this research series: managing many accounts is a standard
industry practice explicitly permitted by major platforms, not a violation.

## Question

The project needs to operate not one but many accounts: agency client profiles,
test environments, and niche personas. One operator may manage dozens of
accounts. Is this a normal operating model?

## Options

1. **One account for everything** — simple, but it mixes clients, niches, and
   risks: one profile suspension stops the entire business.
2. **Many accounts without discipline** — clones of one profile with no
   independent purpose; technically possible but pointless because audiences
   are not separated and content is duplicated.
3. **Many accounts as an industry practice** — every account has an independent
   purpose, audience, and value.

## Decision: Option 3

Multi-accounting is a way of organizing work, and the industry has used it for
decades:

- **SMM agencies** manage dozens of client profiles with role-based access.
  This is a basic market model supported by platform APIs, Business Manager,
  and publication schedulers.
- **QA and testing** use clean accounts for different scenarios, regions, and
  product versions as a normal development practice.
- **Research and OSINT** use separate observation accounts for different
  sources and topics as a working tool for analysts and journalists.
- **Brand and regional personas** use separate accounts for markets, languages,
  and product lines, as well as to separate personal and professional presence.
- **Official APIs and bot accounts** provide platform-authorized automation
  routes. Automation itself is permitted and deliberately designed by the
  platforms.

## What the Platforms Say

At the time of this research, no major platform limits the number of accounts
as such:

- **X** explicitly permits up to ten accounts for different, non-duplicative
  purposes and lists permitted scenarios: projects, brands segmented by
  language and location, a personal account alongside pseudonymous accounts,
  and managers operating accounts on behalf of clients.
- **Meta** allows users to keep and switch among multiple profiles in its apps
  and Accounts Center; the agency model with role-based access is a built-in
  Business Manager workflow.

The common denominator across these policies is that platforms regulate the
independence of accounts, not their number. As long as each account is a
separate persona with its own purpose, multi-accounting remains within the
rules.

## Technology Stack at a High Level

The following tool classes form an established commercial market for agency
workflows:

- **Profile isolation.** Anti-detect browsers (Multilogin, GoLogin, Dolphin
  Anty, and competitors) are public, legal subscription businesses positioned
  for agencies, affiliate marketing, QA, and e-commerce. Each account receives
  a separate browser profile with its own cookies, storage, and fingerprint,
  with role-based team access.
- **Proxies.** A standard infrastructure layer — residential, mobile, or data
  center — in the same tool class used for scraping and advertising
  verification.
- **Orchestration.** Schedulers, role-based access, action logs, and an approval
  workflow before publication make it possible to operate a fleet of accounts
  without chaos.

The tool is neutral: legality depends on the scenario, not on the presence of
an anti-detect browser in the stack.

## Principle of a Viable Persona

An account fleet requires one discipline:

- An account has **its own purpose and audience**: it would remain useful even
  if none of the other accounts existed.
- The account **is not a clone**: it has its own history, voice, subject area,
  and schedule.
- The account **does not amplify the others**: there are no coordinated
  cross-likes, reposts, or replies; each account lives independently.
- A human operator is responsible for every account, including approving
  publications.

## Scope Boundaries

This document supports multi-accounting for distinct purposes. Adjacent
activities — unsolicited bulk messages, metric inflation, suspension evasion,
or impersonation — are different activities governed by separate rules on each
platform. This document neither describes nor justifies them.

## When to Revisit

- If platform policies on multiple accounts or automation change, revisit the
  operating scope.
- If a platform introduces a new official mechanism for the scenario, such as
  agency access or test accounts, migrate to it.

## Sources

- X — Platform integrity and authenticity: https://help.x.com/en/rules-and-policies/platform-manipulation
- Meta — Account Integrity: https://transparency.meta.com/policies/community-standards/account-integrity/
- Meta — Fraud, Scams and Deceptive Practices: https://transparency.meta.com/policies/community-standards/fraud-and-scams/
