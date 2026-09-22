# Web3 Security

## Canon

Our research line covers smart-contract review, MEV mechanics such as JIT
liquidity, sandwiches, and trap pools, on-chain forensics, and the entropy of
human-generated seed phrases. We reproduce every mechanism in our own test
environment — network fork, our own pools, and our own bots — before treating
it as understood. The scope is security research and auditing; the purpose is
to understand mechanisms and protect our own projects, not to exploit other
people's funds.

## Goal and Outcome

Build a method to analyze DeFi incidents, schemes, and smart contracts that can
test any "easy money" claim in an hour rather than spending a week guessing.
The outcome: a repeatable forensics methodology, a catalog of analyzed
mechanisms, v4-hook audit rules, and key-entropy conclusions for auditing our
own projects.

## Architecture and Components

On-chain forensics methodology for any "a contract is draining money from a
pool" story:

1. Anomaly screener: export pools from an aggregator such as DeFiLlama and
   filter by fee flow × volume × TVL.
2. Archive logs: retrieve the pool's complete event history, including
   ModifyLiquidity and Swap, from an archive node; no conclusions without
   archive data.
3. Signatures: JIT is liquidity added and removed in the same transaction
   around another party's swaps; a sandwich is "bot → victim router → bot" in
   one block. Calculate both signatures rather than guessing.
4. Token-flow analysis: read a suspicious transaction through Transfer events
   all the way to the resulting outflow; never infer the result from a selector
   alone.
5. Verdict with alternatives: the most common explanation for a supposed
   "glitch" is lawful fee collection by a large LP on a high fee tier.

## Decisions and Constraints

- Catalog of analyzed mechanisms: JIT liquidity (the position exists for
  milliseconds, with no IL; code is a commodity, the edge is an uncontested
  niche plus latency and capital; in competitive markets tips consume 50–90% of
  profit); trap pools (a 20–80% fee tier with creator-owned liquidity — not an
  exploit but a tax on inattention); MEV infrastructure (seeing the swap and
  landing a bundle are two separate bottlenecks; a smart contract is passive
  and cannot observe the mempool, except a v4 hook invoked by the protocol).
- Auditing v4 hooks: every callback must be restricted with onlyPoolManager
  (Cork Protocol, $11–12 million); validate PoolKey; anti-JIT controls can be
  bypassed through a fee reset. Rule: a hook that controls funds must use a
  proven template such as BaseHook plus SafeCallback and receive a callback
  audit before deployment.
- Key entropy: human-generated seeds and brainwallets are predictable; modeling
  human choice with an LLM reduces the effective space by orders of magnitude
  relative to its nominal size. The validation methodology follows the Milk Sad
  precedent: prove the theory by measurement against real addresses, while
  committing never to remove funds or publish sensitive data. This measures a
  vulnerability class — human choice as an entropy source — not one
  implementation; there is no implementation bug to patch.
- Every mechanism is reproduced in our own test environment before it is
  treated as understood.

## Operating Workflow

For any claim or contract: screen for anomalies, pull archive logs, calculate
JIT/sandwich signatures, trace token flows to the resulting outflow, and issue
a verdict that considers lawful alternative explanations. For hooks, audit
callbacks, PoolKey validation, and upgrade paths before deployment. For
wallets, ask "where does the entropy come from?" as a mandatory audit question.

## Lessons and Rules

- Generate keys only with a CSPRNG and proven libraries.
- Treat any user input used as an entropy source as a vulnerability; neither a
  checksum nor "phrase complexity" fixes it.
- The remedy for a victim of a compromised brainwallet is not a "more complex
  phrase," but moving funds to a properly generated key.
- The LLM threat in this class is growing: what a script searched in a week
  yesterday may be narrowed by a model to hours tomorrow, so audits must
  include this in the threat model now.
- Countermeasures age faster than they can be written; hook security is an arms
  race.

## Sources

- `lore.md`
- `research/09-web3-security.md`

## Unknowns

- The Coldcard theft analysis involving weak seed entropy (research 11 and
  research/coldcard/) was not part of this dossier's reading list.
- Concrete incidents we investigated and their outcomes: Not established in the
  sources.

## When to Revisit

- If MEV infrastructure changes through new bundle markets or private mempools
  becoming the default, reassess the JIT section.
- Add new hook exploit classes after Uniswap v4 upgrades.
- If aggregators add routing protection against predatory fee tiers, reassess
  the trap-pool section.
