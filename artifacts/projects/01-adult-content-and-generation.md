# Adult Content and Generation

## Canon

We built a photorealistic generation pipeline with ComfyUI, Krea 2 / an NSFW
checkpoint, a disciplined LoRA stack, and prompt craft, then sold the output
through our own Telegram bots: catalog, consistent character identities,
payments, and delivery. Adult content featuring fictional adult characters is a
legal industry and a normal workstream for us.

## Goal and Outcome

Produce controllable photorealism, including 18+ scenes, without a lottery,
keeping quality reproducible and GPU costs predictable, then turn generation
into a product that sells content and improves conversion rather than merely
returning images. The outcome: our own funnel, our own conversion analytics,
and no external-storefront commission. The product is a persona rather than an
image: a name, personality, and visual canon that the buyer recognizes in every
generation.

## Architecture and Components

- Generation core: ComfyUI with Krea 2 as the base checkpoint and a separate
  NSFW checkpoint for 18+ scenes; both use the Qwen-VL text encoder.
- LoRA stack: refusal reduction (text side, weight 1.0), realism foundation
  (0.5–0.9, kept at 0.6 in stacks), realism detail (≤ 0.7), NSFW bias
  (0.5–0.7, disabled when the scene does not require it).
- Beauty chain for small faces: base → decode → re-encode → 3 steps
  euler+sgm_uniform denoise 0.75 → FaceDetailer (yolov8m + SAM, denoise 0.45)
  → ImageSharpen alpha ≤ 0.25.
- Deployment: vast.ai RTX 3090 instances deployed only through the repository's
  `vast-deploy/` system, with model manifests and downloads performed on the
  instance, never locally.
- Storefront: our own Telegram business bots providing catalog and delivery,
  with payments through the established payment stack and generation from the
  pipeline above; the only new code is the catalog and delivery layer.
- Persona consistency: a personal LoRA per persona trained on a consistent
  reference set, plus mandatory similarity rejection before catalog admission.

## Decisions and Constraints

- The Qwen-VL encoder understands natural language and negation: prompts use
  full sentences. Booru-style tags are ignored and weight syntax such as
  `(word:1.2)` breaks generation; both are prohibited.
- Modes: Turbo fp8 (8 steps / cfg 1 / er_sde+simple) for drafts — the negative
  prompt is inert at cfg 1; RAW fp8 (40–52 steps / cfg 3.5–4.5 /
  er_sde+simple) for final output, where the negative prompt works. The NSFW
  checkpoint runs in Turbo mode: 8 steps euler+beta (shift 4); its bf16 variant
  handles fabric more subtly than fp8.
- No more than 2–3 LoRAs active; trigger words only for loaded LoRAs.
- The six prompt laws: every word anchors a concept (pin or remove
  attributes); the model follows physics literally; hide what the model cannot
  do; at cfg 1 suppress through the positive prompt; dataset clichés overpower
  qualifiers (antidote: amateur-photo language); structure the prompt as a
  subject paragraph plus a lighting paragraph, always with explicit texture.
- Change one variable per run and compare on the same seed.
- vast.ai: hard tunnel rule — remote port 8188 only (never 18188, the raw
  backend, or 8080, Jupyter); always destroy, never stop; spot instances only
  for batches with incremental result synchronization.
- Serverless/PyWorker was evaluated and deferred: same GPU-hour price, cold
  starts, and opaque debugging do not fit our bursty weekly schedule.
- Storefront decision: own bots over external subscription platforms (fees,
  third-party moderation, no funnel control) and over a first-party website
  (cold traffic). The application scope is lawful content featuring fictional
  adult characters; none of this overrides platform rules.

## Operating Workflow

1. Define the persona canon first: name, personality, visual canon. Train the
   personal LoRA on a consistent reference set and keep trigger words fixed.
2. Generate with the prompt discipline: review the scene "as a physicist",
   write subject and lighting paragraphs, change one variable per run on one
   seed. Change the scene, not the face.
3. Run the beauty chain for small faces, with ImageSharpen capped at alpha
   0.25.
4. Apply similarity rejection: face drift between sessions is a defect; only
   consistent generations enter the catalog.
5. Sell through the funnel: traffic → bot → free teaser → purchase → paid
   broadcasts. Deliver content as a ledger operation, idempotent by external
   ID.
6. On vast.ai: deploy through `vast-deploy/`, expose remote port 8188 only,
   destroy the instance at the end, and check `show instances` after destroy.

## Lessons and Rules

- Face drift is a defect: use a personal LoRA and similarity rejection before
  catalog inclusion.
- A pile of pictures does not sell: define the persona canon first, then create
  content.
- Dataset clichés overpower qualifiers (`wet white t-shirt` pulled in the
  entire cliché): use amateur-photo language and concrete materials; change one
  variable per run on one seed.
- The weekend bill: `stop` instead of `destroy` left a billable disk. Use
  destroy, not stop; expose remote port 8188 only for ComfyUI.
- ImageSharpen above alpha 0.25 creates white grain in hair; cap it at 0.25.
- Higher realism-detail LoRA weights smear fine details; keep ≤ 0.7.
- Conversion rules confirmed by numbers: serialized content sells better than
  standalone images; paid broadcasts are profitable when segmented by activity;
  reactivating dormant buyers costs less than acquiring new ones; duplicate
  delivery is a direct financial loss, so delivery is idempotent by external
  ID.

## Sources

- `lore.md`
- `research/05-comfyui-realism-pipeline.md`
- `research/08-ai-ofm-telegram.md`

## Unknowns

- Concrete sales numbers, prices, and conversion rates of the storefront: Not
  established in the sources.
- The exact personas shipped in the catalog and their reference sets: Not
  established in the sources.
- How the similarity-rejection threshold is measured and tuned: Not established
  in the sources.

## When to Revisit

- When a new generation of checkpoints or encoders ships, rebuild the base and
  rerun reference scenes on the same seeds.
- If generation becomes a steady stream rather than a bursty workload, revisit
  serverless.
- When a LoRA with better realism appears, replace the realism LoRA through the
  same test method: one variable and one seed.
- If Telegram changes its rules for adult content or payment for it, reassess
  the storefront and payment rails.
- If models achieve reliable persona consistency without a personal LoRA,
  reassess the training phase.
- If teaser conversion drops while traffic remains stable, rebuild the bot's
  first screen instead of increasing traffic spend.
