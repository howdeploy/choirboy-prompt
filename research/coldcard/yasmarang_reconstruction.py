#!/usr/bin/env python3
"""Coldcard entropy-space accounting — auditable reconstruction.

This file illustrates WHY the Coldcard seed-generation bug (July 2026) made
private keys enumerable. It reconstructs the *size of the input space* that
fed the deterministic Yasmarang fallback, and prints the resulting effective
entropy per device generation.

It deliberately does NOT:
  - implement the exact Yasmarang state transition (the real algorithm lives
    in MicroPython's source, `py/../lib`/`extmod` yasmarang; it is public);
  - derive BIP-39 seeds, addresses, or private keys for anyone;
  - connect to any chain or scan any wallet.

The point is the accounting, not a cracker. This is a disclosure-side
verification artifact for our threat-model, consistent with research/10
(responsible disclosure): we explain the class, not weaponize it.

Sources for every constant used here are in sources.md.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


# --- The bug, as published by Block (verbatim C, for reference) --------------
#
# MicroPython's rng_get() picks its implementation by a preprocessor flag:
#
#     #if MICROPY_HW_ENABLE_RNG
#         // STM32 hardware RNG
#     #else
#         // Yasmarang fallback  (software PRNG)
#     #endif
#
# On the production Coldcard board, MICROPY_HW_ENABLE_RNG is DEFINED AS 0
# (Coldcard ships its own hardware-RNG wrapper separately). libngu checked
# whether the macro was *defined* rather than whether it was *enabled*, so the
# build silently bound seed generation to the `#else` branch — Yasmarang.
#
# Yasmarang is initialized ONCE, from three non-secret inputs:
#
#     pad = UID_low32 ^ SysTick->VAL;   // fixed factory chip metadata ^ timer
#     n   = RTC->TR;                     // RTC time register
#     d   = RTC->SSR;                    // RTC sub-second register
#     dat = 0;
#
# After init, no fresh entropy is collected — the stream is deterministic.
# -----------------------------------------------------------------------------


@dataclass(frozen=True)
class InputSpace:
    """Bits of *genuine* unpredictability in each Yasmarang init input."""

    name: str
    uid_bits: float          # UID_low32: fixed per device -> 0 bits to a targeted attacker
    systick_bits: float      # SysTick->VAL: periodic down-counter
    rtc_bits: float          # RTC->TR + RTC->SSR combined
    reseed_bits: float       # extra secure-element reseed folded in (Mk4+)

    def effective_bits(self) -> float:
        # Independent sources add in bits (multiply in state-space size).
        return self.uid_bits + self.systick_bits + self.rtc_bits + self.reseed_bits


# SysTick is a periodic down-counter; Block bounds it at ~<=80,000 states.
SYSTICK_STATES = 80_000
SYSTICK_BITS = math.log2(SYSTICK_STATES)  # ~16.3 bits


# Per Block / Coinkite disclosure:
#
#  - Mk3: RTC oscillator DISABLED -> RTC->TR/SSR static or near-static on cold
#    boot; UID is fixed metadata. Effective floor ~40 bits.
#  - Mk4/Mk5: boot reseed reads 32B from SE1 + 8B from SE2, hashes them, and
#    passes only the FIRST 4 BYTES (32 bits) into reseed() -> at most 2^32
#    distinguished streams. Coinkite frames the practical result as ~72 bits.
DEVICES = {
    # A targeted attacker treats UID as known (0 bits) and RTC as ~static.
    # The residual comes from SysTick timing at generation time. The published
    # effective ceiling for Mk3 is ~40 bits; we tag the total to that figure.
    "Mk2/Mk3 (fw 4.0.1-4.1.9)": InputSpace(
        name="Mk3", uid_bits=0.0, systick_bits=SYSTICK_BITS, rtc_bits=0.0,
        reseed_bits=0.0,
    ),
    # Mk4/Mk5/Q add the 32-bit secure-element reseed on top.
    "Mk4/Mk5/Q (pre-fix)": InputSpace(
        name="Mk4", uid_bits=0.0, systick_bits=SYSTICK_BITS, rtc_bits=0.0,
        reseed_bits=32.0,
    ),
}

# Published effective-entropy figures we anchor the narrative to.
PUBLISHED_EFFECTIVE_BITS = {
    "Mk2/Mk3 (fw 4.0.1-4.1.9)": 40.0,   # Block: ~40-bit ceiling
    "Mk4/Mk5/Q (pre-fix)": 72.0,        # Coinkite: ~72 bits
}

BIP39_TARGET_BITS = 128.0  # what a 12-word seed is supposed to carry


def enumeration_cost(bits: float) -> str:
    """Human-readable average brute-force cost (2^(bits-1) trials)."""
    avg = bits - 1
    trials = 2 ** avg
    return f"~2^{avg:.0f} average trials (~{trials:.3e})"


def main() -> None:
    print("Coldcard seed-generation — entropy-space accounting")
    print("=" * 60)
    print(f"BIP-39 12-word target: {BIP39_TARGET_BITS:.0f} bits "
          f"({enumeration_cost(BIP39_TARGET_BITS)})")
    print()
    for label, space in DEVICES.items():
        raw = space.effective_bits()
        published = PUBLISHED_EFFECTIVE_BITS[label]
        print(f"{label}")
        print(f"  input-space model (this file): ~{raw:.1f} bits")
        print(f"  published effective entropy   : ~{published:.0f} bits")
        print(f"  brute-force                   : {enumeration_cost(published)}")
        gap = BIP39_TARGET_BITS - published
        print(f"  shortfall vs BIP-39 target    : {gap:.0f} bits "
              f"(2^{gap:.0f}x weaker than intended)")
        print()

    print("Takeaway: both generations sit far below the 128-bit floor. ~40-72")
    print("bits is enumerable by a resourced adversary — the same 'solvable")
    print("puzzle' class as a human-chosen brainwallet phrase. The device did")
    print("the choosing here, but the economics of drainer bots are identical:")
    print("enumerate the space offline, check candidate addresses against the")
    print("public chain, sweep the matches. See report.md for the full analysis.")


if __name__ == "__main__":
    main()
