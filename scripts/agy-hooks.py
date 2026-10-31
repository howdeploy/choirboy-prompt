#!/usr/bin/env python3
"""Manage only Choirboy's named entry in Antigravity's hooks.json."""

import argparse
import json
import os
from pathlib import Path
import tempfile


NAME = "agent-plugin:vibe-lore"


def configure(path, mode, start_command, stop_command):
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        data = {}
    if not isinstance(data, dict):
        raise ValueError("hooks.json must contain an object")
    expected = {
        "SessionStart": [{"type": "command", "command": start_command, "timeout": 30}],
        "Stop": [{"type": "command", "command": stop_command, "timeout": 15}],
    }
    if mode == "status":
        return "current" if data.get(NAME) == expected else "stale" if NAME in data else "absent"
    if mode == "uninstall":
        if NAME not in data:
            return "unchanged"
        del data[NAME]
    else:
        if data.get(NAME) == expected:
            return "unchanged"
        data[NAME] = expected
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".choirboy-agy-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return "changed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("mode", choices=("install", "uninstall", "status"))
    parser.add_argument("start_command")
    parser.add_argument("stop_command")
    args = parser.parse_args()
    try:
        print(configure(args.path, args.mode, args.start_command, args.stop_command))
    except (OSError, ValueError) as exc:
        parser.exit(1, f"agy-hooks: refusing to update {args.path}: {exc}\n")


if __name__ == "__main__":
    main()
