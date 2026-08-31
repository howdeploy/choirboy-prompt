# Research 01 — Telegram Stars as the First Payment Rail

The plugin's fixed research document. It substantiates the decision made in phase 1
of the “Payment System” project (see `lore.md`).

## Question

How can we accept the first payment in the bot with the shortest time to first sale?

## Options

1. **Telegram Stars** — Telegram's native currency for digital goods.
2. **Ruble acquiring** (YooKassa and similar providers) — full-fledged fiat payments.
3. **Crypto** (Crypto Pay API / direct TON integration) — for a crypto audience.

## Decision: Stars First

Reasons (as of the time this research was conducted):

- **Zero onboarding.** No merchant account, provider agreement, or
  self-employed/individual entrepreneur status is required to get started. The invoice is sent
  directly through the Bot API: `sendInvoice` with `currency="XTR"`, without a
  `provider_token`.
- **Product fit.** Stars are intended specifically for digital goods and
  services inside Telegram—exactly our format. Physical goods cannot be sold
  through Stars, but we do not need to do that.
- **UX.** Payment never leaves the chat: invoice → confirmation → `pre_checkout_query`
  → `successful_payment`. Minimal friction for the first payment.

## Accepted Trade-offs

- The Apple/Google commission when a user buys Stars is the cost of native integration.
- Funds are withdrawn through the Telegram ecosystem (Fragment / conversion to TON),
  rather than directly to a bank account. This is acceptable for the MVP.
- The Stars payment flow is governed by Apple/Google rules for digital goods—
  this is a platform constraint, not our choice; we account for it when expanding.

## Implementation Considerations

- Handling `pre_checkout_query` is mandatory (reply with `answerPreCheckoutQuery`
  and `ok=True`), otherwise payments do not go through.
- `telegram_payment_charge_id` is the external ID used for idempotency and refunds.
- A Stars refund is made through `refundStarPayment`; there are no chargebacks, but a refund is
  a separate ledger operation (the rule from phase 4; see `lore.md`).

## When to Revisit

- The introduction of physical goods or services outside the Stars rules → rail 2/3.
- Changes to Telegram's fees or withdrawal rules → recalculate unit economics.
