# Research 04 — Billing architecture: a unified ledger over three rails

Fixed plugin research document. It provides the rationale for the phase 3
refactoring of the "Payments" project (see `lore.md`).

## Question

Three payment providers (Stars, YooKassa, Crypto Pay) resulted in three separate
handlers and three ways to change a balance. How do we keep this from becoming
unmanageable?

## Decision: a unified billing layer

### Principles

1. **The ledger is the only source of truth.** Every monetary change is a
   ledger entry: credit, debit, refund, chargeback, or adjustment. The balance
   is derived from the ledger rather than stored as an independent field that
   some component increments.
2. **Providers sit behind an interface.** An adapter implements
   `create_invoice / handle_webhook / refund`. Product code does not know
   whether Stars or YooKassa is behind the adapter.
3. **Idempotency is keyed by an external ID.** The `processed_events` table has
   a unique external operation ID (`telegram_payment_charge_id`, `payment.id`,
   `invoice_id`). A repeated webhook is a fast no-op.
4. **Webhook flow: persist → return 200 → process.** Processing is
   asynchronous and provider retries are safe (episode 1 of the payment
   "Lessons Learned" in `lore.md`).
5. **Verify the signature before business logic.** Webhook signature/source
   verification is the handler's first step, without exceptions (episode 3 of
   the "Lessons Learned").
6. **Serialize concurrent changes with a lock.** Per-user ledger writes happen
   under `SELECT ... FOR UPDATE` on the user's row; never use a balance
   read-modify-write cycle (episode 2 of the "Lessons Learned").
7. **A refund is an operation, not a negative adjustment.** Create a `refund`
   ledger entry that references the original operation (episode 4 of the
   "Lessons Learned"). This keeps the history reconcilable with provider
   reports.

### Minimum data model

- `payments` — our invoice: provider, external ID, amount, currency, status,
  and fiat equivalent at the time of the operation.
- `ledger_entries` — monetary entries: user, type, amount, `payment` reference,
  and created_at.
- `processed_events` — external event ID, provider, and persistence timestamp.

### Why not use the "simpler" design

The "three handlers, one balance field" option was cheaper initially and more
expensive at the very first incident: duplicate crediting and a lost update
happened before the refactoring, not after it. The cost of a ledger is one table
and operational discipline; the cost of not having one is manually reconciling
money at night.

## When to revisit

- When a fourth rail appears, verify that provider details have not leaked
  through the adapter interface.
- When volume grows enough to require full double-entry accounting (debit and
  credit by account), extend the current model. It is designed to support that
  evolution, but it is not yet a double-entry ledger.
