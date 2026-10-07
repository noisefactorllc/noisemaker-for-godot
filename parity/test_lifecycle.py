#!/usr/bin/env python3
"""Backend teardown and lifecycle contracts."""

import json
import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot"))
PROBE = REPO / "parity" / "lifecycle_probe.gd"


def _headless_godot(script: str):
    with tempfile.TemporaryDirectory(prefix="nm-lifecycle-") as tmp:
        script_path = Path(tmp) / "lifecycle_test.gd"
        script_path.write_text(textwrap.dedent(script))
        return subprocess.run(
            [str(GODOT), "--headless", "--path", str(REPO / "godot"), "--script", str(script_path)],
            capture_output=True, text=True, timeout=30,
        )


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class HeadlessLifecycleTests(unittest.TestCase):
    """Static teardown seams (no RenderingDevice under --headless)."""

    def test_teardown_release_dedupes_shared_rids_and_clears_the_map(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var frees := {}
                var free_rid := func(rid: RID) -> void:
                    frees[rid.get_id()] = int(frees.get(rid.get_id(), 0)) + 1
                # Pooling aliases share one storage RID; a second id carries an
                # invalid RID that must be skipped.
                var live := ImageTexture.new()
                var shared: RID = live.get_rid()
                var records := {"t1": shared, "t2": shared, "t3": RID()}
                backend_script.call("release_unique_rids", records, free_rid)
                var ok: bool = records.is_empty() \\
                    and int(frees.get(shared.get_id(), 0)) == 1 \\
                    and frees.size() == 1
                if ok:
                    print("LIFECYCLE_UNIT_TEST: PASS")
                    quit(0)
                else:
                    print("LIFECYCLE_UNIT_TEST: frees=", frees)
                    quit(1)
        """
        result = _headless_godot(script)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("LIFECYCLE_UNIT_TEST: PASS", output, output)
        self.assertNotIn("SCRIPT ERROR", output, output)

    def test_close_without_setup_is_flat_idempotent_and_guards_queues(self):
        script = """
            extends SceneTree

            func _init() -> void:
                var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
                var backend = backend_script.new()
                var ok: bool = int(backend.tracked_handle_count()) == 0
                backend.close()
                backend.close()  # idempotent
                ok = ok and int(backend.tracked_handle_count()) == 0
                ok = ok and bool(backend.get("sink_manager").get("_closed"))
                # Closed backend: new frame-export queues are refused.
                var queue = backend.create_frame_export_queue({})
                ok = ok and queue == null
                if ok:
                    print("LIFECYCLE_GUARD_TEST: PASS")
                    quit(0)
                else:
                    print("LIFECYCLE_GUARD_TEST: FAIL")
                    quit(1)
        """
        result = _headless_godot(script)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("LIFECYCLE_GUARD_TEST: PASS", output, output)
        self.assertNotIn("SCRIPT ERROR", output, output)


@unittest.skipUnless(GODOT.exists(), f"Godot binary not found: {GODOT}")
class LiveLifecycleTests(unittest.TestCase):
    """Live RenderingDevice probe (needs a real window + device)."""

    def test_repeated_lifecycles_are_flat_cancel_active_exports_and_free_clean(self):
        result = subprocess.run(
            [str(GODOT), "--path", str(REPO / "godot"), "--script", str(PROBE),
             "--position", "5000,5000"],
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("LIFECYCLE_TEST: PASS", output, output)
        self.assertNotIn("SCRIPT ERROR", output, output)
        # No leaked-handle warnings from the device free
        # (or any other backend teardown step). Precise warning signatures,
        # not a blanket "ERROR:" scan: this floor's engine exit prints an
        # unrelated macOS certificate-store noise line (see test_shader_import,
        # which never loads the backend and fails the same scan).
        for needle in ["Attempted to free invalid ID", "eaked instance",
                       "eaked resource", "till registered in the device",
                       "eaked RID", "till in use",
                       "ObjectDB instances were leaked at exit"]:
            self.assertNotIn(needle, output, output)

    def test_batch_render_releases_each_request_device(self):
        # A batch renders every request on its own local RenderingDevice. Without
        # releasing them, an NVIDIA Vulkan driver refused the 23rd device
        # (VK_ERROR_DEVICE_LOST) and the process crashed.
        requests = 40
        with tempfile.TemporaryDirectory(prefix="nm-batch-") as tmp:
            dsl = Path(tmp) / "solid.dsl"
            dsl.write_bytes(b"search synth\nnoise(seed: 1).write(o0)\nrender(o0)\n")
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(json.dumps({"entries": [
                {"name": f"r{i}", "dsl": dsl.as_posix(), "out": (Path(tmp) / f"r{i}.png").as_posix(),
                 "size": 32, "run_seconds": 0, "sample_every": 0}
                for i in range(requests)]}))
            result = subprocess.run(
                [str(GODOT), "--path", str(REPO / "godot"), "--script",
                 "res://addons/noisemaker/tools/render_graph.gd", "--position", "5000,5000",
                 "--", "--batch-manifest", manifest.as_posix()],
                capture_output=True, text=True, timeout=300,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-4000:])
            self.assertEqual(len(re.findall(r"^NM_BATCH name=r\d+ ok=true$", output, re.M)), requests,
                             output[-4000:])
            self.assertEqual(len(list(Path(tmp).glob("r*.png"))), requests)
            self.assertNotIn("Couldn't create Vulkan device", output)
            self.assertNotIn("ObjectDB instances were leaked at exit", output, output[-4000:])


if __name__ == "__main__":
    unittest.main()
