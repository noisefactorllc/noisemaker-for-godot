"""Pins the accepted expansion-difference class for the expand parity gate.

The rule lives in parity/expand_acceptance.mjs and is consumed by
parity/check_expand.mjs:
a candidate pass may carry `defines` that the reference pass omits exactly
when both passes name the byte-identical program and every define entry is
encoded in that program name as `__<KEY>_<value>`; after stripping those
defines both graphs must compare equal. Anything else stays a gate failure.

Engine-free: runs the Node module on synthetic fixtures plus source guards.
"""

import json
import os
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MODULE = REPO / "parity" / "expand_acceptance.mjs"
GATE = REPO / "parity" / "check_expand.mjs"
TEST = Path(__file__).resolve()

RUNNER = """import { classifyPassDefinesDiff, deepEq } from 'file://{module}';
const cases = JSON.parse(process.argv[1]);
const out = [];
for (const c of cases) {
  const r = classifyPassDefinesDiff(c.ref, c.cand);
  out.push({ name: c.name, accepted: r.accepted, reason: r.reason,
              normalizedEqual: r.normalized !== null && deepEq(c.ref, r.normalized) });
}
console.log(JSON.stringify(out));
"""


def run_cases(cases):
    src = RUNNER.replace("{module}", str(MODULE)).replace("\\", "\\\\")
    p = subprocess.run(
        ["node", "--input-type=module", "-e", src, json.dumps(cases)],
        capture_output=True, text=True, timeout=120, cwd=str(REPO),
    )
    if p.returncode != 0:
        raise AssertionError(f"node runner failed: {p.stderr}")
    return [json.loads(p.stdout)[i] for i in range(len(cases))]


def graph(*passes):
    return {"passes": list(passes)}


def deposit(i):
    return {"name": f"deposit_{i}", "program": f"node_4_deposit__VIEW_MODE_{i}",
            "defines": {"VIEW_MODE": float(i)}}


def ref_deposit(i):
    return {"name": f"deposit_{i}", "program": f"node_4_deposit__VIEW_MODE_{i}"}


class ExpandAcceptanceTests(unittest.TestCase):
    def test_accepted_pass_defines_variant(self):
        """The observed shape: candidate pass defines, suffixed program, no ref defines."""
        [r] = run_cases([{
            "name": "accepted",
            "ref": graph(ref_deposit(0), {"name": "blend", "program": "n_blend"}),
            "cand": graph(deposit(0), {"name": "blend", "program": "n_blend"}),
        }])
        self.assertTrue(r["accepted"], r["reason"])
        self.assertTrue(r["normalizedEqual"])

    def test_rejected_when_program_name_differs(self):
        [r] = run_cases([{
            "name": "program-differs",
            "ref": graph({"name": "deposit_0", "program": "node_4_deposit"}),
            "cand": graph(deposit(0)),
        }])
        self.assertFalse(r["accepted"])
        self.assertIn("program names differ", r["reason"])

    def test_rejected_when_define_not_encoded_in_program(self):
        [r] = run_cases([{
            "name": "not-encoded",
            "ref": graph({"name": "deposit_0", "program": "node_4_deposit"}),
            "cand": graph({"name": "deposit_0", "program": "node_4_deposit",
                           "defines": {"VIEW_MODE": 0.0}}),
        }])
        self.assertFalse(r["accepted"])
        self.assertIn("not encoded in program name", r["reason"])

    def test_rejected_when_ref_pass_also_has_defines(self):
        """A value mismatch on a pass that both sides define is a normal diff, not accepted."""
        [r] = run_cases([{
            "name": "both-define",
            "ref": graph({"name": "deposit_0", "program": "node_4_deposit__VIEW_MODE_0",
                          "defines": {"VIEW_MODE": 2}}),
            "cand": graph(deposit(0)),
        }])
        self.assertFalse(r["accepted"])

    def test_rejected_when_another_field_differs(self):
        [r] = run_cases([{
            "name": "other-field",
            "ref": graph(ref_deposit(0), {"name": "blend", "program": "n_blend"}),
            "cand": graph(deposit(0), {"name": "blend", "program": "n_blend", "count": 7}),
        }])
        self.assertFalse(r["accepted"])
        self.assertIn("passes[1]", r["reason"])

    def test_rejected_when_extra_key_in_cand_defines(self):
        [r] = run_cases([{
            "name": "extra-key",
            "ref": graph(ref_deposit(0)),
            "cand": graph({"name": "deposit_0", "program": "node_4_deposit__VIEW_MODE_0",
                           "defines": {"VIEW_MODE": 0.0, "OTHER": 1}}),
        }])
        self.assertFalse(r["accepted"])

    def test_rejected_on_prefix_collision(self):
        """VIEW_MODE:1 must not ride on a __VIEW_MODE_10 suffix."""
        [r] = run_cases([{
            "name": "prefix-collision",
            "ref": graph({"name": "deposit_0", "program": "node_4_deposit__VIEW_MODE_10"}),
            "cand": graph({"name": "deposit_0", "program": "node_4_deposit__VIEW_MODE_10",
                           "defines": {"VIEW_MODE": 1.0}}),
        }])
        self.assertFalse(r["accepted"])
        self.assertIn("not encoded in program name", r["reason"])

    def test_accepted_when_token_at_segment_boundary(self):
        """Multi-segment names still match at a real segment boundary."""
        [r] = run_cases([{
            "name": "multi-segment",
            "ref": graph({"name": "depositDefocus_1",
                          "program": "node_5_deposit__BLEND_MODE_0__BLUR_LAYER_1__VIEW_MODE_1"}),
            "cand": graph({"name": "depositDefocus_1",
                           "program": "node_5_deposit__BLEND_MODE_0__BLUR_LAYER_1__VIEW_MODE_1",
                           "defines": {"BLEND_MODE": 0, "BLUR_LAYER": 1, "VIEW_MODE": 1}}),
        }])
        self.assertTrue(r["accepted"], r["reason"])
        self.assertTrue(r["normalizedEqual"])

    def test_null_defines_is_a_plain_diff_not_a_crash(self):
        [r] = run_cases([{
            "name": "null-defines",
            "ref": graph({"name": "deposit_0", "program": "node_4_deposit"}),
            "cand": graph({"name": "deposit_0", "program": "node_4_deposit", "defines": None}),
        }])
        self.assertFalse(r["accepted"])
        self.assertIn("defines", r["reason"])

    def test_gate_consumes_the_module(self):
        """Source guard: check_expand.mjs must route every diff through this module."""
        src = GATE.read_text()
        self.assertIn("from './expand_acceptance.mjs'", src)
        self.assertRegex(src, r"classifyPassDefinesDiff\(o\.out, c\.out\)")
        self.assertNotIn("function deepEq", src)

    def test_module_rule_comment_binds_gate_and_test(self):
        """The module documents the acceptance rule the gate enforces."""
        src = MODULE.read_text()
        self.assertIn("__<KEY>_<value>", src)
        self.assertIn("classifyPassDefinesDiff", src)


if __name__ == "__main__":
    unittest.main()