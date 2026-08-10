#!/usr/bin/env python3
"""Compile every definition-referenced shader with Godot's Vulkan compiler."""

import os
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
SWEEP = REPO / "parity" / "shader_compile_sweep.gd"


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class ShaderCompileTests(unittest.TestCase):
    def test_every_definition_shader_compiles_for_vulkan(self):
        result = subprocess.run(
            [
                str(GODOT),
                "--path",
                str(REPO / "godot"),
                "--script",
                str(SWEEP),
                "--position",
                "5000,5000",
            ],
            capture_output=True,
            text=True,
            timeout=300,
        )

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("SHADER_SWEEP", output)
        self.assertNotIn("ERROR:", output, output)


if __name__ == "__main__":
    unittest.main()
