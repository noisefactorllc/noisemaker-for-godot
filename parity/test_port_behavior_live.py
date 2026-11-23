#!/usr/bin/env python3
"""Focused GPU tests for the heightGrid aspect-depth and landscape edge-face ports."""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from parity.windowed import run_windowed
except ImportError:  # direct discovery (unittest discover -s parity)
    from windowed import run_windowed

REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
RENDERER = "res://addons/noisemaker/tools/render_graph.gd"
GRID_ASPECT_PROBE = REPO / "parity" / "grid_aspect_probe.gd"
EDGE_FACE_PROBE = REPO / "parity" / "edge_face_probe.gd"
# The three ported shaders these tests exercise. The edge-face probe extracts its
# functions from the live landscape.glsl; the aspect and frame-shape renders run
# the live agent.glsl and heightmap3d precompute.glsl.
HEIGHT_GRID_SHADER = "godot/addons/noisemaker/shaders/effects/points/heightGrid/agent.glsl"
LANDSCAPE_SHADER = "godot/addons/noisemaker/shaders/effects/render/renderLandscape3d/landscape.glsl"
HEIGHTMAP_SHADER = "godot/addons/noisemaker/shaders/effects/synth3d/heightmap3d/precompute.glsl"

HEIGHT_GRID_DSL = (
    "search synth, points, render\n\n"
    "perlin(scale: 35, colorMode: rgb)\n"
    "  .write(o1)\n\n"
    "perlin(scale: 22, octaves: 4, colorMode: mono)\n"
    "  .write(o2)\n\n"
    "solid()\n"
    "  .pointsEmit(stateSize: x64)\n"
    "  .heightGrid(heightTex: read(o2), diffuseTex: read(o1), heightScale: 0)\n"
    "  .pointsBillboardRender(viewMode: ortho, pointSize: 2, density: 100)\n"
    "  .write(o0)\n\n"
    "render(o0)\n"
)

# Same frame width, four heights: the ported grid depth is gridScale times the
# engine's aspectInv, so the drawn depth span must track the frame height factor
# at that width, while the width span stays fixed. The orthographic billboard
# view fits each screen axis to the frame, so the drawn depth span follows the
# height factor squared on screen; the test fits that law from two sizes and
# requires the other two to match it.
SIZES = [(320, 320), (320, 240), (320, 180), (320, 160)]

# A full-height heightmap terrain, seen from directly above: the ported
# precompute keeps the terrain's proportions inside the volume, so the drawn
# box must match the frame's shape on a square, a wide and a tall frame. The
# camera distances follow the upstream test's proven values.
HEIGHTMAP_DSL_TEMPLATE = (
    "search synth, synth3d, render\n\n"
    "solid(color: #ffffff).write(o1)\n"
    "testPattern(pattern: uvMap).write(o2)\n"
    "heightmap3d(heightTex: read(o1), tex: read(o2), volumeSize: x16, heightScale: 1)\n"
    "  .renderLandscape3d(viewMode: perspective, rotateX: 1.5708, posZ: {pos_z}, "
    "bgColor: #ffffff, ambient: 1, diffuseIntensity: 0, specularIntensity: 0).write(o0)\n\n"
    "render(o0)\n"
)
FRAME_SHAPES = [(128, 128, -40), (256, 128, -40), (128, 256, -120)]


def _bbox_log_pngs(output_log):
    boxes = {}
    pattern = re.compile(
        r"NM_BBOX path=(\S+) x0=(-?\d+) x1=(-?\d+) y0=(-?\d+) y1=(-?\d+)")
    for match in pattern.finditer(output_log):
        boxes[match.group(1)] = tuple(int(match.group(i)) for i in range(2, 6))
    return boxes


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class HeightGridAspectTests(unittest.TestCase):
    def test_grid_depth_spans_follow_frame_aspect(self):
        self.assertTrue((REPO / HEIGHT_GRID_SHADER).is_file())
        with tempfile.TemporaryDirectory(prefix="nm-grid-aspect-") as tmp:
            root = Path(tmp)
            dsl = root / "heightgrid_aspect.dsl"
            dsl.write_text(HEIGHT_GRID_DSL)
            entries = []
            for width, height in SIZES:
                entries.append({
                    "name": f"aspect_{width}x{height}",
                    "dsl": str(dsl),
                    "out": str(root / f"aspect_{width}x{height}.png"),
                    "size": 256,
                    "width": width,
                    "height": height,
                })
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"entries": entries}))
            result = run_windowed(
                [
                    str(GODOT),
                    "--path", str(REPO / "godot"),
                    "--script", RENDERER,
                    "--position", "5000,5000",
                    "--", "--batch-manifest", str(manifest),
                ],
                capture_output=True, text=True, timeout=120,
            )
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            for entry in entries:
                self.assertIn(f'NM_BATCH name={entry["name"]} ok=true', log, log)
            probe = subprocess.run(
                [
                    str(GODOT), "--headless", "--path", str(REPO / "godot"),
                    "--script", str(GRID_ASPECT_PROBE), "--",
                ] + [entry["out"] for entry in entries],
                capture_output=True, text=True, timeout=60,
            )
            probe_log = probe.stdout + probe.stderr
            self.assertEqual(probe.returncode, 0, probe_log)
            boxes = _bbox_log_pngs(probe_log)
            for entry in entries:
                self.assertIn(entry["out"], boxes, probe_log)
            spans = []
            for (width, height), entry in zip(SIZES, entries):
                x0, x1, y0, y1 = boxes[entry["out"]]
                spans.append((height, x1 - x0, y1 - y0))
            width_spans = {s[1] for s in spans}
            self.assertEqual(len(width_spans), 1,
                             f"grid width span must not depend on frame height: {spans}")
            (h1, _, s1), (h2, _, s2) = spans[0], spans[1]
            slope = (s1 - s2) / float(h1 * h1 - h2 * h2)
            self.assertGreater(slope, 1e-6,
                               f"grid depth span must grow with frame height: {spans}")
            intercept = s2 - slope * h2 * h2
            for height, _, span in spans[2:]:
                predicted = slope * height * height + intercept
                self.assertLessEqual(abs(predicted - span), 2.0,
                                     f"depth spans must track the frame height factor: {spans}")


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class HeightmapFrameShapeTests(unittest.TestCase):
    def test_terrain_seen_from_above_keeps_frame_proportions(self):
        self.assertTrue((REPO / HEIGHTMAP_SHADER).is_file())
        with tempfile.TemporaryDirectory(prefix="nm-heightmap-shapes-") as tmp:
            root = Path(tmp)
            entries = []
            for width, height, pos_z in FRAME_SHAPES:
                dsl = root / f"heightmap_{width}x{height}.dsl"
                dsl.write_text(HEIGHTMAP_DSL_TEMPLATE.format(pos_z=pos_z))
                entries.append({
                    "name": f"heightmap_{width}x{height}",
                    "dsl": str(dsl),
                    "out": str(root / f"heightmap_{width}x{height}.png"),
                    "size": 256,
                    "width": width,
                    "height": height,
                })
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"entries": entries}))
            result = run_windowed(
                [
                    str(GODOT),
                    "--path", str(REPO / "godot"),
                    "--script", RENDERER,
                    "--position", "5000,5000",
                    "--", "--batch-manifest", str(manifest),
                ],
                capture_output=True, text=True, timeout=120,
            )
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            for entry in entries:
                self.assertIn(f'NM_BATCH name={entry["name"]} ok=true', log, log)
            probe = subprocess.run(
                [
                    str(GODOT), "--headless", "--path", str(REPO / "godot"),
                    "--script", str(GRID_ASPECT_PROBE), "--",
                ] + [entry["out"] for entry in entries],
                capture_output=True, text=True, timeout=60,
            )
            probe_log = probe.stdout + probe.stderr
            self.assertEqual(probe.returncode, 0, probe_log)
            boxes = _bbox_log_pngs(probe_log)
            for (width, height, _), entry in zip(FRAME_SHAPES, entries):
                self.assertIn(entry["out"], boxes, probe_log)
                x0, x1, y0, y1 = boxes[entry["out"]]
                label = f"{width}x{height}: box x {x0} to {x1}, y {y0} to {y1}"
                self.assertGreater(x0, 0, label)
                self.assertGreater(y0, 0, label)
                self.assertLess(x1, width - 1, label)
                self.assertLess(y1, height - 1, label)
                self.assertLessEqual(abs(x0 + x1 - (width - 1)), 3, label)
                self.assertLessEqual(abs(y0 + y1 - (height - 1)), 3, label)
                box_width = x1 - x0 + 1
                box_height = y1 - y0 + 1
                shape = width / height
                self.assertLessEqual(abs(box_width / box_height - shape), shape * 0.1, label)


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class LandscapeEdgeFaceTests(unittest.TestCase):
    def test_exposed_face_rule_holds_on_gpu(self):
        self.assertTrue((REPO / LANDSCAPE_SHADER).is_file())
        result = run_windowed(
            [
                str(GODOT),
                "--path", str(REPO / "godot"),
                "--script", str(EDGE_FACE_PROBE),
                "--position", "5000,5000",
            ],
            capture_output=True, text=True, timeout=120,
        )
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, log)
        self.assertIn("NM_EDGE_FACE_PROBE: PASS cases=8", log, log)


if __name__ == "__main__":
    unittest.main()
