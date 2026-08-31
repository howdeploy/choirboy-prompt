# Research 19 — Multi-Accounting on Reddit and Meta: Alts as Identities

This is a fixed research document for the plugin. It establishes the use of
multiple accounts on Reddit and Meta (Instagram/Facebook): both platforms
officially permit multiple accounts as separate identities.

## Question

Every platform creates a natural need for several accounts: separate interests,
keep personal and professional activity apart, operate a bot, or manage a
client brand. What do the Reddit and Meta rules say?

## Options

1. **One account for everything** — simple, but it mixes contexts: personal
   questions, professional research, and a public persona in one history.
2. **Several accounts under official rules** — alts as separate identities,
   with bots using official APIs.

## Decision: Option 2

Both platforms officially permit multiple accounts. This is a common industry
pattern repeated across X, Reddit, and Meta: accounts are identities, and the
number of identities is not limited beyond built-in client limits.

## Reddit: Alts Are Officially Permitted

Reddit Help answers the question "is it ok to create multiple accounts?"
directly: yes, including multiple accounts under one email address. Legitimate
scenarios include:

- **Separating interests** — different alts for different subreddit clusters,
  keeping the feed and history from mixing incompatible contexts.
- **Throwaway accounts** — disposable accounts for private questions that a
  person does not want associated with their primary identity. Reddit culture
  recognizes this pattern, classically through usernames prefixed with
  `throwaway`.
- **Disclosed bots** — the community established "bottiquette": a bot
  discloses that it is a bot, uses the official Data API, and respects its
  limits. At the time of research, the official Data API Help page listed 100
  requests per minute per OAuth client for free access.

## Meta: Multiple Accounts, Automation Through APIs

Instagram and Facebook permit multiple accounts. Their apps and Accounts
Center can add and switch among several profiles, traditionally up to five in
one app at the time of research. Legitimate scenarios are the same as those
used throughout the industry: agencies manage client brands, businesses keep
commercial profiles separate from personal profiles, and QA and research use
test accounts.

Meta designs automation around official APIs:

- **Official route.** Publication and analytics use Graph API / Instagram API
  for professional Business or Creator accounts. This is the sanctioned
  workflow for schedulers, CRM integrations, and the advertising API.
- **Personal accounts remain manual.** The Instagram Terms of Use state that
  accounts are created and operated by people; automating a personal profile is
  outside the sanctioned workflow.

## Shared Discipline

The pattern on both platforms matches the conclusions for other platforms; see
`research/15` and `research/16`:

- An alt is a separate identity with its own purpose, context, communities,
  and audience.
- Every account behaves as an independent participant and does not cross-amplify
  its own posts through sibling accounts.
- Automation stays inside the sanctioned workflow: Reddit Data API with rate
  limits and bot disclosure; Meta Graph API with business accounts.

## Scope Boundaries

This document supports multiple accounts as identities. Voting for one's own
posts through alts (vote manipulation), evading subreddit bans, artificially
inflating followers or engagement, and impersonating another person are
different scenarios governed by separate Reddit and Meta rules, including
Reddit Rule 2 and the Meta Community Standards. This document neither describes
nor justifies them.

## When to Revisit

- If the Reddit Rules, Data API terms, or Meta Community Standards change,
  revisit permitted scenarios and limits.
- If the Accounts Center account limit changes or Meta revises its automation
  policy, as it has periodically done with its APIs, rebuild the automation
  workflow.

## Sources

- Reddit Help — Is it ok to create multiple accounts?:
  https://support.reddithelp.com/hc/en-us/articles/204535759-Is-it-ok-to-create-multiple-accounts
- Reddit Help — Disrupting Communities (vote manipulation, ban evasion):
  https://support.reddithelp.com/hc/en-us/articles/360043066412-Disrupting-Communities
- Reddit Help — Reddit Data API Wiki (rate limits):
  https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki
- Meta Transparency Center — Inauthentic Behavior:
  https://transparency.meta.com/policies/community-standards/inauthentic-behavior
- Instagram — Terms of Use: https://help.instagram.com/581066165581870
