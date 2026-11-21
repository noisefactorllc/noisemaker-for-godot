"""The weekly export-kit run also runs the windowed suites.

.github/workflows/export-kit.yml's parity job runs on the self-hosted GPU
group with a window and the verified Godot build. Its windowed step runs
`scripts/test --godot-windowed` only on the schedule or a manual dispatch,
after Godot is in place and after the rendered parity, and the kit dispatch
waits for the job. The workflow is read as text, because the engine-free
suite has no YAML parser, and the reviewed job and triggers are pinned
exactly: any change to them needs a reviewed change here.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "export-kit.yml"

# The reviewed parity job.
PARITY_JOB = "\n".join([
    '  parity:',
    "    if: github.ref == 'refs/heads/main'",
    '    runs-on:',
    '      group: noisemaker-gpu',
    '      labels: [noisemaker-gpu]',
    '    timeout-minutes: 180',
    '    env:',
    '      GODOT_RELEASE: 4.7-stable',
    '      GODOT_ARCHIVE: Godot_v4.7-stable_macos.universal.zip',
    '      GODOT_SHA512: 0d5d635e6d78d4c2b1286586ca62af249609c2f70815b35437049f08476714d08b913faaf8c10f37313c932ee24c4f87a829899c84fa248f788fb612b8f79229',
    '    steps:',
    '      - name: Require qualified M4 host',
    '        run: |',
    '          set -euo pipefail',
    '          test "$(sysctl -n machdep.cpu.brand_string)" = \'Apple M4\'',
    '          test "$(sysctl -n hw.model)" = \'Mac16,12\'',
    '',
    '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1',
    '        with:',
    '          persist-credentials: false',
    '',
    '      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0',
    '        with:',
    '          node-version: 26',
    '',
    '      - name: Install parity dependencies',
    '        run: |',
    '          python311="$(realpath "$HOME/.local/bin/python3.11")"',
    '          "$python311" -m venv --copies parity/.venv',
    '          test -z "$(find parity/.venv -type l -print -quit)"',
    '          parity/.venv/bin/python -m pip install numpy pillow',
    '          npx --yes playwright@1.63.0 install chromium',
    '',
    '      - name: Materialize pinned reference as regular files',
    '        run: |',
    '          set -euo pipefail',
    '          pin="$(sed -n \'s/^  PIN=//p\' scripts/parity-summary)"',
    '          [[ "$pin" =~ ^[0-9a-f]{40}$ ]]',
    '          bare="$RUNNER_TEMP/noisemaker-reference.git"',
    '          reference="$RUNNER_TEMP/noisemaker-reference"',
    '          git clone -q --bare https://github.com/noisefactorllc/noisemaker "$bare"',
    '          git -C "$bare" cat-file -e "$pin^{commit}"',
    '          python3 - "$bare" "$pin" "$reference" <<\'PY\'',
    '          from pathlib import Path',
    '          import shutil',
    '          import subprocess',
    '          import sys',
    '',
    '          bare, pin, root = sys.argv[1:]',
    '          root = Path(root)',
    '          entries = subprocess.check_output(',
    "              ['git', '-C', bare, 'ls-tree', '-rz', pin]).split(b'\\0')",
    '          links = []',
    '          for entry in filter(None, entries):',
    "              metadata, name = entry.split(b'\\t', 1)",
    "              mode, kind, oid = metadata.decode('ascii').split()",
    "              path = name.decode('utf-8')",
    "              if mode == '120000':",
    '                  links.append(path)',
    '                  continue',
    "              if mode not in ('100644', '100755') or kind != 'blob':",
    "                  raise SystemExit(f'unsupported reference entry: {path} ({mode} {kind})')",
    '              destination = root / path',
    '              destination.parent.mkdir(parents=True, exist_ok=True)',
    '              destination.write_bytes(subprocess.check_output(',
    "                  ['git', '-C', bare, 'cat-file', 'blob', oid]))",
    "              if mode == '100755':",
    '                  destination.chmod(0o755)',
    '          # Older pins track shaders/share as a link to ../share; newer pins',
    '          # track no link. Both get the same regular-file copy.',
    "          if links not in ([], ['shaders/share']):",
    "              raise SystemExit(f'unexpected reference links: {links}')",
    '          if links:',
    '              target = subprocess.check_output(',
    "                  ['git', '-C', bare, 'show', f'{pin}:shaders/share']).decode().strip()",
    "              if target != '../share':",
    "                  raise SystemExit(f'unexpected shaders/share target: {target}')",
    "          shutil.copytree(root / 'share', root / 'shaders' / 'share')",
    '          PY',
    '          npm install --prefix "$reference" --no-save --no-bin-links --ignore-scripts --package-lock=false --omit=dev playwright@1.63.0',
    '          if find "$reference" -type l -print -quit | grep -q .; then',
    "            echo 'reference contains a symbolic link' >&2",
    '            exit 1',
    '          fi',
    '          echo "NM_REFERENCE_ROOT=$reference" >> "$GITHUB_ENV"',
    '',
    '      - name: Download and verify Godot',
    '        run: |',
    '          set -euo pipefail',
    '          dir="$RUNNER_TEMP/godot"',
    '          mkdir -p "$dir"',
    '          cd "$dir"',
    '          base="https://github.com/godotengine/godot-builds/releases/download/$GODOT_RELEASE"',
    '          curl -fsSL --retry 3 --connect-timeout 30 --max-time 300 -o "$GODOT_ARCHIVE" "$base/$GODOT_ARCHIVE"',
    '          curl -fsSL --retry 3 --connect-timeout 30 --max-time 300 -o SHA512-SUMS.txt "$base/SHA512-SUMS.txt"',
    '          grep -Fx "$GODOT_SHA512  $GODOT_ARCHIVE" SHA512-SUMS.txt',
    '          echo "$GODOT_SHA512  $GODOT_ARCHIVE" | shasum -a 512 -c -',
    '          unzip -q "$GODOT_ARCHIVE"',
    '          godot="$dir/Godot.app/Contents/MacOS/Godot"',
    '          "$godot" --version',
    '          echo "GODOT=$godot" >> "$GITHUB_ENV"',
    '',
    '      - name: Run full rendered parity',
    '        run: scripts/parity-summary',
    '',
    '      # The windowed suites need the same window, GPU and Godot build as the',
    '      # rendered parity; scripts/test fails on any failure, skip or empty run.',
    '      - name: Run the windowed suites',
    "        if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'",
    '        run: PATH="$PWD/parity/.venv/bin:$PATH" scripts/test --godot-windowed',
])

# The reviewed workflow triggers.
ON_BLOCK = "\n".join([
    '  workflow_dispatch:',
    '  schedule:',
    '    - cron: "17 8 * * 1"',
])


def block(lines, name):
    """A job's header and indented lines, up to the next job or two-space comment."""
    start = lines.index(f"  {name}:")
    out = [lines[start]]
    for line in lines[start + 1:]:
        if re.match(r"^ {2}\S", line) or re.match(r"^\S", line):
            break
        out.append(line)
    while out and not out[-1].strip():
        out.pop()
    return out


def on_block(lines):
    start = lines.index("on:")
    out = []
    for line in lines[start + 1:]:
        if re.match(r"^[^ #]", line):
            break
        out.append(line)
    while out and not out[-1].strip():
        out.pop()
    return "\n".join(out)


class ExportKitWorkflowTests(unittest.TestCase):

    def setUp(self):
        self.text = WORKFLOW.read_text()
        self.lines = self.text.splitlines()

    def test_the_parity_job_is_exactly_the_reviewed_job(self):
        self.assertEqual("\n".join(block(self.lines, "parity")), PARITY_JOB)
        self.assertEqual(self.lines.count("  parity:"), 1, "one parity job")

    def test_the_reviewed_job_runs_the_windowed_suites_after_godot_and_the_rendered_parity(self):
        names = re.findall(r"(?m)^      - name: (.+)$", PARITY_JOB)
        self.assertLess(names.index("Download and verify Godot"), names.index("Run full rendered parity"))
        self.assertEqual(names[-1], "Run the windowed suites")
        self.assertIn("        if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'\n"
                      '        run: PATH="$PWD/parity/.venv/bin:$PATH" scripts/test --godot-windowed', PARITY_JOB)

    def test_the_kit_dispatch_waits_for_the_parity_job(self):
        dispatch = block(self.lines, "dispatch")
        self.assertEqual(dispatch[1:3], ["    needs: parity", "    if: github.ref == 'refs/heads/main'"])

    def test_the_workflow_runs_on_the_reviewed_triggers(self):
        self.assertEqual(on_block(self.lines), ON_BLOCK)

    def test_nothing_in_the_workflow_changes_the_shell_or_narrows_the_suites(self):
        self.assertIsNone(re.search(r"""(?m)^["']?defaults["']?\s*:""", self.text), "no top-level defaults")
        for name in ("NM_SHARD_COUNT", "NM_SHARD_INDEX", "NM_CHANGED_FILES"):
            self.assertNotIn(name, self.text, f"the workflow must not set {name}")


if __name__ == "__main__":
    unittest.main()
