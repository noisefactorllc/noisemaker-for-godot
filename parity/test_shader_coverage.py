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

    def test_registered_effect_definitions_satisfy_specification(self):
        definitions = sorted(DEFINITIONS.glob("*/*.json"))
        self.assertEqual(len(definitions), 210)
        for definition_path in definitions:
            defn = json.loads(definition_path.read_text(encoding="utf-8"))
            eff_name = f"{defn.get('namespace', '?')}.{defn.get('func', '?')}"
            self.assertTrue(
                isinstance(defn.get("name"), str) and defn["name"],
                msg=f"Effect {eff_name} has invalid 'name'",
            )
            self.assertTrue(
                isinstance(defn.get("namespace"), str) and defn["namespace"],
                msg=f"Effect {eff_name} has invalid 'namespace'",
            )
            self.assertTrue(
                isinstance(defn.get("func"), str) and defn["func"],
                msg=f"Effect {eff_name} has invalid 'func'",
            )
            self.assertTrue(
                isinstance(defn.get("passes"), list) and len(defn["passes"]) > 0,
                msg=f"Effect {eff_name} has invalid 'passes'",
            )
            for p in defn["passes"]:
                self.assertIsInstance(p, dict, msg=f"Effect {eff_name} pass is not a dict")
                self.assertTrue(
                    isinstance(p.get("program"), str) and p["program"],
                    msg=f"Effect {eff_name} has invalid pass 'program'",
                )
            globals_dict = defn.get("globals", {})
            if "globals" in defn:
                self.assertIsInstance(globals_dict, dict, msg=f"Effect {eff_name} 'globals' not a dict")
                for k, v in globals_dict.items():
                    self.assertIsInstance(v, dict, msg=f"Effect {eff_name} global '{k}' not a dict")
                    self.assertTrue(
                        isinstance(v.get("type"), str) and v["type"],
                        msg=f"Effect {eff_name} global '{k}' missing valid 'type'",
                    )
            if "paramAliases" in defn:
                self.assertIsInstance(
                    defn["paramAliases"],
                    dict,
                    msg=f"Effect {eff_name} 'paramAliases' not a dict",
                )
                for alias, target in defn["paramAliases"].items():
                    self.assertIn(
                        target,
                        globals_dict,
                        msg=f"Effect {eff_name} alias '{alias}' -> '{target}' not found in globals",
                    )

    def test_registered_effect_definitions_gap004_gap005_contract(self):
        definitions = sorted(DEFINITIONS.glob("*/*.json"))
        self.assertEqual(len(definitions), 210)
        viewport_effects = set()
        viewport_pass_count = 0
        for definition_path in definitions:
            defn = json.loads(definition_path.read_text(encoding="utf-8"))
            eff_name = f"{defn.get('namespace', '?')}.{defn.get('func', '?')}"
            for p in defn.get("passes", []):
                if "viewport" in p:
                    viewport_effects.add(eff_name)
                    viewport_pass_count += 1
                    vp = p["viewport"]
                    self.assertIsInstance(vp, dict, msg=f"Effect {eff_name} viewport is not a dict")
                    self.assertTrue(
                        "width" in vp or "height" in vp or "scale" in vp,
                        msg=f"Effect {eff_name} viewport missing dimensions",
                    )
                if "samplerTypes" in p:
                    st = p["samplerTypes"]
                    self.assertIsInstance(st, dict, msg=f"Effect {eff_name} samplerTypes is not a dict")
                    for s_k, s_v in st.items():
                        self.assertIsInstance(s_v, str, msg=f"Effect {eff_name} samplerType {s_k} not a string")
                if "name" in p:
                    self.assertIsInstance(p["name"], str, msg=f"Effect {eff_name} pass name not a string")
                if "type" in p:
                    self.assertIsInstance(p["type"], str, msg=f"Effect {eff_name} pass type not a string")
            for tex_field in ("textures", "textures3d"):
                if tex_field in defn and isinstance(defn[tex_field], dict):
                    for tex_name, tex_spec in defn[tex_field].items():
                        if "mipmaps" in tex_spec:
                            self.assertIsInstance(
                                tex_spec["mipmaps"],
                                bool,
                                msg=f"Effect {eff_name} texture {tex_name} mipmaps not a bool",
                            )
                        if "persistent" in tex_spec:
                            self.assertIsInstance(
                                tex_spec["persistent"],
                                bool,
                                msg=f"Effect {eff_name} texture {tex_name} persistent not a bool",
                            )
                        if "filter" in tex_spec:
                            self.assertIsInstance(
                                tex_spec["filter"],
                                str,
                                msg=f"Effect {eff_name} texture {tex_name} filter not a str",
                            )
        self.assertEqual(len(viewport_effects), 10)
        self.assertEqual(viewport_pass_count, 13)


if __name__ == "__main__":
    unittest.main()
