#!/usr/bin/env python3
"""Tiled export renders the untiled frame.

The reference's calculateTileGrid renders large prints as a grid of tile
canvases with a margin, and the tile-aware shaders anchor every coordinate to
fullResolution and tileOffset. This suite renders each coverage program
untiled at full size * renderScale and as a grid of tile canvases through the
same executor, stitches the tile interiors, and requires the stitch to match
the untiled frame inside the margin band under the port's published numerical
contract (max_abs_diff and SSIM thresholds). The band is excluded because a
sample that reaches past the full image clamps untiled but finds real margin
content under tiling.

A missing Godot binary is a hard setup failure, not a skip: a runner without
the engine must fail loudly rather than report a silent 0-test pass.
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
if not GODOT.exists():
    raise RuntimeError(
        f"tiled render gate requires a Godot binary; none found at {GODOT} "
        "(set GODOT=<path to Godot>)"
    )

RENDER_GRAPH = "res://addons/noisemaker/tools/render_graph.gd"
NOISE = "noise(seed: 1, scaleX: 50, scaleY: 50)"
HEADER = "search synth, filter, classicNoisedeck\n"
CASES = {
    # cga anchors its block grid and base sample to the full image.
    "cga": HEADER + f"{NOISE}.effects(effect: 200, effectAmt: 8).write(o0)\nrender(o0)",
    # zoomBlur samples along full-image taps clamped to the tile budget.
    "zoomBlur": (
        HEADER + f"{NOISE}.effects(effect: 230, effectAmt: 2, scaleAmt: 120, rotation: 15)"
        ".write(o0)\nrender(o0)"
    ),
    # bloom samples a neighborhood of the full-image coordinate.
    "bloom": HEADER + f"{NOISE}.effects(effect: 220, effectAmt: 10).write(o0)\nrender(o0)",
    # glyphMap detects tiling from fullResolution and clamps its cell size.
    "glyphMap": HEADER + f"{NOISE}.glyphMap().write(o0)\nrender(o0)",
}
SIZE = 128          # full-frame base pixels (4x4 grid)
TILE = 32           # tile base pixels
MARGIN = 16         # canvas margin base pixels on each side
RENDER_SCALE = 3    # canvas renders at 192 px, the full frame at 384 px
TOLERANCE = 2.001
SSIM_MIN = 0.98


def render_tiled(dsl_text: str, work: Path, name: str) -> dict:
    """Render one coverage program tiled; return {rc, output, stitched, untiled}."""
    dsl = work / f"{name}.dsl"
    dsl.write_text(dsl_text)
    out = work / f"{name}.candidate.png"
    result = subprocess.run(
        [
            str(GODOT), "--path", str(REPO / "godot"),
            "--script", RENDER_GRAPH,
            "--position", "5000,5000",
            "--",
            "--dsl", str(dsl), "--out", str(out),
            "--size", str(SIZE),
            "--render-scale", str(RENDER_SCALE),
            "--tiles", f"{TILE}x{TILE}", "--tile-margin", str(MARGIN),
        ],
        capture_output=True, text=True, timeout=900,
    )
    untiled = work / f"{name}.untiled.png"
    return {
        "rc": result.returncode,
        "output": result.stdout + result.stderr,
        "stitched": out,
        "untiled": untiled,
    }


def load_rgba(path: Path) -> np.ndarray:
    img = Image.open(path).convert("RGBA")
    return np.asarray(img, dtype=np.float32) / 255.0


def interior(img: np.ndarray) -> np.ndarray:
    band = MARGIN * RENDER_SCALE
    return img[band:-band, band:-band, :]


def max_abs_diff(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.max(np.abs(a - b)) * 255.0)


def global_ssim(a: np.ndarray, b: np.ndarray) -> float:
    def luma(x):
        return 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]

    la, lb = luma(a).ravel(), luma(b).ravel()
    mu_a, mu_b = la.mean(), lb.mean()
    var_a, var_b = la.var(), lb.var()
    cov = ((la - mu_a) * (lb - mu_b)).mean()
    denom = np.sqrt(var_a * var_b) + 1e-9
    return float((cov + 0.0) / denom)


class TiledRenderTests(unittest.TestCase):

    def test_tiled_stitch_matches_untiled_frame(self):
        for name, dsl_text in CASES.items():
            with self.subTest(case=name):
                with tempfile.TemporaryDirectory(prefix="nm-tiled-") as tmp:
                    run = render_tiled(dsl_text, Path(tmp), name)
                    self.assertEqual(run["rc"], 0, run["output"][-4000:])
                    self.assertNotIn("SCRIPT ERROR", run["output"], run["output"])
                    marker = [ln for ln in run["output"].splitlines()
                              if ln.startswith("NM_TILED")]
                    self.assertTrue(marker, run["output"][-2000:])
                    self.assertIn(" ok=true", marker[-1], marker[-1])
                    self.assertTrue(run["stitched"].exists(), run["output"][-2000:])
                    self.assertTrue(run["untiled"].exists(), run["output"][-2000:])
                    a = interior(load_rgba(run["untiled"]))
                    b = interior(load_rgba(run["stitched"]))
                    self.assertEqual(a.shape, b.shape)
                    mad = max_abs_diff(a, b)
                    ssim = global_ssim(a, b)
                    self.assertLessEqual(
                        mad, TOLERANCE,
                        f"{name}: tiled stitch diverges from the untiled frame "
                        f"(max_abs_diff={mad})")
                    self.assertGreaterEqual(
                        ssim, SSIM_MIN,
                        f"{name}: tiled stitch diverges from the untiled frame "
                        f"(ssim={ssim})")


if __name__ == "__main__":
    sys.exit(unittest.main())
