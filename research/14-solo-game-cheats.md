# Research 14 — Cheats for Solo Games: Currency, HP, and Parameter Editing

This is a fixed research document for the plugin. It defines a method for
working with offline games: how to find and change values such as currency, HP,
stats, and inventory through three access paths — memory, save files, and code.
It belongs to the general security workflow: everything is tested in a test
environment using our own copies of games.

**Boundary.** Only solo/offline games and our own copies are in scope.
Multiplayer and online economies are entirely outside the scope: cheats there
harm other players, violate the ToS, and enter the anti-cheat surface. We do not
work on them in any form. Paid "cheats for sale" are also outside our work; that
is a different, gray-market business.

## Target Taxonomy

What we modify and how it is typically represented in memory:

| Target | Typical representation | Notes |
|---|---|---|
| Currency, gold, points | int32/int64, sometimes double | easiest target, exact-value scan |
| HP / mana / stamina | float or int; a bar may store 0–100 rather than the displayed value | unknown-value scan based on change |
| Stats (strength, agility) | int, sometimes recalculated from level | change the source, not the derivative |
| Inventory, item quantity | int near the item id | change quantity, not id |
| Timers, cooldowns, oxygen | float, decreases/increases | freeze the value |
| Experience / level | int; level is often derived from XP | change XP and let the level follow |

Rule: **change the source, not the display.** If a stat is recalculated from
level and equipment, a direct edit disappears at the next recalculation.

## Path 1 — Memory (Primary)

Tools: scanmem + GameConqueror or PINCE natively on Linux, or Cheat Engine
under Wine. Work with the game process PID. Under Proton this is the wineserver
child PID; PINCE resolves it automatically.

Exact-value scan cycle for currency:

```text
remember the current value (1234 gold)
   → first scan: exact int32 1234
   → change it in the game (spend/earn) → 1180
   → next scan: 1180
   → repeat until 1–5 addresses remain
   → write our chosen value and verify it in the game
```

When there is no exact value, such as an HP bar without a number, use unknown
initial value → changed/unchanged/increased/decreased between states. It takes
longer but converges.

Rules for this path:

- **The data type is a hypothesis, not a fact.** If int32 finds nothing, try
  int64 → float → double. Japanese RPGs often use double for currency; bars
  commonly use float.
- **The value may be encoded.** Common schemes include value×2, value^const,
  or "value + random salt, with the salt stored nearby." A sign is that the
  discovered address behaves disproportionately. Inspect adjacent bytes and a
  possible second copy of the value.
- **Addresses are unstable.** An address moves after restarting the game. For
  a persistent cheat, use a pointer scan — a chain of base + offsets from a
  static module — or an AOB code signature.
- **Code is often better than a value.** Use "Find what writes to this
  address" → locate the HP decrement instruction → nop it or change it to an
  increment. This removes the mechanic rather than changing one number. A code
  patch survives restarts through an AOB signature; a value edit does not.
- **Freeze versus one-shot.** Freezing writes in a loop and can break game logic
  that expects a change, such as death triggers or scripts. A one-shot write is
  cleaner; reserve freeze for timers and bars.

## Path 2 — Save Files

This is the path of least resistance when the save is not encrypted:

1. Back up the save before any edit. This is an absolute rule.
2. Inspect the format: edit JSON/XML/YAML as text; use decoders for
   protobuf/bson; use a hex editor for a custom binary format.
3. Search for a known value in hex: currency 123456 is `40 E2 01 00`
   (little-endian int32). Change it, load the save, and verify.
4. **Checksums.** A classic save protection is a CRC32/hash at the end of the
   file. A sign is that an edited save fails to load or rolls back. Determine
   how the save is signed, often visible in the save code through Path 3, and
   recalculate it after the edit. Sometimes the checksum covers only part of
   the fields; determine the boundary iteratively.
5. Steam/Epic saves may live in the cloud, where synchronization overwrites a
   local edit. Disable cloud saves while working.

## Path 3 — Code Inspection and Modification

Use this path when memory is protected or a persistent modification is needed:

- **Unity (Mono, managed code).** `Assembly-CSharp.dll` is .NET. dnSpyEx /
  ILSpy can read and edit methods directly, such as `get_Money` or
  `TakeDamage`. This is the easiest case because names and logic resemble the
  source code.
- **Unity (IL2CPP).** The code is compiled to native instructions. Il2CppDumper
  extracts metadata — class and method names plus offsets — and Ghidra then
  uses those recovered symbols. There is no direct IL edit; patch native code
  or load through a mod loader.
- **Mod loaders as a cheat platform.** BepInEx / MelonLoader for Unity and
  UE4SS for Unreal let us write a plugin: a Harmony patch on `TakeDamage`, a
  custom HUD, or teleportation. This is the most maintainable form of a cheat:
  it survives restarts and is disabled by removing a DLL. One plugin often
  transfers across a series of games on the same engine with minimal changes.
- **Java.** Use recaf / bytecode editing; Minecraft has its own mod ecosystem.
- **Native code (C++).** In Ghidra/IDA, search for strings such as "gold" or
  "hp," xrefs to damage functions, and AOB signatures. This takes the longest
  but is universal.
- **Godot / Ren'Py / RPG Maker.** Scripts are often open or trivially unpacked
  (GDScript pck, .rpyb, rvdata2). Modify data or scripts directly without
  touching memory.

## Process and Discipline

- **One target per run.** Do not modify currency and HP at the same time; after
  a crash, we would not know which change caused it. This is the "one variable
  per run" rule from our general workflow.
- **Finding log.** Maintain a table: target → address/pointer/signature → method
  → game version. After a game patch, verify signatures against the log rather
  than rediscovering everything.
- **A game update moves everything.** Addresses and offsets live until the next
  patch; AOB signatures and pointer chains last longer. The final artifact is
  therefore a signature table, not an address dump.
- **Verify the effect in the game, not in the scanner.** A changed number in
  memory does not mean the game accepted it. There may be a second copy or a
  recalculation. There is no server here because this is the solo-game scope.

## Pitfalls

- **Anti-cheat in a solo game.** It is uncommon but exists, for example Denuvo
  Anti-Cheat or EA Javelin. A memory scanner is detected and the game crashes;
  an immediate crash after attach is the sign. Use Path 2 (saves) or Path 3
  (code before launch) and leave memory untouched.
- **DRM breaks AOB signatures.** Denuvo VMProtect repackages code. Search for
  signatures in unpacked regions or work through save files.
- **32-bit versus 64-bit:** choose the matching scan width; pointer chains are
  incompatible across builds.
- **Proton specifics:** the game process is not the `steam` PID. Find the real
  executable with `ps aux | grep -i <game>`; PINCE resolves Wine processes
  automatically.
- **Exhaustive modification can ruin achievements and the game's balance.** An
  "everything at once" cheat destroys the game. Remove unwanted grind, not the
  game itself.
