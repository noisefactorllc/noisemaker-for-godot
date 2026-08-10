#!/usr/bin/env python3
"""Live GPU smoke coverage for the formerly missing Godot effect cohort."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
RENDERER = "res://addons/noisemaker/tools/render_graph.gd"
CONTENT_PROBE = REPO / "parity" / "image_content_probe.gd"
SEARCH = "search synth, filter, render, points, mixer, classicNoisedeck, synth3d, filter3d\n\n"
PROGRAMS = {
    "kaleido": "noise().kaleido().write(o0)",
    "shapes3d": "shapes3d().write(o0)",
    "grade": "noise().grade().write(o0)",
    "lensWarp": "noise().lensWarp().write(o0)",
    "pixelSort": "noise().pixelSort().write(o0)",
    "wormhole": "noise().wormhole().write(o0)",
    "attractor": "noise().pointsEmit(stateSize: x64).attractor().pointsRender(density: 100).write(o0)",
    "buddhabrot": "noise().pointsEmit(stateSize: x64).buddhabrot().pointsRender(density: 100).write(o0)",
    "dla": "noise().pointsEmit(stateSize: x64).dla().pointsRender(density: 100).write(o0)",
    "flock": "noise().pointsEmit(stateSize: x64).flock().pointsRender(density: 100).write(o0)",
    "hydraulic": "noise().pointsEmit(stateSize: x64).hydraulic().pointsRender(density: 100).write(o0)",
    "lenia": "noise().pointsEmit(stateSize: x64).lenia().pointsRender(density: 100).write(o0)",
    "life": "noise().pointsEmit(stateSize: x64).life().pointsRender(density: 100).write(o0)",
    "physarum": "noise().pointsEmit(stateSize: x64).physarum().pointsRender(density: 100).write(o0)",
    "physical": "noise().pointsEmit(stateSize: x64).physical().pointsRender(density: 100).write(o0)",
    "loop": "noise().loopBegin().blur().loopEnd().write(o0)",
    "mesh": "meshLoader().meshRender().write(o0)",
    "renderCubemap3d": "noise3d(volumeSize: x16).renderCubemap3d().write(o0)",
    "renderCubemapSurface": "noise3d(volumeSize: x16).renderCubemapSurface().write(o0)",
    "renderLit3d": "noise3d(volumeSize: x16).renderLit3d().write(o0)",
    "media": "media().write(o0)",
    "remap": "remap().write(o0)",
    "roll": "roll().write(o0)",
    "scope": "scope().write(o0)",
    "spectrum": "spectrum().write(o0)",
}


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class MissingEffectsLiveTests(unittest.TestCase):
    def test_formerly_missing_effects_render_without_runtime_errors(self):
        with tempfile.TemporaryDirectory(prefix="nm-missing-effects-") as tmp:
            root = Path(tmp)
            entries = []
            for name, body in PROGRAMS.items():
                search = "search synth3d, render\n\n" if name.startswith("renderCube") or name == "renderLit3d" else SEARCH
                dsl = root / f"{name}.dsl"
                output = root / f"{name}.png"
                dsl.write_text(f"{search}{body}\n\nrender(o0)\n")
                entries.append({"name": name, "dsl": str(dsl), "out": str(output), "size": 32})

            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"entries": entries}))
            result = subprocess.run(
                [
                    str(GODOT),
                    "--path",
                    str(REPO / "godot"),
                    "--script",
                    RENDERER,
                    "--position",
                    "5000,5000",
                    "--",
                    "--batch-manifest",
                    str(manifest),
                ],
                capture_output=True,
                text=True,
                timeout=300,
            )

            output_log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output_log)
            self.assertNotIn("ERROR:", output_log, output_log)
            self.assertNotIn("SCRIPT ERROR", output_log, output_log)
            for entry in entries:
                image = Path(entry["out"])
                self.assertTrue(image.is_file(), f"missing output for {entry['name']}\n{output_log}")
                self.assertEqual(image.read_bytes()[:8], b"\x89PNG\r\n\x1a\n", entry["name"])

            content_result = subprocess.run(
                [
                    str(GODOT),
                    "--headless",
                    "--path",
                    str(REPO / "godot"),
                    "--script",
                    str(CONTENT_PROBE),
                    "--",
                    str(manifest),
                ],
                capture_output=True,
                text=True,
                timeout=60,
            )
            content_log = content_result.stdout + content_result.stderr
            self.assertEqual(content_result.returncode, 0, content_log)
            self.assertIn("IMAGE_CONTENT_TEST: PASS", content_log, content_log)


if __name__ == "__main__":
    unittest.main()
