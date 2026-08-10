#!/usr/bin/env python3
"""GPU-free Godot regression tests for runtime contracts."""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class RuntimeContractTests(unittest.TestCase):
    def _run_godot_script(self, script):
        with tempfile.TemporaryDirectory(prefix="nm-godot-runtime-") as tmp:
            script_path = Path(tmp) / "runtime_test.gd"
            script_path.write_text(textwrap.dedent(script))
            return subprocess.run(
                [str(GODOT), "--headless", "--path", str(REPO / "godot"), "--script", str(script_path)],
                capture_output=True,
                text=True,
                timeout=30,
            )

    def test_boolean_definition_defines_emit_glsl_bool_literals(self):
        script = textwrap.dedent(
            """
            extends SceneTree

            func read_definition(path: String) -> Dictionary:
                var file := FileAccess.open(path, FileAccess.READ)
                var parsed = JSON.parse_string(file.get_as_text())
                file.close()
                return parsed

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                if backend_script == null or not backend_script.can_instantiate():
                    print("DEFINE_TEST: backend failed to load")
                    quit(1)
                    return
                var backend = backend_script.new()
                if not backend.has_method("_format_define_value"):
                    print("DEFINE_TEST: missing definition-aware formatter")
                    quit(1)
                    return
                var noise3d := read_definition("res://addons/noisemaker/effects/synth3d/noise3d.json")
                var render3d := read_definition("res://addons/noisemaker/effects/render/render3d.json")
                var curl := read_definition("res://addons/noisemaker/effects/synth/curl.json")
                var noise_source := FileAccess.get_file_as_string("res://addons/noisemaker/shaders/effects/synth3d/noise3d/precompute.glsl")
                var render_source := FileAccess.get_file_as_string("res://addons/noisemaker/shaders/effects/render/render3d/render3d.glsl")
                var curl_source := FileAccess.get_file_as_string("res://addons/noisemaker/shaders/effects/synth/curl/curl.glsl")
                var actual := [
                    backend.call("_format_define_value", "RIDGES", 0.0, noise3d, noise_source),
                    backend.call("_format_define_value", "RIDGES", 1.0, noise3d, noise_source),
                    backend.call("_format_define_value", "INVERT", 0.0, render3d, render_source),
                    backend.call("_format_define_value", "FILTERING", 0.0, render3d, render_source),
                    backend.call("_format_define_value", "OCTAVES", 4.0, noise3d, noise_source),
                    backend.call("_format_define_value", "RIDGES", 1.0, curl, curl_source),
                    backend.call("_format_define_value", "RIDGES", 1.0, curl, "// if (RIDGES)\\nif (RIDGES != 0) {}"),
                ]
                var expected := ["false", "true", "false", "0", "4", "1", "1"]
                if actual == expected:
                    print("DEFINE_TEST: PASS")
                    quit(0)
                else:
                    print("DEFINE_TEST: expected=", expected, " actual=", actual)
                    quit(1)
            """
        )
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DEFINE_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_parameterized_texture_dimension_applies_power(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                if backend_script == null or not backend_script.can_instantiate():
                    print("DIMENSION_TEST: backend failed to load")
                    quit(1)
                    return
                var backend = backend_script.new()
                var power_spec := {"param": "volumeSize_chain_0", "power": 2, "default": 4096}
                var multiply_spec := {"param": "volumeSize_chain_0", "multiply": 2, "default": 128}
                var actual := [
                    backend.call("_resolve_dim", power_spec, 256, {"volumeSize_chain_0": 64}),
                    backend.call("_resolve_dim", power_spec, 256, {}),
                    backend.call("_resolve_dim", multiply_spec, 256, {"volumeSize_chain_0": 32}),
                ]
                var expected := [4096, 4096, 64]
                if actual == expected:
                    print("DIMENSION_TEST: PASS")
                    quit(0)
                else:
                    print("DIMENSION_TEST: expected=", expected, " actual=", actual)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DIMENSION_TEST: PASS", result.stdout, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
