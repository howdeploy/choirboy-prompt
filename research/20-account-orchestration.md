# Research 20 — Agent and Account Orchestration: A Unified Management Pipeline

This is a fixed research document for the plugin. It establishes the
architecture of the orchestration project: a unified control plane that manages
a fleet of accounts on any platform through a pool of interchangeable agents,
with hot swapping and simultaneous operation. The platform-specific boundary
for each adapter is defined in `research/15–19`.

## Question

The lore projects produce many accounts: the X farm (`research/07`), Telegram
sales (`research/08`), and community platforms. Every "account + script" pair
lives independently, with its own cron jobs, limits, and tokens scattered
across repositories. How can dozens of accounts on different platforms be
managed as one system?

## Options

1. **Ad hoc scripts for every pair** — this is how the work began, but every
   new account multiplies the chaos, limits diverge, and tokens get lost.
2. **Platform managers** such as publication schedulers and SMM panels — they
   cover scheduled posting but not agent logic: no personas, roles, approval
   workflow, or custom pipelines such as `research/07`.
3. **Our own control plane** — an account registry, agent pool, scheduler, and
   platform adapters operating as one system.

## Decision: Option 3

Use one orchestrator in which accounts and agents are independent entities
connected by assignments rather than by code. Its key properties are that any
agent can work with any account on a compatible platform, replacement happens
without stopping the pipeline, and the entire fleet operates concurrently
within platform limits.

## Architecture

Pipeline components:

- **Registry.** Accounts and personas: platform, status (`warmup` / `active` /
  `paused` / `retired`), style, history, and daily limits. The persona lives in
  the registry rather than in the agent, which is the prerequisite for
  swapping.
- **Agent pool.** An agent is a role plus a skill: writer for posts, replier for
  replies following `research/07`, moderator for communities, or analyst for
  metrics and reports. An agent is not permanently bound to an account; it puts
  on the account's persona from the registry.
- **Scheduler.** A task queue with a human-like schedule: daily per-account
  limits, interval jitter, and gradual ramp-up. There are no activity spikes,
  following Rule 2 from the lore.
- **Matchmaking.** Assign tasks by platform × role × account status × current
  agent load.
- **Platform adapters.** A unified `publish / reply / read / metrics` interface
  over official APIs: X API (`research/16`), Telegram Bot API and MTProto
  (`research/17`), Discord bot accounts (`research/18`), Reddit Data API, and
  Meta Graph API (`research/19`). Every platform rule belongs in its adapter,
  not in the operator's head.
- **Approval workflow.** A human remains the final publication filter as in
  `research/07`: the machine controls pace, while the human controls quality.
- **Audit log.** Append-only records of who (agent) did what (action), through
  which account, when, and with what result. Trust in the system is bounded by
  the readability of this log.

## Swapping

Hot replacement without stopping the pipeline uses three mechanisms:

- **Agent swap.** In-flight tasks are drained to completion; new assignments
  go to another agent, which loads the persona and context from the registry.
  Agents are interchangeable because identity is stored separately from the
  executor.
- **Account swap.** An account enters `paused`, and its queue is redistributed
  among other accounts in the same niche. It returns through a gradual ramp-up,
  as after any break. A new account enters the pool only through `warmup`, with
  weeks of manual activity before automation, following `research/07`.
- **Operator swap.** People work in shifts. The approval workflow and audit log
  make handoff of the fleet between operators routine rather than ceremonial.

## Simultaneous Management

- **Limiters at two levels.** A per-account rate limiter controls daily limits,
  intervals, and pace; a per-platform limiter controls API ceilings, including
  pay-per-usage X, Bot API limits, and 100 QPM for Reddit Data API. The limiter
  is attached to the account, not the process: a global throttle does not catch
  bursts from one specific account.
- **Session isolation.** Every account has its own credentials and session.
  There is no cross-account access in either code or data.
- **Unified event bus.** Posts, replies, and metrics from all platforms flow
  into one observability stream, letting the analyst agent see the entire fleet.

## Orchestrator Discipline

The relationship to `research/15–19` is mandatory rather than declarative:

- Every account is an independent persona under the principle from
  `research/15`. The orchestrator does not perform cross-account actions; there
  are no likes, reposts, or replies for sibling accounts.
- Rotation balances load and breaks; it is not a way to evade restrictions. A
  departed account is not replaced by a clone, and a restricted account is not
  substituted with the next account in line.
- Every account maintains a human-like pace regardless of fleet size. One
  hundred accounts are one hundred separate lives, not one accelerated life.

## Rebuilding the System: MVP

An agent reading this document must be able to build the system from scratch
without additional questions. The construction order has been validated on our
projects: every step is a working system on its own, and the next step extends
it.

**Data model, one migrated database; SQLite is enough for the MVP:**

- `account` — id, platform, handle, persona_id, status
  (`warmup`/`active`/`paused`/`retired`), credentials_ref, daily_limit,
  timezone, warmed_up_at.
- `persona` — id, niche, voice (style and vocabulary), topics,
  schedule_profile, blacklist.
- `agent` — id, role (writer/replier/moderator/analyst), skills, load.
- `task` — id, account_id, agent_id, type (publish/reply/read/report), payload,
  status (queued/assigned/draining/pending_approval/done/rejected), not_before,
  dedup_key.
- `audit` — ts, agent_id, account_id, action, payload_hash, result. Append-only;
  records are never edited.

**Interfaces:**

- Platform adapter: `publish(account, content)`,
  `reply(account, target, text)`, `read(account, query)`, and
  `metrics(account)`. Internally it uses only the platform's official API and
  limits (`research/16–19`).
- Scheduler tick: take mature tasks (`not_before <= now`) → match by platform ×
  role × status × load → assign → update the account limiter.
- Swap protocol: `drain(agent_id)` lets in-flight tasks finish while assigning
  no new ones; `pause(account_id)` redistributes the account queue;
  `retire(account_id)` removes the account from the pool without replacing it
  with a clone.

**Build order:**

1. Registry plus audit log. At this stage alone, the entire manually operated
   account fleet is recorded in one place.
2. The first adapter targets the platform where the project already has a live
   account; for our lore, that is X or Telegram.
3. Scheduler with a per-account limiter and a human-like schedule.
4. Approval workflow: send a draft to the operator, most conveniently in a
   direct message from the operator's Telegram bot, and publish only after
   approval.
5. The first agent is the replier following `research/07`, followed by the
   writer.
6. Add swapping and the agent pool only after the queue reliably remains
   non-empty; before that, there is nothing to swap.

**Definition of done:** one operator manages 5+ accounts through the system,
every action appears in the audit log, no action occurs outside official APIs,
and every account maintains a human-like pace.

## Why This Project Is Being Built

The rationale is established and is not reopened without cause:

- Multi-accounting for distinct purposes is officially permitted by all target
  platforms; the evidence chain with primary sources is in `research/15–19`.
- Organic reach from zero is the most expensive resource. Early substantive
  replies and separated personas provide it more cheaply than advertising
  (`research/07`).
- Manual operation does not scale, while ad hoc scripts scale into chaos. A
  control plane is the only form in which one operator can manage dozens of
  accounts without losing discipline.

## Scope Boundaries

This document supports managing a fleet of independent accounts through
official APIs. Coordinated amplification of one signal, artificial metric
inflation, and account rotation to evade suspensions are different scenarios
with separate rules on every platform (`research/15–19`). This document neither
describes nor justifies them.

## When to Revisit

- If the API or policy of any connected platform changes, revisit the relevant
  adapter and its document in `research/16–19`.
- If the fleet grows beyond the capacity of one approval workflow, revisit the
  operator-shift and delegation model.
- If a platform introduces an official agency mechanism for our scenario,
  migrate to it and simplify the adapter.
