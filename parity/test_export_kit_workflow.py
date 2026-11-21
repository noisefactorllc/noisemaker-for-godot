"""The weekly export-kit run also runs the windowed suites.

.github/workflows/export-kit.yml's parity job runs on the self-hosted GPU
group with a window and the verified Godot build. Its windowed step runs
`scripts/test --godot-windowed` only on the schedule or a manual dispatch,
after Godot is in place, and the kit dispatch waits for the job. The
workflow is read as text, because the engine-free suite has no YAML parser.
These checks guard against accidental regressions (a deleted step, a widened
trigger, a soft fail, a dropped argument); they do not pin the job's text, so
a reviewed edit such as an action pin bump still passes.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "export-kit.yml"
CONDITION = "if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'"


def job(text: str, name: str) -> list:
    """The lines of a job, up to the next job header or top-level key."""
    lines = text.splitlines()
    start = lines.index(f"  {name}:")
    block = []
    for line in lines[start + 1:]:
        if re.match(r"^ {2}[A-Za-z0-9_-]+:\s*$", line) or re.match(r"^[^ #]", line):
            break
        block.append(line)
    return block


def steps(block: list) -> list:
    """Each `      - ` step of a job as its own text."""
    found = []
    for line in block:
        if line.startswith("      - "):
            found.append([line])
        elif found and (line.startswith("        ") or not line.strip()):
            found[-1].append(line)
    return ["\n".join(step) for step in found]


class WindowedStepTests(unittest.TestCase):

    def setUp(self):
        text = WORKFLOW.read_text()
        self.assertIn("  parity:", text.splitlines(), "export-kit.yml has no parity job")
        self.parity = job(text, "parity")
        self.dispatch = job(text, "dispatch")
        self.steps = steps(self.parity)
        self.windowed = [step for step in self.steps if "scripts/test --godot-windowed" in step]

    def test_the_parity_job_runs_the_windowed_suites_once(self):
        self.assertEqual(len(self.windowed), 1, "the parity job runs scripts/test --godot-windowed once")

    def test_the_windowed_step_runs_only_on_the_schedule_or_a_dispatch(self):
        conditions = [line.strip() for line in self.windowed[0].splitlines() if line.strip().startswith("if:")]
        self.assertEqual(conditions, [CONDITION])

    def test_the_windowed_step_runs_after_godot_is_in_place(self):
        godot = next(i for i, step in enumerate(self.steps) if "name: Download and verify Godot" in step)
        self.assertGreater(self.steps.index(self.windowed[0]), godot)

    def test_the_windowed_step_uses_the_parity_venv(self):
        self.assertIn('PATH="$PWD/parity/.venv/bin:$PATH" scripts/test --godot-windowed', self.windowed[0])

    def test_nothing_in_the_parity_job_soft_fails(self):
        self.assertNotIn("continue-on-error", "\n".join(self.parity), "neither the job nor a step may soft-fail")
        self.assertNotRegex(self.windowed[0], r"\|\|\s*true", "the windowed command must not ignore its exit status")

    def test_the_kit_dispatch_waits_for_the_parity_job(self):
        needs = [line.strip() for line in self.dispatch if line.startswith("    needs:")]
        self.assertEqual(len(needs), 1)
        self.assertRegex(needs[0], r"^needs: (parity|\[([^\]]*,\s*)?parity(\s*,[^\]]*)?\])$")


if __name__ == "__main__":
    unittest.main()
