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

    def test_volume_uniforms_clamp_power_of_two_to_texture_limit(self):
        script = """
            extends SceneTree

            func graph_with_volume_size(value: int) -> Dictionary:
                return {
                    "passes": [{
                        "uniforms": {
                            "volumeSize": value,
                            "volumeSize_chain_0": value,
                            "volumeSize_node_0": value,
                            "unrelated": value,
                        },
                    }],
                    "textures": {},
                }

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                if not backend.has_method("_clamp_graph_volume_sizes"):
                    print("VOLUME_LIMIT_TEST: missing clamp method")
                    quit(1)
                    return
                var constrained := graph_with_volume_size(128)
                var exact_fit := graph_with_volume_size(128)
                backend.call("_clamp_graph_volume_sizes", constrained, 8192)
                backend.call("_clamp_graph_volume_sizes", exact_fit, 16384)
                var constrained_uniforms: Dictionary = constrained["passes"][0]["uniforms"]
                var exact_uniforms: Dictionary = exact_fit["passes"][0]["uniforms"]
                var constrained_ok: bool = constrained_uniforms == {
                    "volumeSize": 64,
                    "volumeSize_chain_0": 64,
                    "volumeSize_node_0": 64,
                    "unrelated": 128,
                }
                var exact_ok: bool = exact_uniforms["volumeSize"] == 128 \
                    and exact_uniforms["volumeSize_chain_0"] == 128 \
                    and exact_uniforms["volumeSize_node_0"] == 128
                if constrained_ok and exact_ok:
                    print("VOLUME_LIMIT_TEST: PASS")
                    quit(0)
                else:
                    print("VOLUME_LIMIT_TEST: constrained=", constrained_uniforms, " exact=", exact_uniforms)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("VOLUME_LIMIT_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_mrt_budget_demotes_trailing_float_attachment_only_when_needed(self):
        script = """
            extends SceneTree

            func graph_with_mrt() -> Dictionary:
                return {
                    "passes": [{
                        "id": "pointsEmit:init",
                        "outputs": {"xyzOut": "xyz", "velOut": "vel", "rgbaOut": "rgba"},
                    }],
                    "textures": {
                        "xyz": {"format": "rgba32f"},
                        "vel": {"format": "rgba32float"},
                        "rgba": {"format": "rgba8"},
                    },
                }

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                if not backend.has_method("_apply_mrt_format_budget"):
                    print("MRT_BUDGET_TEST: missing budget method")
                    quit(1)
                    return
                var constrained := graph_with_mrt()
                var desktop := graph_with_mrt()
                backend.call("_apply_mrt_format_budget", constrained, 32)
                backend.call("_apply_mrt_format_budget", desktop, 64)
                var constrained_textures: Dictionary = constrained["textures"]
                var desktop_textures: Dictionary = desktop["textures"]
                var constrained_ok: bool = constrained_textures["xyz"]["format"] == "rgba32f" \
                    and constrained_textures["vel"]["format"] == "rgba16f" \
                    and constrained_textures["rgba"]["format"] == "rgba8"
                var desktop_ok: bool = desktop_textures["xyz"]["format"] == "rgba32f" \
                    and desktop_textures["vel"]["format"] == "rgba32float" \
                    and desktop_textures["rgba"]["format"] == "rgba8"
                if constrained_ok and desktop_ok:
                    print("MRT_BUDGET_TEST: PASS")
                    quit(0)
                else:
                    print("MRT_BUDGET_TEST: constrained=", constrained_textures, " desktop=", desktop_textures)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("MRT_BUDGET_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_audio_samples_pack_into_declared_scope_and_spectrum_slots(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                if not backend.has_method("set_audio_samples"):
                    print("AUDIO_PACK_TEST: missing audio sample API")
                    quit(1)
                    return
                var waveform := PackedFloat32Array()
                waveform.resize(128)
                waveform[0] = 0.25
                waveform[1] = 0.5
                waveform[2] = 0.75
                waveform[3] = 1.0
                var spectrum := PackedFloat32Array()
                spectrum.resize(128)
                spectrum[0] = 1.0
                spectrum[1] = 0.75
                spectrum[2] = 0.5
                spectrum[3] = 0.25
                backend.call("set_audio_samples", waveform, spectrum)
                var layout := {
                    "audioWaveform_0": {"slot": 4, "components": "xyzw"},
                    "audioSpectrum_0": {"slot": 5, "components": "xyzw"},
                }
                var packed: PackedByteArray = backend.call("pack_with_layout", layout, {}, {})
                var values := packed.to_float32_array()
                var expected := PackedFloat32Array()
                expected.resize(24)
                expected[16] = 0.25
                expected[17] = 0.5
                expected[18] = 0.75
                expected[19] = 1.0
                expected[20] = 1.0
                expected[21] = 0.75
                expected[22] = 0.5
                expected[23] = 0.25
                if values == expected:
                    print("AUDIO_PACK_TEST: PASS")
                    quit(0)
                else:
                    print("AUDIO_PACK_TEST: expected=", expected, " actual=", values)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("AUDIO_PACK_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_nested_oscillator_uniform_is_seekable_and_scaled_when_packed(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                if not backend.has_method("resolve_uniform_value"):
                    print("NESTED_AUTOMATION_TEST: missing runtime automation resolver")
                    quit(1)
                    return
                var rate := {
                    "type": "Oscillator", "oscType": 0,
                    "min": 0.0, "max": 1.0, "speed": 1.0, "offset": 0.0, "seed": 1.0,
                }
                var carrier := {
                    "type": "Oscillator", "oscType": 2,
                    "min": 0.0, "max": 1.0, "speed": rate, "offset": 0.0, "seed": 1.0,
                }
                var quarter = backend.call("resolve_uniform_value", carrier, 0.25, {"min": 2.0, "max": 6.0})
                var later = backend.call("resolve_uniform_value", carrier, 0.75, null)
                backend.call("resolve_uniform_value", carrier, 0.12, null)
                var repeated = backend.call("resolve_uniform_value", carrier, 0.75, null)
                var expected_quarter = 2.0 + 4.0 * fposmod(-20.0 / TAU, 1.0)
                var expected_later = fposmod(20.0 / TAU, 1.0)
                var layout := {"amount": {"slot": 0, "components": "x"}}
                var pass_data := {
                    "uniforms": {"amount": carrier},
                    "uniformSpecs": {"amount": {"min": 2.0, "max": 6.0}},
                }
                backend.set("_time", 0.25)
                var packed: PackedByteArray = backend.call("pack_with_layout", layout, {}, pass_data)
                var packed_amount = packed.to_float32_array()[0]
                var ok: bool = abs(quarter - expected_quarter) <= 1e-8 \
                    and abs(later - expected_later) <= 1e-8 \
                    and repeated == later \
                    and abs(packed_amount - expected_quarter) <= 1e-6
                if ok:
                    print("NESTED_AUTOMATION_TEST: PASS")
                    quit(0)
                else:
                    print("NESTED_AUTOMATION_TEST: quarter=", quarter, " later=", later,
                        " repeated=", repeated, " packed=", packed_amount)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("NESTED_AUTOMATION_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_external_inputs_drive_nested_rate_and_capture_requirements_recurse(self):
        script = """
            extends SceneTree

            func oscillator(kind: int, speed) -> Dictionary:
                return {
                    "type": "Oscillator", "oscType": kind,
                    "min": 0.0, "max": 1.0, "speed": speed, "offset": 0.0, "seed": 1.0,
                }

            func _init() -> void:
                var backend = load("res://addons/noisemaker/runtime/nm_backend.gd").new()
                if not backend.has_method("get_audio_input_requirements"):
                    print("EXTERNAL_AUTOMATION_TEST: missing capture requirements")
                    quit(1)
                    return
                var midi_rate := {
                    "type": "Midi", "channel": 1, "mode": 2,
                    "min": 0.0, "max": 1.0, "sensitivity": 1.0,
                }
                var audio_rate := {
                    "type": "Audio", "band": 4,
                    "min": 0.0, "max": 1.0, "_invalid": false,
                }
                backend.call("set_midi_state", {
                    "channels": {1: {"key": 60, "velocity": 127, "gate": 1, "time": 0}},
                })
                backend.call("set_audio_state", {"raw": 1.0, "rawReady": true})
                var midi_forward = backend.call("resolve_uniform_value", oscillator(2, midi_rate), 0.0125, null)
                var audio_forward = backend.call("resolve_uniform_value", oscillator(2, audio_rate), 0.0125, null)
                backend.call("set_midi_state", {
                    "channels": {1: {"key": 60, "velocity": 0, "gate": 1, "time": 0}},
                })
                backend.call("set_audio_state", {"raw": -1.0, "rawReady": true})
                var midi_reverse = backend.call("resolve_uniform_value", oscillator(2, midi_rate), 0.0125, null)
                var audio_reverse = backend.call("resolve_uniform_value", oscillator(2, audio_rate), 0.0125, null)

                var inner := {
                    "type": "Audio", "band": 4, "min": 0.0, "max": 1.0, "_invalid": false,
                    "channel": 2, "name": "Inner Interface", "id": "inner-id",
                }
                var outer := {
                    "type": "Audio", "band": 0, "min": inner, "max": 1.0, "_invalid": false,
                    "channel": 1, "name": "Outer Interface", "id": "outer-id",
                }
                var requirements: Dictionary = backend.call("get_audio_input_requirements", {
                    "passes": [
                        {"uniforms": {"amount": outer}},
                        {
                            "effectKey": "synth.scope", "namespace": "synth", "func": "scope",
                            "uniforms": {},
                        },
                    ],
                })
                var ids := []
                for requirement in requirements["selected"]:
                    ids.append(requirement["id"])
                ids.sort()
                var invalid_outer := {
                    "type": "Audio", "band": 0, "min": inner, "max": 1.0, "_invalid": true,
                }
                var invalid_requirements: Dictionary = backend.call("get_audio_input_requirements", {
                    "passes": [{"uniforms": {"amount": invalid_outer}}],
                })
                var invalid_value = backend.call("resolve_uniform_value", invalid_outer, 0.5, null)

                backend.call("set_audio_state", {
                    "devices": {
                        "actual-id": {
                            "name": "Shared Name", "connected": true,
                            "channels": {1: {"low": 0.8}},
                        },
                    },
                })
                var missing_id := {
                    "type": "Audio", "band": 0, "min": 0.0, "max": 1.0, "_invalid": false,
                    "channel": 1, "name": "Shared Name", "id": "missing-id",
                }
                var missing_id_value = backend.call("resolve_uniform_value", missing_id, 0.5, null)
                var cyclic := oscillator(0, 1.0)
                cyclic["speed"] = cyclic
                var cyclic_value = backend.call("resolve_uniform_value", cyclic, 0.25, null)
                var ok: bool = abs(midi_forward - 0.25) <= 1e-8 \
                    and abs(audio_forward - 0.25) <= 1e-8 \
                    and abs(midi_reverse - 0.75) <= 1e-8 \
                    and abs(audio_reverse - 0.75) <= 1e-8 \
                    and ids == ["inner-id", "outer-id"] \
                    and requirements["needsLegacy"] \
                    and invalid_requirements["selected"].is_empty() \
                    and invalid_value == 0.0 \
                    and missing_id_value == 0.0 \
                    and cyclic_value == 0.0
                if ok:
                    print("EXTERNAL_AUTOMATION_TEST: PASS")
                    quit(0)
                else:
                    print("EXTERNAL_AUTOMATION_TEST: midi=", midi_forward, "/", midi_reverse,
                        " audio=", audio_forward, "/", audio_reverse, " ids=", ids,
                        " invalid=", invalid_requirements, "/", invalid_value,
                        " missing-id=", missing_id_value, " cyclic=", cyclic_value)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("EXTERNAL_AUTOMATION_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_midi_expression_modes_and_default_audio_selection(self):
        script = """
            extends SceneTree

            class MidiState extends RefCounted:
                var channel := {"key": 60, "gate": 0, "velocity": 100,
                    "cc": {74: 127}, "cc14": {31: 16383}, "nrpn": {1234: 8192},
                    "pitchBend": 0, "pressure": 127, "polyPressure": {60: 64}}
                func get_channel(_number):
                    return channel
                func get_zone_voice(_config):
                    return {"channel": channel, "key": 60, "velocity": 100, "time": 0}

            class AudioState extends RefCounted:
                func get_device_channel_state(config):
                    return {"raw": 1, "rawReady": true} if config.get("channel") == 32 else null

            func _init() -> void:
                var backend = load("res://addons/noisemaker/runtime/nm_backend.gd").new()
                backend.set_midi_state(MidiState.new())
                backend.set_audio_state(AudioState.new())
                var cases := [[5, {"cc": 74}, 1.0], [6, {"cc": 31}, 1.0],
                    [7, {"nrpn": 1234}, 8192.0 / 16383.0], [8, {}, 0.0],
                    [9, {}, 1.0], [10, {}, 64.0 / 127.0]]
                for item in cases:
                    for selector in [{"channel": 2}, {"zone": 0, "members": 5}]:
                        var value := {"type": "Midi", "mode": item[0], "min": 0.25, "max": 0.75}
                        value.merge(item[1]); value.merge(selector)
                        var actual = backend.resolve_uniform_value(value, 0, null)
                        if abs(actual - (0.25 + item[2] * 0.5)) > 1e-12:
                            print("EXPRESSION_TEST: mismatch ", value, " actual=", actual)
                            quit(1); return
                var audio := {"type": "Audio", "band": 4, "channel": 32, "min": 0.25, "max": 0.75}
                if backend.resolve_uniform_value(audio, 0, null) != 0.75:
                    quit(2); return
                var requirements = backend.get_audio_input_requirements({"passes": [{"uniforms": {"amount": audio}}]})
                if requirements["selected"].size() != 1 or requirements["selected"][0]["name"] != null:
                    print("EXPRESSION_TEST: requirements ", requirements)
                    quit(3); return
                for selector in [{"channel": 33}, {"name": "Input"}, {"channel": 32, "id": "missing-name"}]:
                    var invalid := {"type": "Audio", "band": 4, "min": 0.25, "max": 0.75}
                    invalid.merge(selector)
                    if backend.resolve_uniform_value(invalid, 0, null) != 0.25:
                        quit(4); return
                print("EXPRESSION_TEST: PASS")
                quit(0)
        """
        result = self._run_godot_script(script)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("EXPRESSION_TEST: PASS", result.stdout)

    def test_blend_factor_names_accept_definition_json_casing(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                var upper = backend.call("_blend_factor", "ONE")
                var lower = backend.call("_blend_factor", "one")
                if upper == lower and upper == RenderingDevice.BLEND_FACTOR_ONE:
                    print("BLEND_CASE_TEST: PASS")
                    quit(0)
                else:
                    print("BLEND_CASE_TEST: upper=", upper, " lower=", lower)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BLEND_CASE_TEST: PASS", result.stdout, result.stdout + result.stderr)
        self.assertNotIn("unknown blend factor", result.stdout + result.stderr)

    def test_synthesized_mat3_uniform_uses_three_std140_columns(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                var globals := {
                    "basis": {
                        "type": "mat3",
                        "uniform": "cubeBasis",
                        "default": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0],
                    }
                }
                var layout: Dictionary = backend.call("_synth_layout", "test", "mat3", globals)
                var header: String = backend.call("_synth_header", layout)
                var packed: PackedByteArray = backend.call("pack_with_layout", layout, globals, {})
                var values := packed.to_float32_array()
                var spec: Dictionary = layout.get("cubeBasis", {})
                var slot := int(spec.get("slot", -1))
                var matrix_ok: bool = spec.get("columns") == 3 \
                    and header.contains("mat3(data[%d].xyz, data[%d].xyz, data[%d].xyz)" % [slot, slot + 1, slot + 2]) \
                    and values[slot * 4] == 1.0 and values[slot * 4 + 2] == 3.0 \
                    and values[(slot + 1) * 4] == 4.0 and values[(slot + 2) * 4 + 2] == 9.0
                if matrix_ok:
                    print("MAT3_LAYOUT_TEST: PASS")
                    quit(0)
                else:
                    print("MAT3_LAYOUT_TEST: layout=", layout, " header=", header, " values=", values)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("MAT3_LAYOUT_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_lens_warp_packs_inherited_pipeline_speed_without_definition_drift(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                var globals := {
                    "displacement": {"type": "float", "uniform": "displacement", "default": 0.0625},
                    "antialias": {"type": "boolean", "uniform": "antialias", "default": true},
                }
                var layout: Dictionary = backend.call("_synth_layout", "filter", "lensWarp", globals)
                var speed_spec: Dictionary = layout.get("speed", {})
                var packed: PackedByteArray = backend.call(
                    "pack_with_layout", layout, globals, {"uniforms": {"speed": 7.0}}
                )
                var values := packed.to_float32_array()
                var slot := int(speed_spec.get("slot", -1))
                var offsets: Array = backend.call("_comp_offsets", str(speed_spec.get("components", "")))
                var speed_ok: bool = slot >= 0 and offsets.size() == 1 \
                    and values[slot * 4 + int(offsets[0])] == 7.0
                if speed_ok:
                    print("LENS_WARP_SPEED_TEST: PASS")
                    quit(0)
                else:
                    print("LENS_WARP_SPEED_TEST: layout=", layout, " values=", values)
                    quit(1)
        """
        result = self._run_godot_script(script)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("LENS_WARP_SPEED_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_orchestrator_texture_specs_extracts_gap004_and_gap005_keys(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var Orchestrator := load("res://addons/noisemaker/compiler/graph/orchestrator.gd")
                var orchestrator = Orchestrator.new(null)
                var texture_specs := {
                    "tex2d": {
                        "width": 128,
                        "height": 128,
                        "format": "rgba8",
                        "mipmaps": true,
                        "persistent": true
                    },
                    "tex3d": {
                        "width": 32,
                        "height": 32,
                        "depth": 32,
                        "is3D": true,
                        "filter": "linear"
                    }
                }
                var extracted: Dictionary = orchestrator.call("_extract_texture_specs", [], texture_specs)
                var t2 = extracted.get("tex2d", {})
                var t3 = extracted.get("tex3d", {})
                var ok: bool = t2.get("mipmaps") == true \
                    and t2.get("persistent") == true \
                    and t3.get("filter") == "linear" \
                    and t3.get("is3D") == true \
                    and t3.get("depth") == 32
                if ok:
                    print("TEXTURE_SPECS_GAP004_TEST: PASS")
                    quit(0)
                else:
                    print("TEXTURE_SPECS_GAP004_TEST: extracted=", extracted)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("TEXTURE_SPECS_GAP004_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_expander_propagates_sampler_types_and_clear(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var Expander := load("res://addons/noisemaker/compiler/graph/expander.gd")
                var EffectRegistry := load("res://addons/noisemaker/compiler/lang/effect_registry.gd")
                var reg = EffectRegistry.new()
                reg.call("_register_effect", {
                    "name": "mock",
                    "namespace": "mock",
                    "func": "synth",
                    "passes": [{
                        "program": "synth_prog",
                        "samplerTypes": {"noiseTex": "sampler3D"},
                        "clear": true,
                        "type": "render",
                        "inputs": {},
                        "outputs": {"color": "outputTex"}
                    }],
                    "globals": {}
                })
                var compilation_result := {
                    "plans": [{
                        "chain": [{
                            "op": "mock.synth",
                            "temp": 0,
                            "args": {}
                        }],
                        "write": "o0"
                    }],
                    "render": "o0"
                }
                var expander = Expander.new(reg)
                var expanded: Dictionary = expander.expand(compilation_result)
                var passes: Array = expanded.get("passes", [])
                var synth_pass = passes[0] if passes.size() > 0 else {}
                var ok: bool = synth_pass.get("samplerTypes", {}).get("noiseTex") == "sampler3D" \
                    and synth_pass.get("clear") == true \
                    and synth_pass.get("type") == "render"
                if ok:
                    print("EXPANDER_GAP005_TEST: PASS")
                    quit(0)
                else:
                    print("EXPANDER_GAP005_TEST: expanded=", expanded)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("EXPANDER_GAP005_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_texture_pooling_plan_groups_and_guards(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var Backend := load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = Backend.new()
                var plain := {"width": 64, "height": 64, "format": "rgba16f"}
                var textures := {
                    "a": plain.duplicate(), "b": plain.duplicate(),
                    "c": plain.duplicate(), "d": plain.duplicate(),
                    "e": plain.duplicate(), "f": plain.duplicate(),
                    "g": plain.duplicate(), "h": plain.duplicate(),
                    "i": plain.duplicate(), "i2": plain.duplicate(),
                    "j": plain.duplicate(), "j2": plain.duplicate(),
                    "k": plain.duplicate(), "k2": plain.duplicate(),
                    "l3": plain.duplicate(), "l3b": plain.duplicate(),
                    "m": plain.duplicate(), "m2": plain.duplicate(),
                    "n": plain.duplicate(),
                }
                textures["j"]["persistent"] = true
                textures["j2"]["persistent"] = true
                textures["k"]["mipmaps"] = true
                textures["k2"]["mipmaps"] = true
                textures["l3"]["is3D"] = true
                textures["l3b"]["is3D"] = true
                textures["m2"]["width"] = 128
                var allocations := {
                    "a": "phys_0", "b": "phys_0",
                    "c": "phys_1", "d": "phys_1",
                    "e": "phys_2", "f": "phys_2",
                    "g": "phys_3", "h": "phys_3",
                    "i": "phys_4", "i2": "phys_4",
                    "j": "phys_5", "j2": "phys_5",
                    "k": "phys_6", "k2": "phys_6",
                    "l3": "phys_7", "l3b": "phys_7",
                    "m": "phys_8", "m2": "phys_8",
                    "n": "phys_9",
                    "global_o1": "phys_10", "global_tmp": "phys_10",
                }
                var passes := [
                    # a: plain write-only, but its group-mate b is guarded below
                    # -> the whole physical group falls back standalone
                    {"outputs": {"color": "a"}, "program": "p1"},
                    # c/d: written by later passes (c's first touch is a write,
                    # pass 3 reads c after pass 2 wrote it) -> poolable; the
                    # analyzer only groups non-overlapping live ranges
                    {"inputs": {"src": "b"}, "outputs": {"color": "c"}, "program": "p1"},
                    {"inputs": {"src": "c"}, "outputs": {"color": "d"}, "program": "p1"},
                    {"outputs": {"color": "d"}, "program": "p2"},
                    # e: written by a drawMode (scatter) pass -> partially written
                    {"outputs": {"color": "e"}, "drawMode": "points", "program": "p1"},
                    # f: written by a viewport pass without clear -> partially written
                    {"outputs": {"color": "f"}, "viewport": {"width": 32}, "program": "p1"},
                    # g: written by a full-clear viewport pass -> stays poolable
                    {"outputs": {"color": "g"}, "viewport": {"width": 64}, "clear": true, "program": "p1"},
                    # h: plain write-only -> pools with a
                    {"outputs": {"color": "h"}, "program": "p1"},
                    # i pair: pooled
                    {"outputs": {"color": "i"}, "program": "p3"},
                    {"outputs": {"color": "i2"}, "program": "p3"},
                    # j pair: persistent policy -> excluded
                    {"outputs": {"color": "j"}, "program": "p4"},
                    {"outputs": {"color": "j2"}, "program": "p4"},
                    # k pair: mipmaps policy -> excluded
                    {"outputs": {"color": "k"}, "program": "p5"},
                    {"outputs": {"color": "k2"}, "program": "p5"},
                    # l3 pair: 3D -> excluded
                    {"outputs": {"color": "l3"}, "program": "p6"},
                    {"outputs": {"color": "l3b"}, "program": "p6"},
                    # m pair: signature mismatch -> excluded
                    {"outputs": {"color": "m"}, "program": "p7"},
                    {"outputs": {"color": "m2"}, "program": "p7"},
                ]
                var plan: Dictionary = backend.call("build_texture_pooling_plan", allocations, textures, passes)
                # Guarded members fall back to STANDALONE textures: they get no
                # alias at all (reference skips them from the physical group, and
                # a group that shrinks below 2 members is not pooled either).
                var ok: bool = \\
                    not plan.has("a") and not plan.has("b") \\
                    and plan.get("c", "") == "c" and plan.get("d", "") == "c" \\
                    and not plan.has("e") \\
                    and not plan.has("f") \\
                    and plan.get("g", "") == "g" and plan.get("h", "") == "g" \\
                    and plan.get("i", "") == "i" and plan.get("i2", "") == "i" \\
                    and not plan.has("j") and not plan.has("j2") \\
                    and not plan.has("k") and not plan.has("k2") \\
                    and not plan.has("l3") and not plan.has("l3b") \\
                    and not plan.has("m") and not plan.has("m2") \\
                    and not plan.has("n") \\
                    and not plan.has("global_o1") and not plan.has("global_tmp")
                if ok:
                    print("POOLING_PLAN_TEST: PASS")
                    quit(0)
                else:
                    print("POOLING_PLAN_TEST: plan=", plan)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("POOLING_PLAN_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_texture_pooling_disabled_by_default(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var Backend := load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = Backend.new()
                if backend.texture_pooling != false:
                    print("POOLING_DEFAULT_TEST: pooling=", backend.texture_pooling)
                    quit(1)
                    return
                backend.set_texture_pooling(true)
                if backend.texture_pooling != true:
                    print("POOLING_DEFAULT_TEST: setter failed")
                    quit(1)
                    return
                backend.set_texture_pooling(false)
                var plain := {"width": 64, "height": 64, "format": "rgba16f"}
                var allocations := {"a": "phys_0", "b": "phys_0"}
                var passes := [
                    {"outputs": {"color": "a"}, "program": "p1"},
                    {"outputs": {"color": "b"}, "program": "p1"},
                ]
                var plan: Dictionary = backend.call("build_texture_pooling_plan",
                    allocations, {"a": plain.duplicate(), "b": plain.duplicate()}, passes)
                var ok: bool = plan.get("a", "") == "a" and plan.get("b", "") == "a" \\
                    and backend.texture_pooling == false
                if ok:
                    print("POOLING_DEFAULT_TEST: PASS")
                    quit(0)
                else:
                    print("POOLING_DEFAULT_TEST: plan=", plan)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("POOLING_DEFAULT_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_texture_pooling_runtime_aliases_and_regroup_release(self):
        script = """
            extends SceneTree

            # Exercises the pooling runtime bookkeeping (allocate-skip + alias
            # application + regroup release) headless over the static seams with
            # a counting free callable; RIDs come from ImageTexture (valid and
            # unique headless). Double-frees of a shared storage RID are
            # observable in the free counts.
            func _init() -> void:
                var Backend := load("res://addons/noisemaker/runtime/nm_backend.gd")
                var BackendScript = Backend
                var live := []
                var frees := {}
                var free_rid := func(rid: RID) -> void:
                    var key = rid.get_id()
                    frees[key] = int(frees.get(key, 0)) + 1
                    live = live.filter(func(t): return t.get_rid() != rid)
                var make_tex := func() -> RID:
                    var tex := ImageTexture.new()
                    live.append(tex)
                    return tex.get_rid()
                var textures := {}
                var aliases := {"t1": "t1", "t2": "t1"}
                var storage: RID = make_tex.call()
                var stale: RID = make_tex.call()
                textures["t1"] = storage
                textures["t2"] = stale
                # 1. Alias application: t2's own texture is freed exactly once
                #    and both ids bind the shared storage.
                BackendScript.call("apply_texture_aliases", textures, aliases, free_rid)
                var ok: bool = textures["t1"] == storage and textures["t2"] == storage \\
                    and int(frees.get(stale.get_id(), 0)) == 1 \\
                    and int(frees.get(storage.get_id(), 0)) == 0
                # 2. Regroup release: the group dissolves (t2 -> its own id) so
                #    the shared storage RID is freed exactly once and both map
                #    entries are dropped.
                BackendScript.call("release_regrouped_textures", textures, aliases,
                    {"t1": "t1"}, free_rid)
                ok = ok and not textures.has("t1") and not textures.has("t2") \\
                    and int(frees.get(storage.get_id(), 0)) == 1
                # 3. Unchanged group survives: a matching next plan frees nothing
                #    and keeps the shared entries.
                textures["t1"] = storage
                textures["t2"] = storage
                BackendScript.call("release_regrouped_textures", textures, aliases,
                    aliases, free_rid)
                ok = ok and textures["t1"] == storage and textures["t2"] == storage \\
                    and int(frees.get(storage.get_id(), 0)) == 1
                # 4. No RID was ever freed more than once.
                var max_free := 0
                for key in frees:
                    max_free = max(max_free, int(frees[key]))
                ok = ok and max_free == 1
                if ok:
                    print("POOLING_RUNTIME_TEST: PASS")
                    quit(0)
                else:
                    print("POOLING_RUNTIME_TEST: frees=", frees, " textures=", textures)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("POOLING_RUNTIME_TEST: PASS", result.stdout, result.stdout + result.stderr)

    def test_shader_diagnostics_parse_and_normalize(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var Diag := load("res://addons/noisemaker/runtime/shader_diagnostics.gd")
                var diag = Diag.new()
                var log := "ERROR: 0:12: 'foo' : undeclared identifier\\nWARNING: 0:30: implicit cast\\nplain driver prose"
                var messages: Array = diag.call("parse_glsl_info_log", log)
                var ok: bool = messages.size() == 3 \\
                    and messages[0]["severity"] == "error" and messages[0]["line"] == 12 \\
                    and messages[0]["message"] == "'foo' : undeclared identifier" \\
                    and messages[1]["severity"] == "warning" and messages[1]["line"] == 30 \\
                    and messages[2]["severity"] == "info" and messages[2]["message"] == "plain driver prose" \\
                    and diag.call("parse_glsl_info_log", "").is_empty()
                var parsed: Dictionary = diag.call("parse_diagnostic_text",
                    "Shader bind error: binding index 7 not present in the bind group layout")
                ok = ok and parsed["stage"] == "bind" and parsed["bindingIndex"] == 7 \\
                    and diag.call("parse_diagnostic_text", "").get("bindingIndex", -1) == -1
                var made: Dictionary = diag.call("make", {
                    "code": "ERR_SHADER_COMPILE",
                    "backend": "renderingdevice",
                    "stage": "compile",
                    "program": "noise_prog",
                    "detail": log,
                    "messages": messages,
                    "source": "#version 450\\nbad",
                })
                ok = ok and made["code"] == "ERR_SHADER_COMPILE" \\
                    and made["backend"] == "renderingdevice" \\
                    and made["stage"] == "compile" \\
                    and made["detail"] == log \\
                    and made["messages"].size() == 3 \\
                    and made["program"] == "noise_prog" \\
                    and made["source"].begins_with("#version 450") \\
                    and diag.last_diagnostic["code"] == "ERR_SHADER_COMPILE"
                if ok:
                    print("SHADER_DIAGNOSTICS_TEST: PASS")
                    quit(0)
                else:
                    print("SHADER_DIAGNOSTICS_TEST: messages=", messages, " made=", made)
                    quit(1)
        """
        result = self._run_godot_script(script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SHADER_DIAGNOSTICS_TEST: PASS", result.stdout, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
