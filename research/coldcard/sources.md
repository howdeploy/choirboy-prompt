# Coldcard entropy heist — sources

Collected on 2026-08-02 via Tavily (research + search + extract). Priority was
given to primary sources (Coinkite, Block), followed by corroborating press.

## Primary sources

- **Coinkite — Mk3 Security Advisory** (what to do, firmware ranges,
  dice-roll exception):
  https://blog.coinkite.com/coldcard-mk3-seed-generation-warning
- **Coinkite — Technical Deep Dive into the Entropy Issue** (technical
  backgrounder: ckcc.rng_bytes → ngu.random.bytes, MicroPython fallback, why
  the review missed it, acknowledgment of the AI audit):
  https://blog.coinkite.com/entropy-technical-backgrounder
- **Block Bitcoin Engineering — Predictable RNG Fallback and 32-Bit Reseed
  in COLDCARD Firmware** (root cause, C snippets for the guard and Yasmarang
  initialization, Mk4's 32-bit reseed, git-blame timeline):
  https://engineering.block.xyz/blog/predictable-rng-fallback-and-32-bit-reseed-in-coldcard-firmware

## Corroborating press / analysis

- CoinDesk — Major bitcoin wallet flaw drains 594 BTC in 25-minute sweep:
  https://www.coindesk.com/tech/2026/07/31/major-bitcoin-wallet-flaw-drains-594-btc-in-25-minute-sweep
- KuCoin flash — Coldcard Wallet Entropy Flaw Leads to $38M Bitcoin Theft
  (01:31–01:56 UTC window, bc1qnk… consolidator, TRNG/PRNG analysis):
  https://www.kucoin.com/news/flash/coldcard-wallet-entropy-flaw-leads-to-38m-bitcoin-theft
- TechTimes — commit detail (rng_bytes → ngu.random.bytes on 2021-03-01),
  Mk4 boot reseed: 32B SE1 + 8B SE2 → 4 bytes passed to reseed():
  https://www.techtimes.com/articles/322392/20260731/coldcard-hardware-wallet-hacked-via-firmware-bug-that-bypassed-rng-five-years.htm
- BeInCrypto / Yahoo — Yasmarang initialization from UID/SysTick/RTC, RTC
  oscillator disabled on Mk3, ~four billion combinations (2^32) for Mk4:
  https://beincrypto.com/coldcard-rng-flaw-bitcoin-theft
- Cryptopolitan — Galaxy Research estimate of 1,082.65 BTC / $70M / 1,196
  addresses; Block's quote about Clay Garrett and the on-chain trail:
  https://www.cryptopolitan.com/coldcard-biggest-security-failure-cost-70m
- Cryptonomist — dice-roll thresholds (50–98 → 128 bits, 99+ → 256 bits),
  TAPSIGNER/OPENDIME/SATSCARD unaffected:
  https://en.cryptonomist.ch/2026/07/31/coinkite-seed-vulnerability-theft
- Bitcoin Well — timeline, migration to libsecp256k1/libNgU, “8 years” =
  age of the upstream MicroPython code, not the duration of vulnerable
  generation:
  https://bitcoinwell.com/coldcard-vulnerability
- Forbes — general coverage, Coinkite quote “We were unaware of the bug until
  today,” warning about importing the seed into other wallets:
  https://www.forbes.com/sites/digital-assets/2026/07/31/massive-surprise-bitcoin-attack-sparks-sudden-price-crash-fears

## Related class (for context, not about Coldcard)

- Milk Sad — CVE-2023-39910 (libbitcoin bx seed, mt19937, 32-bit seed):
  https://nvd.nist.gov/vuln/detail/CVE-2023-39910 ; https://milksad.info/disclosure.html
- Trust Wallet Core — CVE-2023-31290 (entropy compressed to 32 bits):
  https://nvd.nist.gov/vuln/detail/CVE-2023-31290
- Vasek et al., “The Bitcoin Brain Drain” (98% of brainwallets cracked,
  median drain time—seconds/minutes):
  https://mvasek.com/static/papers/vasekfc16.pdf
