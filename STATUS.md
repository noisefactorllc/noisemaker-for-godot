# noisemaker-godot — status & parity

*Last verified 2026-07-10 on Apple M4 / Metal (synced to reference commit `36e7f3f5`). The sources of
truth are `parity/sweep.sh` and `parity/check_*.mjs`.*

This file holds the detailed coverage and parity numbers. For what the project is and how to use it,
see the [README](README.md).

## Coverage

**209 effect definitions** and 233 GLSL shaders across 8 namespaces.

| Namespace | Definitions | State |
|---|---|---|
| `synth` | 29 | renders (generators, df64 fractals, value/simplex/cell/gabor/curl noise) |
| `filter` | 116 | renders (color ops, convolutions, warps, multi-pass, feedback) — 21 Photoshop-parity filters added in the `b7c1bc36` sync (parallax, unsharpMask, highPass, median, morphology, directionalBlur, spinBlur, scatter, wind, pondRipples, extrude, halftone, stipple, oilPaint, watercolor, plasticWrap, relief, photocopy, stamp, chrome, hatch); 5 more added in the `36e7f3f5` sync (strokes, craquelure, mosaicTiles, patchwork, lensFlare), plus `lowPoly` extended with stained-glass borders/light |
| `mixer` | 15 | renders (whole namespace) |
| `classicNoisedeck` | 20 | renders (legacy generators) |
| `points` / `render` | 10 / 11 | renders — agents (MRT/scatter); chaotic flows chaos-gated. `points/lenia` ships a definition but no shaders yet (staged, pre-existing gap) |
| `synth3d` / `filter3d` | 7 / 1 | **staged** (definitions only — 3D volumes/raymarch/meshes) |

## Parity

- **In-engine compiler:** 230/230 across all six gates (lex / parse / validate / expand / graph) plus
  full registry parity (ops 209/209, enums, aliases, 625 effect keys) vs the reference.
- **2D effects + agents (single-frame, `parity/sweep.sh`):** 216/216 pass; 3 skipped (2 chaos-gated:
  reactionDiffusion, convolutionFeedback; navierStokes is tested separately below, not chaos — its
  single-frame golden freezes the sim at the seed). Most land within 1-2/255 (SSIM ≈ 1.0); ~20 are
  SSIM-gated with documented per-program tolerances in `parity/sweep.sh`'s `tol_for()` — mostly
  resampling/discontinuity-boundary drift (NEAREST texel-boundary ties), plus discrete argmin/
  threshold selection (oilPaint's Kuwahara sector pick, hatch's coloredPencil stroke-mask step,
  reliefPlaster), nonlinear amplification of the usual sub-LSB residual (chrome's sine tone curve),
  and a newer class from the `36e7f3f5` filter batch: strokes' sprayed-mode bilinear-jitter tap
  positions and smudge-mode's edge-following-angle instability at a Sobel gradient's near-zero
  singularity (same class as hatchPencil). All are isolated to <0.03% of pixels with SSIM ≥ 0.999.
- **Stateful sims (navierStokes):** pixel-parity via 30 s timed sampling (`parity/run_samples.sh`),
  6/6 samples pass, SSIM ≥ 0.999 (mostly ≥ 0.9996) in the stable regime.
- **Live blaster corpus:** 4/5 renderable real programs at parity; 1 chaos-gated (reactionDiffusion).

Two compilers emit **byte-identical** render graphs: the in-engine GDScript compiler (production) and
the reference `compileGraph` via `tools/export-graph.mjs` (used only to verify the in-engine one).
Rendering either graph produces the same PNG.

## Known limits

- **The chaos gate.** Every effect is bit-exact to the reference *except chaotic agent flows* (and
  `target.dsl`, which feeds one into a fluid solver): those render correctly but as a *different
  instance* of the chaos, gated by a single spec-legal ~1-ULP `pow` rounding difference in Godot's
  shader compiler that the chaotic loop amplifies. A second, milder class (~20 effects) drifts by a
  handful of LSB on <0.03% of pixels at resampling / discontinuity / discrete-selection boundaries and
  is SSIM-gated (all ≥ 0.999). Cause, evidence, and repro: [docs/CHAOS-GATE.md](docs/CHAOS-GATE.md).
- **3D is staged:** `synth3d` / `filter3d` ship definitions but **0 shaders** yet.
- **Platform:** verified on Apple Silicon / Metal only; rendering needs a window (no `--headless`).

## Why `RenderingDevice` (not `.gdshader`)

The engine needs exact `rgba16f` / `rgba32f` render targets, MRT-in-one-pass, explicit ping-pong
double-buffering, and bit-exact linear float with **no implicit sRGB**. Godot's high-level
`.gdshader` + `SubViewport` path structurally cannot meet those (it caps at `rgba16f`, forces sRGB on
viewport readback, and has no user MRT). `RenderingDevice` (Vulkan-GLSL, `#version 450`) provides all
of it. Its coordinate system is top-left / Vulkan Y-down clip — identical to WGSL/D3D — so shaders
port from the reference WGSL with no per-effect Y-flip; a single global flip at present reconciles to
the WebGL2 golden.
