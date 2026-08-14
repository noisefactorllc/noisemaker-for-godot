#!/usr/bin/env python3
"""Output-sink contracts and live asynchronous frame export."""

import os
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
PROBE = REPO / "parity" / "frame_export_probe.gd"
UNIT_PROBE = REPO / "parity" / "output_runtime_test.gd"


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class FrameExportTests(unittest.TestCase):
    def test_sink_manager_and_bounded_queue_contracts(self):
        result = subprocess.run(
            [
                str(GODOT),
                "--headless",
                "--path",
                str(REPO / "godot"),
                "--script",
                str(UNIT_PROBE),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("OUTPUT_RUNTIME_TEST: PASS", output, output)
        self.assertNotIn("ERROR:", output, output)

    def test_async_readback_preserves_metadata_and_premultiplies(self):
        result = subprocess.run(
            [
                str(GODOT),
                "--path",
                str(REPO / "godot"),
                "--script",
                str(PROBE),
                "--position",
                "5000,5000",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("FRAME_EXPORT_TEST: PASS", output, output)
        self.assertNotIn("ERROR:", output, output)


if __name__ == "__main__":
    unittest.main()
