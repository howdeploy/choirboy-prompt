# Research 25 — Reverse engineering capability map

## Question

Which reverse routes should an agent see, how should it choose the narrowest
one, and which shared invariant must hold across formats, platforms, and tools?

## Context

This map carries over the capability taxonomy from `reverse-skill` at commit
`71acc8e3115f76bad7a914c36466c1086232288c`. It complements the existing
`research/14` on owned offline games without extending that scope to
multiplayer games or third-party online systems.

Route source:
https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/config/routing.json

## Capability groups

### General and native binary

- **R0 General reverse engineering** — triage of an unknown binary, anti-debug,
  obfuscation, Unity/IL2CPP, and fallback when the exact format is not yet
  known.
- **R6 IDA**, **R22 Ghidra**, **R7 radare2** — alternative analysis surfaces.
  Selection depends on the tool actually available, its license, automation
  API, and the format, not on agent habit.
- **R15 Binary diff/symbol migration** — version comparison, transfer of names
  and function boundaries, and confirmation of changed paths.
- **R16 Patch diff/N-day** concerns security analysis of changes and is bounded
  in more detail by `research/27`.

### Mobile and managed runtimes

- **R1 APK reverse** — APK, resources, manifest, DEX/smali, JNI, signing, and
  observable runtime behavior on an owned device/emulator.
- **R2 Mobile reverse** — iOS/IPA and mixed mobile tasks; Android-only requests
  should route to R1.
- **R5 .NET reverse** — IL, metadata, managed resources, and obfuscation.
- **R33 Go/Rust reverse** — runtime metadata, symbol recovery, and properties
  of stripped binaries.

### Web client and extensions

- **R3 JS/frontend reverse** — bundles, source maps, frontend signing, protocol
  parameters, and runtime observation in a browser.
- **R30 Browser-extension reverse** — CRX/XPI, manifest, permissions, service
  worker/background, content scripts, and message boundaries.
- **R32 Thick-client security** from the adjacent map applies when the desktop
  application matters more than the implementation language.

### Specialized formats and devices

- **R4 DSL/custom VM reverse** — bytecode, opcode map, dispatcher, and
  reproducible virtual-machine semantics.
- **R8 Firmware** — container, filesystem, architecture, configuration, and
  emulation/laboratory runtime.
- **R21 Protocol reverse** — PCAP, message framing, state machine, protobuf/
  gRPC, and a verifiable decoder/dissector.
- **R31 macOS/Mach-O** — load commands, Objective-C/Swift metadata, signing,
  entitlements, and XPC in an owned environment.
- **R34 Hardware/debug interfaces** — UART/JTAG/SWD, flash layout, and USB
  device analysis only on owned laboratory hardware.

## Shared workflow

The route changes the tools and domain checklist, but not the evidence model:

1. identify the artifact, format, architecture, packaging, and actual runtime;
2. record hashes and work on a derived copy;
3. formulate the smallest useful hypothesis;
4. collect static Evidence: imports, strings, metadata, CFG, and resources;
5. collect dynamic Evidence in an owned runtime when possible and necessary
   for a confident conclusion;
6. connect addresses, offsets, symbols, requests, or hook points to an
   observation;
7. build a `callflow` Path and leave unverified claims as candidates;
8. after three actions without new Evidence, change the hypothesis, stage, or
   tool.

A decompiler is a representation, not a source of truth. Runtime behavior may
show another branch, loaded module, or served artifact; record the discrepancy
instead of smoothing it over.

## Tool selection

| Situation | Preferred route |
|---|---|
| Deep interactive commercial work is required and a license is available | IDA/JEB |
| Reproducible headless/open-source automation is required | Ghidra/radare2 |
| APK resources + DEX | jadx + apktool, then runtime when necessary |
| Mobile instrumentation in an owned environment | Frida/Objection after a static anchor |
| Protocol recovered from traffic | Wireshark/dissector + replay in a lab |
| Unknown firmware | hash → binwalk/layout → filesystem → lab/emulation |

Actual availability is determined by `research/24`; names in this table are not
installation promises.

## Options considered

1. One universal reverse skill. Simpler, but it loses format-specific
   invariants.
2. One skill per tool. This couples methodology to an application and
   duplicates guidance.
3. Capabilities organized by domain, with tools selected inside each route.
   Selected.

## Decision and boundaries

Retain domain routes and the shared Evidence workflow. Work is limited to owned
artifacts, local samples, owned devices, and explicitly authorized
environments. Games follow `research/14`; active security testing follows
`security-posture.md` and the case contract in `research/23`.

Do not carry upstream binaries, payload dumps, or the field journal into
memory. They can be separate external sources after review, but they are not
canonical project records or automatically trusted code.

## Revisit when

- A new format appears that no existing PRIMARY covers.
- A tool becomes unavailable or changes its automation API.
- Static and dynamic models diverge systematically.
- An engine/runtime needs a dedicated route because it now overloads R0.
