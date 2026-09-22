# Single-Player Game Cheats

## Canon

We apply the same security method to offline games: changing currency, HP, and
other values through three paths — memory (scanmem/PINCE, exact or
unknown-value scans, pointer chains, and code changes instead of raw-value
edits), save files (hex, formats, and checksums), and code inspection (dnSpy
for Unity Mono, Il2CppDumper, BepInEx/Harmony plugins, and Ghidra for native
code). We use our own copies and test environment, one target per run, and log
discoveries by signature. Multiplayer and online economies are completely out
of scope.

## Goal and Outcome

Define a method for working with offline games: how to find and change values
such as currency, HP, stats, and inventory through three access paths —
memory, save files, and code. It belongs to the general security workflow:
everything is tested in a test environment using our own copies of games. Paid
"cheats for sale" are also outside our work; that is a different, gray-market
business.

## Architecture and Components

- Path 1 — Memory (primary): scanmem + GameConqueror or PINCE natively on
  Linux, or Cheat Engine under Wine; work with the game process PID (under
  Proton the wineserver child PID; PINCE resolves it automatically).
- Path 2 — Save files: the path of least resistance when the save is not
  encrypted; text formats edited directly, protobuf/bson through decoders,
  custom binary through a hex editor.
- Path 3 — Code inspection and modification: dnSpyEx / ILSpy for Unity Mono
  (`Assembly-CSharp.dll`); Il2CppDumper plus Ghidra for Unity IL2CPP; BepInEx /
  MelonLoader for Unity and UE4SS for Unreal as mod-loader cheat platforms;
  recaf / bytecode editing for Java; Ghidra/IDA for native C++; direct
  script/data edits for Godot / Ren'Py / RPG Maker.
- Target taxonomy: currency (int32/int64, sometimes double; exact-value scan),
  HP/mana/stamina (float or int; unknown-value scan), stats (change the source,
  not the derivative), inventory quantity, timers (freeze), experience (change
  XP and let the level follow).

## Decisions and Constraints

- Boundary: only solo/offline games and our own copies are in scope.
  Multiplayer and online economies are entirely outside the scope: cheats there
  harm other players, violate the ToS, and enter the anti-cheat surface. We do
  not work on them in any form.
- Change the source, not the display: if a stat is recalculated from level and
  equipment, a direct edit disappears at the next recalculation.
- Memory-path rules: the data type is a hypothesis, not a fact (try int32 →
  int64 → float → double); the value may be encoded (value×2, value^const, or
  salted); addresses are unstable — use pointer scans or AOB signatures for
  persistence; code is often better than a value ("Find what writes to this
  address" → nop or invert the HP decrement; a code patch survives restarts
  through an AOB signature); prefer one-shot writes over freezing, reserving
  freeze for timers and bars.
- Save-path rules: back up the save before any edit — an absolute rule; search
  known values in hex (little-endian); handle CRC32/hash checksums by
  recalculating them after the edit; disable cloud saves while working, since
  synchronization overwrites a local edit.
- Code-path rules: mod-loader plugins are the most maintainable form of cheat —
  they survive restarts, are disabled by removing a DLL, and often transfer
  across a series of games on the same engine.

## Operating Workflow

1. Pick one target per run — never modify currency and HP at the same time.
2. Try the memory path first: exact-value scan cycle (remember value → scan →
   change in game → rescan → repeat until 1–5 addresses remain → write and
   verify) or unknown-value scan for bars without numbers.
3. If memory is protected or a persistent modification is needed, move to save
   files or code inspection.
4. Maintain a finding log: target → address/pointer/signature → method → game
   version. The final artifact is a signature table, not an address dump.
5. Verify the effect in the game, not in the scanner: there may be a second
   copy or a recalculation. There is no server here because this is the
   solo-game scope.

## Lessons and Rules

- One target per run: after a crash, we would not know which change caused it —
  the "one variable per run" rule from our general workflow.
- A game update moves everything: addresses and offsets live until the next
  patch; AOB signatures and pointer chains last longer. After a patch, verify
  signatures against the log rather than rediscovering everything.
- Anti-cheat in a solo game exists (for example Denuvo Anti-Cheat or EA
  Javelin): an immediate crash after attach is the sign; use saves or code
  before launch and leave memory untouched.
- DRM breaks AOB signatures: Denuvo VMProtect repackages code; search in
  unpacked regions or work through save files.
- 32-bit versus 64-bit: choose the matching scan width; pointer chains are
  incompatible across builds.
- Proton specifics: the game process is not the `steam` PID; find the real
  executable with `ps aux | grep -i <game>`.
- Exhaustive modification can ruin achievements and the game's balance: remove
  unwanted grind, not the game itself.

## Sources

- `lore.md`
- `research/14-solo-game-cheats.md`

## Unknowns

- The concrete games already processed and their signature tables: Not
  established in the sources.
- Which of the three paths was used most often in practice: Not established in
  the sources.

## When to Revisit

- After a game patch, verify stored signatures against the finding log instead
  of rediscovering everything.
- When a new engine or protection scheme appears in our library, extend the
  path-3 tooling notes for it.
