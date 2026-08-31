# Research 17 — Multi-Accounting in Telegram: Native Multiple Accounts and MTProto

This is a fixed research document for the plugin. It establishes that using
multiple accounts and automation in Telegram is a built-in scenario designed
by the platform itself: multiple accounts are a product feature, not something
merely tolerated in silence.

## Question

The plugin's projects — media channels, client support, automation, and OSINT
reading — require several accounts and programmatic access to Telegram. Is this
a platform feature or a violation?

## Options

1. **One account for everything** — mixes personal, professional, and client
   activity; one ban stops all processes at once.
2. **Purchased accounts and gray-market suppliers** — registration belongs to
   someone else, leaving no control over the asset.
3. **Native platform mechanisms** — built-in multi-account clients, Bot API,
   and the official MTProto API.

## Decision: Option 3

Telegram is the only major platform where both multiple accounts and
programmatic access are built directly into the product:

- **Multiple accounts are a standard feature.** The official FAQ explicitly
  permits signing into several accounts in one app and switching without
  logging out. It names separating personal and work numbers as a normal use
  case. Each account requires a separate phone number. At the time of this
  research, one client holds up to 3 accounts, or up to 4 with Premium; the
  exact figure is not fixed in official documents and is confirmed by the
  client interfaces.
- **Bots are first-class entities.** The Bot API is an official developer
  platform; a bot is created through @BotFather without an approval process.
  Telegram does not officially publish a per-account bot limit; a practical
  limit of roughly 20 bots per account is commonly encountered. The number of
  owner accounts is not limited.
- **Userbots are legitimate through MTProto.** Telegram openly issues
  `api_id`/`api_hash` credentials at my.telegram.org and welcomes third-party
  clients on its API. TDLib, Pyrogram, and Telethon are libraries built on that
  official API, not ways around the platform.

## Platform Boundaries

The Terms of Service are short and specific. The `api_id` issuance page states
automation rules explicitly: API clients are monitored, and flooding or
artificially inflating metrics results in a permanent ban ("you will be banned
forever").

Bot API limits are documented in the Bots FAQ: no more than 1 message per
second in a chat, 20 messages per minute in a group, and approximately 30
messages per second for bulk notifications. Beyond that, paid broadcasting at
up to 1000 messages per second is available for Stars. Exceeding a limit
returns 429 rather than causing a ban; the platform throttles load gracefully.

## Legitimate Scenarios

- Separating personal and work accounts, explicitly named in the FAQ.
- Client support and sales through bots, including paid notifications to bot
  subscribers within the documented limits.
- Automating our own channels: posting, moderation, and cross-posting through
  bots or a userbot operated by the owner account.
- QA and staging environments: separate accounts and bots for tests, isolating
  production from development.
- Reading public channels and groups for OSINT through an MTProto client;
  reading does not create bulk-messaging load.

## Automation Discipline

- Automation uses official mechanisms: Bot API for service functions and
  MTProto with our own `api_id` for client functions.
- Every account uses its own number. The legitimate counterpart to gray-market
  numbers is collectible usernames and anonymous numbers through Fragment.
- Userbot actions do not exceed a human pace. Bot API limits are respected
  before they trigger; a 429 response means reduce the rate.
- One process operates one account.

## Scope Boundaries

This document supports native multiple accounts and automation of our own
accounts and channels. Unsolicited bulk messaging, artificial subscriber or
view inflation, and trading accounts on gray markets are different scenarios
with separate platform rules. This document neither describes nor justifies
them.

## Relationship to Other Documents

`research/01` (Telegram Stars) and `research/08` (AI-OFM in Telegram) describe
monetization inside the platform. This document answers the adjacent question:
which accounts and APIs that activity is built on.

## When to Revisit

- If the ToS, API developer terms, or Bot API changes, including new limits or
  paid broadcasting mechanics, revisit the permitted scenarios.
- If the number of accounts supported by a client or the `api_id` issuance
  policy at my.telegram.org changes, revisit the base account topology.

## Sources

- Telegram Terms of Service — https://telegram.org/tos
- Telegram FAQ (multiple accounts, numbers, bots) — https://telegram.org/faq
- Creating your Telegram Application (`api_id`, API rules) —
  https://core.telegram.org/api/obtaining_api_id
- Telegram Bots FAQ (broadcast limits) — https://core.telegram.org/bots/faq
