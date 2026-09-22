# Radio Reconnaissance: Flipper + Marauder

## Canon

We work with the Wi-Fi spectrum through a Flipper Zero and a Wi-Fi dev board
running Marauder in two modes; the laboratory is part of the shared security
frame. In passive mode, the agent runs scanap → listap → BSSID parsing →
scheduled JSONL logging. In active mode, we jointly verify techniques inside
our own laboratory: the human defines target and scope, the agent automates
runs of `attack deauth/beacon/probe` and sniffing, and targets are matched by
BSSID against the lab allowlist. Outside the test environment, work is passive
only; we never attack third-party networks.

## Goal and Outcome

Work with the WiFi radio environment through a Flipper Zero with a WiFi dev
board (ESP32-S2) running Marauder firmware: passive scanning (who is
broadcasting nearby, changes over time, and a wardriving log) and collaborative
active testing with the agent — direct attack runs against our own laboratory
equipment, where the agent automates the cycle and works through the tools
while the human defines the target and scope.

## Architecture and Components

Stack and roles: the agent (LLM on the host) talks over pyserial at
`/dev/ttyACM0` @ 115200 → Flipper Zero running GPIO → USB-UART Bridge → UART
over GPIO → ESP32-S2 WiFi dev board with Marauder firmware → 2.4 GHz radio
(`scanap`/`listap` receive, `attack *`/sniff in the laboratory). The key point
is that the agent does not talk to the Flipper itself; it talks through the
Flipper to the ESP32. While USB-UART Bridge is running, the native Flipper CLI
(230400) is unavailable; the modes are mutually exclusive and their baud rates
must not be confused (CLI 230400 / Marauder 115200 / pyflipper 9600).

## Decisions and Constraints

- Scope is our own test environment. The boundary is strict and one-way: the
  active workflow exists only inside the test environment (our own hardware /
  written authorization); the agent never attacks third-party networks under
  any circumstances or at anyone's request.
- Serial hygiene: use a stable `/dev/serial/by-id/usb-Flipper_Devices_Inc._*
  _flip_*-if00` path; the port must be free (qFlipper and background
  screen/picocom processes hold it); on NixOS use `dialout` group membership or
  udev rules with `:=` (VID:PID `0483:5740`, `MODE:=`); start USB-UART Bridge
  manually on the Flipper once, then the agent operates the port itself.
- Cycle rules: parse by BSSID, not by line format (Marauder line formats vary
  by version; the MAC address is the only stable anchor); one port owner per
  cycle (open → scan → parse → close); run `stopscan` before `scanap`; use
  fixed per-command timeouts instead of waiting for the `>` prompt.
- Active-cycle rules: confirm the target by BSSID against the laboratory
  allowlist before `select` — a BSSID outside the list means stop; one tool per
  run with a fixed duration, because `attack *` does not stop by itself;
  explore systematically (change one parameter per run) and log each result as
  one line; sniff only laboratory traffic we generate ourselves; exit cleanly
  (`stop`, `status`, close the port, one summary of all runs).

## Operating Workflow

Passive cycle: `stopscan` → `scanap` (several seconds) → `listap` → parse lines
by BSSID regex → append JSONL observations (one line per observation, never
overwritten; deduplicate only in the summary by `(bssid)` with first_seen /
last_seen / min/max RSSI). Scheduling is external (host cron/systemd timer),
not a `while True` loop inside the agent.

Active cycle: `scanap` → `listap` → `select <N>` (target from the laboratory
allowlist) → `attack deauth | attack beacon | attack probe` (one tool per run)
→ observation → `stop` → `status` → next tool or parameters.

Analysis of results: new BSSIDs for known SSIDs (replaced hardware or an evil
twin in our own lab), channel drift and utilization, hidden networks (outside
the laboratory, record only their presence), and verification that our own
networks broadcast exactly what we intended.

## Lessons and Rules

- UART Bridge blocks the native Flipper CLI; exit Bridge first if the CLI is
  needed for storage or loader operations.
- pyflipper (9600) targets the native CLI and is unsuitable for Marauder.
- CHIP_TUNE (Momentum) is not mass storage; export SD-card logs through
  qFlipper or CLI `storage`, not a filesystem mount.
- ESP32-S2 range is modest: RSSI figures are comparable only across cycles with
  the same hardware and antenna position; this is not a calibrated meter.
- An SSID may be empty (hidden) or contain garbage; normalize it without
  failing.

## Sources

- `lore.md`
- `research/13-flipper-marauder-wifi-scan.md`

## Unknowns

- The exact laboratory allowlist of BSSIDs: Not established in the sources.
- Collected wardriving logs and their findings: Not established in the sources.
- The hardware knowledge base (`content/tools/flipper-zero.md` from
  mcp.deploychan.webcam) was not part of this dossier's reading list.

## When to Revisit

- When Marauder firmware changes its CLI output format, re-verify the BSSID
  parsing rules against the new format.
- When the laboratory hardware changes (board, antenna), re-baseline RSSI
  comparisons, since figures are not comparable across hardware.
