"""Effect-count claims in the tracked docs must match the shipped catalog.

The root README and the changelog state how many reference effects the
addon ships. The addon effect catalog is the source for that count. The
reference manifest at the parity pin is the source for the catalog. A
count claim that drifts from either source fails here instead of
drifting silently. When no reference checkout at the pin exists, the
authority test prints a visible notice and checks only the catalog.
The engine-free gate never reports a skip.

The scan covers tracked docs only: the files git ls-files lists for
*.md, *.txt, *.cfg and export-kit/*. It matches the count phrasings
those claims use: "the N effects" and "N effect definitions". Subset
counts are not catalog claims and stay unscanned. docs/CHAOS-GATE.md
documents one such drift class.
"""
import json
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EFFECTS_RE = re.compile(r"the (\d+) effects")
DEFINITIONS_RE = re.compile(r"(\d+) effect definitions")
EFFECTS_DIR = ROOT / "godot" / "addons" / "noisemaker" / "effects"
MANIFEST_RELPATH = Path("shaders") / "effects" / "manifest.json"


def _git(root, *args):
    return subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True, text=True, timeout=60,
    )


def _pin():
    text = (ROOT / "scripts" / "parity-summary").read_text()
    match = re.search(r"^ *PIN=([0-9a-f]{40})$", text, re.MULTILINE)
    if not match:
        raise AssertionError("scripts/parity-summary has no PIN line")
    return match.group(1)


def _reference_checkout():
    """A local reference checkout at the parity pin, or an empty path."""
    pin = _pin()
    for candidate in (
        os.environ.get("NM_REFERENCE_ROOT", ""),
        os.environ.get("PARITY_REFERENCE_CACHE", ""),
        str(Path(os.environ.get("TMPDIR", "/tmp")) / "noisemaker-reference"),
    ):
        root = Path(candidate)
        if root.name and ((root / ".git").exists() or (root / "HEAD").exists()):
            head = _git(root, "rev-parse", "HEAD")
            if head.returncode == 0 and head.stdout.strip() == pin:
                return root
    return Path("")


def _tracked_docs():
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.md", "*.txt", "*.cfg", "export-kit/*"],
        capture_output=True, text=True, timeout=60,
    )
    if listed.returncode != 0:
        raise AssertionError("git ls-files failed: " + listed.stderr)
    return [ROOT / name for name in listed.stdout.splitlines() if name]


def _count_claims(paths):
    found = {}
    for path in paths:
        flat = " ".join(path.read_text().split())
        for text in EFFECTS_RE.findall(flat) + DEFINITIONS_RE.findall(flat):
            found.setdefault(int(text), set()).add(path.relative_to(ROOT).as_posix())
    return found


def _effect_catalog_count():
    return len(list(EFFECTS_DIR.glob("**/*.json")))


class DocCountClaimTests(unittest.TestCase):
    def test_doc_effect_counts_match_the_addon_catalog(self):
        catalog = _effect_catalog_count()
        self.assertTrue(catalog, "the addon effect catalog is empty")
        claims = _count_claims(_tracked_docs())
        self.assertTrue(claims, "no effect-count claim found in the tracked docs")
        wrong = {count: sorted(files) for count, files in claims.items()
                 if count != catalog}
        self.assertFalse(
            wrong,
            f"effect-count claims disagree with the addon catalog "
            f"({catalog} definitions): {wrong}",
        )

    def test_addon_catalog_matches_the_authority_manifest(self):
        root = _reference_checkout()
        if not root.name:
            pin = _pin()
            print(
                f"AUTHORITY-CHECK: not run: no reference checkout at the "
                f"parity pin {pin[:12]}. The run checked only the addon "
                f"catalog",
                file=sys.stderr,
            )
            return
        manifest = root / MANIFEST_RELPATH
        self.assertTrue(
            manifest.is_file(),
            f"the reference checkout at the parity pin has no manifest at "
            f"{MANIFEST_RELPATH}",
        )
        data = json.loads(manifest.read_text())
        self.assertIsInstance(
            data, dict,
            f"the authority manifest at {MANIFEST_RELPATH} is not a JSON object",
        )
        self.assertEqual(
            _effect_catalog_count(), len(data),
            f"the addon catalog and the authority manifest at the parity "
            f"pin disagree: {_effect_catalog_count()} vs {len(data)}",
        )


if __name__ == "__main__":
    unittest.main()
