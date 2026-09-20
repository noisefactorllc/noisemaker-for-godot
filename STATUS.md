# Noisemaker for Godot — status & parity

*Last verified 2026-07-14 on Apple M4 / Metal, **content-pinned** to the reference at commit
`75507112`. That SHA is UNSTABLE — upstream amends the artistic-filter batch in place and rebases it,
so history correlation is dead; the reference is pinned by CONTENT (a `git archive 75507112` snapshot),
not by tracking a branch. The sources of truth are `parity/sweep.sh` and `parity/check_*.mjs`.*

*Incrementally synced 2026-07-23 to reference `349e9909` for the one port-affecting change in that
range — `filter/pondRipples` gained a `speed` control (10/10 fixtures PASS, incl. two new animated
ones). The catalogue-wide numbers below are still the `75507112` figures; they were not re-swept.*

*Incrementally synced 2026-09-15 to reference `0ed489ec4684` (`246ff57f43cc..0ed489ec4684`, commit
6a8f925) — same upstream range as the blender/cables/cpu sibling ports: 3 new effects
(`synth3d/heightmap3d`, `render/renderLandscape3d`, `points/heightGrid`, an isometric/perspective voxel
landscape renderer), a new `perspective` view mode on `render/pointsRender` + `render/pointsBillboardRender`
(billboard also gains a depth-sorted alpha-blend path — `depthKeys`/`depthMerge`, a 22-stage GPU merge
sort — and aperture defocus blur via `spriteMeanTiles`/`spriteMean`/`clearDefocus`), a full rewrite of
`synth/remap`'s polygon-zone compositor, and premultiplied-alpha fixes across
`filter/{invert,tint,adjust,grade}`, `mixer/{alphaMask,blendMode}`, `synth/media`, plus a
gradient-normalization fix in `filter/chrome`. This was a hand-translated port (no auto-transpiler),
so unlike the sibling ports it carried real shader-math risk, not just mechanical compiler fixes.

*Incrementally synced 2026-09-17 to reference `688c5146` (`5a14256732b5..688c514655d3`) — audited upstream WebGPU frame export row-inversion changes. Godot's `rendering_device_frame_export.gd` already applies `source.flip_y()` on texture readback to align Vulkan/Metal RD coordinates with Godot's top-down Image convention; runtime contracts verified via `parity/test_frame_export.py` (2/2 PASS). Updated `parity/shader_compile_sweep.gd` to merge pass-level `defines` into sweep variants, restoring 798/798 clean Vulkan shader compiles (59/59 unittest PASS).*

*Incrementally synced 2026-09-18 to reference `ead42a5d` (`688c514655d3..ead42a5df110a7f04d732cb200a1a39629db8a67`) — regenerated effect definitions via `tools/convert-definitions.mjs` (213/213 definitions match reference in `parity/check_definitions.mjs`). Updated `defaultProgram` in `effects/synth3d/heightmap3d.json`, `effects/render/renderLandscape3d.json`, and `parity/programs/heightmap3d_landscape.dsl` to use discrete write/read chains instead of inline surface parameters. All parity gates verified: registry (213/213), lex (355/355), parse (355/355), validate (355/355), graph (355/355), and parity unittests (59/59 PASS).*

*Incrementally synced 2026-09-19 to reference `f1d2b46a` (`ead42a5df110..f1d2b46a2773`) — audited upstream changes (GAP-023 compiler phase-2 harness exit status reporting, chained variable test plan verification, unified agent instructions; no shader source or effect definition changes). Verified effect definitions via `tools/convert-definitions.mjs` (213/213 PASS). Added unit test in `parity/test_compiler_automation.py` covering chained variable alias syntax compilation into terminal write blit graph. All parity gates verified: definitions (213/213), registry (213/213), lex (355/355), parse (355/355), validate (355/355), graph (355/355), and parity unittests (60/60 PASS).*

*Incrementally synced 2026-09-19 to reference `2df19feb` (`f1d2b46a2773..2df19feb6ce1`) — audited upstream commit `2df19feb6ce1` (support for borrowed `VideoFrame` in `updateTextureFromSource` across WebGL2 and WebGPU web backends). Confirmed inapplicable to Godot (runs in Godot engine via GDScript and RenderingDevice Vulkan/Metal and does not consume browser DOM / WebCodecs / WebGL2 / WebGPU media source pipelines). Zero effect definitions, DSL compiler operations, or shaders changed upstream. All parity gates verified: definitions (213/213), registry (213/213), lex (355/355), parse (355/355), validate (355/355), graph (355/355), and parity unittests (60/60 PASS).*


**Compiler parity, fixed this round** (`expander.gd`) — found via `check_expand.mjs`/`check_graph.mjs`,
both pre-existing gaps only now exercised by this round's `viewMode`-conditional pass pattern, not
introduced by it:
- `uniformSpecs` never emitted an entry for a `type:int` global with `choices` used as a pass
  `conditions` selector (e.g. `viewMode`) — the reference emits `{type:"int", min, max}` for exactly
  this case (a "conditional selector" branch the port's `uniformSpecs` builder never had). Fixed by
  porting the reference's `conditionalUniforms` tracking (scans every pass's `conditions.runIf`/
  `skipIf` for referenced uniform names) and the matching `uniformSpecs` branch.
- Per-pass `program` names never got the reference's second, pass-level `defines`-derived suffix
  (`__VIEW_MODE_0`, sorted by key) on top of the effect-level compile-time-define suffix, so
  `agentsNoOklab`/`agentsSpawn`/`agentsPoints`/`target`/`targetO0` (pre-existing corpus programs that
  exercise `pointsRender`'s default `viewMode:flat` pass, first added upstream this round) produced an
  unsuffixed name where the reference expects one. Fixed; verified this has **no runtime effect**
  either way (`orchestrator.gd`'s `_derive_prog_name()` strips any `__...` suffix regardless, and
  `nm_backend.gd`'s shader cache key is built from namespace/func/progName/defines independently of
  this string) — a pure `check_expand.mjs` parity fix.
- **`check_expand.mjs` intentionally NOT fully closed:** those same 5 programs still show
  `passes[N].defines` present in this port's output but absent from the reference's. This is not a bug
  — `orchestrator.gd`'s `_defines_for_pass()` already documents relying on this exact field (the
  reference's alternative, a live `programs` registry lookup, is permanently inert for this port: no
  effect JSON carries a `shaders` key), and `nm_backend.gd`'s `execute_pass()` reads it directly to
  inject `#define`s at shader-load time. Removing it to chase full JSON-shape parity would have broken
  real `viewMode` rendering; confirmed by trying it and reverting.
- **Graph parity fully closed (355/355 pass):** `check_graph.mjs` now passes cleanly across all 355
  programs and corpus files. Resolved the follow-up where `target.dsl`/`targetO0.dsl` and
  `heightGrid_billboard`/`heightGrid_billboard_alpha` showed discrepancies:
  1. Aligned `_scope_dim_spec()` in `expander.gd` with reference `expander.js` so that `stateSize`
     on node-local textures within a particle pipeline inherits the particle pipeline ID
     (`_cur_particle_pipeline_id`) rather than falling back to `_chain_scope_id`.
  2. Supported numeric constants in pass-level `uniforms` (`global_ref is int or global_ref is float`),
     matching reference `expander.js:827-830` and restoring numeric uniforms such as `runLength`
     in bitonic merge sort passes.

**Pixel parity, this round's new/rewritten shader math — verified correct.** Minted fresh goldens
against the reference and rendered the Godot candidate for each (all standalone, non-batch):
`heightmap3d_landscape` (PASS, max-abs-diff=1), `heightGrid_billboard` (PASS, max-abs-diff=1),
`heightGrid_billboard_alpha` (PASS, max-abs-diff=1 — see batch-mode caveat below), `remap` and
`remap_zone` (both PASS, max-abs-diff=1; `synth/remap`'s full rewrite is correct). `full sweep.sh`:
**343/345 pass**. Two residual items:
- `heightGrid_pointsRender_perspective`: 46/65536 px (0.07%) mismatched, every one candidate-background
  where the golden shows a point (never a wrong color at an existing point) — consistent with a
  `fract()` boundary tie in the density-cull test (`particleRandom > cullThreshold`) flipping a handful
  of points in/out right at the threshold, a normal cross-GPU float-precision limit of the same class
  `tol_for()` already documents for a dozen other effects, not a port bug.
- `heightGrid_billboard_alpha`: **passes cleanly standalone** (and in an isolated 2-entry batch run
  immediately after `heightGrid_billboard`) but **fails catastrophically** (ssim≈0.00001, i.e. a
  completely different image) specifically inside the full ~345-program `sweep.sh` batch run —
  reproduced twice, same numbers both times. This means the shader math itself is confirmed correct;
  something about accumulated `RenderingDevice`/resource state across a long batch of `render()` calls
  in one Godot process corrupts this one program's render. Root cause not found — needs bisection
  across the batch order (isolating which earlier program(s) trigger it) with more time than this pass
  had. Flagging as a real, reproducible bug: automated sweep-based CI may currently report a false
  failure here (or mask a real one) depending on batch composition/order.

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

- **In-engine compiler:** all seven gates green vs the reference — lex / parse / validate / expand /
  graph **339/339** each, registry parity (ops **210/210**, 8 enums, 44 param + 3 effect aliases,
  **628 effect keys**), and definition parity **210/210** (`parity/check_definitions.mjs` — the
  committed effect JSONs are byte-identical to what `tools/convert-definitions.mjs` emits from the
  reference).
- **Effect×mode ledger (`parity/sweep.sh` + corpus + timed sims):** **329 fixtures — 279 PASS, 47
  NEAR, 0 FAIL, 3 CHAOS-gated**; the sweep grades 326/326 green (NEAR counts as passing) and skips
  the 3 chaos rows. "NEAR" = passes only
  under a documented, mechanism-traced tolerance in `tol_for()`; every enum/define mode of the 26
  artistic filters has its own fixture (e.g. texture 15/15, oilPaint 6/6, hatch 6/6, strokes 5/5,
  stipple 5/5, scatter 5/5, lensFlare 4/4, lowPoly 4/4, extrude 4/4 type×depthSource, halftone
  color+mono/{dot,line,circle}, morphology mode×shape, pondRipples style+wrap, dither incl.
  errorDiffusion, emboss color+gray, invert full+solarize).
- The 47 NEAR are all sub-LSB cross-backend fp on a handful of pixels (SSIM ≥ 0.999, mean-abs-diff at
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
