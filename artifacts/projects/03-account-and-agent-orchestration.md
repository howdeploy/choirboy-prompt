# Account and Agent Orchestration

## Canon

We built one control plane for an account fleet across platforms: account and
persona registry, a pool of interchangeable agents (writer, replier, moderator,
analyst), a scheduler with human-looking timing, and platform adapters over
official APIs (X, Telegram Bot API/MTProto, Discord bots, Reddit Data API, and
Meta Graph API). The persona lives in the registry rather than in an agent, so
agents and accounts can be hot-swapped through drain → reassign → resume.
Concurrent operation relies on per-account and per-platform limiters plus
session isolation. The platform-specific baseline is `research/15`–`19`; the
complete rebuild specification is `research/20`.

## Goal and Outcome

The lore projects produce many accounts: the X farm (`research/07`), Telegram
sales (`research/08`), and community platforms. Every "account + script" pair
lived independently, with its own cron jobs, limits, and tokens scattered
across repositories. The goal: manage dozens of accounts on different
platforms as one system. The outcome: one operator can manage dozens of
personas without chaos, and platform-specific rules live in adapters rather
than in the operator's head. Multi-accounting for distinct purposes is a
standard industry practice explicitly permitted by major platforms, not a
violation.

## Architecture and Components

- **Registry.** Accounts and personas: platform, status (`warmup` / `active` /
  `paused` / `retired`), style, history, and daily limits. The persona — niche,
  voice, topics, schedule profile, blacklist — lives here, not in any agent,
  which is the prerequisite for swapping.
- **Agent pool.** An agent is a role plus a skill: writer, replier (following
  `research/07`), moderator, or analyst. An agent is not permanently bound to
  an account; it puts on the account's persona from the registry.
- **Scheduler.** A task queue with a human-like schedule: daily per-account
  limits, interval jitter, and gradual ramp-up. No activity spikes.
- **Matchmaking.** Assign tasks by platform × role × account status × current
  agent load.
- **Platform adapters.** A unified `publish / reply / read / metrics`
  interface over official APIs; every platform rule belongs in its adapter.
- **Approval workflow.** A human remains the final publication filter: the
  machine controls pace, the human controls quality.
- **Audit log.** Append-only records of who (agent) did what (action), through
  which account, when, and with what result; records are never edited.
- **Unified event bus.** Posts, replies, and metrics from all platforms flow
  into one observability stream.
- **Commercial tool classes** available for the stack: profile isolation
  through anti-detect browsers (Multilogin, GoLogin, Dolphin Anty) with
  role-based team access; residential/mobile/data-center proxies; and
  orchestration tooling.

## Decisions and Constraints

- **Decision: our own control plane (option 3)**, over ad hoc scripts per
  account (chaos multiplies, tokens get lost) and platform managers/SMM panels
  (no personas, roles, approval workflow, or custom pipelines).
- **Many accounts as an industry practice**: SMM agencies, QA and testing,
  research and OSINT, and brand/regional personas all operate fleets as a
  normal model. Platforms regulate the independence of accounts, not their
  number. The tool is neutral: legality depends on the scenario.
- **X** (`research/16`): up to ten accounts for different, non-duplicative
  purposes is explicitly permitted; automation goes through the official API,
  automated replies require opt-in, and the owner remains responsible for
  third-party app actions. The current API model is pay-per-usage (credits in
  the Developer Console, no subscriptions; ~$0.015 per post-creation request);
  a scenario with several accounts costs tens of dollars per month.
- **Telegram** (`research/17`): multiple accounts are a native product feature
  (up to 3 per client, 4 with Premium; separate phone number each); bots are
  first-class entities via the Bot API (~20 bots per account in practice);
  userbots are legitimate through MTProto with our own `api_id`/`api_hash`.
  Documented Bot API limits: 1 msg/s per chat, 20 msg/min per group, ~30 msg/s
  bulk; exceeding returns 429, not a ban.
- **Discord** (`research/18`): multiple user accounts are not prohibited, and
  the Account Switcher holds up to five; automation goes through official bot
  accounts from the Developer Portal, visibly BOT-labeled, added with server
  admin consent. User accounts stay manual — rule 14 ties every user account
  to a human.
- **Reddit** (`research/19`): alts are officially permitted, including several
  accounts under one email; bots follow community "bottiquette" — disclosed,
  on the official Data API, within 100 requests/minute per OAuth client.
- **Meta** (`research/19`): multiple profiles (traditionally up to five per
  app) are supported via Accounts Center; automation is sanctioned through
  Graph API / Instagram API for Business or Creator accounts; personal
  profiles stay manual.
- **Principle of a viable persona** (`research/15`): each account has its own
  purpose and audience, is not a clone, does not amplify the others (no
  coordinated cross-likes, reposts, or replies), and a human operator is
  responsible for it, including approving publications.
- **Orchestrator discipline**: rotation balances load and breaks; it is not
  restriction evasion. A departed account is not replaced by a clone. One
  hundred accounts are one hundred separate lives, not one accelerated life.
- **Scope boundaries**: unsolicited bulk messages, metric inflation,
  suspension evasion, self-bots, vote manipulation, and impersonation are
  separate scenarios governed by separate platform rules; this project neither
  describes nor justifies them.

## Operating Workflow

- **Swapping** without stopping the pipeline: agent swap drains in-flight
  tasks to completion and reassigns through the registry; account swap puts the
  account in `paused`, redistributes its queue within the niche, and returns it
  through gradual ramp-up; a new account enters only through `warmup`, with
  weeks of manual activity before automation. Operator swap works through
  shifts plus the approval workflow and audit log.
- **Concurrency**: a per-account rate limiter controls daily limits,
  intervals, and pace; a per-platform limiter controls API ceilings
  (pay-per-usage X, Bot API limits, 100 QPM Reddit). The limiter is attached
  to the account, not the process. Every account has its own credentials and
  session — no cross-account access in code or data.
- **MVP data model** (one migrated database, SQLite is enough): `account`,
  `persona`, `agent`, `task` (with `dedup_key` and statuses
  queued/assigned/draining/pending_approval/done/rejected), and append-only
  `audit`.
- **Swap protocol interfaces**: `drain(agent_id)` finishes in-flight tasks and
  assigns no new ones; `pause(account_id)` redistributes the queue;
  `retire(account_id)` removes the account without replacing it with a clone.
- **Build order**: (1) registry + audit log; (2) first adapter on a platform
  with a live account (X or Telegram); (3) scheduler with per-account limiter;
  (4) approval workflow (drafts in the operator's Telegram DM); (5) first
  agent is the replier, then the writer; (6) swapping and the agent pool only
  after the queue reliably stays non-empty.
- **Definition of done**: one operator manages 5+ accounts through the system,
  every action appears in the audit log, no action occurs outside official
  APIs, and every account keeps a human-like pace.

## Lessons and Rules

- Swapping without drain drops tasks: hot replacement killed in-flight
  replies. Drain → reassign → resume; the persona belongs in the registry, not
  in the agent.
- Limit per account, not per process: one global throttle still allowed an
  individual account to spike. Enforce per-account limits plus a per-platform
  ceiling.
- One account = one purpose = its own content plan. Topics may overlap; text
  may not — deduplication is a monitored metric.
- Accounts do not interact with each other; each grows its audience
  independently.
- Userbot actions do not exceed a human pace; a 429 response means reduce the
  rate. One process operates one account.
- Automation stays inside the sanctioned workflow of each platform: official
  APIs, bot disclosure, and rate limits; tokens are never shared with third
  parties.

## Sources

- `lore.md`
- `research/15-multiaccounting-foundations.md`
- `research/16-x-multiaccounting.md`
- `research/17-telegram-multiaccounting.md`
- `research/18-discord-multiaccounting.md`
- `research/19-reddit-meta-multiaccounting.md`
- `research/20-account-orchestration.md`

## Unknowns

- The current production fleet size and which platforms are live: Not
  established in the sources.
- Exact per-account daily limiter values per niche: Not established in the
  sources.
- Whether the X "Automated" label is currently available and required:
  `research/16` says to recheck it in the Help Center.
- The exact Telegram client account limit is not fixed in official documents;
  the figures (3, or 4 with Premium) are confirmed by client interfaces.

## When to Revisit

- If platform policies on multiple accounts or automation change (X policy,
  Telegram ToS/API terms, Discord ToS/Guidelines of 2025-09-29, Reddit Rules,
  Meta Community Standards), revisit the operating scope and the relevant
  adapter.
- If the X API pricing model or limits change, recalculate the economics:
  number of accounts and posting frequency.
- If a platform introduces an official agency mechanism for our scenario,
  migrate to it and simplify the adapter.
- If the fleet grows beyond the capacity of one approval workflow, revisit the
  operator-shift and delegation model.
