"""Unit tests for scripts/parity-summary's classify/manifest/exit logic.

The entrypoint is a bash script; these tests exercise its embedded python
classification heredocs by importing them exactly as the script runs them:
the classify/is_deferred heredoc is extracted from the script and executed
with the same argv/env contract, against fixture files in a temp tree.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "parity-summary"


def _repo_file(rel):
    p = ROOT / rel
    if not p.exists():
        raise unittest.SkipTest(f"{rel} not present")
    return p


class ParitySummaryManifestTests(unittest.TestCase):
    """The ledger-extraction heredoc must fail loudly on a broken manifest."""

    def _run_extract(self, manifest_obj, text=None):
        src = SCRIPT.read_text()
        i = src.index("mapfile") if "mapfile" in src else src.index('while IFS= read -r line')
        seg = src[i:].split("<<'PYEOF'\n", 1)[1]
        heredoc = seg.split("\nPYEOF\n", 1)[0]
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            if text is not None:
                f.write(text)
            else:
                json.dump(manifest_obj, f)
            path = f.name
        r = subprocess.run([sys.executable, "-c", heredoc, path],
                           capture_output=True, text=True)
        os.unlink(path)
        return r

    @staticmethod
    def _heredoc(anchor, pattern):
        src = SCRIPT.read_text()
        i = src.index(anchor)
        m = re.search(pattern, src[i:], re.S)
        return m.group(1)

    def test_ledger_programs_extracted(self):
        ledger = [{"program": "a"}, {"program": "b"}, {"program": None},
                  {"effect": "no-program-key"}]
        r = self._run_extract(ledger)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.split(), ["a", "b"])

    def test_unreadable_manifest_exits_nonzero_with_no_output(self):
        r = self._run_extract(None, text="{not json")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_empty_manifest_exits_nonzero(self):
        r = self._run_extract([])
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_manifest_without_programs_exits_nonzero(self):
        r = self._run_extract([{"effect": "x"}, 42])
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")


class ParitySummaryClassifyTests(unittest.TestCase):
    """classify(): exact/strict/near/fail/missing per the documented contract."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "parity" / "out").mkdir(parents=True)
        self.classify_src = self._classify_heredoc()

    def _classify_heredoc(self):
        src = SCRIPT.read_text()
        i = src.index("classify ()")
        j = src.index("PYEOF\n}", i)
        return src[i:j].split("<<'PYEOF'\n", 1)[1]

    def _classify(self, case, deferrals, report=None, golden=b"G", cand=b"G"):
        out = self.root / "parity" / "out"
        if report is not None:
            (out / f"{case}.parity-summary.report.json").write_text(json.dumps(report))
        (out / f"{case}.golden.png").write_bytes(golden)
        (out / f"{case}.candidate.png").write_bytes(cand)
        env = {**os.environ, "PARITY_ROOT": str(self.root)}
        return subprocess.run([sys.executable, "-c", self.classify_src, case,
                               json.dumps(deferrals)],
                              capture_output=True, text=True, env=env,
                              cwd=tempfile.gettempdir()).stdout.strip()

    def test_exact_byte_identical_pass(self):
        got = self._classify("a", {}, report={"passed": True})
        self.assertEqual(got, "exact")

    def test_strict_nonidentical_pass(self):
        got = self._classify("a", {}, report={"passed": True}, cand=b"H")
        self.assertEqual(got, "strict")

    def test_fail_beyond_recorded_bounds(self):
        rec = {"max_abs_diff": 5.0, "ssim": 0.99}
        got = self._classify("a", {"a": rec}, report={"passed": False,
                                                      "max_abs_diff": 6.0, "ssim": 0.995})
        self.assertEqual(got, "fail")

    def test_near_within_recorded_bounds(self):
        rec = {"max_abs_diff": 5.0, "ssim": 0.99}
        got = self._classify("a", {"a": rec}, report={"passed": False,
                                                      "max_abs_diff": 4.0, "ssim": 0.995})
        self.assertEqual(got, "near")

    def test_near_requires_both_bounds_keys(self):
        got = self._classify("a", {"a": {"max_abs_diff": 5.0}},
                             report={"passed": False, "max_abs_diff": 1.0, "ssim": 0.5})
        self.assertEqual(got, "fail")

    def test_fail_without_record(self):
        got = self._classify("a", {}, report={"passed": False,
                                              "max_abs_diff": 1.0, "ssim": 1.0})
        self.assertEqual(got, "fail")

    def test_missing_report_counts_missing(self):
        out = self.root / "parity" / "out"
        (out / "a.golden.png").write_bytes(b"G")
        (out / "a.candidate.png").write_bytes(b"G")
        env = {**os.environ, "PARITY_ROOT": str(self.root)}
        r = subprocess.run([sys.executable, "-c", self.classify_src, "a", "{}"],
                           capture_output=True, text=True, env=env,
                           cwd=tempfile.gettempdir())
        self.assertEqual(r.stdout.strip(), "missing")

    def test_cwd_independence(self):
        # The defect this locks: classification must use PARITY_ROOT, not cwd.
        got = self._classify("a", {}, report={"passed": True})
        self.assertEqual(got, "exact")

    def test_deferred_only_before_render(self):
        # is_deferred (pre-render) short-circuits a deferred case; classify
        # itself never returns "defer" without a comparator failure.
        src = SCRIPT.read_text()
        i = src.index("is_deferred ()")
        heredoc = src[i:].split("<<'PYEOF'\n", 1)[1].split("\nPYEOF\n", 1)[0]
        env = {**os.environ}
        r = subprocess.run([sys.executable, "-c", heredoc, "a",
                            '{"a": {"deferred": true}}'],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.stdout.strip(), "yes")
        r = subprocess.run([sys.executable, "-c", heredoc, "a", "{}"],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.stdout.strip(), "no")
        # classify with a failing report and a deferred record still defers.
        got = self._classify("a", {"a": {"deferred": True}},
                             report={"passed": False, "max_abs_diff": 99.0,
                                     "ssim": 0.1})
        self.assertEqual(got, "defer")

    def test_empty_manifest_process_substitution_fails_closed(self):
        # The defect this locks: `mapfile < <(cmd)` swallows cmd's failure, so
        # the entrypoint must require at least one case after extraction.
        src = SCRIPT.read_text()
        self.assertIn('[ "${#CASES[@]}" -gt 0 ] || {', src)
        self.assertIn("while IFS= read -r line; do CASES+=(\"$line\")", src)

    def test_reportless_candidate_is_fail_not_missing(self):
        src = SCRIPT.read_text()
        self.assertIn("comparator wrote no report", src)


class ParitySummaryFreshArtifactTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for directory in ("scripts", "parity/programs", "parity/out", "bin"):
            (self.root / directory).mkdir(parents=True)
        shutil.copy2(SCRIPT, self.root / "scripts/parity-summary")
        (self.root / "parity/programs/a.dsl").write_text("noise(seed: 1).write(o0)\n")
        self._executable("bin/node", """#!/bin/sh
printf FRESH > "$3/a.golden.png"
printf '{}' > "$3/a.graph.json"
if [ "${MINT_FAIL:-0}" = 1 ]; then exit 1; fi
""")
        self._executable("bin/godot", "#!/bin/sh\nexit 0\n")
        self._executable("parity/run.sh", """#!/bin/sh
cp "$PARITY_FIXTURE_ROOT/parity/out/a.golden.png" "$PARITY_FIXTURE_ROOT/parity/out/a.candidate.png"
if [ "${REPORT_MODE:-write}" = write ]; then
  printf '{"passed":true}' > "$PARITY_FIXTURE_ROOT/parity/out/a.report.json"
fi
""")

    def _executable(self, relative_path, contents):
        path = self.root / relative_path
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, report_mode="write", mint_fail="0", rm_fail=False):
        if rm_fail:
            self._executable("bin/rm", "#!/bin/sh\nexit 1\n")
        env = {**os.environ,
               "NM_REFERENCE_ROOT": str(self.root / "reference"),
               "GODOT": str(self.root / "bin/godot"),
               "PYTHON": sys.executable,
               "PARITY_FIXTURE_ROOT": str(self.root),
               "REPORT_MODE": report_mode,
               "MINT_FAIL": mint_fail,
               "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"]}
        return subprocess.run([str(self.root / "scripts/parity-summary"), "a"],
                              capture_output=True, text=True, env=env)

    def test_existing_golden_is_regenerated_from_reference(self):
        out = self.root / "parity/out"
        (out / "a.golden.png").write_bytes(b"STALE")
        (out / "a.graph.json").write_text("stale")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((out / "a.golden.png").read_bytes(), b"FRESH")
        self.assertEqual((out / "a.graph.json").read_text(), "{}")
        self.assertIn("[MINT] a", result.stdout)
        self.assertFalse((out / ".parity-summary.lock").exists())

    def test_missing_new_report_cannot_reuse_previous_report(self):
        out = self.root / "parity/out"
        (out / "a.report.json").write_text('{"passed":true}')
        result = self._run(report_mode="omit")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("comparator wrote no report", result.stdout)

    def test_failed_mint_cannot_leave_partial_golden_for_comparison(self):
        out = self.root / "parity/out"
        (out / "a.golden.png").write_bytes(b"STALE")
        result = self._run(mint_fail="1")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("[SKIP] a", result.stdout)
        self.assertFalse((out / "a.golden.png").exists())

    def test_failed_cleanup_cannot_compare_old_artifacts(self):
        out = self.root / "parity/out"
        (out / "a.golden.png").write_bytes(b"STALE")
        (out / "a.graph.json").write_text("stale")
        result = self._run(mint_fail="1", rm_fail=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("[PASS] a", result.stdout)

    def test_existing_run_lock_prevents_shared_artifact_comparison(self):
        out = self.root / "parity/out"
        (out / ".parity-summary.lock").mkdir()
        (out / "a.golden.png").write_bytes(b"STALE")
        result = self._run()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("[RENDER] a", result.stdout)
        self.assertEqual((out / "a.golden.png").read_bytes(), b"STALE")


class ParitySummaryScriptContractTests(unittest.TestCase):
    """Static contract checks on the entrypoint itself."""

    def test_script_is_executable(self):
        self.assertTrue(os.access(SCRIPT, os.X_OK))

    def test_summary_line_format(self):
        src = SCRIPT.read_text()
        self.assertIn('PARITY-SUMMARY {"expected"', src)
        for key in ("executed", "exact", "strict", "near", "defer", "skip",
                    "fail", "missing"):
            self.assertIn(key, src)

    def test_exit0_requires_all_passed(self):
        src = SCRIPT.read_text()
        self.assertIn('[ "$executed" -eq "$EXPECTED" ]', src)
        self.assertIn('[ "$((exact+strict))" -eq "$EXPECTED" ]', src)
        self.assertIn('[ "$near" -eq 0 ]', src)

    def test_bash_syntax(self):
        r = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_stale_report_cleared_before_render(self):
        src = SCRIPT.read_text()
        self.assertIn("rm -f \"$ROOT/parity/out/$case.parity-summary.report.json\"",
                      src)


if __name__ == "__main__":
    unittest.main()
