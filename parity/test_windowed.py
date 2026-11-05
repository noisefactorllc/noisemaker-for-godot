"""Tests for the bounded windowed-spawn helper.

A stalled windowed launch must fail named inside the operator's 300-second
engine-command cap and mark the process so later windowed launches fail
immediately; these tests prove both with a stub command, without an engine.
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import windowed  # direct import: the helper sits next to this test


class WindowedBoundTests(unittest.TestCase):
    def setUp(self):
        os.environ.pop(windowed.STALL_FLAG, None)

    def tearDown(self):
        os.environ.pop(windowed.STALL_FLAG, None)

    def test_fast_launch_passes_through(self):
        result = windowed.run_windowed(["true"], timeout=30)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn(windowed.STALL_FLAG, os.environ)

    def test_stall_raises_named_and_sets_flag(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            windowed.run_windowed(["sleep", "30"], timeout=1)
        self.assertEqual(os.environ.get(windowed.STALL_FLAG), "1")

    def test_later_launch_after_stall_fails_immediately(self):
        os.environ[windowed.STALL_FLAG] = "1"
        with self.assertRaises(RuntimeError) as ctx:
            windowed.run_windowed(["true"], timeout=30)
        self.assertIn("stalled past its bound", str(ctx.exception))

    def test_flag_does_not_block_a_fresh_process(self):
        # A new process (a new suite run) starts clean: the flag is not
        # inherited unless the parent exported it.
        result = subprocess.run(
            [sys.executable, "-c",
             "import sys; sys.path.insert(0, %r); import windowed; "
             "print(windowed.run_windowed(['true'], timeout=30).returncode)"
             % str(Path(__file__).resolve().parent)],
            capture_output=True, text=True, timeout=60,
            env={k: v for k, v in os.environ.items() if k != windowed.STALL_FLAG})
        self.assertEqual(result.stdout.strip(), "0")


if __name__ == "__main__":
    unittest.main()
