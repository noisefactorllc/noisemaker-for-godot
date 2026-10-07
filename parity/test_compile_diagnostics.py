#!/usr/bin/env python3
"""Public entry points reject invalid DSL with actionable diagnostics.

The unknown-effect input must produce an actionable NM_COMPILE_DIAG diagnostic without
rendering; correcting it must restore the render path (verified against the missing-device
baseline, which is the farthest a headless run can go without a GPU). Covers both public
entry points: tools/render_graph.gd and tools/present.gd.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
RENDERER = "res://addons/noisemaker/tools/render_graph.gd"
PRESENT = "res://addons/noisemaker/tools/present.gd"

SEARCH = "search synth, filter, render, points, mixer, classicNoisedeck, synth3d, filter3d\n\n"
VALID = SEARCH + "noise().grade().write(o0)\n\nrender(o0)\n"
UNKNOWN_EFFECT = SEARCH + "noise().notAnEffect().write(o0)\n\nrender(o0)\n"
MALFORMED = SEARCH + "noise(.write(o0)\n\nrender(o0)\n"


def _run(script, args, extra_headless=True):
    cmd = [str(GODOT)]
    if extra_headless:
        cmd.append("--headless")
    cmd += ["--path", str(REPO / "godot"), "--script", script, "--", *args]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=300)


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class RenderGraphCompileDiagnosticsTests(unittest.TestCase):
    """tools/render_graph.gd (single-request + batch paths)."""

    def _render(self, dsl_body, out):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            dsl = Path(tmp) / "program.dsl"
            dsl.write_text(dsl_body)
            result = _run(RENDERER, ["--dsl", str(dsl), "--out", str(out), "--size", "32"])
            log = result.stdout + result.stderr
            return result.returncode, log

    def test_unknown_effect_is_diagnosed_without_rendering(self):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            out = Path(tmp) / "invalid.png"
            code, log = self._render(UNKNOWN_EFFECT, out)
            self.assertEqual(code, 1, log)
            self.assertIn("NM_COMPILE_DIAG", log, log)
            self.assertIn("notAnEffect", log, log)
            self.assertNotIn("NM_RENDERED", log, log)
            self.assertFalse(out.exists(), log)

    def test_malformed_syntax_is_diagnosed_without_rendering(self):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            out = Path(tmp) / "invalid.png"
            code, log = self._render(MALFORMED, out)
            self.assertEqual(code, 1, log)
            self.assertIn("NM_COMPILE_DIAG stage=parser", log, log)
            self.assertNotIn("NM_RENDERED", log, log)
            self.assertFalse(out.exists(), log)

    def test_missing_dsl_file_reports_cannot_read(self):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            out = Path(tmp) / "missing.png"
            code, log = self._render_from_path(Path(tmp) / "does-not-exist.dsl", out)
            self.assertEqual(code, 1, log)
            self.assertIn("cannot read dsl:", log, log)
            self.assertNotIn("NM_RENDERED", log, log)
            self.assertFalse(out.exists(), log)

    def _render_from_path(self, dsl, out):
        result = _run(RENDERER, ["--dsl", str(dsl), "--out", str(out), "--size", "32"])
        return result.returncode, result.stdout + result.stderr

    def test_missing_device_still_fails_after_successful_compile(self):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            out = Path(tmp) / "recovery.png"
            code, log = self._render(VALID, out)
            self.assertEqual(code, 1, log)
            self.assertIn("RD_NULL", log, log)
            self.assertNotIn("NM_COMPILE_DIAG", log, log)
            self.assertNotIn("NM_RENDERED", log, log)
            self.assertFalse(out.exists(), log)

    def test_batch_manifest_marks_invalid_entry_failed(self):
        with tempfile.TemporaryDirectory(prefix="nm-compile-diag-") as tmp:
            root = Path(tmp)
            dsl = root / "invalid.dsl"
            dsl.write_text(UNKNOWN_EFFECT)
            out = root / "invalid.png"
            manifest = root / "manifest.json"
            manifest.write_text(
                '{"entries": [{"name": "invalid", "dsl": "%s", "out": "%s", "size": 32}]}'
                % (dsl.as_posix(), out.as_posix())
            )
            result = _run(RENDERER, ["--batch-manifest", str(manifest)])
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 1, log)
            self.assertIn("NM_COMPILE_DIAG", log, log)
            self.assertIn("notAnEffect", log, log)
            self.assertIn("NM_BATCH name=invalid ok=false", log, log)
            self.assertFalse(out.exists(), log)


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class PresentCompileDiagnosticsTests(unittest.TestCase):
    """tools/present.gd (compiled presentation harness)."""

    def _present(self, dsl_body, out):
        with tempfile.TemporaryDirectory(prefix="nm-present-diag-") as tmp:
            dsl = Path(tmp) / "program.dsl"
            dsl.write_text(dsl_body)
            result = _run(PRESENT, ["--dsl", str(dsl), "--out", str(out), "--size", "32"])
            return result.returncode, result.stdout + result.stderr

    def test_unknown_effect_is_diagnosed_before_device_work(self):
        with tempfile.TemporaryDirectory(prefix="nm-present-diag-") as tmp:
            out = Path(tmp) / "invalid.png"
            code, log = self._present(UNKNOWN_EFFECT, out)
            self.assertEqual(code, 1, log)
            self.assertIn("NM_COMPILE_DIAG", log, log)
            self.assertIn("notAnEffect", log, log)
            self.assertNotIn("RD_NULL", log, log)
            self.assertFalse(out.exists(), log)

    def test_malformed_syntax_is_diagnosed_before_device_work(self):
        with tempfile.TemporaryDirectory(prefix="nm-present-diag-") as tmp:
            out = Path(tmp) / "invalid.png"
            code, log = self._present(MALFORMED, out)
            self.assertEqual(code, 1, log)
            self.assertIn("NM_COMPILE_DIAG stage=parser", log, log)
            self.assertNotIn("RD_NULL", log, log)
            self.assertFalse(out.exists(), log)

    def test_missing_device_fails_after_successful_compile(self):
        with tempfile.TemporaryDirectory(prefix="nm-present-diag-") as tmp:
            out = Path(tmp) / "recovery.png"
            code, log = self._present(VALID, out)
            self.assertEqual(code, 1, log)
            self.assertIn("RD_NULL", log, log)
            self.assertNotIn("NM_COMPILE_DIAG", log, log)
            self.assertFalse(out.exists(), log)

    def test_missing_dsl_file_reports_cannot_read(self):
        with tempfile.TemporaryDirectory(prefix="nm-present-diag-") as tmp:
            out = Path(tmp) / "missing.png"
            result = _run(
                PRESENT,
                ["--dsl", str(Path(tmp) / "does-not-exist.dsl"), "--out", str(out)],
            )
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 1, log)
            self.assertIn("cannot read dsl:", log, log)
            self.assertFalse(out.exists(), log)


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class ExportKitCompileDiagnosticsTests(unittest.TestCase):
    """export-kit/kit/main.gd (exported project startup path).

    Runs a throwaway copy of the kit project (product tree is never modified) with an
    injected program.dsl and asserts the compileError rejection happens before any
    RenderingDevice/render work.
    """

    KIT = REPO / "export-kit" / "kit"
    ADDONS = REPO / "godot" / "addons"

    def _make_kit(self, dsl_body):
        tmp = tempfile.TemporaryDirectory(prefix="nm-kit-diag-")
        root = Path(tmp.name) / "kit"
        shutil.copytree(self.KIT, root)
        shutil.copytree(self.ADDONS, root / "addons")
        (root / "program.dsl").write_text(dsl_body)
        return tmp, root

    def _run_kit(self, dsl_body):
        tmp, root = self._make_kit(dsl_body)
        try:
            result = subprocess.run(
                [str(GODOT), "--headless", "--path", str(root), "--quit-after", "5"],
                capture_output=True, text=True, timeout=300,
            )
            return result.returncode, result.stdout + result.stderr
        finally:
            tmp.cleanup()

    def test_unknown_effect_is_diagnosed_before_device_work(self):
        code, log = self._run_kit(UNKNOWN_EFFECT)
        self.assertIn("NM_COMPILE_DIAG", log, log)
        self.assertIn("notAnEffect", log, log)
        self.assertIn("compile failed (stage=validate): no render", log, log)
        self.assertNotIn("RenderingDevice unavailable", log, log)

    def test_missing_device_fails_after_successful_compile(self):
        code, log = self._run_kit(VALID)
        self.assertIn("RenderingDevice unavailable", log, log)
        self.assertNotIn("NM_COMPILE_DIAG", log, log)


if __name__ == "__main__":
    unittest.main()
