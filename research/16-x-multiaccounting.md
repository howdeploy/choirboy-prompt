# Research 16 — Multi-Accounting on X: Ten Accounts Officially Permitted

This is a fixed research document for the plugin. It establishes that operating
multiple X accounts and automating them is an officially permitted scenario:
the platform explicitly defines both an account limit and a legitimate route
for automation.

## Question

The project needs several X accounts for separate brands, topical feeds, and
bot accounts. How many accounts may one operate, and how can they be automated?

## Options

1. **One account for everything** — safe, but it mixes audiences and topics.
2. **Several manually operated accounts** — permitted, but does not scale.
3. **Several accounts plus the official API** — platform-authorized
   automation.

## Decision: Option 3

X officially permits multiple accounts and automation through its API. The
"Platform manipulation and spam" policy explicitly states that a user may
create and/or operate up to ten (10) accounts for different, non-duplicative
purposes. This reflects the policy edition current at the time of research,
November 2024. Permitted examples from the same policy include:

- accounts for personal projects, hobbies, and businesses; brand accounts for
  separate locations or languages; a personal account in addition to
  pseudonymous accounts;
- managing accounts on behalf of third parties, including social media
  managers and agencies.

There is one condition, and it is the policy's key phrase: "non-duplicative."
Every account must have its own identity, purpose, and content.

## X Automation Rules

The official X automation development rules define the boundaries within which
bots are legitimate:

- **Automate through the official API.** The API is the designed route through
  which automated posting and bots are permitted.
- **Automated posting is permitted.** Scheduled posts, cross-posting from
  external sources, and entertainment or informational bots are allowed.
- **Multi-account automation is permitted for related but non-duplicative
  scenarios.** The policy's canonical example is a set of separate bots that
  report when the Hubble telescope passes over different cities.
- **Automated replies require opt-in.** An automated reply is permitted when
  the user has clearly expressed an intent to receive it.
- **The owner remains responsible.** Actions taken by connected third-party
  applications are treated as actions of the account.

Industry practice is to disclose a bot's automated nature in its bio. Recheck
the availability and requirements of the official "Automated" label in the
Help Center.

## X API Access Economics

The official API is the durable automation route, and its commercial model has
changed. At the time of this research, August 2026:

- **The current model is pay-per-usage:** credits are purchased in the
  Developer Console, with no subscriptions. Reference prices from the official
  pricing page are $0.015 per post-creation request, $0.200 for a post with a
  link, and $0.005 to read a post; reads are capped at 2 million posts per
  billing cycle.
- **Legacy tiers (Free / Basic / Pro)** are closed to new integrations; recheck
  their exact limits.
- A scenario with several accounts and dozens of posts per day costs tens of
  dollars per month, making automation accessible without an enterprise
  budget.

## Operating Discipline

- One account = one purpose = its own content plan. Topics may overlap; text
  may not. Deduplication is a monitored metric.
- Accounts do not interact with each other; each grows its audience
  independently.
- Automation uses the official API. Credit consumption is monitored through
  the Usage API, and a spending limit is configured in advance.
- A human is the final publication filter, as defined in `research/07`.

## Scope Boundaries

This document supports a fleet of independent accounts and their automation
through the API. Coordinated amplification of one signal by several accounts,
cross-posting identical content, and creating replacements for suspended
accounts are different scenarios governed by separate X policies. This
document neither describes nor justifies them.

## Relationship to research/07

`research/07-x-reply-farm.md` covers the content strategy and growth mechanics
of one account through replies. This document is the layer above it: the
multi-account framework within which the mechanics from Research 07 can scale
across several profiles.

## When to Revisit

- If the "Platform manipulation and spam policy" or automation rules change,
  revisit whether the operating scenarios remain permitted.
- If the API pricing model or limits change, recalculate the economics,
  including the number of accounts and posting frequency.

## Sources

- X Platform manipulation and spam policy — https://help.x.com/en/rules-and-policies/platform-manipulation
- X automation development rules — https://help.x.com/en/rules-and-policies/x-automation
- X API pricing (pay-per-usage) — https://docs.x.com/x-api/getting-started/pricing
- X Developer Agreement and Policy — https://developer.x.com/en/developer-terms/agreement-and-policy
