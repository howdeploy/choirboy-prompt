#!/usr/bin/env python3
"""Focused AGY configuration and Bash installer regression checks."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("agy_hooks", ROOT / "scripts/agy-hooks.py")
hooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hooks)


class AgyHooksTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="choirboy agy ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.path = self.root / ".gemini/config/hooks.json"

    def configure(self, mode, start="start --format agy", stop="stop"):
        return hooks.configure(self.path, mode, start, stop)

    def test_foreign_hooks_idempotency_updates_and_uninstall(self):
        foreign = {"foreign": {"SessionStart": [{"command": "keep-me"}]}}
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps(foreign), encoding="utf-8-sig")
        self.assertEqual(self.configure("status"), "absent")
        self.assertEqual(self.configure("install"), "changed")
        before = self.path.stat().st_mtime_ns
        self.assertEqual(self.configure("install"), "unchanged")
        self.assertEqual(self.path.stat().st_mtime_ns, before)
        self.assertEqual(self.configure("status"), "current")
        self.assertEqual(self.configure("status", "new checkout"), "stale")
        self.configure("install", "new checkout")
        self.assertEqual(json.loads(self.path.read_text())[hooks.NAME]["SessionStart"][0]["command"], "new checkout")
        self.assertEqual(self.configure("uninstall"), "changed")
        self.assertEqual(json.loads(self.path.read_text()), foreign)
        self.assertEqual(self.configure("uninstall"), "unchanged")

    def test_invalid_configuration_is_preserved(self):
        self.path.parent.mkdir(parents=True)
        for text in ["{broken", "[]", '"text"', "null"]:
            self.path.write_text(text)
            with self.assertRaises(ValueError):
                self.configure("install")
            self.assertEqual(self.path.read_text(), text)

    def test_missing_uninstall_does_not_create_files(self):
        self.assertEqual(self.configure("uninstall"), "unchanged")
        self.assertFalse(self.path.exists())

    @unittest.skipIf(os.name == "nt", "Native Windows adapters are covered by test-powershell.ps1")
    def test_bash_installer_and_adapter(self):
        # Model an installed CLI without depending on agy being in the host PATH.
        (self.root / ".gemini/antigravity-cli").mkdir(parents=True)
        env = os.environ.copy()
        env.update(HOME=str(self.root), CHOIRBOY_ARTIFACTS_DIR=str(self.root / "artifacts"), CHOIRBOY_BUNDLE_DIR=str(self.root / "no-bundle"))
        def install(*arguments):
            return subprocess.run(["bash", str(ROOT / "install.sh"), "--target", "agy", *arguments], env=env, check=True, capture_output=True, text=True)
        install()
        entry = json.loads(self.path.read_text())[hooks.NAME]
        self.assertEqual(len(entry["SessionStart"]), 1)
        self.assertEqual(len(entry["Stop"]), 1)
        install()
        self.assertEqual(json.loads(self.path.read_text())[hooks.NAME], entry)
        self.assertIn("agy      installed", install("--list").stdout)
        output = subprocess.run(entry["SessionStart"][0]["command"], shell=True, input='{"conversationId":"probe"}', env=env, check=True, capture_output=True, text=True)
        response = json.loads(output.stdout)
        context = response["injectSteps"][0]["systemMessage"]["systemMessage"]
        self.assertIn("<choirboy-context>", context)
        self.assertIn("<choirboy-delivery ", context)
        self.assertIn("context_sha256=", context)
        self.assertNotIn("hookSpecificOutput", response)
        stop = subprocess.run(entry["Stop"][0]["command"], shell=True, input='{"terminationReason":"NO_TOOL_CALL"}', env=env, check=True, capture_output=True, text=True)
        self.assertEqual(json.loads(stop.stdout), {})
        install("--uninstall")
        self.assertNotIn(hooks.NAME, json.loads(self.path.read_text()))


if __name__ == "__main__":
    unittest.main()
