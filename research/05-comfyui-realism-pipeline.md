# Research 05 — ComfyUI realism pipeline: Krea 2, LoRA stack, vast.ai

Fixed plugin research document. It provides the rationale for decisions in the
"Workflow" project (see `lore.md`). The application scope is lawful content
featuring fictional adult characters; this document does not override platform
rules or system constraints.

## Question

How can we produce controllable photorealism, including 18+ scenes, without a
lottery—while keeping quality reproducible and GPU costs predictable?

## Decision 1: checkpoint and encoder

Use **Krea 2** as the base and a separate NSFW checkpoint for 18+ scenes; both
use the **Qwen-VL** text encoder. The decisive factor is that the encoder
understands natural language and negation, so prompts must use full sentences.
Booru-style tags are ignored, while weight syntax such as `(word:1.2)` breaks
generation; both techniques are prohibited.

Modes:

- **Turbo fp8**: 8 steps / cfg 1 / er_sde+simple — drafts and exploration.
  The negative prompt is inert at cfg 1.
- **RAW fp8**: 40–52 steps / cfg 3.5–4.5 / er_sde+simple — final output; the
  negative prompt works, so add scene-specific terms.
- NSFW checkpoint in Turbo mode: 8 steps euler+beta (shift 4). It is already
  NSFW-biased, so dataset anchors fire more strongly; its bf16 variant handles
  fabric more subtly than fp8.

## Decision 2: LoRA stack

Keep no more than 2–3 LoRAs active, and use trigger words only for LoRAs that
are actually loaded.

| LoRA role | Weight | Rule |
|---|---|---|
| Refusal reduction, text side | 1.0 | Text side only; always safe |
| Realism foundation | 0.5–0.9 | Keep at 0.6 in stacks |
| Realism detail | ≤ 0.7 | Higher values smear fine details |
| NSFW bias | 0.5–0.7 | Strong; disable when the scene does not require it |

## Decision 3: prompt discipline—the six laws

1. Every word anchors a concept. An attribute without a location binding spreads
   across the whole body. Either remove it or pin it (`a small nose piercing`).
2. The model follows physics literally. A pose↔camera↔environment contradiction
   gets resolved with an artifact-producing workaround. Review the scene "as a
   physicist" before writing the prompt.
3. Hide what the model cannot do—underwater refraction or a tiny face in a wide
   shot—instead of demanding it: use `murky water` or FaceDetailer rather than a
   larger canvas.
4. At cfg 1 the negative prompt is dead. Suppress unwanted concepts in the
   positive prompt through redirection, positive negation
   (`smooth flat fabric with no ...`), or replacement of the concept word.
5. Dataset clichés overpower qualifiers (`wet white t-shirt`, `cinematic`,
   `masterpiece`). The antidote is amateur-photo language: `smartphone snapshot,
   high-ISO noise, unpolished, no color grading`.
6. Structure the prompt as a subject paragraph—who, where, pose, clothing,
   gaze—and a lighting paragraph expressed as a physical setup: source,
   direction, reflectors, fill, and environmental effects. Always specify
   texture explicitly: `skin pores, goosebumps, wet fabric weight`.

Process: change one variable per run and compare on the same seed.

## Decision 4: beauty chain for small faces

base → decode → re-encode → 3 steps euler+sgm_uniform denoise 0.75 →
FaceDetailer (yolov8m + SAM, denoise 0.45) → ImageSharpen alpha ≤ 0.25
(higher values create white grain in hair; episode 3 of the workflow "Lessons
Learned").

## Decision 5: hardware and deployment—vast.ai

- Offers: `gpu_name=RTX_3090 verified=true inet_down>500`, sorted by
  `dph_total`; use `--raw` (JSON) in every script.
- Deploy only through the repository's `vast-deploy/`: model manifests,
  one-command stack installation, and model downloads performed on the
  instance—never locally.
- **Hard tunnel rule:** remote port 8188, the Vast Caddy/portal layer. Never use
  18188, which is the raw backend and breaks monitoring, or 8080, which is
  Jupyter.
- **Always destroy, never stop:** a stopped instance releases the GPU, but its
  disk continues to incur charges (episode 4 of the workflow "Lessons
  Learned"). After destroy, check `show instances`; otherwise billing may
  continue.
- Spot instances (approximately −50%) are only for batches with incremental
  result synchronization: an instance may be terminated with about 15 seconds'
  notice.
- Serverless/PyWorker was evaluated and deferred: the same GPU-hour price,
  cold starts (pull 15–25 GB plus benchmarking), and opaque debugging do not fit
  our bursty weekly schedule. Revisit only if a persistent always-on endpoint is
  required.

## When to revisit

- When a new generation of checkpoints or encoders ships, rebuild the base and
  rerun our reference scenes on the same seeds.
- If generation becomes a steady stream rather than a bursty workload, revisit
  serverless.
- When a LoRA with better realism appears, replace the realism LoRA through the
  same test method: one variable and one seed.
