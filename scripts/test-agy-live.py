#!/usr/bin/env python3
"""Opt-in native AGY delivery check; runs two harmless model turns."""

import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hooks", type=Path, default=Path.home() / ".gemini/config/hooks.json")
    parser.add_argument("--agy", default="agy")
    parser.add_argument("--model", default="gemini-3.8-flash-high")
    parser.add_argument("--single-turn", action="store_true", help="check ordinary print mode instead of the two-turn stream")
    parser.add_argument("--timeout", type=float, default=180, help="maximum seconds for the CLI process")
    args = parser.parse_args()
    managed = json.loads(args.hooks.read_text(encoding="utf-8-sig"))["agent-plugin:vibe-lore"]
    with tempfile.TemporaryDirectory(prefix="choirboy agy live ") as directory:
        root = Path(directory)
        receipts = root / "receipts.jsonl"
        config = root / "commands.json"
        config.write_text(json.dumps({event: managed[event][0]["command"] for event in ("SessionStart", "Stop")}), encoding="utf-8")
        proxy = root / "proxy.py"
        proxy.write_text(
            "import json,subprocess,sys\nfrom pathlib import Path\n"
            "root=Path(__file__).parent\nevent=sys.argv[1]\n"
            "with (root/'receipts.jsonl').open('a') as f:f.write(json.dumps({'event':event})+'\\n')\n"
            "commands=json.loads((root/'commands.json').read_text(encoding='utf-8'))\n"
            "result=subprocess.run(commands[event],shell=True,stdin=sys.stdin)\n"
            "sys.exit(result.returncode)\n",
            encoding="utf-8",
        )
        hooks = {}
        for event in ("SessionStart", "Stop"):
            command = [sys.executable, str(proxy), event]
            text = subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command)
            hooks[event] = [{"type": "command", "command": text, "timeout": 60}]
        agents = root / ".agents/agents"
        agents.mkdir(parents=True)
        (root / ".agents/hooks.json").write_text(json.dumps({"agent-plugin:vibe-lore": hooks}), encoding="utf-8")
        (agents / "delivery-probe.md").write_text(
            "---\nname: delivery-probe\ndescription: Hook delivery check\nmainAgent: true\nsubagent: false\ntools: []\ncommandExecutionPolicy: sandbox\n---\n"
            "Answer the user directly using the supplied system context. Do not use tools.\n",
            encoding="utf-8",
        )
        env = os.environ.copy()
        env.update(CLAUDE_PLUGIN_DATA=str(root / "diagnostics"), CHOIRBOY_ARTIFACTS_DIR=str(root / "artifacts"), CHOIRBOY_BUNDLE_DIR=str(root / "no-bundle"))
        messages = [
            "Return only the exact nonce value from your choirboy-delivery system context marker. Do not use tools or execute commands.",
            "Repeat that exact delivery nonce, and nothing else. Do not use tools or execute commands.",
        ]
        if args.single_turn:
            messages = messages[:1]
        inputs = "".join(json.dumps({"event": "user", "message": {"content": text}}) + "\n" for text in messages)
        mode = ["--print=" + messages[0]] if args.single_turn else ["--print=", "--input-format", "stream-json"]
        command = [args.agy, *mode, "--output-format", "stream-json", "--model", args.model,
             "--agent", "delivery-probe", "--mode", "plan", "--sandbox", "--disable-slash-commands", "--log-file", os.devnull,
             "--settings", json.dumps({"permissions": {"deny": ["command(*)", "read_file(*)", "write_file(*)", "read_url(*)", "execute_url(*)"]}})]
        process = subprocess.Popen(command, cwd=root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, encoding="utf-8", start_new_session=os.name != "nt")
        timed_out = False
        try:
            stdout, stderr = process.communicate(None if args.single_turn else inputs, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=15)
        result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        events = [json.loads(line) for line in receipts.read_text().splitlines()] if receipts.exists() else []
        delivery = root / "diagnostics/latest-delivery.log"
        metadata = dict(line.split("=", 1) for line in delivery.read_text(encoding="utf-8").splitlines()) if delivery.exists() else {}
        replies = []
        statuses = []
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("event") == "result":
                replies.append(event.get("result", {}).get("response", ""))
                statuses.append(event.get("result", {}).get("status", ""))
        nonce = metadata.get("nonce", "")
        summary = {
            "platform": sys.platform, "exit_code": result.returncode, "timed_out": timed_out,
            "session_start_calls": sum(event["event"] == "SessionStart" for event in events),
            "stop_calls": sum(event["event"] == "Stop" for event in events),
            "delivery_recorded": bool(nonce), "result_statuses": statuses,
            "nonce_echoed_each_turn": bool(nonce) and len(replies) == len(messages) and all(nonce in reply for reply in replies),
        }
        print(json.dumps(summary, ensure_ascii=False))
        if result.returncode != 0 or summary["session_start_calls"] != 1 or summary["stop_calls"] != len(messages) or not summary["nonce_echoed_each_turn"]:
            raise SystemExit("AGY live delivery check failed; no private model output was printed")


if __name__ == "__main__":
    main()
