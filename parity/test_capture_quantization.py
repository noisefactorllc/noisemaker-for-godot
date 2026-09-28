#!/usr/bin/env python3
"""Capture quantization conforms to the reference capture spec.

GAP-002 round 2026-09-27: Image.set_pixel truncated on RGBA8 (0.5 -> 127),
biasing every float-surface candidate PNG 1 LSB low on ~half the pixels.
This suite runs the real nm_backend._capture_byte used by _snapshot_surface
and judges its bytes against a Python transliteration of the reference
capture spec (JS Math.round(v*255): half-up on exact f64, clamped to
[0,255]) — a cross-language conformance check of the same spec; end-to-end
PNG capture equivalence is evidenced separately by the job's archived
comparator receipts (evidence gap002-in-tree-receipts/ and
gap002-native-metal/ of Worker Elves job e5d3fe6f). It also asserts the defect
discriminators: truncation (0.5 -> 127, 0.253 -> 64) must NOT occur. Per
the repo standard (test_kit_playback.py), the suite FAILS LOUDLY when no
Godot binary is available instead of passing as a vacuous 0-test run.
"""

import math
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
PROBE = REPO / "parity" / "capture_quantization_probe.gd"


def _godot():
    env = os.environ.get("GODOT")
    if env:
        return Path(env)
    for name in ("Godot", "godot", "Godot4", "godot4"):
        found = shutil.which(name)
        if found:
            return Path(found)
    candidate = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    return candidate if candidate.exists() else None


def _oracle(i):
    v = i / 20000.0
    # JS Math.round is half-up on the exact f64 v*255; clamp like the
    # reference's Math.max(0, Math.min(255, ...)).
    return min(255, max(0, math.floor(v * 255.0 + 0.5)))


class CaptureQuantizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = _godot()
        if cls.godot is None:
            # Repo standard (GAP-001 round, test_kit_playback.py): fail loudly,
            # never pass as a vacuous 0-test run.
            raise RuntimeError(
                "capture quantization gate requires a Godot binary "
                "(set GODOT or put godot/Godot on PATH)"
            )

    def test_capture_byte_matches_reference_math_round(self):
        result = subprocess.run(
            [
                str(self.godot),
                "--headless",
                "--path",
                str(REPO / "godot"),
                "--script",
                str(PROBE),
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        pairs = {
            int(m.group(1)): int(m.group(2))
            for m in re.finditer(r"^QUANT (\d+) (\d+)$", output, re.M)
        }
        self.assertEqual(
            len(pairs), 20001, f"probe emitted {len(pairs)} of 20001 points: {output[-400:]}"
        )
        mismatches = {i: b for i, b in pairs.items() if b != _oracle(i)}
        self.assertEqual(
            mismatches, {}, f"{len(mismatches)} bytes deviate from the reference capture spec"
        )
        # Defect discriminators (Image.set_pixel truncation must not occur):
        self.assertEqual(pairs[10000], 128, "0.5 must quantize to 128, not the truncation value 127")
        self.assertEqual(pairs[5060], 65, "0.253 must quantize to 65, not the truncation value 64")


if __name__ == "__main__":
    unittest.main()
