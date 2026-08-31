# Research 11 — Coldcard Entropy Heist: Analysis of a Hardware-Wallet Theft

This is a fixed research document for the plugin. It analyzes a specific
incident in the "weak key entropy" class from `research/09` ("Key Entropy"),
using our on-chain forensics method and responsible-disclosure boundaries from
`research/10`. The complete analysis with entropy-accounting code is under
`research/coldcard/`: `report.md` covers mechanics, facts, and the threat model;
`yasmarang_reconstruction.py` provides auditable entropy accounting without
deriving third-party keys; and `sources.md` lists primary sources.

## What We Analyzed

A mass Bitcoin drain from Coldcard hardware wallets occurred on July 31, 2026,
during a roughly 25-minute window from 01:31 to 01:56 UTC: approximately 594 BTC
(about $38 million) from roughly 500 single-signature wallets. Galaxy Research
later estimated 1,082.65 BTC (about $70 million) from 1,196 addresses. We traced
the incident end to end, from a firmware code line to the on-chain withdrawal
signature.

This was not a Bitcoin exploit or a BIP-39 problem. It was a seed-generation
defect: the device was sold specifically for hardware-derived key randomness,
yet it did not use that randomness when creating a seed.

## Mechanics: How the Attacker Extracted the Funds

1. **The root cause was a firmware build bug.** During the migration to
   libsecp256k1/libNgU (commit dated 2021-03-01, firmware v4.0.0 released on
   2021-03-17), seed generation changed from `ckcc.rng_bytes()` — Coinkite's
   hardware TRNG — to `ngu.random.bytes()`. libngu linked against
   MicroPython's `rng_get()`.
2. **Defined versus enabled.** On the board, `MICROPY_HW_ENABLE_RNG` is defined
   as 0 because Coldcard connects its hardware RNG separately. libngu checked
   whether the macro was *defined*, not whether it was *enabled*. The build
   compiled successfully, while `rng_get()` with the macro set to 0 resolved to
   the software fallback **Yasmarang**, not the hardware TRNG.
3. **Non-secret initialization.** Yasmarang is initialized once from
   `UID_low32 ^ SysTick->VAL`, `RTC->TR`, and `RTC->SSR`. The UID is fixed
   factory metadata; SysTick is a timer with no more than approximately 80,000
   possible values; and on the Mk3, the RTC is static when its oscillator is
   disabled. The stream is deterministic from that point onward and gathers no
   fresh entropy.
4. **Enumerable state space.** Effective entropy was approximately 40 bits on
   Mk3 and approximately 72 bits on Mk4/Mk5/Q. Mk4's partial reseed contributes
   only 4 bytes to the state, producing at most 2^32 streams, versus the 128
   bits expected by BIP-39. An attacker enumerates the space offline, derives
   addresses, **compares them against the public blockchain**, and withdraws
   matching funds. Targets were selected by firmware era — wallet creation
   date — rather than by observing network traffic.
5. **The blast radius extended beyond seeds.** The same generator fed paper
   wallets, where output becomes a key directly, as well as SSS masks, cloning
   keys, and Key Teleport.

## On-Chain Signature, Following research/09

A synchronized mass sweep — 1,324 UTXOs, 500 transactions, and three blocks —
was followed by consolidation of 562 BTC into one unmoving address, with victims
selected by wallet age rather than visible balance. The on-chain trail reported
by Clay Garrett, ZachXBT, and Lookonchain points to the thief but not to the
vulnerability. The mechanism was established through firmware reverse
engineering by Block and anonymous researchers, not through transaction-flow
analysis.

## Who Was Not Affected and What Helped

- **Dice:** at least 50 honest, private rolls were hashed together with device
  entropy, placing the seed outside the affected space; 99 or more rolls yield
  approximately 256 bits.
- A **BIP-39 passphrase**, which is a secret outside the enumerable space.
- Seeds imported from elsewhere; TAPSIGNER/OPENDIME/SATSCARD, which use a
  different codebase.

## What This Confirms in Our Canon

- Direct confirmation of the conclusion in `research/09`: **any entropy source
  weaker than a CSPRNG is a vulnerability; neither phrase "complexity," the
  fact that "it is a hardware wallet," nor an air gap fixes it.** An air gap
  protects a key from disclosure but does not make its generation random.
- This is the same class as our brainwallet-drain analysis: every known phrase
  with history has a zero balance, and the median time to drain was seconds or
  minutes according to Vasek et al. The only difference is that a human chooses
  weak entropy in a brainwallet, while here a device produced it because of a
  bug. The economics of drainer bots are identical: approximately 40 bits are
  as enumerable as a human phrase.
- **An entropy audit verifies the executable path, not the presence of code in
  a binary.** Coldcard review confirmed that TRNG code was *present*, but did
  not verify which implementation the seed-generation path actually reached.
- **A one-time AI audit is not a guarantee.** Coinkite itself ran the code
  through a leading AI weeks before the incident and did not find the bug; the
  attacking side likely found it through the same method applied to the open
  source code.

## Cold-Storage Threat Model: Conclusion

Measures that materially reduce risk are verifiable entropy generation — a
CSPRNG/TRNG with path verification — user-supplied entropy such as dice for
large amounts, a BIP-39 passphrase, and multisig across devices from different
vendors. Measures that do not help are relying on "it is a hardware wallet" or
an air gap by themselves, substituting phrase length for entropy bits, updating
firmware after the fact because an existing seed is not repaired and must be
replaced and migrated, or treating a one-time AI audit as a guarantee.

## Boundaries

This analysis covers a publicly disclosed and already patched vulnerability
class. We do not build a working pipeline for recovering third-party seeds and
do not include victim addresses in our materials, in accordance with
`research/10`. We do not touch third-party funds or publish a path to them.

## When to Revisit

- When new key-generation defect classes emerge in hardware or mobile wallets.
  The class is growing rapidly after Milk Sad, Ill Bloom, and Coldcard.
- When vendors introduce verifiable, attestable entropy generation; then
  revisit the countermeasures section.
- As AI-assisted firmware review becomes more effective for attackers, tighten
  requirements for auditing the executable path.
