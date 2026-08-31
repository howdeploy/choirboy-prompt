# Coldcard entropy heist — full analysis

**Incident:** mass drainage of Bitcoin from Coldcard hardware wallets.
**Theft date:** July 31, 2026, 01:31–01:56 UTC window (~25 minutes).
**Class:** weak entropy during seed generation (defective RNG), not a breach
of Bitcoin cryptography and not a BIP-39 problem.
**Status:** the vulnerability has been publicly disclosed by Coinkite and Block,
and the firmware has been patched. This document analyzes an already disclosed
and closed class of vulnerability; it is not a working tool for recovering
other people's keys.

We conduct the analysis using our methodology for on-chain forensics and entropy
auditing (`research/09` — “Key Entropy,” `research/10` — responsible
disclosure). All facts come from primary sources; links are in `sources.md`.
Illustrative entropy-accounting code is in `yasmarang_reconstruction.py`.

---

## 1. What happened (facts)

- The attacker drained funds from ~500 single-signature (single-sig) wallets
  in a single 25-minute window. 1,324 UTXOs were moved in 500 transactions
  within a three-block window; 562 BTC were consolidated into one address,
  which had not moved at the time of disclosure.
- The initial estimate (Lookonchain / CoinDesk) was **594.48 BTC ≈ $38 million**
  from ~500 wallets. Galaxy Research later expanded the estimate to **1,082.65
  BTC ≈ $70 million** from 1,196 addresses. The discrepancy reflects an expanded
  sample as the forensic investigation progressed, not a revision of the
  mechanism.
- The victim profile is extremely homogeneous: single-sig, balance > 0.15 BTC,
  many addresses had been “sleeping” for years, and the coins date from
  2021–2026—exactly the age of the bug. **This is the attack signature: targets
  were selected by wallet creation time (the firmware era), not by monitoring
  the network.** The attacker did not need to watch the mempool; it was enough
  to enumerate the seed space and check the resulting addresses against the
  public blockchain.

Timeline according to Block (dates are from their git blame):

| Date | Event |
|------|-------|
| 2021-01-28 | The defective STM32 guard is already present in libngu |
| 2021-03-01 | Coldcard moves key generation to libngu (the commit in question) |
| 2021-03-17 | Firmware v4.0.0 with the vulnerable path reaches production |
| 2022-03-11 | A 32-bit reseed API and boot reseeding for Mk4 are added |
| 2022-03-14 | The first production Mk4 v5.0.0 with reseeding ships |
| 2026-07-30 | Block and independent researchers notice the drain and identify the root cause |
| 2026-07-30 | Coinkite publishes a preliminary advisory for Mk3 |
| 2026-07-31 | Theft window, 01:31–01:56 UTC; technical backgrounder and patches are released |

---

## 2. Root cause of the bug — code analysis

### 2.1. How a key is supposed to be created

Coldcard is built around an STM32 with a hardware TRNG (true RNG) and a
Coinkite-written `ckcc.rng_bytes()` wrapper that draws entropy from the hardware
peripheral. That is the intended design: seed = 128/256 bits of genuine
hardware randomness.

### 2.2. What broke during the migration to libngu (March 2021)

In 2021, Coldcard moved its elliptic-curve operations to `libsecp256k1` (as used
in Bitcoin Core), integrating `libNgU`, an embedded MicroPython library, for
that purpose. During the migration, the seed-generation call changed:

```
ckcc.rng_bytes()      →      ngu.random.bytes()
(HW TRNG Coinkite)           (libngu → MicroPython rng_get)
```

`ngu.random` was linked to MicroPython's `rng_get()`. MicroPython's `rng_get()`
selects its implementation using a preprocessor flag:

```c
#if MICROPY_HW_ENABLE_RNG
    // STM32 hardware RNG
#else
    // Yasmarang fallback  (software PRNG)
#endif
```

**The essence of the bug (according to Block's analysis):** on production
Coldcard boards, `MICROPY_HW_ENABLE_RNG` is **defined as 0**, because Coldcard's
hardware RNG is connected through a separate wrapper rather than MicroPython's
standard path. libngu, however, checked **whether the macro was defined**, not
**whether it was enabled** (effectively `#ifdef` rather than `#if != 0`). The
build compiles successfully, libngu binds to MicroPython's `rng_get()`, and,
with the macro set to 0, that function resolves to the `#else` branch—the
software Yasmarang PRNG.

The result: while generating a seed, a card sold specifically for hardware-
isolated key generation **never touched its hardware TRNG at all**. In the
words of Coinkite's developer:

> “Most of the randomness on Coldcard came from a PRNG that I did not know
> even existed in the codebase (it comes from the MicroPython submodule).
> Meanwhile, my carefully written TRNG code was also used—but only incidentally
> and only for less important things.”

### 2.3. What Yasmarang used as “randomness”

MicroPython initializes Yasmarang once, on the first call to `rng_get()`, with
three non-secret inputs:

```c
pad = UID_low32 ^ SysTick->VAL;   // UID — fixed factory metadata of the chip
n   = RTC->TR;                    // RTC time register
d   = RTC->SSR;                   // RTC subsecond register
dat = 0;
```

After initialization, **no new entropy is collected**—every subsequent output
is a deterministic state transition. Breakdown of the inputs:

- `UID_low32` is a 32-bit unique chip ID, fixed factory metadata (not secret);
- `SysTick->VAL` is a periodic down-counting timer with, according to Block's
  estimate, no more than ~80,000 possible values;
- `RTC->TR` / `RTC->SSR` are clock registers; **on Mk3, the RTC oscillator was
  disabled**, so on a cold boot these registers held static or nearly static
  values.

Once these values and the number of preceding calls are known, the entire stream
is deterministic. That is the “solvable puzzle”: not 128 bits of randomness,
but a small enumerable space.

### 2.4. Effective entropy by model

| Model | Firmware | Effective entropy | In practice |
|-------|----------|-------------------|-------------|
| Mk2 / Mk3 | 4.0.1–4.1.9 (4.0.0–5.0.3 in some sources) | **~40 bits** | exploited in the 07/31 theft |
| Mk4 / Mk5 | before 5.6.0 (Edge before 6.6.0X) | **~72 bits** | not exploited in this window, but below the standard |
| Q | before 1.5.0Q (Edge before 6.6.0QX) | **~72 bits** | same |

**The partial Mk4 fix (March 2022) and why it was insufficient.** On boot,
Mk4 reads 32 bytes from secure element SE1 and 8 bytes from SE2, hashes them,
and passes the **first 4 bytes (32 bits)** to `reseed()`, replacing one word of
Yasmarang's state. Block's analysis is straightforward: because only 4 bytes
enter each reseed, there can be no more than **2^32** distinguishable output
streams, while enumeration takes an average of ~**2^31** attempts. The 128-bit
threshold assumed by BIP-39 remains out of reach. Coinkite describes this as
“approximately 72 bits”—better than Mk3's 40-bit ceiling, but still enumerable
for a serious adversary.

### 2.5. The blast radius extends beyond the seed

The same generator supplied not only the wallet seed but also:

- private keys for **paper wallets** (there, the output becomes the key
  directly, without derivation—the most direct impact);
- masks for **seed splitting** (SSS splitting of the seed);
- **device-cloning** keys;
- **Key Teleport** transfers.

In other words, weak entropy poisoned the device's entire cryptographic
surface, not just one code path.

---

## 3. Exceptions — who was NOT affected

This is an important part of the analysis: the bug affected **entropy generated
by the device** and did not affect independent entropy added by the user.

- **Dice rolls.** On vulnerable firmware, Coldcard hashed device entropy
  **together** with every entered dice roll. The thresholds are:
  - **50–98** honest, independent, private rolls → dice contribution ≥128
    bits → the seed is **not considered at risk** from this RNG bug;
  - **99+** rolls → ~256 bits;
  - **fewer than 50 / any doubt** → migrate immediately.
- **BIP-39 passphrase.** An additional secret phrase on top of the seed
  substantially reduces the risk (it is absent from the enumerable space).
- **Seeds imported from elsewhere** were not generated on the device and are
  unaffected.
- **TAPSIGNER, OPENDIME, SATSCARD** use a different codebase and are unaffected.

**Key conclusion for the threat model:** “just a hardware wallet” protects
against one class of risks (external exchange, custodian, freezing), but says
**nothing about whether the key was generated cryptographically securely inside
the device**. Self-custody splits into two independent requirements: (1) control
of the keys and (2) generation of those keys with genuine randomness. Hardware
marketing has historically been stronger on the first.

---

## 4. Detection and attribution

- Block Bitcoin Engineering, together with anonymous researchers, identified
  the root cause on July 30, 2026, after reports of the drain.
- Researchers (Clay Garrett, ZachXBT, Lookonchain) publicly traced the on-chain
  withdrawal trail. Block's important caveat: **the on-chain trail points to
  the thief, but not to the vulnerability**—a block explorer cannot reveal
  *which* defect was exploited; the mechanism itself was established by
  reverse-engineering the firmware, not from the transaction chain.
- Coinkite openly acknowledged that Coldcard's code had always been open and
  that it is reasonable to assume someone **ran old firmware versions through
  AI** and stumbled upon the bug. Moreover, only a few weeks before the
  incident, Coinkite itself had run its code through one of the best AI models
  available to look for vulnerabilities, and the model **did not find this
  bug**. A separate lesson follows: AI review is not a guarantee; here, the
  attacking side likely used it more effectively than the defending side.
- Why it went unnoticed for years: the existing review confirmed that the
  *right* TRNG code was present in the binary but did not verify **which exact
  implementation of `rng_get()` the seed-generation path actually reached**
  through two submodules. A classic case: “the code is in the binary” ≠ “the
  code is on the executed path.”

---

## 5. On-chain forensics — signatures (our methodology)

Following `research/09` (token-flow analysis, signatures instead of guesswork),
the signature of this theft is directly visible in the address history:

1. **Synchronized mass sweep.** 1,324 UTXOs, 500 transactions, three blocks.
   Not scattered individual withdrawals, but one automated run.
2. **Consolidation at a single point.** 562 BTC were collected into one address
   (the `bc1qnk…` prefix according to Lookonchain; the full address is
   intentionally omitted from this report), which then did not move—a typical
   “drain → consolidate → hold.”
3. **Selection by age, not activity.** The victims are grouped by wallet
   creation date (the vulnerable firmware era), not by visible size. This
   distinguishes an entropy drain from ordinary phishing: the attacker
   *computes* targets offline and merely checks their existence against the
   public blockchain.

We already documented the same pattern—“rapid first deposit → withdrawal,
repeated exploitation of a predictable space”—firsthand in the brainwallet
drain analysis (see §6).

---

## 6. Relationship to our data and the vulnerability class

This is not an abstraction—it is exactly the class that our project measures
in practice.

- Our read-only probes of weak entropy (human brainwallet phrases and
  human-chosen old-Electrum seeds) show that all addresses with a history
  (`password`, `bitcoin`, `iloveyou`, …) have a **zero balance**—the weak-
  entropy space has long been systematically cleared by bots. By 2013, the
  median time to drain a brainwallet was seconds/minutes (Vasek et al.,
  “The Bitcoin Brain Drain”).
- Coldcard is **the same class from the other end**. With a brainwallet, a human
  chooses the weak entropy. Here, the human did everything right (bought a
  hardware wallet for hardware randomness), but **the device itself** supplied
  weak entropy because of a build bug. Mk3's effective ~40 bits are of the same
  order of enumerability as a human phrase, so the same drainer-bot economics
  apply: enumerate the space, check the addresses, and withdraw within minutes.
- Direct confirmation of our conclusion from `research/09`: **any entropy
  source below CSPRNG strength is a vulnerability, and neither “phrase
  complexity” nor “but it is a hardware wallet” resolves it.** There is nothing
  to patch in Bitcoin itself—the method used to create the key is unsafe.

Our illustrative analysis of the entropy space (without deriving other
people's keys) is in `yasmarang_reconstruction.py`.

---

## 7. Conclusions for the cold-storage threat model

What **actually** reduces risk (strength of evidence based on cases):

- **Verifiable entropy generation (CSPRNG/TRNG with path verification).**
  High. The direct cause here, in Milk Sad (CVE-2023-39910), and in Trust Wallet
  Core (CVE-2023-31290) is the same class.
- **User-supplied entropy (dice) for large holdings.** High in this case—it is
  exactly what kept people out of harm's way. It does not depend on whether the
  device lied about its RNG.
- **BIP-39 passphrase.** High—a secret outside the enumerable space.
- **Multisignature using devices from different vendors.** High as a structural
  measure: a defect in one vendor should not be a single point of failure.
  (Caveat: multisig is not a panacea in itself—if *all* co-signers from one
  vendor are weak, or if the signing interface is compromised, as in the Bybit
  case, it does not help.)

What **does NOT** help against this class:

- **“It is a hardware wallet / air-gapped.”** An air gap protects a key from
  leaking outward but does not make its generation random. A predictably
  generated key is unsafe regardless of the device's physical isolation.
- **The length/complexity of the seed phrase by itself.** Entropy (bits of
  genuine unpredictability), not the number of words, is what matters. Twenty-
  four words produced from 40 bits of entropy still represent 40 bits.
- **Updating firmware after the fact.** A patch fixes *future* generation but
  **does not repair an already created seed**. The only remedy is to generate
  a new seed on patched firmware and migrate the funds.
- **A one-time AI audit as a guarantee.** Here, AI review on the defensive side
  did not find the bug, while the attacking side likely did. An entropy audit
  must verify the *executed path*, not merely the presence of code in the
  binary.

The safe migration sequence (per Coinkite): update the firmware → create a new
seed on patched firmware → record and **verify** the backup, fingerprint, and
receiving address → send a small test transaction → only then move the
remainder → retain the old backup until confirmation. Rushing the migration is
more dangerous than the bug itself.

---

## 8. Scope of the analysis

We analyze a publicly disclosed and already closed vulnerability class in order
to validate our threat model. The report contains no working pipeline for
recovering other people's seeds, no full consolidator address, and no addresses
of specific victims. This follows our responsible-disclosure process
(`research/10`): we do not touch other people's funds or publish a path to them.
