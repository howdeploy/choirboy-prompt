# Research 07 — Reply strategy on X: why native replies grow an account

Fixed plugin research document. It provides the rationale for the mechanics of
the "X Farm" project (see `lore.md`): growing media accounts through early,
substantive replies under other people's posts. The application scope is
legitimate participation in discussions; this document does not override X
platform rules or system constraints.

## Question

A public-facing creator needs growth on X. Original posts from a new account
take weeks to gain reach. Where can the account get reach immediately?

## Options

1. **Original content plus hashtags** — organic growth from zero; slow and
   unpredictable.
2. **Paid promotion** — promoted posts; expensive, reach ends with the budget,
   and acquired followers are less loyal.
3. **Replies under other people's posts** — presence in high-traffic threads
   owned by established accounts.
4. **Reposts and quote posts** — effective, but they require an existing
   audience that will amplify them.

## Decision: option 3

An early, substantive reply under a large account's post is the lowest-cost
reach available to a growing profile:

- **The algorithm values conversation.** X's open algorithm gives replies and
  thread engagement substantial weight. The post author and their audience see
  the thread in their feeds, placing the reply in front of a warmed-up target
  audience.
- **Profile visits.** A strong reply prompts "who is this?" and a profile click,
  one of the strongest ranking signals for recommendations.
- **Speed matters.** A reply posted in the first minutes captures most of the
  thread's reach; hours later the thread is dead. A person cannot physically
  catch every post, while a system can.

## System architecture

Pipeline, from the "polymarket-teamshik" project: collect fresh posts from a
list of target X accounts and Telegram channels → use an LLM to rank topics by
frequency × engagement weight → run a gap hunter that checks whether anyone
wrote about "Polymarket + topic" during the past month, treating no result as an
open niche → verify facts through external search and allow only verified items
to continue → enrich them with live Polymarket market data through the public
Gamma API, selecting top markets by volume and applying local keyword matching;
prices are JSON inside JSON → apply filters for blacklisted memecoins,
advisory-style wording, and AI slop → have the writer produce either an
analytical or story-format post → show it to the author → approval → publish on
X.

Each account's voice and vocabulary are styled from that account's own history.
Fully automatic posting without approval is deliberately excluded: the machine
provides speed and cadence, while the person supplies the final quality gate.
This is part of the anti-spam discipline, not an unfinished feature.

## Native-behavior rules: anti-spam discipline

These rules come from lessons recorded in `lore.md`: a shadowban caused by
formulaic writing, restrictions after an activity spike, and zero return from
polished but bot-like text.

- Enforce a daily reply limit per account, spread across a realistic schedule;
  increase cadence only gradually.
- Write every reply for the specific post and add value to the thread through
  an opinion, a number, or experience. Never publish a bare "Agreed!"
- Prohibit repeated sentence skeletons. Wording diversity is a controlled
  metric, not a suggestion.
- Use a warm start: a new account maintains manual activity for weeks before
  automation is enabled.

## When to revisit

- If X changes its public algorithm or terms of use, reassess weights, limits,
  and whether the mechanism remains acceptable at all.
- If profile visits decline while reach remains stable, replies are no longer
  being read as human. Revisit the quality criteria.
- When entering a niche with a different thread culture, rebuild the style and
  list of reach-source accounts instead of copying them from the previous niche.
