#!/usr/bin/env python3
"""App-free regression tests for the shell parity gate contract."""

import os
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


class HarnessContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nm-godot-harness-"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_sweep_exits_nonzero_when_a_case_fails(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        shutil.copy2(REPO / "parity" / "sweep.sh", parity / "sweep.sh")
        ledger_writer = REPO / "parity" / "write-ledger.py"
        if ledger_writer.exists():
            shutil.copy2(ledger_writer, parity / "write-ledger.py")
        shutil.copy2(REPO / "parity" / "make-batch-manifest.py", parity / "make-batch-manifest.py")
        (parity / "programs" / "forcedFailure.dsl").write_text(
            "noise().chrome().write(o0)\n"
        )
        (parity / "out" / "forcedFailure.golden.png").touch()
        runner = parity / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "echo '[FAIL] forcedFailure: injected comparator failure'\n"
            "exit 1\n"
        )
        runner.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false"},
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FAILED: forcedFailure", result.stdout)
        ledger = json.loads((parity / "ledger.json").read_text())
        self.assertEqual(ledger[0]["program"], "forcedFailure")
        self.assertEqual(ledger[0]["verdict"], "FAIL")
        self.assertFalse(ledger[0]["passed"])
        self.assertIn("comparison", ledger[0]["policy"]["reason"])

    def test_sweep_counts_a_required_dsl_with_no_golden_as_failure(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        for helper in ("sweep.sh", "write-ledger.py", "make-batch-manifest.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        (parity / "programs" / "missingGolden.dsl").write_text(
            "noise().chrome().write(o0)\n"
        )

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false", "SKIP_RENDER": "1"},
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no golden", result.stdout.lower())
        ledger = json.loads((parity / "ledger.json").read_text())
        self.assertEqual(ledger[0]["program"], "missingGolden")
        self.assertEqual(ledger[0]["verdict"], "FAIL")

    def test_sweep_records_chaos_as_distinct_from_policy_skip(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        shutil.copy2(REPO / "parity" / "sweep.sh", parity / "sweep.sh")
        ledger_writer = REPO / "parity" / "write-ledger.py"
        if ledger_writer.exists():
            shutil.copy2(ledger_writer, parity / "write-ledger.py")
        shutil.copy2(REPO / "parity" / "make-batch-manifest.py", parity / "make-batch-manifest.py")
        (parity / "programs" / "reactionDiffusion.dsl").write_text(
            "noise().reactionDiffusion().write(o0)\n"
        )
        (parity / "out" / "reactionDiffusion.golden.png").touch()

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false"},
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ledger = json.loads((parity / "ledger.json").read_text())
        self.assertEqual(ledger[0]["verdict"], "CHAOS")
        self.assertFalse(ledger[0]["passed"])
        self.assertTrue(ledger[0]["skipped"])
        self.assertIn("non-determinism", ledger[0]["policy"]["reason"])

    def test_ledger_marks_only_explicit_bounded_exceptions_near(self):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        shutil.copy2(REPO / "parity" / "write-ledger.py", parity / "write-ledger.py")
        (parity / "out" / "edge.report.json").write_text(json.dumps({
            "name": "edge",
            "passed": True,
            "max_abs_diff": 3,
            "mean_abs_diff": 0.01,
            "ssim": 0.999,
            "tolerance": 8,
            "ssim_min": 0.98,
        }))
        results = self.tmp / "results.tsv"
        results.write_text(
            "edge\tAUTO\t8\t0.98\ttexture-coordinate boundary tie\n"
        )

        subprocess.run([
            "python3", str(parity / "write-ledger.py"),
            "--root", str(self.tmp), "--results", str(results),
            "--output", "parity/ledger.json",
        ], check=True)

        row = json.loads((parity / "ledger.json").read_text())[0]
        self.assertEqual(row["verdict"], "NEAR")
        self.assertTrue(row["passed"])
        self.assertFalse(row["skipped"])
        self.assertEqual(row["policy"]["tolerance"], 8)
        self.assertEqual(row["policy"]["strict_tolerance"], 2.001)

    def test_ledger_records_timed_sample_evidence_instead_of_nonexistent_single_frame(self):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / "programs").mkdir()
        shutil.copy2(REPO / "parity" / "write-ledger.py", parity / "write-ledger.py")
        (parity / "programs" / "temporalAberration.dsl").write_text(
            "noise().temporalAberration().write(o0)\n"
        )
        for second, diff in ((10, 1), (20, 2), (30, 1)):
            (parity / "out" / f"temporalAberration.golden.t{second}.png").touch()
            (parity / "out" / f"temporalAberration.candidate.t{second}.png").touch()
            (parity / "out" / f"temporalAberration.report.t{second}.json").write_text(json.dumps({
                "name": f"temporalAberration_t{second}",
                "passed": True,
                "max_abs_diff": diff,
                "mean_abs_diff": 0.1,
                "ssim": 0.9999,
                "tolerance": 2.001,
                "ssim_min": 0.98,
            }))
        results = self.tmp / "timed-results.tsv"
        results.write_text(
            "temporalAberration\tTIMED\t2.001\t0.98\ttimed delay-line samples passed\n"
        )

        subprocess.run([
            "python3", str(parity / "write-ledger.py"),
            "--root", str(self.tmp), "--results", str(results),
            "--output", "parity/ledger.json",
        ], check=True)

        row = json.loads((parity / "ledger.json").read_text())[0]
        self.assertEqual(row["verdict"], "PASS")
        self.assertEqual(row["max_abs_diff"], 2)
        self.assertEqual(len(row["samples"]), 3)
        self.assertIsInstance(row["golden"], list)
        self.assertTrue(all(Path(self.tmp / path).exists() for path in row["golden"]))

    def test_sweep_routes_navier_stokes_through_six_timed_samples(self):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / "programs").mkdir()
        for helper in ("sweep.sh", "write-ledger.py", "make-batch-manifest.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        (parity / "programs" / "navierStokes.dsl").write_text(
            "noise().navierStokes().write(o0)\n"
        )
        for second in (5, 10, 15, 20, 25, 30):
            (parity / "out" / f"navierStokes.golden.t{second}.png").touch()
            (parity / "out" / f"navierStokes.candidate.t{second}.png").touch()
            (parity / "out" / f"navierStokes.report.t{second}.json").write_text(json.dumps({
                "name": f"navierStokes_t{second}",
                "passed": True,
                "max_abs_diff": 8,
                "mean_abs_diff": 0.1,
                "ssim": 0.9999,
                "tolerance": 10.001,
                "ssim_min": 0.999,
            }))
        runner = parity / "run_samples.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "echo '=== SAMPLES: navierStokes 6/6 pass (tol=10.001 ssim>=0.999) ==='\n"
        )
        runner.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false", "SKIP_RENDER": "1"},
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        row = json.loads((parity / "ledger.json").read_text())[0]
        self.assertEqual(row["program"], "navierStokes")
        self.assertEqual(row["verdict"], "NEAR")
        self.assertEqual(len(row["samples"]), 6)

    def test_one_batch_manifest_renders_both_timed_effects_and_clears_stale_samples(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        manifest_builder = parity / "make-batch-manifest.py"
        shutil.copy2(REPO / "parity" / "make-batch-manifest.py", manifest_builder)
        for name in ("temporalAberration", "navierStokes"):
            (parity / "programs" / f"{name}.dsl").write_text(
                f"noise().{name}().write(o0)\n"
            )
            (parity / "out" / f"{name}.candidate.t5.png").touch()
            (parity / "out" / f"{name}.candidate.t30.png").touch()
        manifest_path = self.tmp / "batch.json"

        result = subprocess.run([
            "python3", str(manifest_builder), "--root", str(self.tmp),
            "--output", str(manifest_path), "--size", "256",
        ], capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        entries = {entry["name"]: entry for entry in json.loads(manifest_path.read_text())["entries"]}
        self.assertEqual(set(entries), {"temporalAberration", "navierStokes"})
        self.assertEqual(entries["temporalAberration"]["run_seconds"], 30)
        self.assertEqual(entries["temporalAberration"]["sample_every"], 10)
        self.assertEqual(entries["navierStokes"]["run_seconds"], 30)
        self.assertEqual(entries["navierStokes"]["sample_every"], 5)
        self.assertEqual(list((parity / "out").glob("*.candidate.t*.png")), [])

    def test_ledger_rejects_timed_report_with_mismatched_policy(self):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / "programs").mkdir()
        shutil.copy2(REPO / "parity" / "write-ledger.py", parity / "write-ledger.py")
        (parity / "programs" / "navierStokes.dsl").write_text(
            "noise().navierStokes().write(o0)\n"
        )
        (parity / "out" / "navierStokes.golden.t5.png").touch()
        (parity / "out" / "navierStokes.candidate.t5.png").touch()
        (parity / "out" / "navierStokes.report.t5.json").write_text(json.dumps({
            "name": "navierStokes_t5",
            "passed": True,
            "max_abs_diff": 7,
            "mean_abs_diff": 0.1,
            "ssim": 0.9999,
            "tolerance": 255,
            "ssim_min": 0,
        }))
        results = self.tmp / "timed-results.tsv"
        results.write_text(
            "navierStokes\tTIMED\t10.001\t0.999\ttimed fluid samples passed\n"
        )

        result = subprocess.run([
            "python3", str(parity / "write-ledger.py"),
            "--root", str(self.tmp), "--results", str(results),
            "--output", "parity/ledger.json",
        ], capture_output=True, text=True)

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        row = json.loads((parity / "ledger.json").read_text())[0]
        self.assertEqual(row["verdict"], "FAIL")

    def test_ledger_mode_comes_from_explicit_effect_arguments(self):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / "programs").mkdir()
        shutil.copy2(REPO / "parity" / "write-ledger.py", parity / "write-ledger.py")
        program = "ditherReferenceErrorDiffusion"
        (parity / "programs" / f"{program}.dsl").write_text(
            "noise().dither(type: errorDiffusion).write(o0)\n"
        )
        (parity / "out" / f"{program}.report.json").write_text(json.dumps({
            "name": program,
            "passed": True,
            "max_abs_diff": 1,
            "mean_abs_diff": 0.1,
            "ssim": 0.9999,
            "tolerance": 2.001,
            "ssim_min": 0.98,
        }))
        results = self.tmp / "mode-results.tsv"
        results.write_text(
            f"{program}\tAUTO\t2.001\t0.98\tstrict comparison\n"
        )

        subprocess.run([
            "python3", str(parity / "write-ledger.py"),
            "--root", str(self.tmp), "--results", str(results),
            "--output", "parity/ledger.json",
        ], check=True)

        row = json.loads((parity / "ledger.json").read_text())[0]
        self.assertEqual(row["effect"], "filter/dither")
        self.assertEqual(row["mode"], "type: errorDiffusion")

    def test_sweep_renders_multiple_cases_in_one_godot_launch(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        for helper in ("sweep.sh", "write-ledger.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        manifest_builder = REPO / "parity" / "make-batch-manifest.py"
        if manifest_builder.exists():
            shutil.copy2(manifest_builder, parity / "make-batch-manifest.py")
        for name in ("chrome", "stamp"):
            (parity / "programs" / f"{name}.dsl").write_text(
                f"noise().{name}().write(o0)\n"
            )
            (parity / "out" / f"{name}.golden.png").touch()
            (parity / "out" / f"{name}.graph.json").write_text("{}")

        runner = parity / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "name=$1\n"
            "printf '%s\\n' \"{\\\"name\\\":\\\"$name\\\",\\\"passed\\\":true,\\\"max_abs_diff\\\":0,\\\"mean_abs_diff\\\":0,\\\"ssim\\\":1,\\\"tolerance\\\":$2,\\\"ssim_min\\\":$3}\" > \"$(dirname \"$0\")/out/$name.report.json\"\n"
            "echo \"[PASS] $name: synthetic batch candidate\"\n"
        )
        runner.chmod(0o755)
        renderer = self.tmp / "fake-godot"
        renderer.write_text(
            "#!/usr/bin/env bash\n"
            f"printf 'launch\\n' >> '{self.tmp / 'launches'}'\n"
            "manifest=''\n"
            "while [ $# -gt 0 ]; do\n"
            "  if [ \"$1\" = --batch-manifest ]; then manifest=$2; shift 2; else shift; fi\n"
            "done\n"
            "python3 -c 'import json,pathlib,sys; [pathlib.Path(e[\"out\"]).touch() for e in json.load(open(sys.argv[1]))[\"entries\"]]' \"$manifest\"\n"
        )
        renderer.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": str(renderer)},
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.tmp / "launches").read_text().splitlines(), ["launch"])
        ledger = json.loads((parity / "ledger.json").read_text())
        self.assertEqual({row["program"] for row in ledger}, {"chrome", "stamp"})
        self.assertTrue(all(row["verdict"] == "PASS" for row in ledger))

    def test_compare_only_sweep_does_not_launch_godot(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        for helper in ("sweep.sh", "write-ledger.py", "make-batch-manifest.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        (parity / "programs" / "chrome.dsl").write_text("noise().chrome().write(o0)\n")
        (parity / "out" / "chrome.golden.png").touch()
        runner = parity / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"{\\\"name\\\":\\\"$1\\\",\\\"passed\\\":true,\\\"max_abs_diff\\\":0,\\\"mean_abs_diff\\\":0,\\\"ssim\\\":1,\\\"tolerance\\\":$2,\\\"ssim_min\\\":$3}\" > \"$(dirname \"$0\")/out/$1.report.json\"\n"
            "echo '[PASS] compare-only candidate'\n"
        )
        runner.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false", "SKIP_RENDER": "1"},
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ledger = json.loads((parity / "ledger.json").read_text())
        self.assertEqual(ledger[0]["verdict"], "PASS")

    def test_sweep_rejects_normal_child_nonzero_even_with_pass_report(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        for helper in ("sweep.sh", "write-ledger.py", "make-batch-manifest.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        (parity / "programs" / "chrome.dsl").write_text("noise().chrome().write(o0)\n")
        (parity / "out" / "chrome.golden.png").touch()
        runner = parity / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' '{\"name\":\"chrome\",\"passed\":true,\"max_abs_diff\":0,\"mean_abs_diff\":0,\"ssim\":1,\"tolerance\":32.001,\"ssim_min\":0.999}' > \"$(dirname \"$0\")/out/chrome.report.json\"\n"
            "echo '[PASS] chrome: forged status line'\n"
            "exit 7\n"
        )
        runner.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false", "SKIP_RENDER": "1"},
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((parity / "ledger.json").read_text())[0]["verdict"], "FAIL")

    def test_sweep_rejects_timed_child_nonzero_even_with_pass_summary(self):
        parity = self.tmp / "parity"
        (parity / "programs").mkdir(parents=True)
        (parity / "out").mkdir()
        for helper in ("sweep.sh", "write-ledger.py", "make-batch-manifest.py"):
            shutil.copy2(REPO / "parity" / helper, parity / helper)
        name = "temporalAberration"
        (parity / "programs" / f"{name}.dsl").write_text(
            "noise().temporalAberration().write(o0)\n"
        )
        for second in (10, 20, 30):
            (parity / "out" / f"{name}.golden.t{second}.png").touch()
            (parity / "out" / f"{name}.candidate.t{second}.png").touch()
            (parity / "out" / f"{name}.report.t{second}.json").write_text(json.dumps({
                "name": f"{name}_t{second}",
                "passed": True,
                "max_abs_diff": 1,
                "mean_abs_diff": 0.1,
                "ssim": 0.9999,
                "tolerance": 2.001,
                "ssim_min": 0.98,
            }))
        runner = parity / "run_samples.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "echo '=== SAMPLES: temporalAberration 3/3 pass (tol=2.001 ssim>=0.98) ==='\n"
            "exit 7\n"
        )
        runner.chmod(0o755)

        result = subprocess.run(
            ["bash", str(parity / "sweep.sh")],
            env={**os.environ, "GODOT": "/bin/false", "SKIP_RENDER": "1"},
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((parity / "ledger.json").read_text())[0]["verdict"], "FAIL")

    def _run_with_fake_renderer(self, renderer_exit):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / ".venv" / "bin").mkdir(parents=True)
        shutil.copy2(REPO / "parity" / "run.sh", parity / "run.sh")
        for suffix in ("graph.json", "golden.png", "candidate.png"):
            (parity / "out" / f"chrome.{suffix}").touch()
        (parity / "compare.py").write_text("# comparator stub\n")
        python = parity / ".venv" / "bin" / "python"
        python.write_text(
            "#!/usr/bin/env bash\n"
            "if [ -f \"$3\" ]; then echo '[PASS] stale candidate'; exit 0; fi\n"
            "echo '[FAIL] candidate missing'; exit 1\n"
        )
        python.chmod(0o755)
        renderer = self.tmp / "fake-godot"
        renderer.write_text(f"#!/usr/bin/env bash\nexit {renderer_exit}\n")
        renderer.chmod(0o755)

        return subprocess.run(
            ["bash", str(parity / "run.sh"), "chrome", "0", "0.999"],
            env={**os.environ, "GODOT": str(renderer)},
            capture_output=True,
            text=True,
        )

    def test_runner_rejects_stale_candidate_when_renderer_fails(self):
        result = self._run_with_fake_renderer(1)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_runner_requires_renderer_to_create_a_new_candidate(self):
        result = self._run_with_fake_renderer(0)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no candidate", (result.stdout + result.stderr).lower())

    def _run_samples_with_fake_renderer(self, renderer_body, stale_candidates=False, compare_body=None):
        parity = self.tmp / "parity"
        (parity / "out").mkdir(parents=True)
        (parity / ".venv" / "bin").mkdir(parents=True)
        shutil.copy2(REPO / "parity" / "run_samples.sh", parity / "run_samples.sh")
        (parity / "out" / "temporalAberration.graph.json").write_text("{}")
        for second in (10, 20, 30):
            (parity / "out" / f"temporalAberration.golden.t{second}.png").touch()
            if stale_candidates:
                (parity / "out" / f"temporalAberration.candidate.t{second}.png").touch()
        (parity / "compare.py").write_text("# comparator stub\n")
        python = parity / ".venv" / "bin" / "python"
        python.write_text(
            "#!/usr/bin/env bash\n"
            + (compare_body or "echo '[PASS] synthetic timed sample'\n")
        )
        python.chmod(0o755)
        renderer = self.tmp / "fake-godot-samples"
        renderer.write_text("#!/usr/bin/env bash\n" + renderer_body)
        renderer.chmod(0o755)

        return subprocess.run(
            ["bash", str(parity / "run_samples.sh"), "temporalAberration", "2.001", "0.98", "30", "10", "256"],
            env={**os.environ, "GODOT": str(renderer)},
            capture_output=True,
            text=True,
        )

    def test_timed_runner_rejects_stale_samples_when_renderer_fails(self):
        result = self._run_samples_with_fake_renderer("exit 1\n", stale_candidates=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_timed_runner_requires_every_expected_sample(self):
        candidate = self.tmp / "parity" / "out" / "temporalAberration.candidate.t10.png"
        result = self._run_samples_with_fake_renderer(
            f"touch '{candidate}'\nexit 0\n"
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1/3 pass", result.stdout)

    def test_timed_runner_does_not_count_pass_text_from_failing_comparator(self):
        out = self.tmp / "parity" / "out"
        renderer = ""
        for second in (10, 20, 30):
            renderer += f"touch '{out / f'temporalAberration.candidate.t{second}.png'}'\n"
        result = self._run_samples_with_fake_renderer(
            renderer,
            compare_body="echo '[PASS] forged comparator line'\nexit 7\n",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0/3 pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
