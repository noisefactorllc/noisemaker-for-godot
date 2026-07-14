# noisemaker-godot — status & parity

*Last verified 2026-07-14 on Apple M4 / Metal, **content-pinned** to the reference at commit
`75507112`. That SHA is UNSTABLE — upstream amends the artistic-filter batch in place and rebases it,
so history correlation is dead; the reference is pinned by CONTENT (a `git archive 75507112` snapshot),
not by tracking a branch. The sources of truth are `parity/sweep.sh` and `parity/check_*.mjs`.*

This file holds the detailed coverage and parity numbers. For what the project is and how to use it,
see the [README](README.md).

## Coverage

**209 effect definitions** and 231 GLSL shaders across 8 namespaces. (Shader count is 231, not the
earlier 233: `filter/median` was re-derived from a 3-pass approximation to the reference's single-pass
exact quickselect, −2 files.)

| Namespace | Definitions | State |
|---|---|---|
| `synth` | 29 | renders (generators, df64 fractals, value/simplex/cell/gabor/curl noise) |
| `filter` | 116 | renders (color ops, convolutions, warps, multi-pass, feedback) — 26 Photoshop-parity artistic filters, **re-crystallized against `75507112`** (see Parity). The `75507112` pass re-ported drifted algorithms (strokes, photocopy, chrome, wind, mosaicTiles, plasticWrap, halftone, lensFlare, spinBlur, median), extended `texture` to 15 material modes and `dither` with error-diffusion, added `emboss` gray / `edge` contourSide / `plasticWrap` lightDirection, fixed a define-vs-uniform class across pondRipples/relief/scatter/morphology/stipple/extrude, and **reverted** `grain`'s round-1 grain-types back to the pinned alpha/pause form |
| `mixer` | 15 | renders (whole namespace) |
| `classicNoisedeck` | 20 | renders (legacy generators) |
| `points` / `render` | 10 / 11 | renders — agents (MRT/scatter); chaotic flows chaos-gated. `points/lenia` ships a definition but no shaders yet (staged, pre-existing gap) |
| `synth3d` / `filter3d` | 7 / 1 | **staged** (definitions only — 3D volumes/raymarch/meshes) |

## Parity

Re-verified as a **full parity re-crystallization** against the content-pinned `75507112` snapshot
(every effect and every enum/define-selected mode re-minted from the snapshot and graded bit-exact;
nothing trusted from prior rounds).

- **In-engine compiler:** all six gates green vs the reference — lex / parse / validate / expand
  **230/230**, graph **263/263** (grew with the new mode fixtures), registry parity (ops **209/209**,
  8 enums, 43 param + 3 effect aliases, **625 effect keys**).
- **Effect×mode ledger (`parity/sweep.sh` + corpus + timed sims):** **268 fixtures — 221 PASS, 40
  NEAR, 0 FAIL, 7 SKIP**. The single-frame sweep is **249/249 pass, 4 skipped**. "NEAR" = passes only
  under a documented, mechanism-traced tolerance in `tol_for()`; every enum/define mode of the 26
  artistic filters has its own fixture (e.g. texture 15/15, oilPaint 6/6, hatch 6/6, strokes 5/5,
  stipple 5/5, scatter 5/5, lensFlare 4/4, lowPoly 4/4, extrude 4/4 type×depthSource, halftone
  color+mono/{dot,line,circle}, morphology mode×shape, pondRipples style+wrap, dither incl.
  errorDiffusion, emboss color+gray, invert full+solarize).
- The 40 NEAR are all sub-LSB cross-backend fp on a handful of pixels (SSIM ≥ 0.999, mean-abs-diff at
  the ~0.37 noise floor): NEAREST/bilinear resampling ties (uvRemap/refract/rotate/…), discrete
  argmin/threshold/quickselect selection (oilPaint's Kuwahara sector, median's 7×7 edge-clamp tie,
  hatchPencil's stroke-mask step), and pow/sine nonlinear amplification (chrome, plasticWrap family,
  reliefPlaster, unsharpMask). **Two exceed the informal <0.03%-of-pixels ceiling and are flagged
  explicitly** (not silently widened), both inherent algorithm-level cross-backend fp — not port bugs,
  mean-abs-diff at the noise floor confirming sparse outliers: `strokesSmudge` (256 px / 0.39 %; the
  correct re-ported algorithm couples an `atan2` Sobel-near-zero-singularity edge angle into two
  systems) and `ditherErrorDiffusion` (38 px / 0.058 %; a Floyd-Steinberg error cascade propagates one
  quantization tie-flip across a downstream run).
- **Stateful sims:** navierStokes pixel-parity via 30 s / 5 s timed sampling (`parity/run_samples.sh`),
  **6/6** samples SSIM ≥ 0.999; temporalAberration **3/3** (routed through timed sampling by the sweep).
- **Live blaster corpus:** **7/7** renderable real programs at parity, 3 chaos-gated skips
  (`rd_example`, and the `target`/`targetO0` north-star flow→navierStokes chain, docs/CHAOS-GATE.md);
  `navTargetParams` (navierStokes at the target's params, static input) passes via timed sampling 5/6
  (the t5 fluid spin-up transient tolerated like navierStokes' own weakest sample).

Two compilers emit **byte-identical** render graphs: the in-engine GDScript compiler (production) and
the reference `compileGraph` via `tools/export-graph.mjs` (used only to verify the in-engine one).
Rendering either graph produces the same PNG.

## Known limits

- **The chaos gate.** Every effect is bit-exact to the reference *except chaotic agent flows* (and
  `target.dsl`/`targetO0.dsl`, which feed one into a fluid solver): those render correctly but as a
  *different instance* of the chaos, gated by a single spec-legal ~1-ULP `pow` rounding difference in
  Godot's shader compiler that the chaotic loop amplifies. A second, milder class (the 40 NEAR fixtures
  above) drifts by a handful of LSB at resampling / discontinuity / discrete-selection boundaries and
  is SSIM-gated (all ≥ 0.999); two of these (`strokesSmudge`, `ditherErrorDiffusion`) exceed the
  informal <0.03%-of-pixels ceiling and are flagged explicitly in `tol_for()` as inherent
  algorithm-level cross-backend fp, not port bugs. Cause, evidence, and repro:
  [docs/CHAOS-GATE.md](docs/CHAOS-GATE.md).
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
