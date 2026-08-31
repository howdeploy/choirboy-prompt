# Research 18 — Multi-Accounting in Discord: Account Switcher and Bots

This is a fixed research document for the plugin. It establishes the operating
model for Discord: multiple user accounts plus automation through official bot
accounts, both mechanisms designed by the platform itself.

## Question

The project needs a Discord presence with separate personas (personal account /
community management), moderation of our own servers, and service automation.
Which of these does the platform support natively?

## Options

1. **One account for everything** — simple, but it mixes personal and
   professional personas and does not solve the automation requirement.
2. **Several user accounts under manual control** — separate personas through
   the built-in switcher.
3. **Official bot accounts through the Developer Portal and Bot API** —
   automation within boundaries designed by the platform.

## Decision: Options 2 + 3

The combination of user accounts and official bots covers all scenarios using
only native mechanisms:

- **Multiple accounts are not prohibited.** The Discord ToS does not prohibit
  owning several accounts, and the client includes Account Switcher. At the
  time of this research, it supports up to five accounts on one device. This is
  a built-in platform mechanism.
- **Automation goes through bots.** The Developer Portal, Bot API, and
  Application Commands are the official, supported route: a bot is registered,
  marked with the BOT label, added to a server with an administrator's explicit
  consent, and operates under the Developer Terms and Developer Policy.
- **User accounts remain manual.** Community Guidelines rule 14 states that
  every user account is associated with a human. The division of labor is
  simple: humans operate user accounts, and code operates bots.

## Legitimate Scenarios

- **Separate personas.** A personal account and an account for community work,
  switched through Account Switcher, are standard practice for community
  managers and agencies.
- **Bots for our own servers.** Moderation, automatic greetings, logging, and
  integrations use registered bots with the minimum required permissions.
  This is the purpose for which the Bot API exists.
- **Agency server management.** A manager works on a client's server through
  their own account; automation uses bots knowingly added by the server owner.
- **Bot development and QA.** Test accounts and test servers are a normal part
  of the Developer Portal development cycle.

## Operating Rules

- Automation in Discord means bot accounts. User accounts are operated
  manually.
- Every account is an independent persona with its own servers and role;
  accounts do not act as a coordinated front.
- A bot requests only necessary permissions, is visibly marked as a bot, and
  can be removed by a server administrator in one click, as required by the
  Developer Policy.
- Tokens, especially user tokens but also bot tokens, are never shared with
  third parties.

## Scope Boundaries

This document supports separate personas and bot automation. Automating user
accounts (self-bots), spam tools, raids, and artificial member inflation are
different scenarios explicitly covered by Community Guidelines rules 13–15 and
18–19. This document neither describes nor justifies them.

## When to Revisit

- If the Discord ToS, Community Guidelines, or Developer Policy changes,
  recheck the wording. This document is tied to the editions dated 2025-09-29.
- If the Account Switcher limit changes or Discord introduces new official
  multi-account mechanisms, update the section describing what is permitted.
- If a required scenario cannot be implemented with a bot account, revisit the
  architecture rather than the boundary.

## Sources

- https://discord.com/terms — Terms of Service (edition dated 2025-09-29).
- https://discord.com/guidelines — Community Guidelines: rule 13 (spam), rule
  14 (self-bots), rule 15 (artificial engagement), and rules 18–19 (identity,
  enforcement evasion).
- https://discord.com/developers/docs/policies-and-agreements/developer-policy
  — Developer Policy.
- https://support.discord.com/hc/en-us/articles/360008197871 — Account
  Switcher; limit of up to five accounts at the time of research.
