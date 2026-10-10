"""Tests for scripts/export-kit-gate.

The gate decides from `git ls-remote --tags` output whether a commit already
carries a kit-* tag. These tests drive the script through a fake `git` on
PATH, so no network and no real tags are involved. Exit codes: 0 proceed,
1 already released, 2 could not check.
"""

import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
GATE = ROOT / "scripts" / "export-kit-gate"

SHA = "a" * 40
OTHER = "b" * 40
TAG_OBJECT = "c" * 40
URL = "https://git.example.test/noisefactorllc/noisemaker-for-godot.git"

LIGHTWEIGHT_AT_SHA = [f"{SHA}\trefs/tags/kit-godot-v0.1.49"]
# An annotated tag: the direct entry is the tag object, the peeled entry
# carries the commit.
ANNOTATED_AT_SHA = [
    f"{TAG_OBJECT}\trefs/tags/kit-godot-v0.1.50",
    f"{SHA}\trefs/tags/kit-godot-v0.1.50^{{}}",
]
ANNOTATED_AT_OTHER = [
    f"{TAG_OBJECT}\trefs/tags/kit-godot-v0.1.50",
    f"{OTHER}\trefs/tags/kit-godot-v0.1.50^{{}}",
]
LIGHTWEIGHT_AT_OTHER = [f"{OTHER}\trefs/tags/kit-godot-v0.1.49"]
NON_KIT_TAG_AT_SHA = [f"{SHA}\trefs/tags/v1.2.3"]


def make_bindir(with_git=True):
    """A PATH-front directory whose `git` is fake; without git, only the
    external commands the gate needs before its git check (bash via env,
    dirname, tr) are present."""
    bindir = tempfile.mkdtemp()
    bindir = pathlib.Path(bindir) / "bin"
    bindir.mkdir(parents=True)
    for tool in ("bash", "dirname", "tr"):
        target = subprocess.run(
            ["which", tool], capture_output=True, text=True, check=True
        ).stdout.strip()
        (bindir / tool).symlink_to(target)
    if with_git:
        fake_git = bindir / "git"
        fake_git.write_text(
            "#!/bin/sh\n"
            'if [ "$1" = "remote" ]; then\n'
            '  printf "%s\\n" "$FAKE_ORIGIN_URL"\n'
            "  exit 0\n"
            "fi\n"
            'printf "%s" "$FAKE_LS_REMOTE"\n'
            'exit "$FAKE_GIT_RC"\n'
        )
        fake_git.chmod(0o755)
    return bindir


def run_gate(tags, sha=SHA, git_rc=0, url=URL, with_git=True):
    bindir = make_bindir(with_git)
    env = dict(os.environ)
    env["PATH"] = f"{bindir}{os.pathsep}{env.get('PATH', '')}"
    env["FAKE_LS_REMOTE"] = "".join(line + "\n" for line in tags)
    env["FAKE_GIT_RC"] = str(git_rc)
    env["FAKE_ORIGIN_URL"] = URL
    argv = [str(GATE)] + ([sha] if sha is not None else []) + ([url] if url is not None else [])
    try:
        return subprocess.run(
            argv,
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )
    finally:
        import shutil

        shutil.rmtree(bindir.parent, ignore_errors=True)


class ExportKitGateTests(unittest.TestCase):
    def test_script_is_executable_with_shebang(self):
        self.assertTrue(os.access(GATE, os.X_OK), "scripts/export-kit-gate must be executable")
        self.assertTrue(GATE.read_text().startswith("#!"))

    def test_no_tags_proceeds(self):
        self.assertEqual(run_gate([]).returncode, 0)

    def test_lightweight_tag_at_sha_is_released(self):
        self.assertEqual(run_gate(LIGHTWEIGHT_AT_SHA).returncode, 1)

    def test_annotated_tag_at_sha_is_released(self):
        self.assertEqual(run_gate(ANNOTATED_AT_SHA).returncode, 1)

    def test_annotated_tag_at_other_commit_proceeds(self):
        self.assertEqual(run_gate(ANNOTATED_AT_OTHER).returncode, 0)

    def test_lightweight_tag_at_other_commit_proceeds(self):
        self.assertEqual(run_gate(LIGHTWEIGHT_AT_OTHER).returncode, 0)

    def test_non_kit_tag_at_sha_proceeds(self):
        self.assertEqual(run_gate(NON_KIT_TAG_AT_SHA).returncode, 0)

    def test_uppercase_sha_is_normalized(self):
        self.assertEqual(run_gate(LIGHTWEIGHT_AT_SHA, sha=SHA.upper()).returncode, 1)

    def test_short_sha_is_refused(self):
        self.assertEqual(run_gate([], sha=SHA[:12]).returncode, 2)

    def test_explicit_empty_sha_is_refused(self):
        result = run_gate(LIGHTWEIGHT_AT_SHA, sha="")
        self.assertEqual(result.returncode, 2)

    def test_origin_fallback_supplies_the_url(self):
        # The fake git answers `remote get-url origin`; reaching exit 1 (and
        # not the no-origin exit 2) proves the fallback URL was used.
        self.assertEqual(run_gate(LIGHTWEIGHT_AT_SHA, url=None).returncode, 1)

    def test_missing_git_fails_closed(self):
        result = run_gate(LIGHTWEIGHT_AT_SHA, with_git=False)
        self.assertEqual(result.returncode, 2)

    def test_ls_remote_failure_fails_closed(self):
        self.assertEqual(run_gate(LIGHTWEIGHT_AT_SHA, git_rc=128).returncode, 2)


if __name__ == "__main__":
    unittest.main()
