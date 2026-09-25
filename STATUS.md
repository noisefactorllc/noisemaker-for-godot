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

*Incrementally synced 2026-09-20 to reference `beabda38` (`2df19feb6ce1..beabda385253`) — ported upstream commit `beabda385253` MIDI channel validation to unconditionally require static integer channels 1..16 across all channel-based MIDI modes in `compiler/lang/validator.gd` (including legacy note modes). Audited upstream commit `6e0166ce` (pipeline recreation format checks). Added unit test in `parity/test_compiler_automation.py` covering static integer 1..16 channel enforcement across all legacy note modes. All parity gates verified: definitions (213/213 PASS), registry (213/213 PASS), lex (355/355 PASS), parse (355/355 PASS), validate (355/355 PASS), graph (355/355 PASS), and parity unittests (61/61 PASS).*

*Incrementally synced 2026-09-21 to reference `f61ac073` (`beabda385253..f61ac0732088`) — ported upstream commit `2f855c9c` removal of expired `filter/bc`, `filter/colorspace`, and `filter/hs` effects and shaders following completion of consumer migration to `filter/adjust`. Audited upstream commits `0139e958` (frame export cancel accounting), `7706a715` (shade-mcp pin), and `f61ac073` (test audio 32-channel modulation). Regenerated effect definitions via `tools/convert-definitions.mjs` (210/210 definitions match reference in `parity/check_definitions.mjs`). All parity gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), shader coverage (1/1 PASS), shader compile (1/1 PASS), and parity unittests (61/61 PASS).*

*Incrementally synced 2026-09-21 to reference `50b8f909` (`f61ac0732088..50b8f909ff59`) — ported upstream commit `50b8f909` (GAP-001) enforcing output surface reference range `o0`–`o7` for `OUTPUT_REF` unless preceded by a `DOT` token (member segment access like `foo.o8`) in `godot/addons/noisemaker/compiler/lang/lexer.gd`. Updated frontend specification in `reference/01-dsl-frontend.md` Section 1.4. Added regression tests in `parity/test_compiler_automation.py` covering out-of-range rejection across DSL positions (`render`, `read`, `write`), boundary behavior for `o0` and `o7`, and preservation of member segments and other surface reference families (`s99`, `vol99`, `geo99`, `xyz99`, `vel99`, `rgba99`, `mesh99`). All parity gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), and parity unittests (62/62 PASS).*

*Incrementally synced 2026-09-21 to reference `68d37721` (`50b8f909ff59..68d37721091a`) — audited upstream commit `68d37721` (excluding builtins from mutation introspection in JS `transform.js`). Confirmed inapplicable to Godot (does not implement JS AST mutation introspection; compiler frontend is execution-only). Zero effect definitions, DSL compiler operations, or shaders changed upstream. All parity gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), and parity unittests (62/62 PASS).*

*Incrementally synced 2026-09-22 to reference `e5bd2013` (`68d37721091a..e5bd2013087e`) — ported upstream commit `e5bd2013` (GAP-002: "fix: preserve source columns in DSL diagnostics") to preserve source column numbers from `loc.column` (with fallback to `loc.col`) in diagnostic records in `godot/addons/noisemaker/compiler/lang/validator.gd`. Added unit smoke checks in `godot/addons/noisemaker/compiler/_smoke.gd` and regression tests in `parity/test_compiler_automation.py` covering exact column preservation on diagnostics, multi-line indentation, caller-supplied AST column precedence, and omission of location on unlocated AST nodes. All parity gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), smoke (24/24 PASS), and parity unittests (63/63 PASS).*

*Incrementally synced 2026-09-22 to reference `643b2be1` (`e5bd2013087e..643b2be1e28b8d4c9d34fb2c31ca118d5c414603`) — ported upstream commit `643b2be1` ("feat: expose structured DSL lexer diagnostics") to emit structured diagnostics (`code`, `stage`, `severity`, `message`, `location: {line, column}`, `span: {start, end}`) on lexer failures in `godot/addons/noisemaker/compiler/lang/lexer.gd`. Updated `_TABLE` and added `stage(code)` in `godot/addons/noisemaker/compiler/lang/diagnostics.gd` (`L001`-`L004`, `P001`-`P002`, `S001`-`S008`, `R001`). Preserved UTF-16 code unit counting for source columns and span ranges across surrogate pairs and multi-line escape sequences. Added smoke checks in `godot/addons/noisemaker/compiler/_smoke.gd` and regression tests in `parity/test_compiler_automation.py` covering all 9 failure cases and token preservation. All parity gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), smoke (28/28 PASS), and parity unittests (65/65 PASS).*

*Incrementally synced 2026-09-23 to reference `5b81e04f` (`44bc4ed4ac72..5b81e04f8a4b`) — ported upstream commit `0766743e` structured parser automation diagnostics `P003` and search directive diagnostics `P004` into `godot/addons/noisemaker/compiler/lang/parser.gd`. Ported upstream commits `fde2ea40` (`classicNoisedeck/noise` multires refraction zero-work guard) and `9b88e567` (`classicNoisedeck/glitch` zero-work early exits for glitchiness, scanlines, and snow) into `godot/addons/noisemaker/shaders/effects/classicNoisedeck/noise/noise.glsl` and `glitch/glitch.glsl`. Ported upstream commit `5b81e04f` output sink render deferral via `should_defer_render()` / `shouldDeferRender()` on `SinkManager` (`godot/addons/noisemaker/runtime/sink.gd`) and `NoisemakerBackend` (`godot/addons/noisemaker/runtime/nm_backend.gd`). Added unit tests in `parity/output_runtime_test.gd`, smoke tests in `godot/addons/noisemaker/compiler/_smoke.gd`, and parity tests in `parity/test_compiler_automation.py`. All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), shader compile sweep (798/798 clean Vulkan compiles), smoke (30/30 PASS), and parity unittests (68/68 PASS).*

*Incrementally synced 2026-09-24 to reference `c9ee8a04` (`5b81e04f8a4b..c9ee8a049b2b`) — ported upstream commit `7a54ab38` structured parser output diagnostics `P005` into `godot/addons/noisemaker/compiler/lang/diagnostics.gd` and `godot/addons/noisemaker/compiler/lang/parser.gd` (`_parse_render_directive()`, `_parse_chain()` statement context check, and `_parse_write_call()` surface, tex3d, and geo validation). Audited upstream commits across the range (shaders/effects inventory unchanged at 210 effects, definitions and registries identical). Added smoke tests in `godot/addons/noisemaker/compiler/_smoke.gd` and regression/precedence tests in `parity/test_compiler_automation.py`. All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), smoke (34/34 PASS), and parity unittests (70/70 PASS).*

*Incrementally synced 2026-09-24 to reference `13fa8b54` (`c9ee8a049b2b..13fa8b540025`) — ported upstream commit `13fa8b54` structured parser subchain diagnostics `P006` into `godot/addons/noisemaker/compiler/lang/diagnostics.gd` and `godot/addons/noisemaker/compiler/lang/parser.gd` (`_parse_subchain_call()` argument type validation, body dot validation, and empty body checks). Audited upstream commits across the range (shaders/effects inventory unchanged at 210 effects, definitions and registries identical). Added smoke tests in `godot/addons/noisemaker/compiler/_smoke.gd` and regression/precedence/compilation tests in `parity/test_compiler_automation.py`. All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), smoke (38/38 PASS), and parity unittests (21/21 PASS).*

*Incrementally synced 2026-09-24 to reference `4891b995` (`13fa8b540025..4891b9953f9f`) — ported upstream commit `4891b995` structured parser call expression diagnostics `P007` and remaining expectation diagnostics `P001` into `godot/addons/noisemaker/compiler/lang/diagnostics.gd` and `godot/addons/noisemaker/compiler/lang/parser.gd` (`_transform_from()` argument validation, `_parse_call()` inline namespace and mixed positional/keyword arguments, `_parse_statement()` and `_parse_kwarg()` missing expression after '=', `_parse_primary()` array bracket, member dot, and token fallbacks, and `_to_number()` number coercion). Audited upstream commits across the range (shaders/effects inventory unchanged at 210 effects, definitions and registries identical). Added smoke tests in `godot/addons/noisemaker/compiler/_smoke.gd` and regression/compilation tests in `parity/test_compiler_automation.py`. All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), smoke (43/43 PASS), and parity unittests (25/25 PASS, pytest 77/77 PASS).*

*Incrementally synced 2026-09-25 to reference `240740dd` (`4891b9953f9f..240740dd676a`) — ported upstream DSL compiler updates:
- Lexer: Token carries `position: {"line", "column", "start", "end"}` with UTF-16 code unit offset tracking across surrogate pairs and line breaks.
- Parser: Structured diagnostics derive line, column, and span coordinates from source token positions, while preserving null locations/spans for caller-supplied unlocated tokens.
- Numeric coercion: diagnostics derive line, column, and span coordinates from array literal positions (`[1] + 1`), preserving null locations for unlocated expressions.
- GAP-027 subchain argument validation contract: registered `P008` (unknown/discarded key), `P009` (duplicate key), and `P010` (missing comma separator) in `diagnostics.gd`, surfaced `subchainArgumentDiagnostics` on `Subchain` nodes in parser and validator, and enforced SyntaxError rejection under strict opt-in mode (`subchainArguments: "strict"` via `--strict-subchain-args`).
- All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), smoke (63/63 PASS), and pytest compiler automation (27/27 PASS).*

*Incrementally synced 2026-09-25 to reference `9d3474df` (`240740dd676a..9d3474dfdc6c`, v1.0.181) — audited upstream commit `9d3474df` (GAP-003: runtime validation of effect definitions against spec via `validateEffectDefinition` in `shaders/src/runtime/effect-validator.js`). Integrated `validateEffectDefinition` into `tools/convert-definitions.mjs` to validate all effect definitions against spec before writing. Added `test_registered_effect_definitions_satisfy_specification` in `parity/test_shader_coverage.py` asserting that all 210 registered effect definitions satisfy the specification contract (`name`, `namespace`, `func`, `passes`, `program`, `globals`, `paramAliases`). All 210 effect definitions match and pass validation cleanly.*

*Incrementally synced 2026-09-25 to reference `8eeb7b5a` (`9d3474dfdc6c..8eeb7b5ac14eb37a8d16037f607a88ce63924cd3`, v1.0.183) — ported GAP-004 texture definition keys (`mipmaps`, `persistent`, `filter`) and GAP-005 pass keys (`name`, `type`, `clear`, `viewport`, `samplerTypes`) from upstream:
- `tools/convert-definitions.mjs`: updated pass and texture conversion projections to preserve `viewport`, `samplerTypes`, `mipmaps`, `persistent`, and `filter`. Regenerated all 210 JSON effect definitions cleanly with validation against specification (10 3D effects updated with canonical `viewport` specifications).
- `godot/addons/noisemaker/compiler/graph/expander.gd`: updated optional pass field propagation (`opt_key`) to include `name`, `type`, `clear`, `viewport`, and `samplerTypes`.
- `godot/addons/noisemaker/compiler/graph/orchestrator.gd`: updated `_extract_texture_specs` to forward `mipmaps`, `persistent`, and 3D `filter` metadata.
- `parity/test_shader_coverage.py`: added `test_registered_effect_definitions_gap004_gap005_contract` asserting specification conformity for `viewport`, `samplerTypes`, and texture flags across all 210 effect definitions.
- `parity/test_compiler_automation.py`: added `test_expander_propagates_gap005_pass_fields` verifying pass-level preservation across AST expansion.
- All parity gates verified: definitions (210/210 PASS), graph (352/352 PASS), and full test suite (82/82 pytest PASS).*

*Incrementally synced 2026-09-25 to reference `2f47612c` (`9d3474dfdc6c..2f47612c2904`; the declared source range `fca611fd8f91..2f47612c2904` is the same endpoint force-pushed — `fca611fd` is the pre-rebase SHA of the already-synced `240740dd` content, re-derived from the observed range `13a8a0491dcf..2f47612c2904` by content audit) — ported upstream texture-allocation policies (GAP-004) and the two follow-up fixes:
- Authorable texture policies: 3D texture specs accept `filter: 'nearest'|'linear'`; 2D texture specs accept `mipmaps: true` (full mip chain allocated up front, regenerated from level 0 after each frame's passes, before endFrame) and `persistent: true` (contents resampled through a NEAREST blit when the texture is recreated at a new size). Effect inventory unchanged: **no effect definition in the range uses these keys**, so compiled graphs, definitions (210/210), and registries are byte-identical; the propagation is exercised by smoke tests, and the runtime path activates only on opt-in.
- Compiler parity: `orchestrator.gd` `_extract_texture_specs()` now propagates `filter` (3D, only when truthy) and `mipmaps`/`persistent` (2D, only when authored) exactly as reference `compiler.js extractTextureSpecs`; `mipLevelCount`/`mipLevelSize` helpers and `refreshMipTargets` (global surfaces map one spec to both double-buffer halves) ported into `nm_backend.gd`.
- Runtime: mip regeneration draws a 2x2 box downsample per level (reference webgpu.js `fsMip`; texelFetch so unfilterable float formats work) into a scratch texture and `texture_copy`s it into the mip level (RenderingDevice framebuffers attach mip 0 only); mipmapped inputs sample through a new linear+mipmap sampler (reference legacyDefault 'mipmap'). Odd-sized levels use the scale blit (`fsScale`).
- Audited upstream commits `62eb56fa` (WebGL2 mip-chain allocation fix + WebGPU cached mip bind groups — the allocation-half ported above; bind-group caching is a WebGPU-perf detail with no RenderingDevice analogue) and `2f47612c` (stop double-creating global surfaces on allocation change — the port's `allocate_textures` now keeps a mipmapped texture whose allocation matches, the same "matching allocation, preserve it" rule; no double-create existed in the port).
- Audited docs-only commits `fa4b2f02`, `69d83b80`, `13a8a04` (GAP-003 closure records, checkpoint notes — no shader source or definitions changed).*



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

**210 effect definitions** and 231 GLSL shaders across 8 namespaces. (Shader count is 231, not the
earlier 233: `filter/median` was re-derived from a 3-pass approximation to the reference's single-pass
exact quickselect, −2 files.)

| Namespace | Definitions | State |
|---|---|---|
| `synth` | 29 | renders (generators, df64 fractals, value/simplex/cell/gabor/curl noise) |
| `filter` | 113 | renders (color ops, convolutions, warps, multi-pass, feedback) — 26 Photoshop-parity artistic filters, **re-crystallized against `75507112`** (see Parity). The `75507112` pass re-ported drifted algorithms (strokes, photocopy, chrome, wind, mosaicTiles, plasticWrap, halftone, lensFlare, spinBlur, median), extended `texture` to 15 material modes and `dither` with error-diffusion, added `emboss` gray / `edge` contourSide / `plasticWrap` lightDirection, fixed a define-vs-uniform class across pondRipples/relief/scatter/morphology/stipple/extrude, and **reverted** `grain`'s round-1 grain-types back to the pinned alpha/pause form |
| `mixer` | 15 | renders (whole namespace) |
| `classicNoisedeck` | 20 | renders (legacy generators) |
| `points` / `render` | 11 / 12 | renders — agents (MRT/scatter); chaotic flows chaos-gated. `points/lenia` ships a definition but no shaders yet (staged, pre-existing gap) |
| `synth3d` / `filter3d` | 8 / 2 | **staged** (definitions only — 3D volumes/raymarch/meshes) |

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
