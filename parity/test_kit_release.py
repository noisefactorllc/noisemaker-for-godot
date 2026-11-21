"""The exported kit releases its RenderingDevice once the program has rendered.

The addon README requires `backend.close()` and then freeing the device:
"Freeing the device first leaks backend handles" (godot/addons/noisemaker/
README.md, Ownership). The kit's main.gd captures every still as an Image, so
it needs neither the backend nor the device once rendering is done. These
checks read the template; parity/test_kit_playback.py checks the same release
in Godot.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "export-kit" / "kit" / "main.gd"


def function_body(text: str, name: str):
    """The indented lines of `func name(...)`, comments removed, or None if it is not defined."""
    match = re.search(
        rf"^func {name}\([^)]*\)(?:\s*->\s*\w+)?\s*:\n((?:(?:\t[^\n]*)?\n)*)", text, re.M)
    if not match:
        return None
    return "\n".join(line.split("#", 1)[0].rstrip() for line in match.group(1).splitlines())


class KitReleaseTests(unittest.TestCase):

    def setUp(self):
        self.text = MAIN.read_text()

    def test_release_closes_the_backend_before_freeing_the_device(self):
        body = function_body(self.text, "_release")
        self.assertIsNotNone(body, "main.gd defines no _release()")
        close = body.find("_backend.close()")
        free = body.find("_rd.free()")
        self.assertGreaterEqual(close, 0, "_release() does not close the backend")
        self.assertGreaterEqual(free, 0, "_release() does not free the device")
        self.assertLess(close, free, "_release() frees the device before closing the backend")

    def test_every_path_after_setup_releases_before_it_ends(self):
        # The release must sit at the top level of _ready(), after the last
        # render and before any later return, so that no path after setup,
        # successful or not, can skip it.
        body = function_body(self.text, "_ready")
        self.assertIsNotNone(body, "main.gd defines no _ready()")
        lines = body.splitlines()
        setup = next((i for i, line in enumerate(lines) if "_backend.setup(" in line), None)
        self.assertIsNotNone(setup, "_ready() does not set the backend up as _backend")
        renders = [i for i, line in enumerate(lines) if "render_samples(" in line]
        self.assertTrue(renders, "_ready() does not render")
        release = next((i for i in range(renders[-1] + 1, len(lines))
                        if lines[i] == "\t_release()"), None)
        self.assertIsNotNone(release, "_ready() has no top-level _release() after its last render")
        for line in lines[setup + 1:release]:
            self.assertIsNone(re.search(r"\breturn\b", line),
                              f"_ready() returns before releasing: {line.strip()}")

    def test_leaving_the_tree_releases_as_well(self):
        body = function_body(self.text, "_exit_tree")
        self.assertIsNotNone(body, "main.gd defines no _exit_tree()")
        self.assertIn("_release()", body)


if __name__ == "__main__":
    unittest.main()
