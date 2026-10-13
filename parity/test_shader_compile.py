#!/usr/bin/env python3
"""Compile every definition-referenced shader with Godot's active backend."""

import os
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from parity.godot_floor_noise import without_engine_exit_noise
except ImportError:  # direct discovery (unittest discover -s parity)
    from godot_floor_noise import without_engine_exit_noise


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
        self.assertRegex(output, r"SHADER_SWEEP compiled=\d+ missing=0 failed=0\b")
        self.assertNotIn("ERROR:", without_engine_exit_noise(output), output)

    @unittest.skipUnless(platform.system() == "Darwin", "Metal shader compiler requires macOS")
    def test_metal_compile_error_fails_sweep(self):
        with tempfile.TemporaryDirectory(prefix="godot-metal-sweep-") as temporary:
            project = Path(temporary) / "godot"
            shutil.copytree(REPO / "godot", project, ignore=shutil.ignore_patterns(".godot"))
            shader = project / "addons/noisemaker/shaders/effects/synth/solid/solid.glsl"
            source = shader.read_text(encoding="utf-8")
            self.assertIn("void main() {", source)
            self.assertIn("fragColor = vec4(color * alpha, alpha);", source)
            source = source.replace("void main() {", "float constant(float x) { return x; }\n\nvoid main() {")
            source = source.replace(
                "fragColor = vec4(color * alpha, alpha);",
                "fragColor = vec4(color * constant(alpha), alpha);",
            )
            shader.write_text(source, encoding="utf-8")

            result = subprocess.run(
                [str(GODOT), "--path", str(project), "--script", str(SWEEP), "--position", "5000,5000"],
                capture_output=True,
                text=True,
                timeout=300,
            )

        output = result.stdout + result.stderr
        self.assertIn("Metal", output)
        self.assertIn("Error compiling shader", output)
        self.assertRegex(output, r"SHADER_SWEEP compiled=\d+ missing=0 failed=1\b")
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("synth/solid/solid", output)


if __name__ == "__main__":
    unittest.main()
