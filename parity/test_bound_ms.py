"""Unit tests for the bound_ms TERM-then-SIGKILL escalation.

bound_ms in parity/run.sh and scripts/parity-summary bounds every engine and
network step. A child that ignores TERM must not survive the bound: the bound
escalates to SIGKILL 10s after the deadline on every branch, so a stalled
launch always exits 124 as a named failure instead of burning the engine
command's whole deadline. These tests extract the function text from each
changed script and run the real function against a TERM-ignoring child.
"""
import os
import re
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A child that ignores TERM and sleeps far past any reasonable deadline.
IGNORE_TERM = 'trap "" TERM; sleep 120'


def _extract(script: Path) -> str:
    """Return the exact bound_ms function text from a script."""
    src = script.read_text()
    m = re.search(r"^bound_ms \(\) \{.*?^\}", src, re.S | re.M)
    if not m:
        raise unittest.SkipTest(f"no bound_ms in {script}")
    return m.group(0)


class BoundMsEscalationTests(unittest.TestCase):
    """The bound must kill a TERM-ignoring child and exit 124."""

    def _run_bound(self, script: Path, bound_ms: int, extra_path: str = None):
        fn = _extract(script)
        cmd = (
            f"{fn}\n"
            f"bound_ms {bound_ms} bash -c '{IGNORE_TERM}'\n"
            f"echo RC=$?\n"
        )
        env = dict(os.environ)
        if extra_path is not None:
            env["PATH"] = extra_path
        start = time.monotonic()
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                           timeout=60, env=env)
        elapsed = time.monotonic() - start
        return r, elapsed

    def _escalates(self, rel):
        r, elapsed = self._run_bound(ROOT / rel, 1000)
        self.assertIn("RC=124", r.stdout, f"exit: {r.returncode} {r.stderr}")
        self.assertLess(elapsed, 40, "SIGKILL escalation did not fire in time")

    def test_run_sh_escalates_to_sigkill(self):
        self._escalates("parity/run.sh")

    def test_parity_summary_escalates_to_sigkill(self):
        self._escalates("scripts/parity-summary")

    def test_node_fallback_branch_escapes_term_ignoring_child(self):
        """With no timeout(1) on PATH, the node spawnSync branch must still
        end the bound (killSignal SIGKILL) and exit 124."""
        script = ROOT / "parity" / "run.sh"
        with tempfile.TemporaryDirectory() as d:
            for exe in ("bash", "node"):
                src = next(Path(p) for p in ("/bin/bash", "/usr/bin/bash")
                           if Path(p).exists()) if exe == "bash" else \
                    subprocess.run(["sh", "-c", "command -v node"],
                                   capture_output=True, text=True).stdout.strip()
                link = Path(d) / exe
                if not link.exists() and src:
                    link.symlink_to(src)
            r, elapsed = self._run_bound(script, 1000, extra_path=d)
        self.assertIn("RC=124", r.stdout, f"exit: {r.returncode} {r.stderr}")
        self.assertLess(elapsed, 40, "node fallback did not end the bound")


if __name__ == "__main__":
    unittest.main()
