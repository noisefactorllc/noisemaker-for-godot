"""The weekly export-kit run also runs the windowed suites.

.github/workflows/export-kit.yml's parity job runs on the self-hosted GPU
group with a window and the verified Godot build. Its windowed step runs
`scripts/test --godot-windowed` only on the schedule or a manual dispatch,
after Godot is in place, and nothing in the job may soft-fail. The workflow
is read as text, because the engine-free suite has no YAML parser.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "export-kit.yml"
CONDITION = "if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'"


def job(text: str, name: str) -> list:
    lines = text.splitlines()
    start = lines.index(f"  {name}:")
    block = []
    for line in lines[start + 1:]:
        if line and not line.startswith("   ") and not line.startswith("#"):
            break
        block.append(line)
    return block


def steps(block: list) -> list:
    """Each `      - ` step of a job as its own text."""
    found, current = [], None
    for line in block:
        if line.startswith("      - "):
            current = [line]
            found.append(current)
        elif current is not None and (line.startswith("        ") or not line.strip()):
            current.append(line)
        else:
            current = None
    return ["\n".join(step) for step in found]


class WindowedStepTests(unittest.TestCase):

    def setUp(self):
        self.parity = job(WORKFLOW.read_text(), "parity")
        self.steps = steps(self.parity)
        self.windowed = [step for step in self.steps if "scripts/test --godot-windowed" in step]

    def test_the_parity_job_runs_the_windowed_suites_once(self):
        self.assertEqual(len(self.windowed), 1, "the parity job runs scripts/test --godot-windowed once")

    def test_the_windowed_step_runs_only_on_the_schedule_or_a_dispatch(self):
        conditions = [line.strip() for line in self.windowed[0].splitlines() if line.strip().startswith("if:")]
        self.assertEqual(conditions, [CONDITION])

    def test_the_windowed_step_runs_after_godot_is_in_place(self):
        names = [re.search(r"name: (.+)", step).group(1) if "name:" in step else "" for step in self.steps]
        godot = names.index("Download and verify Godot")
        self.assertGreater(self.steps.index(self.windowed[0]), godot)

    def test_the_windowed_step_uses_the_parity_venv(self):
        self.assertIn('PATH="$PWD/parity/.venv/bin:$PATH"', self.windowed[0])

    def test_nothing_in_the_parity_job_soft_fails(self):
        self.assertNotIn("continue-on-error", "\n".join(self.parity))


if __name__ == "__main__":
    unittest.main()
