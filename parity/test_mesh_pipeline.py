#!/usr/bin/env python3
"""Live depth/culling contract for procedural mesh triangle passes."""

import os
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
PROBE = REPO / "parity" / "mesh_pipeline_probe.gd"


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class MeshPipelineTests(unittest.TestCase):
    def test_triangles_use_depth_and_back_face_culling(self):
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
        self.assertIn("MESH_PIPELINE_TEST: PASS", output, output)
        self.assertNotIn("ERROR:", output, output)


if __name__ == "__main__":
    unittest.main()
