"""scripts/test runs the windowed suites with --godot-windowed.

The windowed suites (GODOT_WINDOWED) need a Godot binary with a window and a
GPU. --godot-windowed runs exactly that group through run_unittest, which
fails on any failure, error, skip or empty run, and it fails by name when no
usable Godot binary is given. These checks run scripts/test without a Godot.
"""

import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "test"


def run_script(*args, godot=None):
    env = {key: value for key, value in os.environ.items()
           if key not in ("GODOT", "NM_CHANGED_FILES", "NM_SHARD_COUNT", "NM_SHARD_INDEX")}
    if godot is not None:
        env["GODOT"] = godot
    # scripts/test checks the python3 on PATH; use the interpreter running this suite.
    env["PATH"] = os.pathsep.join([str(Path(sys.executable).parent), env.get("PATH", "")])
    return subprocess.run([str(SCRIPT), *args], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=60)


class WindowedModeTests(unittest.TestCase):

    def test_windowed_mode_without_godot_fails_by_name(self):
        result = run_script("--godot-windowed")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("--godot-windowed needs GODOT=", result.stderr)

    def test_windowed_mode_with_a_missing_binary_fails_by_name(self):
        result = run_script("--godot-windowed", godot=str(ROOT / "no-such-godot"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("GODOT is not an executable file", result.stderr)

    def test_windowed_mode_runs_the_windowed_group_through_run_unittest(self):
        text = SCRIPT.read_text()
        body = re.search(r"^run_godot_windowed\(\) \{\n(.*?)^\}", text, re.S | re.M)
        self.assertIsNotNone(body, "scripts/test defines no run_godot_windowed")
        self.assertIn('select_suites "${GODOT_WINDOWED[@]}"', body.group(1))
        self.assertRegex(body.group(1), r'run_unittest "\$\{godot_windowed\[@\]\}"')
        self.assertRegex(text, r"(?m)^\t--godot-windowed\)\n\t\trun_godot_windowed\n")


if __name__ == "__main__":
    unittest.main()
