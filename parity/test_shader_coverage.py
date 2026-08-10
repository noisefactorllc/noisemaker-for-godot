#!/usr/bin/env python3
"""Definition-driven coverage gate for shipped Godot effect shaders."""

import json
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
ADDON = REPO / "godot" / "addons" / "noisemaker"
DEFINITIONS = ADDON / "effects"
SHADERS = ADDON / "shaders" / "effects"


def missing_required_shaders():
    missing = []
    for definition_path in sorted(DEFINITIONS.glob("*/*.json")):
        definition = json.loads(definition_path.read_text())
        namespace = definition["namespace"]
        effect = definition["func"]
        for pass_spec in definition.get("passes", []):
            program = pass_spec["program"]
            base = SHADERS / namespace / effect / program
            fragment = base.with_suffix(".glsl")
            if not fragment.is_file():
                missing.append(fragment.relative_to(ADDON).as_posix())
            if pass_spec.get("drawMode") in {"points", "billboards", "triangles"}:
                vertex = base.with_suffix(".vert.glsl")
                if not vertex.is_file():
                    missing.append(vertex.relative_to(ADDON).as_posix())
    return missing


class ShaderCoverageTests(unittest.TestCase):
    def test_every_definition_pass_has_its_required_shader_stages(self):
        self.assertEqual([], missing_required_shaders())


if __name__ == "__main__":
    unittest.main()
