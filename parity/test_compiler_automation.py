#!/usr/bin/env python3
"""GPU-free regression tests for MIDI/audio compiler descriptors."""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class CompilerAutomationTests(unittest.TestCase):
    def _dump(self, script_name, programs):
        with tempfile.TemporaryDirectory(prefix="nm-godot-automation-") as tmp:
            paths = []
            for name, source in programs.items():
                path = Path(tmp) / name
                path.write_text(textwrap.dedent(source))
                paths.append(path)
            result = subprocess.run(
                [
                    str(GODOT),
                    "--headless",
                    "--path",
                    str(REPO / "godot"),
                    "--script",
                    f"res://addons/noisemaker/compiler/{script_name}",
                    "--",
                    *(str(path) for path in paths),
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            markers = {
                "_lex_dump.gd": "LEXDUMP:",
                "_parse_dump.gd": "PARSEDUMP:",
                "_graph_dump.gd": "GRAPHDUMP:",
                "_validate_dump.gd": "VALIDATEDUMP:",
            }
            if script_name not in markers:
                raise ValueError(f"Unknown dump script: {script_name}")
            marker = markers[script_name]
            marker_line = next(
                (line for line in result.stdout.splitlines() if line.startswith(marker)),
                None,
            )
            self.assertIsNotNone(marker_line, result.stdout + result.stderr)
            payload = json.loads(marker_line[len(marker) :])
            return {Path(path).name: payload[str(path)] for path in paths}

    def test_selected_descriptors_survive_validation(self):
        source = r'''
            search synth
            noise(
                scaleX: midi(mode: 0, 2, 0.1, 0.9, 3, name: "Launchkey\\Main", id: "midi-1"),
                scaleY: audio(max: 0.9, audioBand.raw, 0.1, channel: 2, name: 'Interface "A"', id: "audio-1")
            ).write(o0)
            render(o0)
        '''
        output = self._dump("_validate_dump.gd", {"selected.dsl": source})["selected.dsl"]

        self.assertTrue(output["ok"])
        self.assertEqual(output["out"]["diagnostics"], [])
        args = output["out"]["plans"][0]["chain"][0]["args"]
        midi = args["scaleX"]
        audio = args["scaleY"]

        self.assertEqual(
            {key: midi[key] for key in ("type", "channel", "mode", "min", "max", "sensitivity", "name", "id")},
            {
                "type": "Midi",
                "channel": 2,
                "mode": 0,
                "min": 0.1,
                "max": 0.9,
                "sensitivity": 3,
                "name": r"Launchkey\Main",
                "id": "midi-1",
            },
        )
        self.assertEqual(
            {key: audio[key] for key in ("type", "band", "min", "max", "channel", "name", "id", "_invalid")},
            {
                "type": "Audio",
                "band": 4,
                "min": 0.1,
                "max": 0.9,
                "channel": 2,
                "name": 'Interface "A"',
                "id": "audio-1",
                "_invalid": False,
            },
        )

    def test_expression_modes_and_default_audio_channels(self):
        expressions = {
            **{f"mode-{mode}.dsl": f"midi(zone: selected, members: count, mode: midiMode.{mode}" +
               (", nrpn: parameter" if mode == "nrpn" else "") + ")"
               for mode in ("cc", "cc14", "nrpn", "pitchBend", "pressure", "polyPressure")},
            "default-audio.dsl": "audio(band: audioBand.raw, channel: 32)",
        }
        programs = {name: "search synth\nlet selected = midiZone.upper\nlet count = 7\nlet parameter = 1234\n"
                    f"noise(scaleX: {expression}).write(o0)\nrender(o0)"
                    for name, expression in expressions.items()}
        outputs = self._dump("_validate_dump.gd", programs)
        for mode, number in (("cc", 5), ("cc14", 6), ("nrpn", 7), ("pitchBend", 8), ("pressure", 9), ("polyPressure", 10)):
            output = outputs[f"mode-{mode}.dsl"]
            self.assertTrue(output["ok"], output)
            self.assertEqual([], output["out"]["diagnostics"])
            value = output["out"]["plans"][0]["chain"][0]["args"]["scaleX"]
            self.assertEqual(number, value["mode"])
            self.assertEqual(1, value["zone"])
            self.assertEqual(7, value["members"])
            self.assertNotIn("channel", value)
            if mode == "nrpn": self.assertEqual(1234, value["nrpn"])
            if mode in ("cc", "cc14"): self.assertEqual(1, value["cc"])
        output = outputs["default-audio.dsl"]
        self.assertTrue(output["ok"], output)
        self.assertEqual([], output["out"]["diagnostics"])
        value = output["out"]["plans"][0]["chain"][0]["args"]["scaleX"]
        self.assertEqual(32, value["channel"])
        self.assertNotIn("name", value)

    def test_invalid_expression_selectors_fail_closed(self):
        expressions = ["midi(channel: 0, mode: 5)", "midi(channel: true, mode: 8)",
                       "midi(channel: 2, mode: 6, cc: 32)", "midi(channel: 2, mode: 7)",
                       "midi(channel: 2, mode: 7, nrpn: 16383)", "midi(zone: 2)",
                       "midi(zone: 0, members: 16)", "audio(band: audioBand.raw, channel: 33)"]
        programs = {f"invalid-{index}.dsl": f"search synth\nnoise(scaleX: {expr}).write(o0)\nrender(o0)"
                    for index, expr in enumerate(expressions)}
        for name, output in self._dump("_validate_dump.gd", programs).items():
            self.assertTrue(output["ok"], name)
            self.assertTrue(output["out"]["diagnostics"], name)
            self.assertTrue(output["out"]["plans"][0]["chain"][0]["args"]["scaleX"]["_invalid"], name)

    def test_invalid_selector_forms_are_rejected(self):
        expressions = {
            "midi_id_without_name.dsl": 'midi(1, id: "midi-1")',
            "midi_unquoted_name.dsl": "midi(1, name: controller)",
            "audio_unpaired_selector.dsl": 'audio(audioBand.raw, name: "Input")',
            "midi_duplicate_selector.dsl": "midi(channel: 2, zone: 0)",
            "midi_unpaired_members.dsl": "midi(channel: 2, members: 5)",
            "audio_selector_positional.dsl": "audio(audioBand.raw, 0, 1, 2)",
            "unknown_selector.dsl": 'midi(1, port: "Launchkey")',
        }
        programs = {
            name: f"search synth\nnoise(scaleX: {expression}).write(o0)\nrender(o0)\n"
            for name, expression in expressions.items()
        }
        outputs = self._dump("_parse_dump.gd", programs)

        self.assertEqual(set(outputs), set(expressions))
        self.assertTrue(all(not output["ok"] for output in outputs.values()))

    def test_invalid_audio_diagnostics_match_javascript_value_formatting(self):
        cases = {
            "band_member.dsl": (
                "audio(band: audioBand.bogus)",
                "audio() band must resolve to an integer from 0 to 4 (got undefined): 'audioBand.bogus'",
                "audioBand.bogus",
                "band",
            ),
            "band_boolean.dsl": (
                "audio(band: true)",
                "audio() band must resolve to an integer from 0 to 4 (got undefined): 'true'",
                "true",
                "band",
            ),
            "band_negative.dsl": (
                "audio(band: -1)",
                "audio() band must resolve to an integer from 0 to 4 (got -1)",
                "-1",
                "band",
            ),
            "band_integer.dsl": (
                "audio(band: 5)",
                "audio() band must resolve to an integer from 0 to 4 (got 5)",
                "5",
                "band",
            ),
            "band_fraction.dsl": (
                "audio(band: 1.5)",
                "audio() band must resolve to an integer from 0 to 4 (got 1.5)",
                "1.5",
                "band",
            ),
            "channel_zero.dsl": (
                'audio(band: audioBand.raw, channel: 0, name: "Interface")',
                "audio() channel must be a positive integer from 1 to 32 (got 0): '[Number]'",
                "[Number]",
                "channel",
            ),
            "channel_negative.dsl": (
                'audio(band: audioBand.raw, channel: -1, name: "Interface")',
                "audio() channel must be a positive integer from 1 to 32 (got -1)",
                "-1",
                "channel",
            ),
            "channel_fraction.dsl": (
                'audio(band: audioBand.raw, channel: 1.5, name: "Interface")',
                "audio() channel must be a positive integer from 1 to 32 (got 1.5)",
                "1.5",
                "channel",
            ),
        }
        programs = {
            name: f"search synth\nnoise(scaleX: {case[0]}).write(o0)\nrender(o0)\n"
            for name, case in cases.items()
        }
        outputs = self._dump("_validate_dump.gd", programs)

        for name, (_, message, identifier, invalid_field) in cases.items():
            output = outputs[name]
            self.assertTrue(output["ok"], name)
            self.assertEqual(len(output["out"]["diagnostics"]), 1, name)
            diagnostic = output["out"]["diagnostics"][0]
            self.assertEqual(diagnostic["message"], message, name)
            self.assertEqual(diagnostic["identifier"], identifier, name)
            config = output["out"]["plans"][0]["chain"][0]["args"]["scaleX"]
            self.assertTrue(config["_invalid"], name)
            self.assertNotIn(invalid_field, config, name)

    def test_nested_automation_sources_survive_validation(self):
        source = """
            search synth
            let rate = audio(band: audioBand.raw, min: 0.25, max: 0.75)
            let carrier = osc(type: oscKind.saw, min: rate, speed: rate)
            noise(scaleX: carrier).write(o0)
            render(o0)
        """
        output = self._dump("_validate_dump.gd", {"nested.dsl": source})["nested.dsl"]

        self.assertTrue(output["ok"])
        self.assertEqual(output["out"]["diagnostics"], [])
        carrier = output["out"]["plans"][0]["chain"][0]["args"]["scaleX"]
        self.assertEqual(carrier["type"], "Oscillator")
        self.assertEqual(carrier["oscType"], 2)
        for field in ("min", "speed"):
            self.assertEqual(carrier[field]["type"], "Audio")
            self.assertEqual(carrier[field]["_varRef"], "rate")

    def test_automation_cycles_and_excess_depth_are_reported(self):
        programs = {
            "cycle.dsl": """
                search synth
                let first = osc(type: oscKind.sine, speed: second)
                let second = osc(type: oscKind.tri, speed: first)
                noise(scaleX: first).write(o0)
                render(o0)
            """,
            "depth.dsl": """
                search synth
                let rate9 = osc(type: oscKind.sine)
                let rate8 = osc(type: oscKind.sine, speed: rate9)
                let rate7 = osc(type: oscKind.sine, speed: rate8)
                let rate6 = osc(type: oscKind.sine, speed: rate7)
                let rate5 = osc(type: oscKind.sine, speed: rate6)
                let rate4 = osc(type: oscKind.sine, speed: rate5)
                let rate3 = osc(type: oscKind.sine, speed: rate4)
                let rate2 = osc(type: oscKind.sine, speed: rate3)
                let rate1 = osc(type: oscKind.sine, speed: rate2)
                let carrier = osc(type: oscKind.saw, speed: rate1)
                noise(scaleX: carrier).write(o0)
                render(o0)
            """,
        }
        outputs = self._dump("_validate_dump.gd", programs)

        cycle_messages = [item["message"] for item in outputs["cycle.dsl"]["out"]["diagnostics"]]
        depth_messages = [item["message"] for item in outputs["depth.dsl"]["out"]["diagnostics"]]
        self.assertTrue(any("cycle" in message.lower() for message in cycle_messages), cycle_messages)
        self.assertTrue(any("maximum depth of 8" in message for message in depth_messages), depth_messages)

    def test_chained_variable_compiles_to_terminal_write_blit(self):
        programs = {
            "chained.dsl": """
                search synth, filter
                let gen = noise(scaleX: 50)
                let eff = rotate(1, 0.1)
                gen().eff().write(o0)
                render(o0)
            """
        }
        output = self._dump("_graph_dump.gd", programs)["chained.dsl"]
        self.assertTrue(output["ok"])
        graph = output["out"]
        self.assertEqual(graph.get("renderSurface"), "o0")
        self.assertEqual(len(graph.get("passes", [])), 3)
        pass_ids = [p["id"] for p in graph["passes"]]
        self.assertEqual(pass_ids, ["node_0_pass_0", "node_1_pass_0", "node_2_write_blit"])
        write_pass = graph["passes"][2]
        self.assertEqual(write_pass.get("program"), "blit")
        self.assertEqual(write_pass.get("outputs", {}).get("color"), "global_o0")
        self.assertEqual(write_pass.get("inputs", {}).get("src"), "node_1_out")

    def test_legacy_midi_note_mode_channels_must_be_static_integers(self):
        modes = [
            ("noteChange", "midiMode.noteChange"),
            ("gateNote", "midiMode.gateNote"),
            ("gateVelocity", "midiMode.gateVelocity"),
            ("triggerNote", "midiMode.triggerNote"),
            ("velocity", "midiMode.velocity"),
        ]
        programs = {}
        for name, mode_expr in modes:
            programs[f"{name}_valid_1.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: 1)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_valid_16.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: 16)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_0.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: 0)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_17.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: 17)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_float.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: 1.5)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_bool.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: true)
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_string.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: "1")
                noise(scaleX: m).write(o0)
                render(o0)
            """
            programs[f"{name}_invalid_osc.dsl"] = f"""
                search synth
                let m = midi(mode: {mode_expr}, channel: osc())
                noise(scaleX: m).write(o0)
                render(o0)
            """
        outputs = self._dump("_validate_dump.gd", programs)
        for name, _ in modes:
            self.assertTrue(outputs[f"{name}_valid_1.dsl"]["ok"])
            self.assertEqual(outputs[f"{name}_valid_1.dsl"]["out"]["diagnostics"], [])
            self.assertTrue(outputs[f"{name}_valid_16.dsl"]["ok"])
            self.assertEqual(outputs[f"{name}_valid_16.dsl"]["out"]["diagnostics"], [])

            for bad_case in ("0", "17", "float", "bool", "string", "osc"):
                file_key = f"{name}_invalid_{bad_case}.dsl"
                diags = outputs[file_key]["out"]["diagnostics"]
                self.assertTrue(len(diags) > 0, f"Expected diagnostics for {file_key}")
                self.assertTrue(
                    any("channel" in d["message"].lower() for d in diags),
                    f"Expected channel error in {diags}",
                )
                desc = outputs[file_key]["out"]["plans"][0]["chain"][0]["args"]["scaleX"]
                self.assertTrue(desc.get("_invalid", False), f"Expected _invalid: true for {file_key}")

    def test_output_surface_range_enforcement(self):
        invalid_programs = {
            "render_o8.dsl": "search synth\nnoise().write(o0)\nrender(o8)",
            "read_o99.dsl": "search synth\nread(o99).write(o0)\nrender(o0)",
            "write_o10.dsl": "search synth\nnoise().write(o10)\nrender(o0)",
        }
        invalid_outputs = self._dump("_lex_dump.gd", invalid_programs)
        for key in invalid_programs:
            tokens = invalid_outputs[key]
            self.assertFalse(
                any(t["type"] == "EOF" for t in tokens),
                f"Expected lexer error (no EOF token) for {key}",
            )

        valid_programs = {
            "boundary.dsl": "search synth\nread(o0).write(o7)\nrender(o7)",
            "member_and_refs.dsl": """
                search synth
                let low = foo.o0
                let high = foo.o7
                let extended = foo.o8
                let many = foo.o99
                let source = s99
                let vol = vol99
                let geo = geo99
                let xyz = xyz99
                let vel = vel99
                let rgba = rgba99
                let mesh = mesh99
            """,
        }
        valid_outputs = self._dump("_lex_dump.gd", valid_programs)
        boundary_tokens = valid_outputs["boundary.dsl"]
        self.assertTrue(any(t["type"] == "EOF" for t in boundary_tokens))
        output_refs = [t["lexeme"] for t in boundary_tokens if t["type"] == "OUTPUT_REF"]
        self.assertEqual(output_refs, ["o0", "o7", "o7"])

        member_tokens = valid_outputs["member_and_refs.dsl"]
        self.assertTrue(any(t["type"] == "EOF" for t in member_tokens))
        member_output_refs = [t["lexeme"] for t in member_tokens if t["type"] == "OUTPUT_REF"]
        self.assertEqual(member_output_refs, ["o0", "o7", "o8", "o99"])
        self.assertTrue(any(t["type"] == "SOURCE_REF" and t["lexeme"] == "s99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "VOL_REF" and t["lexeme"] == "vol99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "GEO_REF" and t["lexeme"] == "geo99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "XYZ_REF" and t["lexeme"] == "xyz99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "VEL_REF" and t["lexeme"] == "vel99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "RGBA_REF" and t["lexeme"] == "rgba99" for t in member_tokens))
        self.assertTrue(any(t["type"] == "MESH_REF" and t["lexeme"] == "mesh99" for t in member_tokens))


if __name__ == "__main__":
    unittest.main()


