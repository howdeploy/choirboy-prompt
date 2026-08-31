# Research 24 — Tool registry, bootstrap, and MCP boundaries

## Question

How can an agent use the full available arsenal without inventing paths or
versions, mistaking a declared capability for an installed tool, or executing
an unreviewed installer from an external skill?

## Sources and evidence

The sources are the `reverse-skill` manifests and scripts at commit
`71acc8e3115f76bad7a914c36466c1086232288c`, reviewed on 2026-08-31:

- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/scripts/bootstrap-manifest.json
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/kali/scripts/bootstrap-manifest.json
- https://github.com/zhaoxuya520/reverse-skill/blob/71acc8e3115f76bad7a914c36466c1086232288c/skills/ops/skill-supply-chain.md

The upstream `test-bootstrap-manifest.sh` test passed. The manifests distinguish
auto-installed, manual, local MCP, and remote MCP capabilities; a tool index is
built for a specific machine after actual verification.

## Base set: 25 capabilities

`jadx`, `apktool`, `jeb-pro`, `frida`, `frida-ps`, `idalib-mcp`,
`reqable-mcp`, `jshookmcp`, `xquik-mcp`, `anything-analyzer`, `idapro`, `r2`,
`rabin2`, `adb`, `agent-browser`, `ghidra-mcp`, `seclists`, `proxycat`,
`burpsuite-mcp`, `nmap`, `pentestswarm`, `binwalk`, `yara`, `pwntools`,
`bkcrack`.

## Kali profile: 44 capabilities

It includes the base set adapted for apt plus these additional capabilities:
`sqlmap`, `hashcat`, `hydra`, `gobuster`, `ffuf`, `msfconsole`, `nuclei`,
`mcp-kali-server`, `metasploitmcp`, `hexstrike-ai`, `adaptixc2`,
`atomic-operator`, `sstimap`, `xsstrike`, `wpprobe`, `fluxion`, `gef`,
`evil-winrm-py`, `coercer`.

This is an option catalog, not a list of automatically authorized actions.

## Registry contract

Every capability requires:

- a stable name;
- a discovery method and `verifyCommand`;
- install kind: package manager, pinned package, Git commit, release artifact,
  manual, local HTTP MCP, or remote HTTP MCP;
- exact version/commit/tag and checksum when upstream supports them;
- install directory and real absolute paths after installation;
- MCP name/command/args/URL and a registration-verification method;
- dependencies, post-install steps, and a `canAutoInstall` flag;
- a source and manual instructions for commercial/licensed products.

The agent's sequence is:

1. read the current tool index;
2. independently verify the binary, service, or registration;
3. use an already working tool;
4. if it is absent, locate the capability in the manifest;
5. show the risk and request approval when installation changes external state
   or the environment requires it;
6. install only by the declared method;
7. verify again and update the index;
8. after another failure, switch tools or provide an exact blocker rather than
   guessing a path or rerunning the installer indefinitely.

## Pinning and reproducibility

Good upstream examples include `jadx v1.5.6` and `apktool v3.0.2` with
SHA-256, `frida-tools 14.10.4`, `agent-browser 0.31.1`, `pwntools 4.15.0`, and
Git dependencies pinned to full commits. The catalog is not fully
reproducible, however:

- `winget-latest` and some apt packages change over time;
- some GitHub release installers choose the current asset;
- commercial JEB/IDA/Burp products are installed manually;
- remote `xquik-mcp` has no local artifact pin;
- "MCP registered" does not mean "service running and reachable."

The index must therefore distinguish `declared`, `installed`, `verified`,
`registered`, and `connected` rather than reducing everything to one
`available=true` value.

## MCP as a separate trust boundary

Before an external MCP is registered, read its manifest, dependencies, and
scripts; inspect its bind address, authentication, CORS, filesystem/network
scope, logging, request limits, and dangerous defaults. Configuration from an
untrusted repository is not copied into the global MCP registry automatically.

The upstream Burp MCP genuinely connects a Java extension to a Node stdio
bridge, listens on loopback, and uses a Bearer token. Its `scope_gate` and
`privacy_mode`, however, only store flags and audit events: request-sending
handlers do not check those flags. Those switches therefore cannot be treated
as protection until tool-layer enforcement is fixed.

## Options considered

1. Install using the first command found in a skill. Fast, but unauditable.
2. Rely only on `$PATH`. This misses MCPs, versions, services, and manually
   installed products.
3. Vendor the entire toolchain. Heavy, licensing-sensitive, and quickly stale.
4. Use a manifest plus an observed machine-local index. Selected: declaration
   remains separate from observed state.

## Decision

Carry over the capability catalog and the registry/bootstrap model as
knowledge. Installer and MCP code move only in separate changes after review
and with licenses preserved. The prompt rule to "use all available tools" is
grounded specifically in the verified tool index: an absent or disconnected
tool does not count as available.

## Revisit when

- Manifest versions become stale or upstream changes an install contract.
- A runtime provides a native, versioned capability registry with health
  checks.
- A reproducible lockfile becomes possible for apt/winget/remote MCP.
- An MCP audit discovers broader filesystem/network authority.
