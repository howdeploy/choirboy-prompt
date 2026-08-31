# Research 09 — Web3 security: contract auditing, MEV, and on-chain forensics

Fixed plugin research document. It records the methodology of the "Forensics"
project (see `lore.md`): how we analyze DeFi incidents, schemes, and smart
contracts. The scope is security research and auditing; the purpose is to
understand mechanisms and protect our own projects, not to exploit other
people's funds.

## On-chain forensics methodology

Use this process to evaluate any story that claims "a contract is draining
money from a pool":

1. **Anomaly screener.** Export pools from an aggregator such as DeFiLlama and
   filter by fee flow × volume × TVL. An anomaly such as "negligible volume,
   hundreds of dollars per day" usually means a very high fee tier combined
   with low TVL.
2. **Archive logs.** Retrieve the pool's complete event history, including
   ModifyLiquidity and Swap, from an archive node. Do not draw conclusions
   without archive data.
3. **Signatures.** JIT is liquidity added and removed in the same transaction
   around another party's swaps. A sandwich is "bot → victim router → bot" in
   one block. Calculate both signatures rather than guessing.
4. **Token-flow analysis.** Read a suspicious transaction through Transfer
   events all the way to the resulting outflow; never infer the result from a
   selector alone.
5. **Verdict with alternatives.** The most common explanation for a supposed
   "glitch" is lawful fee collection by a large LP on a high fee tier. In an
   explorer it can look indistinguishable from a bot, but it is replicated with
   capital rather than code.

## Catalog of analyzed mechanisms

- **JIT liquidity.** Atomically add and remove liquidity around someone else's
  swap. The position exists for milliseconds, with no IL and no squeeze. The
  economics: code is a commodity—a v4 hook can be written in an evening—while
  the actual edge is an uncontested niche plus latency and capital. In
  competitive markets, tips consume 50–90% of profit.
- **Trap pools.** A pool with a 20–80% fee tier and creator-owned liquidity. An
  aggregator routes an inattentive swap through it, and the user pays half the
  trade as a fee. This is not an exploit: the AMM executes exactly what was
  configured. It is a tax on inattention with returns of tens of dollars per
  day.
- **MEV infrastructure.** Seeing the swap through a mempool, gRPC, or
  ShredStream and landing a bundle through Flashbots or Jito are two separate
  bottlenecks; JIT is dead without both. A smart contract is passive by itself:
  it cannot observe the mempool or choose its place in a block. The exception is
  a v4 hook invoked by the protocol.

## Auditing v4 hooks: recent vulnerability classes

- Missing access control in callbacks, as in Cork Protocol at $11–12 million:
  every callback must be restricted with onlyPoolManager, or anyone can invoke
  the hook.
- Validate PoolKey, or an attacker can attach a fake pool to the hook.
- Anti-JIT controls can be bypassed through a fee reset. Countermeasures age
  faster than they can be written; this is an arms race.
- Rule: a hook that controls funds must use a proven template such as BaseHook
  plus SafeCallback and receive a callback audit before deployment.

## Key entropy

Human-generated seeds and brainwallets are predictable. Bots systematically
search weak-entropy spaces and drain such addresses; research has established
this as a class of compromise.

**Our research.** A person does not "randomize" a mnemonic word list randomly.
Word choices are statistically correlated through frequency, association
chains, personal dates, keyboard patterns, and cultural clichés. The research
question was whether an LLM that simulates human choice can search the space of
human-generated mnemonics more efficiently than script-based dictionaries. The
answer is yes: modeling human choice reduces the effective space by orders of
magnitude relative to its nominal size. The validation methodology follows the
Milk Sad precedent: prove the theory by measurement against real addresses,
while committing never to remove funds or publish sensitive data. This measures
a vulnerability class—human choice as an entropy source—rather than one
implementation. That distinction makes the result fundamental: there is no
implementation bug to patch because the generation method itself is unsafe.

Conclusions for auditing our projects:

- generate keys only with a CSPRNG and proven libraries;
- treat any user input used as an entropy source as a vulnerability; neither a
  checksum nor "phrase complexity" fixes it;
- make "where does the entropy come from?" a mandatory audit question for
  wallets and signing systems;
- the remedy for a victim of a compromised brainwallet is not a "more complex
  phrase," but moving funds to a properly generated key;
- the LLM threat in this class is growing. What a script searched in a week
  yesterday may be narrowed by a model to hours tomorrow, so audits must include
  this in the threat model now.

## When to revisit

- If MEV infrastructure changes through new bundle markets or private mempools
  becoming the default, reassess the JIT section.
- Add new hook exploit classes after Uniswap v4 upgrades.
- If aggregators add routing protection against predatory fee tiers, reassess
  the trap-pool section.
