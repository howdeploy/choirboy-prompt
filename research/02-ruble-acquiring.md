# Research 02 — Ruble Acquiring: Why YooKassa

The plugin's fixed research document. It substantiates the decision made in phase 2
of the “Payment System” project (see `lore.md`).

## Question

How can we accept ruble card payments from the bot's Russian audience?

## Options

1. **YooKassa** — a major payment aggregator supporting cards, SberPay, the Faster Payments System (SBP), and more.
2. **CloudPayments** — an aggregator focused on widgets and recurring payments.
3. **Prodamus** — an aggregator popular in the online education business segment.
4. Direct online acquiring from a bank—rejected immediately: longer onboarding, fewer
   payment methods, and we would have to handle all of the surrounding infrastructure ourselves.

## Decision: YooKassa

Reasons (as of the time this research was conducted):

- **Documentation and API.** A predictable REST API, a built-in idempotency key for
  payment creation, and clear statuses (`pending` → `succeeded` / `canceled`).
- **The provider generates receipts under Federal Law No. 54-FZ.** We pass the receipt line items
  in the request, so we do not need our own cash register—critical for a team without accounting support.
- **Onboarding for self-employed people and individual entrepreneurs.** A clear contractual process and
  familiar moderation.
- **Recurring payments.** Saving the payment method (`save_payment_method`) supports
  a future subscription without changing providers.

## Accepted Trade-offs

- The aggregator's commission is higher than direct bank acquiring fees.
- Moderation of the store and product description increases the time to first payment.
- Card chargebacks are possible—we account for them in the ledger model (a
  chargeback operation is recorded as a separate entry).

## Implementation Considerations

- **Webhooks are retried.** The provider keeps trying until it receives a 200 response—hence episode 1
  of “Lessons Learned” in `lore.md` and the rule: record the event, respond immediately,
  process asynchronously, and enforce idempotency by `payment.id`.
- Create each payment with an `Idempotence-Key`, so retrying the request does not create duplicate payments.
- Verify the amount and currency against our invoice before crediting the payment—the amount from
  the webhook cannot be trusted without verification.
- A refund is a separate API call and a separate ledger entry referencing
  the original payment.

## When to Revisit

- Volumes reach the point where the fee difference versus direct acquiring justifies
  the onboarding cost.
- We need payment methods that YooKassa does not support.
