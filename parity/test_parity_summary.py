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
    """classify(): exact/strict/near/fail/missing per the published policy."""

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

    def _classify(self, case, report=None, golden=b"G", cand=b"G",
                  tolerance=2.001, ssim_min=0.98):
        out = self.root / "parity" / "out"
        if report is not None:
            (out / f"{case}.parity-summary.report.json").write_text(json.dumps(report))
        (out / f"{case}.golden.png").write_bytes(golden)
        (out / f"{case}.candidate.png").write_bytes(cand)
        env = {**os.environ, "PARITY_ROOT": str(self.root)}
        return subprocess.run([sys.executable, "-c", self.classify_src, case,
                               str(tolerance), str(ssim_min), ""],
                              capture_output=True, text=True, env=env,
                              cwd=tempfile.gettempdir()).stdout.strip()

    @staticmethod
    def _report(case="a", diff=0, ssim=1.0, tolerance=2.001, ssim_min=0.98,
                passed=True):
        return {"name": case, "max_abs_diff": diff, "ssim": ssim,
                "tolerance": tolerance, "ssim_min": ssim_min, "passed": passed}

    def test_exact_byte_identical_pass(self):
        got = self._classify("a", report=self._report())
        self.assertEqual(got, "exact")

    def test_strict_nonidentical_pass(self):
        got = self._classify("a", report=self._report(diff=1), cand=b"H")
        self.assertEqual(got, "strict")

    def test_fail_beyond_published_bounds(self):
        got = self._classify("a", report=self._report(diff=7, tolerance=6),
                             cand=b"H", tolerance=6)
        self.assertEqual(got, "fail")

    def test_near_within_published_bounds(self):
        got = self._classify("a", report=self._report(diff=4, tolerance=6),
                             cand=b"H", tolerance=6)
        self.assertEqual(got, "near")

    def test_near_requires_matching_policy_in_comparator_report(self):
        got = self._classify("a", report=self._report(diff=4, tolerance=7),
                             cand=b"H", tolerance=6)
        self.assertEqual(got, "fail")

    def test_failed_comparator_cannot_become_near(self):
        got = self._classify("a", report=self._report(diff=4, tolerance=6,
                                                      passed=False),
                             cand=b"H", tolerance=6)
        self.assertEqual(got, "fail")

    def test_nonfinite_metric_cannot_become_near(self):
        got = self._classify("a", report=self._report(diff=float("nan"),
                                                      tolerance=6),
                             cand=b"H", tolerance=6)
        self.assertEqual(got, "fail")

    def test_missing_report_counts_missing(self):
        out = self.root / "parity" / "out"
        (out / "a.golden.png").write_bytes(b"G")
        (out / "a.candidate.png").write_bytes(b"G")
        env = {**os.environ, "PARITY_ROOT": str(self.root)}
        r = subprocess.run([sys.executable, "-c", self.classify_src,
                            "a", "2.001", "0.98", ""],
                           capture_output=True, text=True, env=env,
                           cwd=tempfile.gettempdir())
        self.assertEqual(r.stdout.strip(), "missing")

    def test_cwd_independence(self):
        # The defect this locks: classification must use PARITY_ROOT, not cwd.
        got = self._classify("a", report=self._report())
        self.assertEqual(got, "exact")

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
        shutil.copy2(ROOT / "parity/sweep.sh", self.root / "parity/sweep.sh")
        (self.root / "parity/programs/a.dsl").write_text("noise(seed: 1).write(o0)\n")
        self._executable("bin/node", """#!/bin/sh
case=${2##*/}
case=${case%.dsl}
printf '{}' > "$3/$case.graph.json"
shift 3
run=0; every=0
while [ "$#" -gt 0 ]; do
  if [ "$1" = --run-seconds ]; then run=$2; shift 2
  elif [ "$1" = --sample-every ]; then every=$2; shift 2
  else shift; fi
done
if [ "$run" -gt 0 ] && [ "$every" -gt 0 ]; then
  t=$every
  while [ "$t" -le "$run" ]; do
    printf FRESH > "$PARITY_FIXTURE_ROOT/parity/out/$case.golden.t$t.png"
    t=$((t + every))
  done
else
  printf FRESH > "$PARITY_FIXTURE_ROOT/parity/out/$case.golden.png"
fi
if [ "${MINT_FAIL:-0}" = 1 ]; then exit 1; fi
""")
        self._executable("bin/godot", "#!/bin/sh\nexit 0\n")
        self._executable("parity/run.sh", """#!/bin/sh
cp "$PARITY_FIXTURE_ROOT/parity/out/$1.golden.png" "$PARITY_FIXTURE_ROOT/parity/out/$1.candidate.png"
if [ "${REPORT_MODE:-write}" = write ] || [ "${REPORT_MODE:-write}" = nonzero ]; then
  printf '{"passed":true,"name":"%s","max_abs_diff":0,"ssim":1,"tolerance":%s,"ssim_min":%s}' "$1" "$2" "$3" > "$PARITY_FIXTURE_ROOT/parity/out/$1.report.json"
elif [ "${REPORT_MODE:-write}" = near ]; then
  printf DIFFERENT > "$PARITY_FIXTURE_ROOT/parity/out/$1.candidate.png"
  printf '{"passed":true,"name":"%s","max_abs_diff":7,"ssim":0.9999,"tolerance":%s,"ssim_min":%s}' "$1" "$2" "$3" > "$PARITY_FIXTURE_ROOT/parity/out/$1.report.json"
elif [ "${REPORT_MODE:-write}" = malformed ]; then
  printf 'not-json' > "$PARITY_FIXTURE_ROOT/parity/out/$1.report.json"
fi
if [ "${REPORT_MODE:-write}" = nonzero ]; then exit 1; fi
""")
        self._executable("parity/run_samples.sh", """#!/bin/sh
name=$1; tol=$2; ssim=$3; run=$4; every=$5
t=$every
while [ "$t" -le "$run" ]; do
  if [ "$t" = "${TIMED_NEAR_SAMPLE:-}" ]; then
    printf DIFFERENT > "$PARITY_FIXTURE_ROOT/parity/out/$name.candidate.t$t.png"
    printf '{"passed":true,"name":"%s_t%s","max_abs_diff":7,"ssim":0.9999,"tolerance":%s,"ssim_min":%s}' "$name" "$t" "$tol" "$ssim" > "$PARITY_FIXTURE_ROOT/parity/out/$name.report.t$t.json"
  elif [ "$t" = "${TIMED_BAD_SAMPLE:-}" ]; then
    printf DIFFERENT > "$PARITY_FIXTURE_ROOT/parity/out/$name.candidate.t$t.png"
    printf '{"passed":true,"name":"%s_t%s","max_abs_diff":11,"ssim":0.9999,"tolerance":%s,"ssim_min":%s}' "$name" "$t" "$tol" "$ssim" > "$PARITY_FIXTURE_ROOT/parity/out/$name.report.t$t.json"
  else
    printf FRESH > "$PARITY_FIXTURE_ROOT/parity/out/$name.candidate.t$t.png"
    printf '{"passed":true,"name":"%s_t%s","max_abs_diff":0,"ssim":1,"tolerance":%s,"ssim_min":%s}' "$name" "$t" "$tol" "$ssim" > "$PARITY_FIXTURE_ROOT/parity/out/$name.report.t$t.json"
  fi
  t=$((t + every))
done
echo "=== SAMPLES: $name $((run/every))/$((run/every)) pass ==="
""")

    def _executable(self, relative_path, contents):
        path = self.root / relative_path
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, report_mode="write", mint_fail="0", rm_fail=False, case="a",
             timed_near_sample="", timed_bad_sample=""):
        if rm_fail:
            self._executable("bin/rm", "#!/bin/sh\nexit 1\n")
        env = {**os.environ,
               "NM_REFERENCE_ROOT": str(self.root / "reference"),
               "GODOT": str(self.root / "bin/godot"),
               "PYTHON": sys.executable,
               "PARITY_FIXTURE_ROOT": str(self.root),
               "REPORT_MODE": report_mode,
               "MINT_FAIL": mint_fail,
               "TIMED_NEAR_SAMPLE": timed_near_sample,
               "TIMED_BAD_SAMPLE": timed_bad_sample,
               "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"]}
        return subprocess.run([str(self.root / "scripts/parity-summary"), case],
                              capture_output=True, text=True, env=env)

    def test_existing_spiral_policy_accepts_rotated_boundary_ties(self):
        (self.root / "parity/programs/spiralRotated.dsl").write_text(
            "noise(seed: 1).spiral(rotation: 30).write(o0)\n")
        result = self._run(report_mode="near", case="spiralRotated")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("[NEAR] spiralRotated", result.stdout)
        self.assertIn('"executed":1,"exact":0,"strict":0,"near":1', result.stdout)
        report = json.loads((self.root / "parity/out/spiralRotated.report.json").read_text())
        self.assertEqual(report["tolerance"], 8)
        self.assertEqual(report["ssim_min"], 0.99)

    def test_policy_lookup_has_one_machine_readable_line(self):
        self._executable("bin/uname", "#!/bin/sh\nif [ \"$1\" = -s ]; then echo Linux; else echo x86_64; fi\n")
        env = {**os.environ, "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"]}
        result = subprocess.run(["bash", str(self.root / "parity/sweep.sh"),
                                 "--policy", "spiral"], capture_output=True, text=True,
                                env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1, result.stdout)
        self.assertEqual(result.stdout.split("\t")[:2], ["8", "0.99"])

    def test_timed_case_uses_sweep_sample_policy(self):
        (self.root / "parity/programs/navierStokes.dsl").write_text("noise(seed: 1).write(o0)\n")
        result = self._run(case="navierStokes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('"expected":1,"executed":1,"exact":1', result.stdout)
        self.assertTrue((self.root / "parity/out/navierStokes.report.t30.json").exists())
        self.assertFalse((self.root / "parity/out/navierStokes.report.json").exists())
        report = json.loads((self.root / "parity/out/navierStokes.report.t30.json").read_text())
        self.assertEqual(report["tolerance"], 10.001)
        self.assertEqual(report["ssim_min"], 0.999)
        self.assertFalse((self.root / "parity/out/navierStokes.golden.png").exists())

    def test_timed_case_accepts_near_sample_within_named_policy(self):
        (self.root / "parity/programs/navierStokes.dsl").write_text("noise(seed: 1).write(o0)\n")
        result = self._run(case="navierStokes", timed_near_sample="25")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('"near":1', result.stdout)

    def test_timed_case_rejects_sample_beyond_named_policy(self):
        (self.root / "parity/programs/navierStokes.dsl").write_text("noise(seed: 1).write(o0)\n")
        result = self._run(case="navierStokes", timed_bad_sample="25")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('"fail":1', result.stdout)

    def test_timed_case_rejects_missing_sample_after_render(self):
        (self.root / "parity/programs/temporalAberration.dsl").write_text("noise(seed: 1).write(o0)\n")
        self._executable("parity/run_samples.sh", "#!/bin/sh\nexit 0\n")
        result = self._run(case="temporalAberration")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('"missing":1', result.stdout)

    def test_malformed_comparator_report_counts_as_failure(self):
        result = self._run(report_mode="malformed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[FAIL] a", result.stdout)
        self.assertIn('"fail":1', result.stdout)

    def test_nonzero_runner_cannot_pass_from_report_alone(self):
        result = self._run(report_mode="nonzero")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[FAIL] a", result.stdout)
        self.assertIn('"fail":1', result.stdout)

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
        self.assertIn('[ "$((exact+strict+near))" -eq "$EXPECTED" ]', src)
        self.assertIn('[ "$fail" -eq 0 ]', src)

    def test_bash_syntax(self):
        r = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_stale_report_cleared_before_render(self):
        src = SCRIPT.read_text()
        self.assertIn("rm -f \"$ROOT/parity/out/$case.parity-summary.report.json\"",
                      src)


if __name__ == "__main__":
    unittest.main()
