#!/usr/bin/env python3
"""GAP-001 executable check: the installed kit plays sampled animation.

Assembles the exported-kit layout (kit template + addon + program.dsl), runs the
committed kit-observer (parity/kit-observe.gd) against it with the documented
temporal fixture, and requires the pass condition: differing displayed frames,
plus FRAMES / SAMPLE_EVERY / PLAYBACK_FPS each changing its stated behavior.
Also gates the Godot 4.7 RDSamplerState mip_filter compat set: on a 4.7 engine,
a regression to the pre-4.7 `mipmap_filter` name aborts Backend.setup() and
surfaces as SCRIPT ERROR + "render pipeline creation failed" lines, which this
suite treats as failure.

Skipped automatically when no Godot binary is available (GODOT env var), like
the other live tests in this directory.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
KIT_DIR = REPO / "export-kit" / "kit"
ADDON_DIR = REPO / "godot" / "addons" / "noisemaker"
OBSERVER = REPO / "parity" / "kit-observe.gd"
FIXTURE = REPO / "parity" / "programs" / "navierStokes.dsl"  # known temporal fixture
OBSERVE_FRAMES = 120


def build_kit(dest: Path, frames: int, sample_every: int, playback_fps: int,
              with_program: bool = True) -> None:
    """Assemble an installed-kit layout with the requested frame constants."""
    dest.mkdir(parents=True)
    for name in ("main.gd", "main.tscn", "project.godot"):
        shutil.copy(KIT_DIR / name, dest / name)
    shutil.copytree(ADDON_DIR, dest / "addons" / "noisemaker")
    if with_program:
        shutil.copy(FIXTURE, dest / "program.dsl")
    main = dest / "main.gd"
    text = main.read_text()
    text = re.sub(r"const FRAMES := \d+", f"const FRAMES := {frames}", text)
    text = re.sub(r"const SAMPLE_EVERY := \d+", f"const SAMPLE_EVERY := {sample_every}", text)
    text = re.sub(r"const PLAYBACK_FPS := \d+", f"const PLAYBACK_FPS := {playback_fps}", text)
    main.write_text(text)


def observe(kit: Path, out_png: Path, timeout: int = 300) -> dict:
    """Run the committed observer; return {rc, output, summary}."""
    result = subprocess.run(
        [
            str(GODOT), "--path", str(kit),
            "--script", str(OBSERVER),
            "--position", "5000,5000",
            "--", str(out_png),
        ],
        capture_output=True, text=True, timeout=timeout,
    )
    output = result.stdout + result.stderr
    match = re.search(r"NM_OBSERVE frames=(\d+) distinct=(\d+) first=(-?\d+) last=(-?\d+) transitions=(\d+)", output)
    summary = None
    if match:
        summary = {"frames": int(match[1]), "distinct": int(match[2]),
                   "first": int(match[3]), "last": int(match[4]), "transitions": int(match[5])}
    return {"rc": result.returncode, "output": output, "summary": summary}


def assert_engine_clean(case, run: dict) -> None:
    """No script errors and no failed pipeline creation (regression gate for
    the Godot 4.7 RDSamplerState mip_filter compat set in nm_backend.gd)."""
    case.assertNotIn("SCRIPT ERROR", run["output"], run["output"])
    case.assertNotIn("render pipeline creation failed", run["output"], run["output"])
    case.assertEqual(run["rc"], 0, run["output"][-4000:])


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class KitPlaybackTests(unittest.TestCase):

    def test_temporal_program_evolves_with_differing_displayed_frames(self):
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            kit = Path(tmp) / "kit"
            build_kit(kit, frames=120, sample_every=20, playback_fps=30)
            png = Path(tmp) / "first.png"
            run = observe(kit, png)
            assert_engine_clean(self, run)
            self.assertIsNotNone(run["summary"], run["output"][-4000:])
            self.assertGreaterEqual(run["summary"]["distinct"], 2, run["output"][-4000:])
            self.assertTrue(png.exists(), "observer wrote no first.png")
            self.assertGreater(png.stat().st_size, 0)

    def test_playback_fps_changes_the_stated_behavior(self):
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            slow = Path(tmp) / "slow"
            fast = Path(tmp) / "fast"
            build_kit(slow, frames=120, sample_every=20, playback_fps=5)
            build_kit(fast, frames=120, sample_every=20, playback_fps=30)
            slow_run = observe(slow, Path(tmp) / "slow.png")
            fast_run = observe(fast, Path(tmp) / "fast.png")
            assert_engine_clean(self, slow_run)
            assert_engine_clean(self, fast_run)
            self.assertGreater(fast_run["summary"]["transitions"],
                               slow_run["summary"]["transitions"],
                               f"slow={slow_run['summary']} fast={fast_run['summary']}")

    def test_sample_every_changes_the_still_count(self):
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            fine = Path(tmp) / "fine"
            coarse = Path(tmp) / "coarse"
            build_kit(fine, frames=120, sample_every=20, playback_fps=30)
            build_kit(coarse, frames=120, sample_every=30, playback_fps=30)
            fine_run = observe(fine, Path(tmp) / "fine.png")
            coarse_run = observe(coarse, Path(tmp) / "coarse.png")
            assert_engine_clean(self, fine_run)
            assert_engine_clean(self, coarse_run)
            self.assertGreater(fine_run["summary"]["distinct"],
                               coarse_run["summary"]["distinct"],
                               f"fine={fine_run['summary']} coarse={coarse_run['summary']}")

    def test_frames_1_renders_a_single_still_immediately(self):
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            kit = Path(tmp) / "kit"
            build_kit(kit, frames=1, sample_every=20, playback_fps=5)
            png = Path(tmp) / "first.png"
            run = observe(kit, png)
            assert_engine_clean(self, run)
            self.assertEqual(run["summary"]["distinct"], 1, run["output"][-4000:])
            self.assertTrue(png.exists())

    def test_cancellation_then_recovery(self):
        """A run cancelled mid-render must not wedge the kit: a fresh run after
        it completes the documented playback (recovery)."""
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            kit = Path(tmp) / "kit"
            build_kit(kit, frames=1800, sample_every=60, playback_fps=5)
            cancelled = False
            try:
                subprocess.run(
                    [str(GODOT), "--path", str(kit), "--script", str(OBSERVER),
                     "--position", "5000,5000", "--", str(Path(tmp) / "cancelled.png")],
                    capture_output=True, text=True, timeout=20,
                )
            except subprocess.TimeoutExpired:
                cancelled = True
            self.assertTrue(cancelled, "shipped-constant run unexpectedly finished before the cancel window")
            replay = Path(tmp) / "replay"
            build_kit(replay, frames=120, sample_every=20, playback_fps=30)
            run = observe(replay, Path(tmp) / "replay.png")
            assert_engine_clean(self, run)
            self.assertGreaterEqual(run["summary"]["distinct"], 2, run["output"][-4000:])

    def test_missing_program_fails_cleanly_and_recovers(self):
        with tempfile.TemporaryDirectory(prefix="nm-kit-") as tmp:
            kit = Path(tmp) / "kit"
            build_kit(kit, frames=120, sample_every=20, playback_fps=5, with_program=False)
            run = observe(kit, Path(tmp) / "missing.png")
            assert_engine_clean(self, run)
            self.assertEqual(run["summary"]["distinct"], 0, run["output"][-4000:])
            self.assertIn("cannot read res://program.dsl", run["output"], run["output"][-4000:])
            (kit / "program.dsl").write_text(FIXTURE.read_text())
            recovered = observe(kit, Path(tmp) / "recovered.png")
            assert_engine_clean(self, recovered)
            self.assertGreaterEqual(recovered["summary"]["distinct"], 2, recovered["output"][-4000:])


if __name__ == "__main__":
    unittest.main()
