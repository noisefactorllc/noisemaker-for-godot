"""Tests for parity/ensure_compare_python.sh's interpreter resolution.

The gate sources this script on fresh runner checkouts, where parity/.venv is
absent, so the provisioning branches (uv first, then python3 -m venv) must
resolve the interpreter through either the bin/ or the Scripts/ layout and
fail named when nothing works. The tests stub uv/python3 on PATH, so they run
without network and never touch a real venv.
"""

import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "ensure_compare_python.sh")

# The quick system-python check imports the comparator's needs; the stub
# python3 refuses it so the tests actually reach the provisioning branches.
STUB_PYTHON3 = """#!/usr/bin/env bash
case "$1" in
  -c) exit 1 ;;
  -m)
    case "$2" in
      venv) mkdir -p "$3/bin"; printf '#!/bin/sh\\n' > "$3/bin/python"; chmod +x "$3/bin/python"; exit 0 ;;
      pip) exit 0 ;;
    esac ;;
esac
exit 1
"""

# The stub uv provisions the documented bin/ layout and succeeds at installs.
STUB_UV_BIN = """#!/usr/bin/env bash
case "$1" in
  venv) mkdir -p "$2/bin"; printf '#!/bin/sh\\n' > "$2/bin/python"; chmod +x "$2/bin/python"; exit 0 ;;
  pip) exit 0 ;;
esac
exit 1
"""

# Same, but with the Windows Scripts/ layout, to exercise _venv_python's
# second resolution branch.
STUB_UV_SCRIPTS = """#!/usr/bin/env bash
case "$1" in
  venv) mkdir -p "$2/Scripts"; printf '#!/bin/sh\\n' > "$2/Scripts/python.exe"; chmod +x "$2/Scripts/python.exe"; exit 0 ;;
  pip) exit 0 ;;
esac
exit 1
"""


class EnsureComparePythonTests(unittest.TestCase):
    def _run(self, stubs, extra_setup=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "repo")
            os.makedirs(os.path.join(root, "parity"))
            stubdir = os.path.join(tmp, "stubs")
            os.makedirs(stubdir)
            for name, body in stubs.items():
                path = os.path.join(stubdir, name)
                with open(path, "w") as f:
                    f.write(body)
                os.chmod(path, 0o755)
            if extra_setup:
                extra_setup(root)
            env = dict(os.environ)
            env["PATH"] = stubdir + os.pathsep + env.get("PATH", "")
            proc = subprocess.run(
                ["bash", "-c", '. "$1" "$2" >/dev/null; echo "rc=$?"; echo "PY=$PY"',
                 "probe", SCRIPT, root],
                env=env, capture_output=True, text=True, timeout=60)
            out = dict(line.split("=", 1) for line in proc.stdout.splitlines() if "=" in line)
            return proc, out, root

    def test_existing_venv_bin_layout_is_used_directly(self):
        def setup(root):
            p = os.path.join(root, "parity", ".venv", "bin")
            os.makedirs(p)
            open(os.path.join(p, "python"), "w").close()
            os.chmod(os.path.join(p, "python"), 0o755)
        proc, out, root = self._run({}, setup)
        self.assertEqual(out["rc"], "0")
        self.assertEqual(out["PY"], os.path.join(root, "parity", ".venv", "bin", "python"))

    def test_existing_venv_scripts_layout_is_used_directly(self):
        def setup(root):
            p = os.path.join(root, "parity", ".venv", "Scripts")
            os.makedirs(p)
            open(os.path.join(p, "python.exe"), "w").close()
            os.chmod(os.path.join(p, "python.exe"), 0o755)
        proc, out, root = self._run({}, setup)
        self.assertEqual(out["rc"], "0")
        self.assertEqual(out["PY"], os.path.join(root, "parity", ".venv", "Scripts", "python.exe"))

    def test_uv_provision_resolves_bin_layout(self):
        proc, out, root = self._run({"python3": STUB_PYTHON3, "uv": STUB_UV_BIN})
        self.assertEqual(out["rc"], "0")
        self.assertEqual(out["PY"], os.path.join(root, "parity", ".venv", "bin", "python"))

    def test_uv_provision_resolves_scripts_layout(self):
        proc, out, root = self._run({"python3": STUB_PYTHON3, "uv": STUB_UV_SCRIPTS})
        self.assertEqual(out["rc"], "0")
        self.assertEqual(out["PY"], os.path.join(root, "parity", ".venv", "Scripts", "python.exe"))

    def test_venv_fallback_resolves_without_uv(self):
        # No uv on PATH: the python3 -m venv branch provisions instead.
        proc, out, root = self._run({"python3": STUB_PYTHON3})
        self.assertEqual(out["rc"], "0")
        self.assertEqual(out["PY"], os.path.join(root, "parity", ".venv", "bin", "python"))

    def test_failed_provision_returns_named_failure(self):
        failing = """#!/usr/bin/env bash
exit 1
"""
        proc, out, root = self._run({"python3": failing, "uv": failing})
        self.assertEqual(out["rc"], "1")
        # A provisioning failure must name its cause, not just its exit code.
        self.assertIn("FAIL: the comparator environment is unavailable", proc.stderr)


if __name__ == "__main__":
    unittest.main()
