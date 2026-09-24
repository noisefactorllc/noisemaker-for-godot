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

    def test_diagnostic_locations_preserve_source_columns(self):
        source = """
            search synth
              read(123).write(o0)
              render(o0)
        """
        output = self._dump("_validate_dump.gd", {"diag.dsl": source})["diag.dsl"]
        self.assertTrue(output["ok"])
        diagnostics = output["out"]["diagnostics"]
        self.assertGreaterEqual(len(diagnostics), 2)
        read_diag = next(
            (d for d in diagnostics if "read() requires a valid surface reference" in d["message"]),
            None,
        )
        self.assertIsNotNone(read_diag)
        self.assertEqual(read_diag.get("location"), {"line": 3, "column": 3})

        write_diag = next(
            (d for d in diagnostics if "write() requires an input" in d["message"]),
            None,
        )
        self.assertIsNotNone(write_diag)
        self.assertEqual(write_diag.get("location"), {"line": 3, "column": 13})

        source_indented = """
            search synth


                    read(123).write(o0)
            render(o0)
        """
        output_indented = self._dump("_validate_dump.gd", {"indented.dsl": source_indented})["indented.dsl"]
        self.assertTrue(output_indented["ok"])
        indented_read_diag = next(
            (d for d in output_indented["out"]["diagnostics"] if "read() requires a valid surface reference" in d["message"]),
            None,
        )
        self.assertIsNotNone(indented_read_diag)
        self.assertEqual(indented_read_diag.get("location"), {"line": 5, "column": 9})

    def test_structured_lexer_diagnostics(self):
        cases = [
            {
                "name": "unexpected character after CRLF, tab, and UTF-16 text",
                "source": "// 😀\r\n\t@",
                "code": "L001",
                "stage": "lexer",
                "severity": "error",
                "message": "Unexpected character '@' at line 2 col 2",
                "location": {"line": 2, "column": 2},
                "span": {"start": 8, "end": 9},
            },
            {
                "name": "unterminated double-quoted string at EOF",
                "source": '"abc',
                "code": "L002",
                "stage": "lexer",
                "severity": "error",
                "message": "Unterminated string literal at line 1 col 1",
                "location": {"line": 1, "column": 1},
                "span": {"start": 0, "end": 4},
            },
            {
                "name": "unterminated single-quoted string at LF",
                "source": " 'abc\nnext",
                "code": "L002",
                "stage": "lexer",
                "severity": "error",
                "message": "Unterminated string literal at line 1 col 2",
                "location": {"line": 1, "column": 2},
                "span": {"start": 1, "end": 5},
            },
            {
                "name": "unterminated triple-quoted string across lines",
                "source": '\n  """a\nb',
                "code": "L002",
                "stage": "lexer",
                "severity": "error",
                "message": "Unterminated triple-quoted string at line 2 col 3",
                "location": {"line": 2, "column": 3},
                "span": {"start": 3, "end": 9},
            },
            {
                "name": "unterminated block comment across lines",
                "source": "\n /* a\nb",
                "code": "L003",
                "stage": "lexer",
                "severity": "error",
                "message": "Unterminated comment at line 2 col 2",
                "location": {"line": 2, "column": 2},
                "span": {"start": 2, "end": 8},
            },
            {
                "name": "out-of-range output reference",
                "source": "search synth\nrender(o99)",
                "code": "L004",
                "stage": "lexer",
                "severity": "error",
                "message": "Output surface reference 'o99' is out of range; expected o0-o7 at line 2 col 8",
                "location": {"line": 2, "column": 8},
                "span": {"start": 20, "end": 23},
            },
            {
                "name": "UTF-16 columns after a string",
                "source": '"😀" @',
                "code": "L001",
                "stage": "lexer",
                "severity": "error",
                "message": "Unexpected character '@' at line 1 col 6",
                "location": {"line": 1, "column": 6},
                "span": {"start": 5, "end": 6},
            },
            {
                "name": "source coordinates after a multiline function token",
                "source": "() => (1\n + 2), @",
                "code": "L001",
                "stage": "lexer",
                "severity": "error",
                "message": "Unexpected character '@' at line 1 col 17",
                "location": {"line": 2, "column": 8},
                "span": {"start": 16, "end": 17},
            },
            {
                "name": "source coordinates after an escaped LF in a string",
                "source": '"a\\\nb" @',
                "code": "L001",
                "stage": "lexer",
                "severity": "error",
                "message": "Unexpected character '@' at line 1 col 8",
                "location": {"line": 2, "column": 4},
                "span": {"start": 7, "end": 8},
            },
        ]
        programs = {f"case_{idx}.dsl": case["source"] for idx, case in enumerate(cases)}
        dumped = self._dump("_validate_dump.gd", programs)
        for idx, case in enumerate(cases):
            key = f"case_{idx}.dsl"
            res = dumped[key]
            self.assertFalse(res["ok"], f"Expected {case['name']} to fail validation")
            self.assertEqual(res["error"], case["message"])
            diag = res["diagnostic"]
            self.assertEqual(diag["code"], case["code"])
            self.assertEqual(diag["stage"], case["stage"])
            self.assertEqual(diag["severity"], case["severity"])
            self.assertEqual(diag["message"], case["message"])
            self.assertEqual(diag["location"], case["location"])
            self.assertEqual(diag["span"], case["span"])

    def test_structured_lexer_failures_leave_successful_tokens_unchanged(self):
        source = '/*x*/\nfoo.o99 "😀"'
        dumped = self._dump("_lex_dump.gd", {"tokens.dsl": source})["tokens.dsl"]
        expected = [
            {"type": "COMMENT", "lexeme": "/*x*/", "line": 1, "col": 1},
            {"type": "IDENT", "lexeme": "foo", "line": 2, "col": 1},
            {"type": "DOT", "lexeme": ".", "line": 2, "col": 4},
            {"type": "OUTPUT_REF", "lexeme": "o99", "line": 2, "col": 5},
            {"type": "STRING", "lexeme": "😀", "line": 2, "col": 9},
            {"type": "EOF", "lexeme": "", "line": 2, "col": 13},
        ]
        self.assertEqual(dumped, expected)

    def test_structured_parser_expectation_diagnostics(self):
        cases = [
            {
                "name": "opening parenthesis",
                "source": "search synth\nrender o0",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expect '(' at line 2 col 8",
                "location": {"line": 2, "column": 8},
                "span": None,
            },
            {
                "name": "closing parenthesis at EOF",
                "source": "search synth\nrender(o0",
                "code": "P002",
                "stage": "parser",
                "severity": "error",
                "message": "Expect ')' at line 2 col 10",
                "location": {"line": 2, "column": 10},
                "span": None,
            },
            {
                "name": "identifier",
                "source": "search synth\nlet = 1",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expected identifier at line 2 col 5",
                "location": {"line": 2, "column": 5},
                "span": None,
            },
            {
                "name": "assignment sign",
                "source": "search synth\nlet x 1",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expect '=' at line 2 col 7",
                "location": {"line": 2, "column": 7},
                "span": None,
            },
            {
                "name": "block opening",
                "source": "search synth\nif(true) return 1",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expect '{' at line 2 col 10",
                "location": {"line": 2, "column": 10},
                "span": None,
            },
            {
                "name": "end of input",
                "source": "search synth\nrender(o0) xyz",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expected end of input at line 2 col 12",
                "location": {"line": 2, "column": 12},
                "span": None,
            },
            {
                "name": "call closing parenthesis",
                "source": "search synth\nfoo(1",
                "code": "P002",
                "stage": "parser",
                "severity": "error",
                "message": "Expect ')' at line 2 col 6",
                "location": {"line": 2, "column": 6},
                "span": None,
            },
            {
                "name": "write3d separator",
                "source": "search synth\nfoo().write3d(tex3d0 geo0)",
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expect ',' between tex3d and geo in write3d() at line 2 col 22",
                "location": {"line": 2, "column": 22},
                "span": None,
            },
            {
                "name": "CRLF and tab",
                "source": "// 😀\r\nsearch synth\r\n\trender(o0",
                "code": "P002",
                "stage": "parser",
                "severity": "error",
                "message": "Expect ')' at line 3 col 11",
                "location": {"line": 3, "column": 11},
                "span": None,
            },
            {
                "name": "UTF-16 column",
                "source": 'search synth\nlet x = "😀"; render o0',
                "code": "P001",
                "stage": "parser",
                "severity": "error",
                "message": "Expect '(' at line 2 col 22",
                "location": {"line": 2, "column": 22},
                "span": None,
            },
        ]
        programs = {f"case_{idx}.dsl": case["source"] for idx, case in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, case in enumerate(cases):
                key = f"case_{idx}.dsl"
                res = dumped[key]
                self.assertFalse(res["ok"], f"Expected {case['name']} to fail in {dump_script}")
                self.assertEqual(res["error"], case["message"])
                diag = res["diagnostic"]
                self.assertEqual(diag["code"], case["code"])
                self.assertEqual(diag["stage"], case["stage"])
                self.assertEqual(diag["severity"], case["severity"])
                self.assertEqual(diag["message"], case["message"])
                self.assertEqual(diag["location"], case["location"])
                self.assertEqual(diag["span"], case["span"])

    def test_structured_parser_automation_diagnostics(self):
        cases = [
            ("osc(type: oscKind.sine, bogus: 1)", "osc() unknown parameter 'bogus'", ". Valid: type, min, max, speed, offset, seed"),
            ("midi(1, 2, 3, 4, 5, 6)", "midi() name, id, cc, nrpn, zone and members are keyword-only", ""),
            ("midi(bogus: 1)", "midi() unknown parameter 'bogus'", ". Valid: channel, mode, min, max, sensitivity, name, id, cc, nrpn, zone, members"),
            ("midi(1, 2, 3, 4, 5, channel: 1)", "midi() has an excess positional argument", ""),
            ("midi()", "midi() requires 'channel' or 'zone' argument", ""),
            ("midi(1, zone: 1)", "midi() 'channel' and 'zone' are mutually exclusive", ""),
            ("midi(1, members: 2)", "midi() 'members' requires 'zone'", ""),
            ("midi(1, id: \"port\")", "midi() 'id' requires readable 'name'", ""),
            ("midi(1, name: 1)", "midi() 'name' requires a quoted string", ""),
            ("midi(1, name: \"\")", "midi() 'name' must not be empty", ""),
            ("midi(1, name: \"port\", id: 1)", "midi() 'id' requires a quoted string", ""),
            ("midi(1, name: \"port\", id: \"\")", "midi() 'id' must not be empty", ""),
            ("audio(1, 2, 3, 4)", "audio() channel, name and id are keyword-only", ""),
            ("audio(bogus: 1)", "audio() unknown parameter 'bogus'", ". Valid: band, min, max, channel, name, id"),
            ("audio(1, 2, 3, band: 1)", "audio() has an excess positional argument", ""),
            ("audio()", "audio() requires 'band' argument", ""),
            ("audio(1, id: \"device\")", "audio() 'id' requires readable 'name'", ""),
            ("audio(1, name: \"device\")", "audio() selected device requires both 'name' and 'channel'", ""),
            ("audio(1, channel: 1, name: 1)", "audio() 'name' requires a quoted string", ""),
            ("audio(1, channel: 1, name: \"\")", "audio() 'name' must not be empty", ""),
            ("audio(1, channel: 1, name: \"device\", id: 1)", "audio() 'id' requires a quoted string", ""),
            ("audio(1, channel: 1, name: \"device\", id: \"\")", "audio() 'id' must not be empty", ""),
        ]
        programs = {}
        expected_meta = []
        for idx, (inv, prefix, suffix) in enumerate(cases):
            key = f"auto_{idx}.dsl"
            programs[key] = f"search synth\nlet x = {inv}"
            msg = f"{prefix} at line 2 col 9{suffix}"
            expected_meta.append((msg, {"line": 2, "column": 9}))

        key_crlf = "auto_crlf.dsl"
        programs[key_crlf] = 'search synth\r\n\tlet x = "😀"; let y = midi()'
        expected_meta.append(("midi() requires 'channel' or 'zone' argument at line 2 col 24", {"line": 2, "column": 24}))

        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx in range(len(cases)):
                key = f"auto_{idx}.dsl"
                exp_msg, exp_loc = expected_meta[idx]
                res = dumped[key]
                self.assertFalse(res["ok"], f"Expected {cases[idx][0]} to fail in {dump_script}")
                self.assertEqual(res["error"], exp_msg)
                diag = res["diagnostic"]
                self.assertEqual(diag["code"], "P003")
                self.assertEqual(diag["stage"], "parser")
                self.assertEqual(diag["severity"], "error")
                self.assertEqual(diag["message"], exp_msg)
                self.assertEqual(diag["location"], exp_loc)
                self.assertEqual(diag["span"], None)
            res_crlf = dumped[key_crlf]
            self.assertFalse(res_crlf["ok"])
            exp_msg_crlf, exp_loc_crlf = expected_meta[-1]
            self.assertEqual(res_crlf["error"], exp_msg_crlf)
            self.assertEqual(res_crlf["diagnostic"]["code"], "P003")
            self.assertEqual(res_crlf["diagnostic"]["location"], exp_loc_crlf)

    def test_structured_parser_search_diagnostics(self):
        missing_msg = "Missing required 'search' directive. Every program must start with 'search <namespace>, ...' to specify namespace search order."
        cases = [
            ("empty program", "", missing_msg, 1, 1),
            ("missing directive after statements", "let x = 1", missing_msg, 1, 10),
            ("duplicate directive", "search synth search filter", "Only one search directive is allowed per program at line 1 col 14", 1, 14),
            ("invalid namespace", "search bogus", "Invalid namespace 'bogus' at line 1 col 8. Valid namespaces: io, classicNoisedeck, synth, mixer, filter, render, points, synth3d, filter3d, user", 1, 8),
            ("missing first namespace", "search", "Expected namespace identifier after search at line 1 col 7", 1, 7),
            ("missing additional namespace", "search synth,", "Expected namespace identifier after comma at line 1 col 14", 1, 14),
            ("misplaced directive", "let x = 1; search synth", "'search' directive must appear before other statements at line 1 col 12", 1, 12),
            ("nested directive", "search synth\nif(true) { search filter }", "'search' directive is only allowed at the start of the program at line 2 col 12", 2, 12),
            ("CRLF and tab", "// 😀\r\n\tsearch 1", "Expected namespace identifier after search at line 2 col 9", 2, 9),
            ("UTF-16 column", 'search synth\nlet x = "😀"; search filter', "'search' directive must appear before other statements at line 2 col 15", 2, 15),
        ]
        programs = {f"search_{idx}.dsl": src for idx, (_, src, _, _, _) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (name, _, msg, line, col) in enumerate(cases):
                key = f"search_{idx}.dsl"
                res = dumped[key]
                self.assertFalse(res["ok"], f"Expected {name} to fail in {dump_script}")
                self.assertEqual(res["error"], msg)
                diag = res["diagnostic"]
                self.assertEqual(diag["code"], "P004")
                self.assertEqual(diag["stage"], "parser")
                self.assertEqual(diag["severity"], "error")
                self.assertEqual(diag["message"], msg)
                self.assertEqual(diag["location"], {"line": line, "column": col})
                self.assertEqual(diag["span"], None)

    def test_structured_parser_output_diagnostics(self):
        cases = [
            ("invalid render target", "search synth\nrender(1)", "Expected output reference in render()", 2, 8),
            ("render target at EOF", "search synth\nrender(", "Expected output reference in render()", 2, 8),
            ("write in expression", "search synth\nlet x = noise().write(o0)", "'.write()' is only allowed in statement context at line 2 col 17", 2, 17),
            ("write3d in expression", "search synth\nlet x = noise().write3d(vol0, geo0)", "'.write()' is only allowed in statement context at line 2 col 17", 2, 17),
            ("missing write surface", "search synth\nnoise().write()", "write() requires an explicit surface reference (e.g., o0, o1, xyz0, vel0, rgba0, mesh0, none) at line 2 col 15", 2, 15),
            ("write surface at EOF", "search synth\nnoise().write(", "write() requires an explicit surface reference (e.g., o0, o1, xyz0, vel0, rgba0, mesh0, none) at line 2 col 15", 2, 15),
            ("invalid write surface", "search synth\nnoise().write(1)", "write() requires an explicit surface reference (e.g., o0, o1, xyz0, vel0, rgba0, mesh0, none) at line 2 col 15", 2, 15),
            ("invalid write3d texture", "search synth\nnoise().write3d(1, geo0)", "Expected tex3d reference in write3d() at line 2 col 17", 2, 17),
            ("write3d texture at EOF", "search synth\nnoise().write3d(", "Expected tex3d reference in write3d() at line 2 col 17", 2, 17),
            ("invalid write3d geometry", "search synth\nnoise().write3d(vol0, 1)", "Expected geo reference in write3d() at line 2 col 23", 2, 23),
            ("write3d geometry at EOF", "search synth\nnoise().write3d(vol0,", "Expected geo reference in write3d() at line 2 col 22", 2, 22),
            ("CRLF and tab render target", "// 😀\r\nsearch synth\r\n\trender(\"😀\")", "Expected output reference in render()", 3, 9),
            ("UTF-16 render target column", 'search synth\nlet x = "😀"; render(none)', "Expected output reference in render()", 2, 22),
        ]
        programs = {f"output_{idx}.dsl": src for idx, (_, src, _, _, _) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (name, _, msg, line, col) in enumerate(cases):
                key = f"output_{idx}.dsl"
                res = dumped[key]
                self.assertFalse(res["ok"], f"Expected {name} to fail in {dump_script}")
                self.assertEqual(res["error"], msg)
                diag = res["diagnostic"]
                self.assertEqual(diag["code"], "P005")
                self.assertEqual(diag["stage"], "parser")
                self.assertEqual(diag["severity"], "error")
                self.assertEqual(diag["message"], msg)
                self.assertEqual(diag["location"], {"line": line, "column": col})
                self.assertEqual(diag["span"], None)

    def test_output_expectation_precedence(self):
        cases = [
            ("search synth\nrender o0", "P001", "Expect '(' at line 2 col 8"),
            ("search synth\nrender(o0", "P002", "Expect ')' at line 2 col 10"),
            ("search synth\nnoise().write(o0", "P002", "Expect ')' at line 2 col 17"),
            ("search synth\nnoise().write3d(vol0 geo0)", "P001", "Expect ',' between tex3d and geo in write3d() at line 2 col 22"),
        ]
        programs = {f"prec_{idx}.dsl": src for idx, (src, _, _) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (_, code, msg) in enumerate(cases):
                res = dumped[f"prec_{idx}.dsl"]
                self.assertFalse(res["ok"])
                self.assertEqual(res["error"], msg)
                self.assertEqual(res["diagnostic"]["code"], code)

    def test_subchain_diagnostics_p006(self):
        cases = [
            ("non-string subchain name kwarg", "search synth\nnoise().subchain(name: 123) { .noise() }.write(o0)", "Expected string value for subchain name at line 2 col 24", 2, 24),
            ("non-string subchain id kwarg", "search synth\nnoise().subchain(id: 456) { .noise() }.write(o0)", "Expected string value for subchain id at line 2 col 22", 2, 22),
            ("subchain arg value at EOF", "search synth\nnoise().subchain(name: ", "Expected string value for subchain name at line 2 col 24", 2, 24),
            ("missing dot before subchain element", 'search synth\nnoise().subchain("test") { noise() }.write(o0)', "Expected '.' before chain element in subchain body at line 2 col 28", 2, 28),
            ("empty subchain body", 'search synth\nnoise().subchain("test") {}.write(o0)', "Subchain body cannot be empty at line 2 col 9", 2, 9),
            ("comment-only subchain body", 'search synth\nnoise().subchain("test") {\n  /* empty */\n}.write(o0)', "Subchain body cannot be empty at line 2 col 9", 2, 9),
            ("CRLF and tab subchain kwarg", "// 😀\r\nsearch synth\r\n\tnoise().subchain(name: 123) { .noise() }.write(o0)", "Expected string value for subchain name at line 3 col 25", 3, 25),
            ("UTF-16 subchain missing dot column", 'search synth\nlet x = "😀"; noise().subchain("test") { noise() }.write(o0)', "Expected '.' before chain element in subchain body at line 2 col 42", 2, 42),
        ]
        programs = {f"subchain_{idx}.dsl": src for idx, (_, src, _, _, _) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (name, _, msg, line, col) in enumerate(cases):
                key = f"subchain_{idx}.dsl"
                res = dumped[key]
                self.assertFalse(res["ok"], f"Expected {name} to fail in {dump_script}")
                self.assertEqual(res["error"], msg)
                diag = res["diagnostic"]
                self.assertEqual(diag["code"], "P006")
                self.assertEqual(diag["stage"], "parser")
                self.assertEqual(diag["severity"], "error")
                self.assertEqual(diag["message"], msg)
                self.assertEqual(diag["location"], {"line": line, "column": col})
                self.assertEqual(diag["span"], None)

    def test_subchain_expectation_precedence(self):
        cases = [
            ("missing lparen after subchain", 'search synth\nnoise().subchain "test" { .noise() }.write(o0)', "P001", "Expect '(' after subchain at line 2 col 18"),
            ("non-string positional subchain arg", "search synth\nnoise().subchain(1) {}", "P002", "Expect ')' after subchain arguments at line 2 col 18"),
            ("missing lbrace for subchain body", 'search synth\nnoise().subchain("test") .noise().write(o0)', "P001", "Expect '{' to start subchain body at line 2 col 26"),
            ("trailing dot in subchain body", 'search synth\nnoise().subchain("test") { . }', "P001", "Expected identifier at line 2 col 30"),
        ]
        programs = {f"subchain_prec_{idx}.dsl": src for idx, (_, src, _, _) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (name, _, code, msg) in enumerate(cases):
                res = dumped[f"subchain_prec_{idx}.dsl"]
                self.assertFalse(res["ok"], f"Expected {name} to fail in {dump_script}")
                self.assertEqual(res["error"], msg)
                self.assertEqual(res["diagnostic"]["code"], code)

    def test_valid_subchains_compile(self):
        cases = [
            ("empty args", "search synth\nnoise().subchain() { .noise() }.write(o0)\nrender(o0)"),
            ("positional name", 'search synth\nnoise().subchain("loop") { .noise() }.write(o0)\nrender(o0)'),
            ("keyword args", 'search synth\nnoise().subchain(name: "loop", id: "sc1") { .noise() }.write(o0)\nrender(o0)'),
        ]
        programs = {f"valid_subchain_{idx}.dsl": src for idx, (_, src) in enumerate(cases)}
        for dump_script in ("_parse_dump.gd", "_validate_dump.gd"):
            dumped = self._dump(dump_script, programs)
            for idx, (name, _) in enumerate(cases):
                res = dumped[f"valid_subchain_{idx}.dsl"]
                self.assertTrue(res["ok"], f"Expected {name} to succeed in {dump_script}: {res.get('error')}")


if __name__ == "__main__":
    unittest.main()


