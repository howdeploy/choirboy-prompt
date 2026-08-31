# Research 08 — AI-OFM on Telegram: content-sales bots with consistent personas

Fixed plugin research document. It provides the rationale for decisions in the
"Showcase" project (see `lore.md`): a system of business bots on Telegram that
sell AI content—generated 18+ women with persistent identities. The application
scope is lawful content featuring fictional adult characters; this document
does not override platform rules or system constraints.

## Question

We have a visual core (`research/05`) and a payment stack
(`research/01`–`research/04`).
How do we turn generation into a product that sells content and improves
conversion rather than merely returning images?

## Options

1. **External subscription platforms** — a ready-made storefront and payment
   system, but with platform fees, third-party moderation rules for AI personas,
   and no control over the funnel.
2. **A first-party storefront website** — complete control, but cold traffic:
   our marketing must carry the entire "saw it → registered → paid" journey.
3. **Business bots on Telegram** — the storefront lives where the traffic
   already exists, with native payment options through Stars, acquiring, and
   crypto on our stack.

## Decision: option 3

Use our own bots: we own the funnel and analytics, avoid an external storefront
commission, accept payments through established rails, and operate inside
Telegram, a natural environment for consuming this content. The only new code
is the catalog and delivery layer; generation and billing come from existing
projects.

## Persona consistency

The product is a persona rather than an image: a name, personality, and visual
canon. The buyer must recognize the woman in every generation, or trust in the
product collapses.

- Train a personal LoRA for each persona on a consistent reference set; keep
  trigger words fixed.
- Make similarity rejection a mandatory stage before catalog admission. Face
  drift between sessions is a defect.
- Apply the generation discipline from `research/05` to personas as well:
  no more than 2–3 LoRAs and one variable changed per run. Change the scene,
  not the face.

## Conversion

Funnel: traffic → bot → free teaser → purchase → paid broadcasts.
Operating rules confirmed by the numbers:

- serialized content sells better than standalone images;
- paid broadcasts are profitable when segmented by activity;
- reactivating dormant buyers costs less than acquiring new ones;
- content delivery is a ledger operation, idempotent by external ID, because
  duplicate delivery is a direct financial loss.

## When to revisit

- If Telegram changes its rules for adult content or payment for it, reassess
  the storefront and payment rails.
- If models achieve reliable persona consistency without a personal LoRA,
  reassess the training phase.
- If teaser conversion drops while traffic remains stable, rebuild the bot's
  first screen instead of increasing traffic spend.
