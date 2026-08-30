#!/usr/bin/env python3
"""Create a Claude custom-plugin ZIP with preserved executable bits."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    "hooks/hooks.json",
    "hooks/artifact-stop.sh",
    "hooks/session-start.sh",
    "scripts/artifact-generator.py",
    "skills/load-context/SKILL.md",
    "skills/diagnose/SKILL.md",
}
EXECUTABLES = {
    "install.sh",
    "hooks/artifact-stop.sh",
    "hooks/session-start.sh",
    "scripts/artifact-generator.py",
    "scripts/build-context.py",
    "scripts/package-plugin.py",
    "scripts/test.sh",
}


def version() -> str:
    manifest = json.loads((ROOT / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
    return manifest["version"]


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    paths = set()
    for raw in result.stdout.split(b"\0"):
        if not raw:
            continue
        relative = Path(os.fsdecode(raw))
        path = ROOT / relative
        if path.is_file() and relative.parts[0] != "dist":
            paths.add(relative)
    # REQUIRED is the distribution contract. Include newly added required
    # files even before their first commit so local release validation cannot
    # accidentally test a ZIP that omits the feature under development.
    for required in REQUIRED:
        relative = Path(required)
        path = ROOT / relative
        if path.is_file():
            paths.add(relative)
    return sorted(paths, key=lambda value: value.as_posix())


def write_zip(output: Path) -> None:
    files = repository_files()
    missing = REQUIRED.difference(path.as_posix() for path in files)
    if missing:
        raise SystemExit(f"required plugin files are missing: {', '.join(sorted(missing))}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative in files:
            source = ROOT / relative
            info = zipfile.ZipInfo.from_file(source, arcname=relative.as_posix())
            info.compress_type = zipfile.ZIP_DEFLATED
            # Build the same Unix-compatible ZIP on Windows, macOS, and Linux.
            # Windows stat() does not preserve Git's executable bit.
            info.create_system = 3
            mode = 0o100755 if relative.as_posix() in EXECUTABLES else 0o100644
            info.external_attr = mode << 16
            archive.writestr(info, source.read_bytes(), compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="destination ZIP path")
    args = parser.parse_args()
    subprocess.run(["python3", "scripts/build-context.py", "--check"], cwd=ROOT, check=True)
    output = args.output or ROOT / "dist" / f"choirboy-prompt-{version()}.zip"
    if not output.is_absolute():
        output = ROOT / output
    write_zip(output)
    with zipfile.ZipFile(output) as archive:
        missing = REQUIRED.difference(archive.namelist())
        if missing:
            raise SystemExit(f"invalid ZIP, missing: {', '.join(sorted(missing))}")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
