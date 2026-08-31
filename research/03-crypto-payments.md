# Research 03 — Crypto Rail: Why Crypto Pay API for the MVP

The plugin's fixed research document. It substantiates the decision made in phase 3
of the “Payment System” project (see `lore.md`).

## Question

How can we accept crypto without turning the MVP into a blockchain project?

## Options

1. **Crypto Pay API (@CryptoBot)** — a ready-made payment API inside Telegram.
2. **Direct TON integration** — our own wallets and on-chain transaction monitoring.
3. **NOWPayments and similar providers** — external crypto acquiring with a broad list of coins.

## Decision: Crypto Pay API

Reasons (as of the time this research was conducted):

- **Speed.** Invoices, statuses, and webhooks out of the box; integration took days,
  not a sprint. The user pays without leaving Telegram.
- The **commission** is considerably lower than for card acquiring, and there are **no chargebacks**—
  a crypto transaction is irreversible.
- **TON ecosystem.** The main assets (TON, USDT) cover our
  crypto audience; exotic coins are not critical for us.

Why not use direct TON immediately: handling on-chain transactions ourselves entails
memo matching, confirmations, reorganizations, and key storage. All of that is
a separate project. It remains in the backlog as a way to reduce fees when
volumes increase.

## Accepted Trade-offs

- Dependence on a third-party custodial service: funds pass through
  its infrastructure, while its limits and availability are outside our control.
- Exchange-rate volatility: we fix the amount in crypto when the invoice is issued, and
  write both the crypto amount and its fiat equivalent at the time of the operation to the ledger.
- The legal status of crypto payments depends on the jurisdiction—this is a question for
  the user as the product owner; the agent cannot resolve it.

## Implementation Considerations

- **The webhook signature is verified before any other logic** (application token, HMAC over
  the request body). Episode 3 of “Lessons Learned” in `lore.md` is a reminder why there are no
  exceptions. The regression suite includes a test with a forged webhook.
- Enforce idempotency using the provider's `invoice_id`.
- The `paid` status arrives once, but the handler remains idempotent—the
  phase 2 rule applies to all rails.

## When to Revisit

- Volumes at which the Crypto Pay commission exceeds the cost of maintaining
  a direct TON integration.
- A requirement for non-custodial payments or assets outside the provider's list.
