"""Unit tests for the bound_ms TERM-then-SIGKILL escalation.

bound_ms in parity/run.sh, scripts/parity-summary and scripts/test bounds
every engine and network step. A child that ignores TERM must not survive the
bound: the bound escalates to SIGKILL 10s after the deadline on every branch,
so a stalled launch always exits 124 as a named failure instead of burning the
engine command's whole deadline. These tests extract the function text from
each changed script and run the real function against a TERM-ignoring child.
"""
import os
import re
import shutil
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


def _extract_named(script: Path, name: str) -> str:
    """Return a bound function's text, also when it is defined indented."""
    src = script.read_text()
    m = re.search(rf"^([ \t]*){name} \(\) \{{.*?^\1\}}", src, re.S | re.M)
    if not m:
        raise AssertionError(f"no {name} function in {script}")
    return m.group(0)


class BoundMsEscalationTests(unittest.TestCase):
    """The bound must kill a TERM-ignoring child and exit 124."""

    def _run_bound(self, script: Path, bound_ms: int, extra_path: str = None,
                   child: str = IGNORE_TERM):
        fn = _extract(script)
        cmd = (
            f"{fn}\n"
            f"bound_ms {bound_ms} bash -c '{child}'\n"
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

    def test_scripts_test_escalates_to_sigkill(self):
        self._escalates("scripts/test")

    def test_node_fallback_branch_escapes_term_ignoring_child(self):
        """With no timeout(1) on PATH, the node spawnSync branch must still
        end the bound (killSignal SIGKILL) and exit 124. The child also
        writes a marker before it sleeps: a fallback whose argv is broken
        launches nothing and exits 124 at once, so only the marker proves
        the branch really ran the bounded command."""
        script = ROOT / "parity" / "run.sh"
        self._node_fallback_runs_child(script)

    def test_scripts_test_node_fallback_launches_the_bounded_command(self):
        """Same contract for the scripts/test copy added beside the smoke
        bound: with no timeout(1) on PATH the node branch must launch the
        bounded child, not exit 124 without running it."""
        self._node_fallback_runs_child(ROOT / "scripts" / "test")

    def _node_fallback_runs_child(self, script: Path):
        with tempfile.TemporaryDirectory() as d:
            for exe in ("bash", "node"):
                src = next(Path(p) for p in ("/bin/bash", "/usr/bin/bash")
                           if Path(p).exists()) if exe == "bash" else \
                    subprocess.run(["sh", "-c", "command -v node"],
                                   capture_output=True, text=True).stdout.strip()
                link = Path(d) / exe
                if not link.exists() and src:
                    link.symlink_to(src)
            # `:` and redirection are bash builtins and sleep(1) is named by
            # absolute path: the restricted PATH has neither.
            marker = Path(d) / "child-ran"
            child = f'trap "" TERM; : > {marker}; /bin/sleep 120'
            r, elapsed = self._run_bound(script, 1000, extra_path=d, child=child)
            ran = marker.exists()
        self.assertIn("RC=124", r.stdout, f"exit: {r.returncode} {r.stderr}")
        self.assertTrue(ran,
                        "the node fallback exited 124 without running the bounded command")
        self.assertLess(elapsed, 40, "node fallback did not end the bound")


class NodeFallbackLaunchTests(unittest.TestCase):
    """With no timeout(1) or gtimeout(1) on PATH (a macOS host without
    coreutils), each bound helper falls back to node's spawnSync. The
    fallback must launch the bounded command and return its exit code, and
    it must still end a stalled command with 124. A fallback that passes an
    extra word before the command launches nothing and exits 124 at once."""

    def _bound(self, script: Path, name: str, bound_ms: int, child: str):
        fn = _extract_named(script, name)
        node = shutil.which("node")
        if not node:
            raise unittest.SkipTest("node is not installed")
        with tempfile.TemporaryDirectory() as d:
            # PATH holds only a node launcher, written as a regular file.
            launcher = Path(d) / "node"
            launcher.write_text(f'#!/bin/sh\nexec "{node}" "$@"\n')
            launcher.chmod(0o755)
            marker = Path(d) / "child-ran"
            body = child.replace("MARKER", str(marker))
            cmd = f"{fn}\n{name} {bound_ms} /bin/sh -c '{body}'\necho RC=$?\n"
            start = time.monotonic()
            r = subprocess.run(["/bin/bash", "-c", cmd], capture_output=True,
                               text=True, timeout=60, env={"PATH": d})
            elapsed = time.monotonic() - start
            ran = marker.exists()
        return r, elapsed, ran

    def _launches_and_bounds(self, rel: str, name: str):
        script = ROOT / rel
        r, _, ran = self._bound(script, name, 20000, ": > MARKER; exit 3")
        self.assertIn("RC=3", r.stdout, f"exit: {r.returncode} {r.stderr}")
        self.assertTrue(ran, "the node fallback did not run the bounded command")
        r, elapsed, ran = self._bound(script, name, 1000,
                                      'trap "" TERM; : > MARKER; exec /bin/sleep 120')
        self.assertIn("RC=124", r.stdout, f"exit: {r.returncode} {r.stderr}")
        self.assertTrue(ran, "the node fallback did not run the bounded command")
        self.assertLess(elapsed, 40, "the node fallback did not end the bound")

    def test_run_samples_node_fallback_launches_the_timed_render(self):
        self._launches_and_bounds("parity/run_samples.sh", "bound_ms")

    def test_comparator_provisioning_node_fallback_launches_the_install(self):
        self._launches_and_bounds("parity/ensure_compare_python.sh", "bound")

    def test_parity_summary_node_fallback_launches_the_command(self):
        self._launches_and_bounds("scripts/parity-summary", "bound_ms")


if __name__ == "__main__":
    unittest.main()
