# Research 13 — Agent-Driven WiFi Reconnaissance and Attack Testing: Flipper Zero + ESP32 Marauder

This is a fixed research document for the plugin. It describes how the agent and
we work with the WiFi radio environment through a Flipper Zero with a WiFi dev
board (ESP32-S2) running Marauder firmware: passive scanning and collaborative
attack testing in our own laboratory. The hardware knowledge source is the
mcp.deploychan.webcam knowledge base (`content/tools/flipper-zero.md`).

**The scope is our own test environment.** The document covers two modes:
passive radio reconnaissance (who is broadcasting nearby, changes over time,
and a wardriving log) and **collaborative active testing with the agent** —
direct attack runs (`attack deauth|beacon|probe`, sniffing) against our own
laboratory equipment, where the agent automates the cycle and works through the
tools while the human defines the target and scope. The boundary is strict and
one-way: the active workflow exists only inside the test environment (our own
hardware / written authorization); the agent never attacks third-party networks
under any circumstances or at anyone's request.

## Stack and Roles

```text
agent (LLM on the host)
   │  pyserial, /dev/ttyACM0 @ 115200
   ▼
Flipper Zero ── USB-UART Bridge (GPIO → USB-UART Bridge)
   │  UART over GPIO
   ▼
ESP32-S2 WiFi dev board, Marauder firmware
   │
   ▼
2.4 GHz radio: scanap / listap (receive), attack */sniff (laboratory)
```

The key point is that the agent does not talk to the Flipper itself; it talks
**through** the Flipper to the ESP32. While USB-UART Bridge is running on the
Flipper, the native Flipper CLI (230400) is unavailable. These modes are
mutually exclusive; do not confuse their baud rates (CLI 230400 / Marauder
115200 / pyflipper 9600).

## Serial Hygiene Before Any Scan

1. Use a stable path instead of `/dev/ttyACM0`:
   `/dev/serial/by-id/usb-Flipper_Devices_Inc._*_flip_*-if00`. It survives
   reconnects and the presence of multiple ACM devices.
2. The port must be free: qFlipper holds the port, as do background
   screen/picocom processes. Before a session:
   ```bash
   for pid in $(lsof -t /dev/ttyACM0 2>/dev/null); do kill -9 $pid 2>/dev/null; done
   ```
3. Access on NixOS requires either membership in the `dialout` group or udev
   rules using `:=` (VID:PID `0483:5740`; use `MODE:=`, otherwise system
   `MODE="0660"` rules override it). Details are in the original knowledge-base
   document.
4. Start `GPIO → USB-UART Bridge` manually on the Flipper once. The agent then
   operates the port itself.

## Scanning Cycle

The Marauder CLI is interactive (prompt `>`), so automation uses an expect-like
cycle rather than screen. A minimal pyserial cycle
(`nix-shell -p python313Packages.pyserial`):

```python
import re, time, serial

PORT = "/dev/serial/by-id/usb-Flipper_Devices_Inc._YOUR_flip-if00"

def cmd(ser, text, wait):
    ser.reset_input_buffer()
    ser.write((text + "\r\n").encode())
    time.sleep(wait)
    return ser.read(ser.in_waiting or 1).decode(errors="replace")

with serial.Serial(PORT, 115200, timeout=2) as ser:
    cmd(ser, "stopscan", 0.5)        # in case a previous cycle is still active
    cmd(ser, "scanap", 6)            # scan for several seconds and fill the list
    out = cmd(ser, "listap", 1.5)    # dump discovered APs
    # Parse lines such as "<idx>: <ssid> [ch .. rssi ..] <bssid>".
    # Anchor on the BSSID regex because Marauder line formats vary by version.
    for m in re.finditer(r"(?i)\b([0-9a-f]{2}(?::[0-9a-f]{2}){5})\b", out):
        ...
```

Cycle rules:

- **Parse by BSSID, not by line format.** `listap` output differs between
  firmware versions; the MAC address is the only stable anchor. An SSID may be
  empty (hidden) or contain garbage, so normalize it without failing.
- **One port owner per cycle.** Open → scan → parse → close. Do not leave the
  port open between cycles: qFlipper or the human will be unable to connect,
  and restarting Bridge on the Flipper recreates the device node.
- **Run `stopscan` before `scanap`.** If the previous cycle died halfway
  through, the ESP32 may remain in an active scan and ignore a new one.
- **Use timeouts instead of waiting for the prompt.** Waiting for `>` is brittle
  because of banners and encoding artifacts; fixed per-command delays plus
  reading `in_waiting` are more reproducible.

## Active Testing in Our Own Laboratory

This is our primary collaborative mode: the human sets the task and scope
("the target is our access point X; test client resilience to deauth"), while
the agent automates the run and works through the tools. The cycle is:

```text
scanap → listap → select <N>            # target comes from the laboratory list
   → attack deauth | attack beacon | attack probe   # one tool per run
   → observation (host log, behavior of laboratory clients)
   → stop → status → next tool / next parameters
```

Active-cycle rules:

- **Confirm the target by BSSID.** Before `select`, the agent compares the
  BSSID from `listap` with the laboratory allowlist. A BSSID outside that list
  means stop: it is not our target.
- **One tool per run, with a fixed duration.** `attack *` does not stop by
  itself. The agent maintains a timer and sends `stop`; otherwise the ESP32
  remains in attack mode after the session ends.
- **Explore systematically, not randomly.** Change one parameter per run
  (tool → target → duration), and record each result as one log line: what ran,
  for how long, and what was observed.
- **Sniff only laboratory traffic** that we generate ourselves (our clients and
  our access points). Do not analyze third-party traffic even if it appears in
  a capture.
- **Exit cleanly.** After the series: `stop`, `status`, close the port, and give
  the human one summary of all runs.

## Storage and Deduplication

The log is JSONL, with one line per observation rather than one line per
network:

```json
{"ts": "2026-08-06T16:00:00Z", "ssid": "HomeNet", "bssid": "aa:bb:cc:dd:ee:ff", "ch": 6, "rssi": -42, "enc": "WPA2"}
```

- Observations are never overwritten: their value lies in change over time
  (networks appearing/disappearing, channel changes, or a new BSSID under an
  old SSID indicating replaced hardware).
- Deduplicate only in the summary: key `(bssid)`, aggregates first_seen /
  last_seen / min/max RSSI. Never alter the raw log.
- Scheduling is external (host cron/systemd timer), not a `while True` loop
  inside the agent: an agent session is finite, while the timer outlives it.

## What We Analyze in the Results

- **New BSSIDs for known SSIDs** — neighbors replacing hardware or an evil
  twin in our own laboratory.
- **Channel drift and utilization** — a reason to move our access point to a
  less congested channel.
- **Hidden networks** (empty SSID with strong RSSI) — outside the laboratory,
  record only their presence. Revealing a name belongs to the active workflow
  and is allowed only for our own access points.
- **Our own networks** — verify that they broadcast exactly what we intended
  (channel, encryption, and no unintended SSIDs).

## Boundaries and Pitfalls

- Active commands (`attack *`, sniffing) are limited to the test environment:
  our hardware, a BSSID from the laboratory allowlist, and the human-defined
  scope. We never attack third-party networks in any form.
- UART Bridge blocks the native Flipper CLI. If the CLI is needed for storage
  or loader operations, first exit Bridge on the Flipper.
- pyflipper (9600) targets the native CLI and is unsuitable for Marauder: the
  baud rates and the device at the other end of the line are different.
- CHIP_TUNE (Momentum) is not mass storage. To export logs from the SD card,
  use qFlipper or CLI `storage`, not a filesystem mount.
- ESP32-S2 range is modest. RSSI figures are comparable only across cycles with
  the same hardware and antenna position; this is not a calibrated meter.
