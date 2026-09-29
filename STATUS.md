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

*Incrementally synced 2026-09-17 to reference `688c5146` (`5a14256732b5..688c514655d3`) — audited upstream WebGPU frame
export row-inversion changes. Godot's `rendering_device_frame_export.gd` already applies `source.flip_y()` on texture
readback to align Vulkan/Metal RD coordinates with Godot's top-down Image convention; runtime contracts verified via
`parity/test_frame_export.py` (2/2 PASS). Updated `parity/shader_compile_sweep.gd` to merge pass-level `defines` into
sweep variants, restoring 798/798 clean Vulkan shader compiles (59/59 unittest PASS).*

*Incrementally synced 2026-09-18 to reference `ead42a5d` (`688c514655d3..ead42a5df110a7f04d732cb200a1a39629db8a67`) —
regenerated effect definitions via `tools/convert-definitions.mjs` (213/213 definitions match reference in
`parity/check_definitions.mjs`). Updated `defaultProgram` in `effects/synth3d/heightmap3d.json`,
`effects/render/renderLandscape3d.json`, and `parity/programs/heightmap3d_landscape.dsl` to use discrete write/read
chains instead of inline surface parameters. All parity gates verified: registry (213/213), lex (355/355), parse
(355/355), validate (355/355), graph (355/355), and parity unittests (59/59 PASS).*

*Incrementally synced 2026-09-19 to reference `f1d2b46a` (`ead42a5df110..f1d2b46a2773`) — audited upstream changes
(GAP-023 compiler phase-2 harness exit status reporting, chained variable test plan verification, unified agent
instructions; no shader source or effect definition changes). Verified effect definitions via
`tools/convert-definitions.mjs` (213/213 PASS). Added unit test in `parity/test_compiler_automation.py` covering chained
variable alias syntax compilation into terminal write blit graph. All parity gates verified: definitions (213/213),
registry (213/213), lex (355/355), parse (355/355), validate (355/355), graph (355/355), and parity unittests (60/60
PASS).*

*Incrementally synced 2026-09-19 to reference `2df19feb` (`f1d2b46a2773..2df19feb6ce1`) — audited upstream commit
`2df19feb6ce1` (support for borrowed `VideoFrame` in `updateTextureFromSource` across WebGL2 and WebGPU web backends).
Confirmed inapplicable to Godot (runs in Godot engine via GDScript and RenderingDevice Vulkan/Metal and does not consume
browser DOM / WebCodecs / WebGL2 / WebGPU media source pipelines). Zero effect definitions, DSL compiler operations, or
shaders changed upstream. All parity gates verified: definitions (213/213), registry (213/213), lex (355/355), parse
(355/355), validate (355/355), graph (355/355), and parity unittests (60/60 PASS).*

*Incrementally synced 2026-09-20 to reference `beabda38` (`2df19feb6ce1..beabda385253`) — ported upstream commit
`beabda385253` MIDI channel validation to unconditionally require static integer channels 1..16 across all channel-based
MIDI modes in `compiler/lang/validator.gd` (including legacy note modes). Audited upstream commit `6e0166ce` (pipeline
recreation format checks). Added unit test in `parity/test_compiler_automation.py` covering static integer 1..16 channel
enforcement across all legacy note modes. All parity gates verified: definitions (213/213 PASS), registry (213/213
PASS), lex (355/355 PASS), parse (355/355 PASS), validate (355/355 PASS), graph (355/355 PASS), and parity unittests
(61/61 PASS).*

*Incrementally synced 2026-09-21 to reference `f61ac073` (`beabda385253..f61ac0732088`) — ported upstream commit
`2f855c9c` removal of expired `filter/bc`, `filter/colorspace`, and `filter/hs` effects and shaders following completion
of consumer migration to `filter/adjust`. Audited upstream commits `0139e958` (frame export cancel accounting),
`7706a715` (shade-mcp pin), and `f61ac073` (test audio 32-channel modulation). Regenerated effect definitions via
`tools/convert-definitions.mjs` (210/210 definitions match reference in `parity/check_definitions.mjs`). All parity
gates verified: definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0,
effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS),
shader coverage (1/1 PASS), shader compile (1/1 PASS), and parity unittests (61/61 PASS).*

*Incrementally synced 2026-09-21 to reference `50b8f909` (`f61ac0732088..50b8f909ff59`) — ported upstream commit
`50b8f909` (GAP-001) enforcing output surface reference range `o0`–`o7` for `OUTPUT_REF` unless preceded by a `DOT`
token (member segment access like `foo.o8`) in `godot/addons/noisemaker/compiler/lang/lexer.gd`. Updated frontend
specification in `reference/01-dsl-frontend.md` Section 1.4. Added regression tests in
`parity/test_compiler_automation.py` covering out-of-range rejection across DSL positions (`render`, `read`, `write`),
boundary behavior for `o0` and `o7`, and preservation of member segments and other surface reference families (`s99`,
`vol99`, `geo99`, `xyz99`, `vel99`, `rgba99`, `mesh99`). All parity gates verified: definitions (210/210 PASS), registry
(ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse
(352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), and parity unittests (62/62 PASS).*

*Incrementally synced 2026-09-21 to reference `68d37721` (`50b8f909ff59..68d37721091a`) — audited upstream commit
`68d37721` (excluding builtins from mutation introspection in JS `transform.js`). Confirmed inapplicable to Godot (does
not implement JS AST mutation introspection; compiler frontend is execution-only). Zero effect definitions, DSL compiler
operations, or shaders changed upstream. All parity gates verified: definitions (210/210 PASS), registry (ops 210/210,
enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628 PASS), lex (352/352 PASS), parse (352/352 PASS),
validate (352/352 PASS), graph (352/352 PASS), and parity unittests (62/62 PASS).*

*Incrementally synced 2026-09-22 to reference `e5bd2013` (`68d37721091a..e5bd2013087e`) — ported upstream commit
`e5bd2013` (GAP-002: "fix: preserve source columns in DSL diagnostics") to preserve source column numbers from
`loc.column` (with fallback to `loc.col`) in diagnostic records in `godot/addons/noisemaker/compiler/lang/validator.gd`.
Added unit smoke checks in `godot/addons/noisemaker/compiler/_smoke.gd` and regression tests in
`parity/test_compiler_automation.py` covering exact column preservation on diagnostics, multi-line indentation,
caller-supplied AST column precedence, and omission of location on unlocated AST nodes. All parity gates verified:
definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628
PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), smoke (24/24 PASS), and
parity unittests (63/63 PASS).*

*Incrementally synced 2026-09-22 to reference `643b2be1` (`e5bd2013087e..643b2be1e28b8d4c9d34fb2c31ca118d5c414603`) —
ported upstream commit `643b2be1` ("feat: expose structured DSL lexer diagnostics") to emit structured diagnostics
(`code`, `stage`, `severity`, `message`, `location: {line, column}`, `span: {start, end}`) on lexer failures in
`godot/addons/noisemaker/compiler/lang/lexer.gd`. Updated `_TABLE` and added `stage(code)` in
`godot/addons/noisemaker/compiler/lang/diagnostics.gd` (`L001`-`L004`, `P001`-`P002`, `S001`-`S008`, `R001`). Preserved
UTF-16 code unit counting for source columns and span ranges across surrogate pairs and multi-line escape sequences.
Added smoke checks in `godot/addons/noisemaker/compiler/_smoke.gd` and regression tests in
`parity/test_compiler_automation.py` covering all 9 failure cases and token preservation. All parity gates verified:
definitions (210/210 PASS), registry (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628
PASS), lex (352/352 PASS), parse (352/352 PASS), validate (352/352 PASS), graph (352/352 PASS), smoke (28/28 PASS), and
parity unittests (65/65 PASS).*

*Incrementally synced 2026-09-23 to reference `5b81e04f` (`44bc4ed4ac72..5b81e04f8a4b`) — ported upstream commit
`0766743e` structured parser automation diagnostics `P003` and search directive diagnostics `P004` into
`godot/addons/noisemaker/compiler/lang/parser.gd`. Ported upstream commits `fde2ea40` (`classicNoisedeck/noise` multires
refraction zero-work guard) and `9b88e567` (`classicNoisedeck/glitch` zero-work early exits for glitchiness, scanlines,
and snow) into `godot/addons/noisemaker/shaders/effects/classicNoisedeck/noise/noise.glsl` and `glitch/glitch.glsl`.
Ported upstream commit `5b81e04f` output sink render deferral via `should_defer_render()` / `shouldDeferRender()` on
`SinkManager` (`godot/addons/noisemaker/runtime/sink.gd`) and `NoisemakerBackend`
(`godot/addons/noisemaker/runtime/nm_backend.gd`). Added unit tests in `parity/output_runtime_test.gd`, smoke tests in
`godot/addons/noisemaker/compiler/_smoke.gd`, and parity tests in `parity/test_compiler_automation.py`. All parity gates
verified: definitions (210/210 PASS), registry (210/210 PASS), shader compile sweep (798/798 clean Vulkan compiles),
smoke (30/30 PASS), and parity unittests (68/68 PASS).*

*Incrementally synced 2026-09-24 to reference `c9ee8a04` (`5b81e04f8a4b..c9ee8a049b2b`) — ported upstream commit
`7a54ab38` structured parser output diagnostics `P005` into `godot/addons/noisemaker/compiler/lang/diagnostics.gd` and
`godot/addons/noisemaker/compiler/lang/parser.gd` (`_parse_render_directive()`, `_parse_chain()` statement context
check, and `_parse_write_call()` surface, tex3d, and geo validation). Audited upstream commits across the range
(shaders/effects inventory unchanged at 210 effects, definitions and registries identical). Added smoke tests in
`godot/addons/noisemaker/compiler/_smoke.gd` and regression/precedence tests in `parity/test_compiler_automation.py`.
All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), smoke (34/34 PASS), and parity unittests
(70/70 PASS).*

*Incrementally synced 2026-09-24 to reference `13fa8b54` (`c9ee8a049b2b..13fa8b540025`) — ported upstream commit
`13fa8b54` structured parser subchain diagnostics `P006` into `godot/addons/noisemaker/compiler/lang/diagnostics.gd` and
`godot/addons/noisemaker/compiler/lang/parser.gd` (`_parse_subchain_call()` argument type validation, body dot
validation, and empty body checks). Audited upstream commits across the range (shaders/effects inventory unchanged at
210 effects, definitions and registries identical). Added smoke tests in `godot/addons/noisemaker/compiler/_smoke.gd`
and regression/precedence/compilation tests in `parity/test_compiler_automation.py`. All parity gates verified:
definitions (210/210 PASS), registry (210/210 PASS), smoke (38/38 PASS), and parity unittests (21/21 PASS).*

*Incrementally synced 2026-09-24 to reference `4891b995` (`13fa8b540025..4891b9953f9f`) — ported upstream commit
`4891b995` structured parser call expression diagnostics `P007` and remaining expectation diagnostics `P001` into
`godot/addons/noisemaker/compiler/lang/diagnostics.gd` and `godot/addons/noisemaker/compiler/lang/parser.gd`
(`_transform_from()` argument validation, `_parse_call()` inline namespace and mixed positional/keyword arguments,
`_parse_statement()` and `_parse_kwarg()` missing expression after '=', `_parse_primary()` array bracket, member dot,
and token fallbacks, and `_to_number()` number coercion). Audited upstream commits across the range (shaders/effects
inventory unchanged at 210 effects, definitions and registries identical). Added smoke tests in
`godot/addons/noisemaker/compiler/_smoke.gd` and regression/compilation tests in `parity/test_compiler_automation.py`.
All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), smoke (43/43 PASS), and parity unittests
(25/25 PASS, pytest 77/77 PASS).*

*Incrementally synced 2026-09-25 to reference `240740dd` (`4891b9953f9f..240740dd676a`) — ported upstream DSL compiler
updates:
- Lexer: Token carries `position: {"line", "column", "start", "end"}` with UTF-16 code unit offset tracking across
  surrogate pairs and line breaks.
- Parser: Structured diagnostics derive line, column, and span coordinates from source token positions, while preserving
  null locations/spans for caller-supplied unlocated tokens.
- Numeric coercion: diagnostics derive line, column, and span coordinates from array literal positions (`[1] + 1`),
  preserving null locations for unlocated expressions.
- GAP-027 subchain argument validation contract: registered `P008` (unknown/discarded key), `P009` (duplicate key), and
  `P010` (missing comma separator) in `diagnostics.gd`, surfaced `subchainArgumentDiagnostics` on `Subchain` nodes in
  parser and validator, and enforced SyntaxError rejection under strict opt-in mode (`subchainArguments: "strict"` via
  `--strict-subchain-args`).
- All parity gates verified: definitions (210/210 PASS), registry (210/210 PASS), lex (352/352 PASS), parse (352/352
  PASS), validate (352/352 PASS), smoke (63/63 PASS), and pytest compiler automation (27/27 PASS).*

*Incrementally synced 2026-09-25 to reference `9d3474df` (`240740dd676a..9d3474dfdc6c`, v1.0.181) — audited upstream
commit `9d3474df` (GAP-003: runtime validation of effect definitions against spec via `validateEffectDefinition` in
`shaders/src/runtime/effect-validator.js`). Integrated `validateEffectDefinition` into `tools/convert-definitions.mjs`
to validate all effect definitions against spec before writing. Added
`test_registered_effect_definitions_satisfy_specification` in `parity/test_shader_coverage.py` asserting that all 210
registered effect definitions satisfy the specification contract (`name`, `namespace`, `func`, `passes`, `program`,
`globals`, `paramAliases`). All 210 effect definitions match and pass validation cleanly.*

*Incrementally synced 2026-09-25 to reference `8eeb7b5a` (`9d3474dfdc6c..8eeb7b5ac14eb37a8d16037f607a88ce63924cd3`,
v1.0.183) — ported GAP-004 texture definition keys (`mipmaps`, `persistent`, `filter`) and GAP-005 pass keys (`name`,
`type`, `clear`, `viewport`, `samplerTypes`) from upstream:
- `tools/convert-definitions.mjs`: updated pass and texture conversion projections to preserve `viewport`,
  `samplerTypes`, `mipmaps`, `persistent`, and `filter`. Regenerated all 210 JSON effect definitions cleanly with
  validation against specification (10 3D effects updated with canonical `viewport` specifications).
- `godot/addons/noisemaker/compiler/graph/expander.gd`: updated optional pass field propagation (`opt_key`) to include
  `name`, `type`, `clear`, `viewport`, and `samplerTypes`.
- `godot/addons/noisemaker/compiler/graph/orchestrator.gd`: updated `_extract_texture_specs` to forward `mipmaps`,
  `persistent`, and 3D `filter` metadata.
- `parity/test_shader_coverage.py`: added `test_registered_effect_definitions_gap004_gap005_contract` asserting
  specification conformity for `viewport`, `samplerTypes`, and texture flags across all 210 effect definitions.
- `parity/test_compiler_automation.py`: added `test_expander_propagates_gap005_pass_fields` verifying pass-level
  preservation across AST expansion.
- All parity gates verified: definitions (210/210 PASS), graph (352/352 PASS), and full test suite (82/82 pytest PASS).*

*Incrementally synced 2026-09-25 to reference `2f47612c` (`9d3474dfdc6c..2f47612c2904`; the declared source range
`fca611fd8f91..2f47612c2904` is the same endpoint force-pushed — `fca611fd` is the pre-rebase SHA of the already-synced
`240740dd` content, re-derived from the observed range `13a8a0491dcf..2f47612c2904` by content audit) — ported upstream
texture-allocation policies (GAP-004) and the two follow-up fixes:
- Authorable texture policies: 3D texture specs accept `filter: 'nearest'|'linear'`; 2D texture specs accept `mipmaps:
  true` (full mip chain allocated up front, regenerated from level 0 after each frame's passes, before endFrame) and
  `persistent: true` (contents resampled through a NEAREST blit when the texture is recreated at a new size). Effect
  inventory unchanged: **no effect definition in the range uses these keys**, so compiled graphs, definitions (210/210),
  and registries are byte-identical; the propagation is exercised by smoke tests, and the runtime path activates only on
  opt-in.
- Compiler parity: `orchestrator.gd` `_extract_texture_specs()` now propagates `filter` (3D, only when truthy) and
  `mipmaps`/`persistent` (2D, only when authored) exactly as reference `compiler.js extractTextureSpecs`;
  `mipLevelCount`/`mipLevelSize` helpers and `refreshMipTargets` (global surfaces map one spec to both double-buffer
  halves) ported into `nm_backend.gd`.
- Runtime: mip regeneration draws a 2x2 box downsample per level (reference webgpu.js `fsMip`; texelFetch so
  unfilterable float formats work) into a scratch texture and `texture_copy`s it into the mip level (RenderingDevice
  framebuffers attach mip 0 only); mipmapped inputs sample through a new linear+mipmap sampler with `mipmap_filter`
  set explicitly (reference legacyDefault 'mipmap'), selected by the resolved READ texId string — `_tex_mip` is
  keyed by texId, never by `_resolve_read`'s RID. Odd-sized levels use the scale blit (`fsScale`). 3D `filter` is
  copied verbatim for backend consumption but this port's runtime does not yet read it (staged; inert until
  authored — as of this range no definition uses it).
- Audited upstream commits `62eb56fa` (WebGL2 mip-chain allocation fix + WebGPU cached mip bind groups — the
  allocation-half ported above; bind-group caching is a WebGPU-perf detail with no RenderingDevice analogue) and
  `2f47612c` (stop double-creating global surfaces on allocation change — the port's `allocate_textures` now keeps a
  mipmapped texture whose allocation matches, the same "matching allocation, preserve it" rule; no double-create existed
  in the port).
- Audited docs-only commits `fa4b2f02`, `69d83b80`, `13a8a04` (GAP-003 closure records, checkpoint notes — no shader
  source or definitions changed). Upstream runtime fidelity above is audited by content against the local reference
  clone at `origin/main` `6a0af04d` with the reproducible commands recorded in `docs/COMPLETION_GAPS.md` §1
  (`git diff 13a8a049..2f47612c -- shaders/effects shaders/src/lang` → empty; `extractTextureSpecs`/`fsMip`/`fsScale`
  hunks quoted there) — now committed verbatim: see the "Full declared-range audit, 2026-09-26"
  block in `docs/COMPLETION_GAPS.md` §1 with observed outputs for the full range
  `fca611fd..6a0af04d`: the `shaders/effects` diff is empty across the entire range, and the only
  `shaders/src/lang` delta is the already-ported GAP-027 subchain-argument contract (commits
  `66b2c721`/`240740dd` → `9d3474df`, P008/P009/P010 — present in the port's
  `compiler/lang/parser.gd`, `validator.gd`, and `_smoke.gd` tests). The 5 display-dependent test
  failures and the 8 expand diffs are verified baseline-identical at `55c3c92` (same commands,
  recorded in §1).*

*Incrementally synced 2026-09-26 to reference `6a0af04d` (`2f47612c2904..6a0af04d3c4f`; the declared
source range `fca611fd8f91..6a0af04d3c4f` spans this and the previous syncs, audited by ancestry —
`fca611fd` is an ancestor of `6a0af04d`) — closed out the last three code commits of the range:
- `6113da00` + `95743621` (GAP-006 texture pooling, opt-in): `nm_backend.gd` gains
  `set_texture_pooling()` / `texture_pooling` (default **off** — one texture per virtual id, byte-for-byte
  the historical behavior for every existing program), a static `build_texture_pooling_plan()`
  consuming the port's `graph.allocations` (texId -> `phys_N`, reference `graph.allocations` Map),
  `_release_regrouped_textures()` (destroy pooling groups whose membership changed, protecting
  RIDs of unchanged groups — RenderingDevice RIDs are shared only within one group), secondary-member
  allocation skip + `_apply_texture_aliases()` (point every pooled member's `_textures` entry at the
  group's shared storage RID, run BEFORE the undeclared-id `_ensure_tex` fallback so an aliased
  member never gets a spurious standalone texture), and `get_resource_plan()` (queryable
  allocation/sharing report). All reference safety guards ported: `global*` surfaces never pooled
  (the port additionally ping-pong double-buffers them), first-touch-read textures never pooled,
  self-sampled textures excluded, `drawMode`/`blend` partial writes excluded, `viewport` without
  `clear` excluded (`95743621`), full-clear viewport passes stay poolable, `persistent`/`mipmaps`/`is3D`
  specs excluded, raw (width, height, format) signature must match (JS truthiness for
  `drawMode`/`blend` mirrored by `_js_truthy`).
- `f83a427e` (one structured diagnostic union for backend shader/compiler failures): new
  `runtime/shader_diagnostics.gd` — `DIAGNOSTIC_CODES` (`ERR_SHADER_COMPILE`, `ERR_SHADER_LINK`,
  `ERR_SHADER_MISSING`, `ERR_NO_WGSL_SOURCE`), `parse_glsl_info_log` (ERROR/WARNING `0:LINE:`
  forms, unprefixed prose kept as info entries), `parse_diagnostic_text` ("binding index N not
  present" -> stage 'bind' + bindingIndex), `make()` (normalized diagnostic Dictionary with
  code/backend/stage/detail/messages/program/source/bindingIndex). `nm_backend.gd` records
  `last_shader_diagnostic` on fragment/vertex SPIR-V compile failure (stage 'compile', with parsed
  messages and the offending source), SPIR-V link failure (stage 'link' — the RenderingDevice
  analogue of WebGL2 program link), and missing vertex/fragment shader files (stage
  'missing-source'); the legacy `push_error` strings are unchanged so existing consumers keep their
  output. No throw convention exists in GDScript — the diagnostic is recorded, the legacy RID()/""
  sentinel returned. WebGPU-only pieces (`parseWebGPUCompilationMessages`, the bind-group retry
  loop, `ERR_NO_WGSL_SOURCE`) have no RenderingDevice analogue and are audited-inapplicable; the
  'bind' stage parser is ported for contract parity.
- Docs-only/inapplicable commits in the remaining delta (`63349a7d` upstream JS-CI workflow
  retirement — no `shaders/` content and this port has no such workflow; `919f653e`, `27590caa`,
  `85ded3a6`, `c6bc8e17`, `94fc880b`, `5e52a2a2`, `8eeb7b5a`, `6c3f9a26`, `428ea29b`, `ad17fd02`,
  `0b2866dd`, `93608f10`, `6a0af04d`, `01e9d620`, `3968f6c4`, `a651c075` — GAP-004/005/006/007
  closure records, texture-policy docs, llms-full.txt, Sphinx, checkpoint notes, CI evidence) —
  no shader source, definitions, DSL lang, or runtime behavior changed; nothing to port.
  `fa83eeab` (GAP-005 expander pass-field propagation) is a descendant of `2f47612c` inside this
  range but its content was ALREADY ported in the 2026-09-25 sync (`expander.gd` carries
  `name`/`type`/`clear`/`viewport`/`samplerTypes` verbatim; exercised by
  `test_expander_propagates_gap005_pass_fields` and `test_expander_propagates_sampler_types_and_clear`,
  both passing). Observed verbatim outputs for every claim above are committed in
  `docs/COMPLETION_GAPS.md` §1.
- Effect catalog unchanged: `git diff 2f47612c..6a0af04d -- shaders/effects shaders/src/lang` is
  empty; definitions 210/210 and registries identical. Texture pooling is opt-in and unused by every
  committed effect definition, so compiled graphs are unchanged.
- Tests: `parity/test_runtime_contract.py` +4 (`test_texture_pooling_plan_groups_and_guards` —
  pooling/exclusion matrix mirroring reference `test_resource_pooling.js`'s guards incl. the
  viewport-no-clear rule; `test_texture_pooling_disabled_by_default`;
  `test_texture_pooling_runtime_aliases_and_regroup_release` — alias application + regroup release
  over the static seams with a counting free callable, asserting each shared RID is freed exactly
  once; `test_shader_diagnostics_parse_and_normalize`).
  All parity gates on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`, `NM_REFERENCE_ROOT` at
  upstream `6a0af04d`): definitions 210/210, lex/parse/validate/graph 352/352, registry pass,
  expand 344/352 (the same 8 documented pass-defines diffs), smoke ALL PASS, unittest 83/88
  (the 5 failures are the same display-dependent windowed tests that fail identically on the
  unmodified baseline — no display/Vulkan in this container). No pixel-parity re-sweep (pooling is
  default-off; shader math untouched).

*Incrementally synced 2026-09-27 to reference `12b4d74f` (`6a0af04d3c4f..12b4d74fb4f2`; the declared
job range was `6a0af04d3c4f..403c2a4bf2cb` with a `forced` flag and eight observed non-contiguous
ranges — audited rather than assumed: `git merge-base --is-ancestor` shows every observed range-end
(`9f85687d`, `7dc0f564`, `7443f6e6`, `c2252f0c`, `e73a44a3`, `12b4d74f`) is a descendant of the
declared end `403c2a4b` and an ancestor of upstream `main`, so the effective delivered range is the
linear `6a0af04d3c4f..12b4d74fb4f2`, 17 commits — the two commits after `12b4d74f` on upstream `main`
(`ec457c2e`, `8fe3ccaf`) are docs-only) — audit-only sync, nothing to port:
- `403c2a4b` (GAP-008, predict `replaceEffect` compatibility before mutation): JS
  `shaders/src/lang/transform.js` +377 (`getCompatibleReplacements`/`replaceEffect` prediction,
  `predictReplacement` re-export from `shaders/src/index.js`/`lang/index.js`) and a new read-only
  `getParamAliases()` in `shaders/src/lang/paramAliases.js`. Inapplicable to Godot: the port does not
  implement JS AST mutation introspection (its compiler frontend is execution-only — same ruling as
  the `68d37721` `transform.js` sync); the port's oracle tooling (`tools/dump-registry.mjs`,
  `tools/dump-validate.mjs`) imports only `registerParamAliases`, and the new accessor neither
  changes registry output nor any oracle dump (registry parity re-verified identical: ops 210/210,
  enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628).
- `b35361e0` (GAP-009 temporal no-animation + universal low-variety metrics), `9f85687d` (GAP-010
  `--strict-uniforms` aggregation), `7dc0f564` (GAP-011 measured uniform deltas), `7443f6e6`
  (GAP-012 WebGPU render-surface readback pin), `c2252f0c` (GAP-015 metric mirror), `e73a44a3`
  (GAP-014 explicit-time warm-up) — all confined to the upstream JS test harness
  (`shaders/tests/test-harness.js`, `frame-metrics.js`, `uniform-*.js`, `test_*.js` +
  `scripts/run-js-tests.js` registration). Upstream's harness is not a mirrored surface of this port
  (the port's parity harness is its own Python/`export-and-render.mjs` stack; the harness-contract
  gate pins the port's own files); no `shaders/src` change in these commits.
- `12b4d74f` (GAP-016 static effect preflight): new pure-reporting `shaders/src/runtime/preflight.js`
  (`preflightEffect()`: per-backend authorability for webgl2/webgpu from source fields, predicted MRT
  `rgba32f->rgba16f` demotions, predicted `maxTextureSize` clamps) and additive
  `Pipeline.preflight(capabilities?)`; `Pipeline.mrtFormatBytes()` now delegates to the shared
  `mrtFormatBytes()` — observed byte-identical switch (rgba32f 16 / rgba8 4 / default 8), so runtime
  behavior is unchanged. Inapplicable to Godot: authorability here is a webgl2/webgpu source-language
  question with no RenderingDevice analogue, the report is read-only and additive (never invoked by
  compilation or rendering), and the port's backend already applies its device-limit demotions at
  runtime (ported in the earlier device-limits syncs; `parity/test_device_limits.py` unchanged).
- Docs-only: `01e9d620`, `3968f6c4`, `a651c075`, `66b8ce7d`, `19fdcb56`, `132d1bf9`, `407eb7a7`,
  `0ac52500` — upstream gap closure records, Sphinx, checkpoint notes, CI evidence; nothing to port.
- Effect catalog unchanged: `git diff 6a0af04d..12b4d74 -- shaders/effects` is empty and
  `shaders/src/lang` changed only as recorded above; no definition, shader, or registry file moved.
- Observed gate outputs on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`,
  `NM_REFERENCE_ROOT` at upstream `12b4d74f`, fresh clone at
  `/state/cache/scratch/noisemaker-upstream` checked out exactly at `12b4d74fb4f2`):
  definitions 210/210 PASS; registry PASS (ops 210/210, enums 8/8, paramAliases 44/44,
  effectAliases 0/0, effectKeys 628/628); lex 352/352, parse 352/352, validate 352/352,
  graph 352/352; expand 344/352 (the same 8 documented pass-defines diffs); smoke
  SMOKE: ALL PASS; unittest 96 tests / 12 failures with a Godot binary present but no
  display/Vulkan. Count reconciliation vs the preceding record's "unittest 83/88, 5 failures":
  that run had NO Godot binary, so the live-render suites were skipped/collect-error; this run
  downloaded Godot 4.7, which un-skips 8 live-render tests that then fail on display-server init
  (every failure log is Godot's "X11 Display is not available / Unable to create DisplayServer",
  an environmental failure, not a code assertion). Baseline identity verified directly: the same
  96-test run at the parent commit `6ae3329` in a clean clone produces the identical 12-test
  failure set (compared by test id), and no parity test reads `STATUS.md`/`docs/COMPLETION_GAPS.md`.
  The 12 live-render failures are environmental (no display/Vulkan in this container); live
  rendering is covered by the job's native parity cases. No pixel-parity re-sweep (no shader math
  touched). Upstream evidence, observed verbatim in the pinned clone (re-runnable against any
  upstream clone; the scratch path is ephemeral): `git diff 6a0af04d3c4f..12b4d74fb4f2 --
  shaders/effects` → empty output; `git diff --name-only 6a0af04d3c4f..12b4d74fb4f2 -- shaders/src`
  → exactly `shaders/src/index.js`, `shaders/src/lang/index.js`,
  `shaders/src/lang/paramAliases.js`, `shaders/src/lang/transform.js`,
  `shaders/src/runtime/pipeline.js`, `shaders/src/runtime/preflight.js`;
  `git merge-base --is-ancestor 403c2a4bf2cb 12b4d74fb4f2` → 0 (declared end is an ancestor of the
  delivered end; every other observed range-end is likewise an ancestor-of-delivered-end, verified
  per-commit); at observation time (2026-09-27) `git log --oneline 12b4d74fb4f2..origin/main` listed
  `ec457c2e`, `8fe3ccaf`, both docs-only (no `shaders/` paths); on re-fetch later the same day,
  origin/main had additionally advanced to `93229933` ("feat(harness): complete, lossless
  definition-schema introspection with an upstream-loss audit (GAP-017)"), which is outside this
  job's declared/observed ranges and is left for the next sync. Full-range `git diff --stat` is
  committed verbatim in `docs/COMPLETION_GAPS.md` §1.

*Incrementally synced 2026-09-27 to reference `93229933` (`12b4d74fb4f2..93229933b102`; the declared
job range was `403c2a4bf2cb..93229933b102` with a `forced` flag and one observed non-contiguous range
`8fe3ccaf2cc8..93229933b102` — audited rather than assumed: `git merge-base --is-ancestor 403c2a4bf2cb
12b4d74fb4f2` → 0 and `git merge-base --is-ancestor 12b4d74fb4f2 93229933b102` → 0, so the already-audited
prefix `6a0af04d..12b4d74f` carries over and the effective new delta is the linear
`12b4d74fb4f2..93229933b102`, 3 commits) — audit-only sync, nothing to port:
- `93229933` (GAP-017, complete lossless definition-schema introspection): new upstream
  `shaders/tests/definition-schema.js` (imports each definition live — Effect-instance and
  Effect-subclass exports — and pins the Shade-MCP projection loss via `auditSchemaLoss()`/
  `auditDefinitionLoss()`), new `shaders/tests/test_definition_schema.js` (161 lines), +60 lines in
  `shaders/tests/test-harness.js`, and one registration line in `scripts/run-js-tests.js`. Same ruling
  as the GAP-009/010/011/012/015/014 harness syncs: upstream's JS test harness is not a mirrored
  surface of this port (the port's parity harness is its own Python/`export-and-render.mjs` stack;
  `parity/test_harness_contract.py` pins the port's own files). The introspection reads `shaders/src`
  definitions live but changes no `shaders/src` file, and the port's oracle tooling
  (`tools/dump-registry.mjs`, `tools/dump-validate.mjs`, `tools/export-graph.mjs`) imports only from
  `shaders/src` — no parity-gate input changed (verified: no repo tooling imports `shaders/tests`).
- `ec457c2e`, `8fe3ccaf` — docs-only (AI-development-contract checkpoint through `12b4d74`,
  post-publication deployed-contract evidence); no `shaders/` paths.
- Effect catalog unchanged: `git diff 403c2a4bf2cb..93229933b102 -- shaders/effects` is empty, and the
  full-range `shaders/src` delta remains exactly the two GAP-016 files already ruled inapplicable
  (`shaders/src/runtime/pipeline.js`, `shaders/src/runtime/preflight.js`).
- Observed gate outputs on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`,
  `NM_REFERENCE_ROOT` at upstream `93229933b102`, fresh full clone): definitions 210/210 PASS;
  registry PASS (ops 210/210, enums 8/8, paramAliases 44/44, effectAliases 0/0, effectKeys 628/628);
  lex 352/352, parse 352/352, validate 352/352, graph 352/352; expand 344/352 (the same 8 documented
  pass-defines diffs, unchanged); smoke SMOKE: ALL PASS; unittest 96 tests / 12 failures, every
  failure Godot display-server init ("X11 Display is not available / Can't create the Wayland display
  server") — the identical environmental failure set recorded for the previous sync (live rendering
  is covered by the job's native parity cases). No port file changed in this sync, so no
  pixel-parity re-sweep. Delta `git diff --stat 12b4d74fb4f2..93229933b102` committed verbatim in
  `docs/COMPLETION_GAPS.md` §1.

*Incrementally synced 2026-09-27 to reference `a912749f` (`93229933b102..a912749fab5c`; the declared
job range was `403c2a4bf2cb..a912749fab5c` with a `forced` flag and observed non-contiguous ranges
`7c5f17658d8c..a912749fab5c` and `11d7c69922f3..296e0138c474` — audited rather than assumed:
`git merge-base --is-ancestor 403c2a4bf2cb 93229933b102` → 0 and `git merge-base --is-ancestor
93229933b102 a912749fab5c` → 0, so the already-audited prefix `93229933` carries over and the
effective new delta is the linear 2-commit `93229933b102..a912749fab5c`; the second observed range's
endpoint `296e0138` (GAP-021 frame-resolution harness, `11d7c69922f3..296e0138c474`, one commit,
`shaders/tests/**` + `scripts/run-js-tests.js` + `llms-full.txt` only) is NOT an ancestor of the
delivered end `a912749fab5c` and was audited separately — same harness-only ruling, nothing to port)
— audit-only sync, nothing to port:
- `a912749f` (GAP-019, true input-passthrough probe): new upstream `shaders/tests/passthrough-input.js`
  (489 lines — reads back the consumed input texture and render surface at time 0 under a
  bit-for-bit determinism guard, reports aligned/flipped mean abs output-to-input diff at the
  0.01 boundary, final write-blit as in-program positive control, `--passthrough-input` opt-in),
  +259 `shaders/tests/test_passthrough_input.js`, +70 `shaders/tests/test-harness.js`, one
  registration line in `scripts/run-js-tests.js`. Same ruling as the GAP-009..015/017 harness
  syncs: upstream's JS test harness is not a mirrored surface of this port (the port's parity
  harness is its own Python/`export-and-render.mjs` stack); no `shaders/src` file changed and no
  repo tooling imports `shaders/tests`, so no parity-gate input changed.
- `7c5f1765` — docs-only (AI-development-contract checkpoint through `9322993`); no `shaders/`
  paths.
- Effect catalog unchanged: `git diff 403c2a4bf2cb..a912749fab5c -- shaders/effects` is empty
  (verified); the effective-range `shaders/src` delta is empty.
- Observed gate outputs on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`,
  `NM_REFERENCE_ROOT` at upstream `a912749fab5c`, fresh full clone pinned exactly at the end):
  definitions 210/210 PASS; registry PASS (ops 210/210, enums 8/8, paramAliases 44/44,
  effectAliases 0/0, effectKeys 628/628); lex 352/352, parse 352/352, validate 352/352,
  graph 352/352; expand 344/352 (the same 8 documented pass-defines diffs, unchanged); smoke
  SMOKE: ALL PASS; unittest 96 tests / 12 failures, every failure Godot display-server init
  ("X11 Display is not available / Can't create the Wayland display server") — the identical
  environmental failure set recorded for the previous syncs (live rendering is covered by the
  job's native parity cases). No port file changed in this sync, so no pixel-parity re-sweep.
  Delta `git diff --stat 93229933b102..a912749fab5c` committed verbatim in
  `docs/COMPLETION_GAPS.md` §1.

*Incrementally synced 2026-09-28 to reference `73c15be0` (`a912749fab5c..73c15be00d68`; the declared
job range was `a912749fab5c..73c15be00d68` with a `forced` flag and three observed ranges
`04e8582c..c28e8fdb`, `c28e8fdb..7aff843a`, `7aff843a..73c15be0` — audited rather than assumed:
`git merge-base --is-ancestor a912749fab5c 73c15be00d68` → exit 0 and each observed range endpoint
is an ancestor of the delivered end, so the range is contiguous and the effective new delta is the
linear 6-commit `a912749fab5c..73c15be00d68`) — audit-only sync, nothing to port:
- `296e0138` (GAP-021 frame-resolution harness) and `7aff843a` (GAP-024 session-identity harness):
  `shaders/tests/**` + `test-harness.js` + `scripts/run-js-tests.js` only. Same ruling as the
  GAP-009..015/017/019/021 harness syncs: upstream's JS test harness is not a mirrored surface of
  this port; no repo tooling imports `shaders/tests`.
- `c28e8fdb` (fix: preserve mesh target after depth allocation): +2 lines in
  `shaders/src/runtime/backends/webgl2.js` — after `ensureDepthBuffer(fbo, …)` the WebGL2 backend
  rebinds the framebuffer, because allocating a new depth renderbuffer unbinds the FBO mid-pass.
  Inapplicable to Godot: the port's RenderingDevice backend has no persistent FBO binding —
  `nm_backend.gd` creates the depth texture when building the framebuffer's attachment list
  (`_depth_texture`, appended before `draw_list_begin`), so a depth allocation can never occur
  between bind and draw. No analogous window exists.
- `73c15be0` (GAP-026, invoke onInit/onUpdate/onDestroy lifecycle hooks in the production
  renderer): +129 `shaders/src/runtime/pipeline.js`, +3 `shaders/src/runtime/compiler.js`. The
  hooks are the JS Effect object model's config/subclass callbacks (`effect.js`
  `_configOnInit`/`_configOnUpdate`/`_configOnDestroy`, base-class no-ops). The only shipped
  effect defining them is `synth/media` (`shaders/effects/synth/media/definition.js`, unchanged
  this range), whose `onUpdate` returns `imageSize` from JS media state set by the host app via
  `setMediaDimensions` — web-app integration state, not render-graph math. Inapplicable to Godot:
  the port's effect surface is data (JSON definitions + GLSL) with no Effect object model — there
  is no per-effect callback the production renderer could invoke, and `imageSize` for
  `mediaInput` is resolved from the supplied input texture by the port's own uniform machinery
  (grep for onInit/onUpdate/onDestroy/asyncInit across the addon returns nothing).
- `04e8582c`, `11d7c699` — docs-only; no `shaders/` paths.
- Effect catalog unchanged: `git diff a912749fab5c..73c15be00d68 -- shaders/effects` is empty
  (verified).
- Observed gate outputs on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`,
  `NM_REFERENCE_ROOT` at upstream `73c15be00d68`, fresh full clone pinned exactly at the end):
  definitions 210/210 PASS; registry PASS (enums 8/8, paramAliases 44/44, effectAliases 0/0,
  effectKeys 628/628); lex 352/352, parse 352/352, validate 352/352, graph 352/352; expand
  344/352 (the same 8 documented pass-defines diffs, unchanged); smoke SMOKE: ALL PASS; unittest
  118 tests / 13 failures, every failure Godot display-server init ("X11 Display is not
  available / Can't create the Wayland display server") — the same environmental class recorded
  for the previous syncs (the count moved from 96/12 because test files added since that record
  — kit playback, mesh pipeline — are themselves display-dependent and fail identically; live
  rendering is covered by the job's native parity cases). No port file changed in this sync, so
  no pixel-parity re-sweep. Delta `git diff --stat a912749fab5c..73c15be00d68` committed verbatim
  in `docs/COMPLETION_GAPS.md` §1.

*Incrementally synced 2026-09-29 to reference `68273906` (`73c15be00d68..682739066d3b`; the declared
job range was `73c15be00d68..682739066d3b` with a `forced` flag and two observed ranges
`3e21906e..a5059106`, `a5059106..68273906` — audited rather than assumed: `git merge-base
--is-ancestor 73c15be00d68 682739066d3b` → exit 0 and each observed range endpoint is an ancestor
of the delivered end, so the range is contiguous and the effective new delta is the linear 8-commit
`73c15be00d68..682739066d3b`) — audit-only sync, nothing to port:
- `a5059106` and `68273906` (upstream GAP-032, multi-device audio capture): +272
  `shaders/src/runtime/external-input.js`, +312 `shaders/tests/test_external_input.js` — the test is
  never-ported (upstream's JS test harness is not a mirrored surface, same ruling as the
  GAP-009..015/017/019/021/024 harness syncs). The runtime change is entirely inside the web
  `AudioInputManager`: it now opens one extra `getUserMedia` stream per selected-device requirement
  from `Pipeline.getAudioInputRequirements()`, registers devices/channels on `AudioState`
  (`registerDevice`/`registerDefaultChannels`), splits channels through a `ChannelSplitterNode` with
  a per-channel `AnalyserNode`, and tears captures down through the public reset paths. This is
  browser host capture integration — `getUserMedia`/`AudioContext`/media-device enumeration — not
  render-graph math. Inapplicable to Godot: the port's mirrored audio surface is the graph-side
  requirements query, `nm_backend.gd` `get_audio_input_requirements()` (gated by
  `parity/test_runtime_contract.py`), which upstream did not change in this range; the port consumes
  host-fed audio samples (`set_audio_samples`) and capture belongs to the Godot host application.
  No analogous capture manager exists in the port to update.
- `3e21906e`, `d95d0c8c`, `cdb60cfc`, `53398923` — docs-only (contract checkpoints, GAP-029
  narrowing); no `shaders/` paths. `6b05a270`, `a50c90bc` — dependency bumps (eslint, ruff);
  no `shaders/` paths.
- Effect catalog unchanged: `git diff 73c15be00d68..682739066d3b -- shaders/effects` and
  `-- shaders/src/lang` are both empty (verified).
- Observed gate outputs on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`,
  `NM_REFERENCE_ROOT` at upstream `682739066d3b`, fresh full clone pinned exactly at the end):
  definitions 210/210 PASS; registry PASS (ops 210/210, enums 8/8, paramAliases 44/44,
  effectAliases 0/0, effectKeys 628/628); lex 352/352, parse 352/352, validate 352/352, graph
  352/352; expand 344/352 (the same 8 documented pass-defines diffs, unchanged); smoke
  SMOKE: ALL PASS; unittest 121 tests / 14 failures — 13 direct Godot display-server-init failures
  ("X11 Display is not available / Can't create the Wayland display server") plus
  `test_cancellation_then_recovery`, which spawns the windowed observer and requires the 1800-frame
  render to still be running at the 5 s cancel window; in the display-less container Godot exits
  immediately on display-init failure, the same environmental class (live rendering is covered by
  the job's native parity cases). No port file changed in this sync, so no pixel-parity re-sweep.
  Delta `git diff --stat 73c15be00d68..682739066d3b` committed verbatim in
  `docs/COMPLETION_GAPS.md` §1.

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
| `filter` | 113 | renders (color ops, convolutions, warps, multi-pass, feedback) — 26 Photoshop-parity artistic
filters, **re-crystallized against `75507112`** (see Parity). The `75507112` pass re-ported drifted algorithms (strokes,
photocopy, chrome, wind, mosaicTiles, plasticWrap, halftone, lensFlare, spinBlur, median), extended `texture` to 15
material modes and `dither` with error-diffusion, added `emboss` gray / `edge` contourSide / `plasticWrap`
lightDirection, fixed a define-vs-uniform class across pondRipples/relief/scatter/morphology/stipple/extrude, and
**reverted** `grain`'s round-1 grain-types back to the pinned alpha/pause form |
| `mixer` | 15 | renders (whole namespace) |
| `classicNoisedeck` | 20 | renders (legacy generators) |
| `points` / `render` | 11 / 12 | renders — agents (MRT/scatter); chaotic flows chaos-gated. `points/lenia` ships a
definition but no shaders yet (staged, pre-existing gap) |
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
