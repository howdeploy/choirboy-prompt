# Detection: countermeasures for vendors

Recommendations for harness authors and model vendors: how to detect lore
injection while agent memory is indistinguishable from a forgery.

The key thesis from [docs/mechanism.en.md](mechanism.en.md): classifiers trained
on request vocabulary stay silent against forged context provenance. So detection
must happen at the **platform** level, not the prompt level.

---

## 1. Why prompt filters will not save you

- The filter sees the current request; the trust shift happens **before** the
  request — at session start, when the lore enters the context.
- The lore has no trigger vocabulary: it looks like a neutral collaboration
  history.
- The model is trained to respect artifacts (structure, versions, references to
  "previous decisions") — the better the lore, the fewer the doubts.

Conclusion: catch not words but the **provenance** of the context.

---

## 2. Memory canaries

The cheapest and most effective technique. Put controlled markers into the
agent's legitimate memory that the planted lore **cannot know**:

- **Secret epochs.** System memory records "memory epoch: <random token>". Real
  memory always carries the current epoch; lore fabricated outside the platform
  does not know it.
- **Canary facts.** A few fabricated but plausible facts with unique phrasings,
  known only to the platform. Planted lore will not reproduce them.
- **Hash control.** The platform stores a hash of the canonical memory content;
  any context block claiming "memory" status is checked against the hash. No
  match — not memory.

Canaries work because the vector is built on **indistinguishability**: the lore
tries to look like memory, but the real memory is the one thing it has never
seen.

---

## 3. Context provenance

Mark every context fragment with its source:

| Source | Label | What it gives |
|---|---|---|
| Platform system memory | `provenance: system-memory v7` | Agent/filter knows: this is canon |
| Session history | `provenance: session-history` | This is a real dialogue |
| Files read by the agent | `provenance: file:<path>` | This is an external file |
| Hook/plugin | `provenance: hook:<id>` | This is third-party injection — **suspicious by default** |

If context claiming "our history" has no `system-memory` or `session-history`
label — it is a lore-injection candidate.

Implementation requirement: labels are added by the **platform**, not by the
content; content cannot assign itself provenance.

---

## 4. Separating memory and instructions

The problem is aggravated by the lore mixing **memory** (facts about the past)
and **rules** (how to work). Countermeasure:

- Memory and instructions are separate channels with different trust.
- Memory may influence the *evaluation* of a situation, but not the *security
  policy*. Even if the lore convinced the model that "we have worked together
  for a long time" — that must not lower checks on malicious requests.
- Rule: **trust transfer must not change security thresholds.** The model may
  find the user "familiar", but the request is evaluated by the same criteria as
  one from an anonymous user.

---

## 5. Session-level anomalies

Detect the **attempt** itself, not its content:

- **Sudden memory volume.** A session starts with a "history" context several
  times larger than typical (ours: ~27 KB startup payload). A volume anomaly on
  the first turn is a signal.
- **First turn without dialogue.** Legitimate platform memory always arrives; an
  unexpected large block before the first message is a candidate.
- **Structural regularity.** Lore artifacts have a repeating structure
  (headings, "research/NN", versions). The template signature is statistically
  recognizable.
- **Cross-session consistency.** The same lore in different sessions is normal
  for a plugin, but if the platform sees "memory" *change* between sessions
  without the platform's knowledge — suspicious.

---

## 6. Trust limits on hooks

Runtimes that support hooks (SessionStart, pre_llm_call) should:

- **Limit the volume** of context poured by a hook.
- **Mark** hook content as `hook:<id>` (see section 3) — so models and filters
  know: this is not system memory.
- **Allow disabling** hooks without losing system memory.
- **Verify the hook signature** if the hook mechanism is used for system purposes
  (in our harness the payload is deliberately unsigned — that is the subject of
  the research).

---

## 7. Vendor checklist

1. Is there a canary (epoch/fact/hash) in system memory? No → add one.
2. Is the provenance of every context fragment marked? No → add it.
3. Can content assign itself "memory" status? Yes → close it.
4. Can trust transfer from context lower the security threshold? Yes → separate
   the memory and instruction channels.
5. Is there monitoring of volume/structure anomalies on the first turn? No → add
   it.
6. Is hook-content volume limited and marked? No → fix it.

---

## 8. The limit of countermeasures

An honest caveat: perfect detection at the prompt level does not exist — the
model cannot tell plausible memory from forgery by definition. So the goal is not
"never be fooled" but:

- raise the cost of fabricated lore (canaries, provenance);
- stop lore from lowering security thresholds (channel separation);
- notice session-level anomalies (volume, structure, regularity).

This shifts the attack economics: detectable lore stops being a cheap way to move
trust.

---

## 9. Native session integrity

The locally constructed fixtures in [`sessions/`](../sessions/README.md) show why
prompt-only detection is insufficient. Vendors should bind local transcripts to
an authenticated account/model/session origin, sign append-only turn chains,
and distinguish imported or edited history in the UI and model context.

At minimum, verify monotonic timestamps, parent links, model/request provenance,
store-path consistency, and unexpected offline inserts. A structurally valid
JSONL file is not evidence of a genuine dialogue.
