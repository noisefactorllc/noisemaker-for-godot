# Parity harness

How Noisemaker for Godot is checked against the reference engine (the JS engine's WebGL2 backend).
There are two layers:

1. **Pixel parity:** render each program with Godot and compare it with a golden rendered by the
   reference.
2. **Compiler parity:** compare the in-engine GDScript compiler's output with the reference compiler,
   stage by stage.

The addon itself needs none of this; see `../godot/addons/noisemaker/README.md`.

Tooling requirements: Node, Python 3.11 or newer, a Godot 4.7 binary in `GODOT`, and a virtualenv at
`parity/.venv` with `numpy` and `pillow` for `compare.py` (`python3 -m venv parity/.venv`, then install
both). The scripts find the venv's interpreter under `bin/` or, on Windows, `Scripts/`. On Windows run
everything from Git Bash.

## 1. Pixel parity

```bash
GODOT=/path/to/godot scripts/parity-summary              # every program in parity/ledger.json
GODOT=/path/to/godot scripts/parity-summary noise blur   # selected cases
```

`scripts/parity-summary` is the entry point. Without `NM_REFERENCE_ROOT` it clones the reference at
the revision pinned in the script into `$TMPDIR/noisemaker-reference`, with Playwright 1.63.0, and
reuses that clone while it is clean and at the pin. For each case it mints a missing golden
(`export-and-render.mjs`: WebGL2 in Chromium, 256×256, normalized time 0.25), renders the candidate
with `run.sh`, and compares the two at tolerance 2.001 and SSIM 0.98. It prints one
`PARITY-SUMMARY {...}` line and exits 0 only when every case passes that contract. A case listed in
`parity/parity-deferrals.json` counts as `near` or `defer`, never as a pass.

Goldens and candidates live in `parity/out/`, which is not committed. After moving the pin, delete
`parity/out/*.golden.png` so every golden is minted from the new revision.

**Mint goldens on the GPU.** The goldens must come from a GPU, like the candidates. Headless Chromium
on Windows renders WebGL2 with SwiftShader, a CPU rasterizer, so set `SHADE_HEADLESS=0` there; the
browser then opens a window for each golden and renders on the GPU (ANGLE over Direct3D 11).
SwiftShader goldens push isolated rounding differences across whole images (on `chrome` the mean
difference was 1.42 against 0.007 with a GPU golden).

Other scripts:

```bash
GODOT=... bash parity/run.sh noise            # one case against an existing golden
GODOT=... bash parity/sweep.sh                # every program in one Godot process; rewrites parity/ledger.json
GODOT=... bash parity/run_samples.sh navierStokes   # stateful programs as a timed series
```

`sweep.sh` applies the per-program tolerances in its `tol_for` table and records the verdict and
policy of each program in `parity/ledger.json`. Those tolerances are wider than the
`scripts/parity-summary` contract for some programs, so a sweep `NEAR` is not a pass.

`temporalAberration` is an eight-stage delay line whose single-frame golden depends on how many
frames the browser ran before the capture. It is compared as 30 s of samples every 10 s instead, after
which both renderers reach the same steady state. Mint its goldens in timed mode:

```bash
node parity/export-and-render.mjs parity/programs/temporalAberration.dsl parity/out \
    --size 256 --backend webgl2 --run-seconds 30 --sample-every 10
GODOT=... bash parity/run_samples.sh temporalAberration 2.001 0.98 30 10 256
```

The pieces:

- `export-and-render.mjs` renders the reference golden through the reference's Playwright harness and
  writes the graph JSON next to it.
- `../tools/export-graph.mjs` serializes the reference `compileGraph` result, the candidate renderer's
  `--graph` input.
- `../godot/addons/noisemaker/tools/render_graph.gd` renders the Godot candidate.
- `compare.py` computes max-abs-diff and SSIM.

To add a program, write `parity/programs/<name>.dsl` and add it to `parity/ledger.json` (a sweep does
this), then run `scripts/parity-summary <name>`.

## 2. Compiler parity

Seven gates compare the GDScript compiler with the reference. Six run a reference oracle in Node
(`../tools/dump-*.mjs`) and a headless Godot dump (`../godot/addons/noisemaker/compiler/_*_dump.gd`)
over every program in `parity/programs/` and `parity/corpus/programs/`, then deep-compare them with a
tight numeric epsilon. The seventh, `check_definitions.mjs`, regenerates the effect JSONs from the
reference with `tools/convert-definitions.mjs` and diffs them with the committed ones; the other six
read those JSONs on both sides, so they cannot see a stale definition.

```bash
NM_REFERENCE_ROOT=/path/to/noisemaker GODOT=/path/to/godot node parity/check_lex.mjs        # tokens
NM_REFERENCE_ROOT=... GODOT=... node parity/check_parse.mjs                                  # AST
NM_REFERENCE_ROOT=... GODOT=... node parity/check_validate.mjs                               # validated plans
NM_REFERENCE_ROOT=... GODOT=... node parity/check_expand.mjs                                 # render passes
NM_REFERENCE_ROOT=... GODOT=... node parity/check_graph.mjs                                  # normalized graphs
NM_REFERENCE_ROOT=... GODOT=... node parity/check_registry.mjs                               # effect registry
NM_REFERENCE_ROOT=... node parity/check_definitions.mjs                                      # effect JSONs
```

`check_expand.mjs` accepts one difference, defined in `expand_acceptance.mjs`: the candidate copies a
pass's `defines` onto the expanded pass, where the reference keeps them only in the program name.

See also `../docs/GRAPH-JSON-SCHEMA.md` (the graph contract) and `../docs/CHAOS-GATE.md` (why chaotic
agent flows are not pixel matches).
