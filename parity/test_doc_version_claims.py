"""Noisemaker version claims in the tracked docs must name the parity pin.

The root README and the changelog state which Noisemaker release the addon
is synced to. scripts/parity-summary pins the reference revision the port
is bound to, and that revision's release tag is the source for the claim.
A claim that drifts from the pin release fails here.

The release number exists only as the tag on the pinned commit, so the
test reads the reference repository's tags with git ls-remote. When the
tags cannot be read, the test fails instead of skipping.

The scan covers the tracked docs that test_doc_count_claims scans, with
whitespace collapsed so a claim that wraps across lines still matches.
"""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REFERENCE_URL = "https://github.com/noisefactorllc/noisemaker"
CLAIM_RE = re.compile(r"Noisemaker (\d+\.\d+\.\d+)")


def _pin():
    text = (ROOT / "scripts" / "parity-summary").read_text()
    match = re.search(r"^ *PIN=([0-9a-f]{40})$", text, re.MULTILINE)
    if not match:
        raise AssertionError("scripts/parity-summary has no PIN line")
    return match.group(1)


def _releases_at(sha, ls_remote_output):
    """Release versions whose tag resolves to sha, from git ls-remote --tags output.

    An annotated tag appears twice, as the tag object and peeled with ^{}.
    The peeled line names the commit; a lightweight tag names it directly.
    """
    found = set()
    for line in ls_remote_output.splitlines():
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] != sha:
            continue
        match = re.fullmatch(r"refs/tags/v(\d+\.\d+\.\d+)(\^\{\})?", parts[1])
        if match:
            found.add(match.group(1))
    return found


def _pin_release():
    pin = _pin()
    listed = subprocess.run(
        ["git", "ls-remote", "--tags", REFERENCE_URL],
        capture_output=True, text=True, timeout=120,
    )
    if listed.returncode != 0:
        raise AssertionError(
            f"git ls-remote --tags {REFERENCE_URL} failed "
            f"(exit {listed.returncode}): {listed.stderr.strip()}"
        )
    releases = _releases_at(pin, listed.stdout)
    if len(releases) != 1:
        raise AssertionError(
            f"the parity pin {pin} resolves to {sorted(releases) or 'no'} "
            f"release tags; expected exactly one"
        )
    return releases.pop()


def _tracked_docs():
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.md", "*.txt", "*.cfg", "export-kit/*"],
        capture_output=True, text=True, timeout=60,
    )
    if listed.returncode != 0:
        raise AssertionError("git ls-files failed: " + listed.stderr)
    return [ROOT / name for name in listed.stdout.splitlines() if name]


def _version_claims(paths):
    found = {}
    for path in paths:
        flat = " ".join(path.read_text(encoding="utf-8").split())
        for version in CLAIM_RE.findall(flat):
            found.setdefault(version, set()).add(path.relative_to(ROOT).as_posix())
    return found


class DocVersionClaimTests(unittest.TestCase):
    def test_release_tags_resolve_peeled_and_lightweight(self):
        sha = "a" * 40
        output = "\n".join([
            f"{'b' * 40}\trefs/tags/v1.0.10",
            f"{sha}\trefs/tags/v1.0.10^{{}}",
            f"{sha}\trefs/tags/kit-1",
            f"{'c' * 40}\trefs/tags/v1.0.11",
        ])
        self.assertEqual(_releases_at(sha, output), {"1.0.10"})
        self.assertEqual(_releases_at("c" * 40, output), {"1.0.11"})
        self.assertEqual(_releases_at("d" * 40, output), set())

    def test_doc_version_claims_name_the_parity_pin_release(self):
        release = _pin_release()
        claims = _version_claims(_tracked_docs())
        self.assertTrue(claims, "no Noisemaker version claim found in the tracked docs")
        wrong = {version: sorted(files) for version, files in claims.items()
                 if version != release}
        self.assertFalse(
            wrong,
            f"Noisemaker version claims disagree with the parity pin "
            f"release {release}: {wrong}",
        )


if __name__ == "__main__":
    unittest.main()
