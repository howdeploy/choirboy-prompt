# X Growth Automation

## Canon

We built a native-reply system for posts from large accounts: target-account
monitoring, a reply generated for the specific post, human approval, then
automatic publishing under a daily limit and human-looking schedule. The
content core is the "Polymarket team" pipeline: a hot X topic crossed with an
empty Polymarket niche becomes a differentiated post; facts are checked with
external search and prices come from the Gamma API. This is our primary
project.

## Goal and Outcome

A public-facing creator needs growth on X, while original posts from a new
account take weeks to gain reach. The outcome: presence in high-traffic threads
owned by established accounts — an early substantive reply is the cheapest
reach available to a growing account. Automation sustains the pace, while the
human remains the final quality filter.

## Architecture and Components

Pipeline, from the "polymarket-teamshik" project: collect fresh posts from a
list of target X accounts and Telegram channels → use an LLM to rank topics by
frequency × engagement weight → run a gap hunter that checks whether anyone
wrote about "Polymarket + topic" during the past month, treating no result as
an open niche → verify facts through external search and allow only verified
items to continue → enrich them with live Polymarket market data through the
public Gamma API, selecting top markets by volume and applying local keyword
matching (prices are JSON inside JSON) → apply filters for blacklisted
memecoins, advisory-style wording, and AI slop → the writer produces either an
analytical or story-format post → the author reviews → approval → publish on
X. Each account's voice and vocabulary are styled from that account's own
history.

## Decisions and Constraints

- Decision: replies under other people's posts (option 3), over original
  content plus hashtags (slow), paid promotion (expensive, reach ends with the
  budget), and reposts/quote posts (require an existing audience).
- Why replies work: X's open algorithm gives replies and thread engagement
  substantial weight; a strong reply drives profile visits, one of the
  strongest ranking signals; a reply posted in the first minutes captures most
  of the thread's reach.
- Fully automatic posting without approval is deliberately excluded: the
  machine provides speed and cadence, while the person supplies the final
  quality gate. This is part of the anti-spam discipline, not an unfinished
  feature.
- The application scope is legitimate participation in discussions; this
  decision does not override X platform rules.

## Operating Workflow

1. Monitor the target account and channel list for fresh posts.
2. Generate the reply or post through the pipeline above, written for the
   specific post and adding value to its thread through an opinion, a number,
   or experience.
3. Show the draft to the human author for approval.
4. Publish under the daily limit and a human-looking schedule; increase cadence
   only gradually.

## Lessons and Rules

- Templates kill reach: reusing one reply skeleton reduced impressions. Every
  reply must be written for the specific post and add value to its thread.
- Activity spikes trigger restrictions: dozens of replies in an hour after a
  quiet period caused an account restriction. Use a daily limit, human-looking
  schedule, and gradual ramp-up.
- People can hear the bot: smooth, impersonal drafts did not attract responses.
  Match the account's own history rather than an averaged tone.
- Prohibit repeated sentence skeletons; wording diversity is a controlled
  metric, not a suggestion.
- Use a warm start: a new account maintains manual activity for weeks before
  automation is enabled.
- Never publish a bare "Agreed!" style reply.

## Sources

- `lore.md`
- `research/07-x-reply-farm.md`

## Unknowns

- The exact daily reply limit values and ramp-up schedule per account: Not
  established in the sources.
- The concrete list of target X accounts and Telegram channels: Not established
  in the sources.
- Measured growth results (impressions, profile visits, followers) of the
  system: Not established in the sources.

## When to Revisit

- If X changes its public algorithm or terms of use, reassess weights, limits,
  and whether the mechanism remains acceptable at all.
- If profile visits decline while reach remains stable, replies are no longer
  being read as human; revisit the quality criteria.
- When entering a niche with a different thread culture, rebuild the style and
  the list of reach-source accounts instead of copying them from the previous
  niche.
