# Changelog

All notable changes to Noisemaker for Godot. Versions track `godot/addons/noisemaker/plugin.cfg`.
This is pre-1.0, WIP software — see the README's status banner.

## [Unreleased]

### Synced to reference `349e9909` — `filter/pondRipples` gains `speed`

Incremental sync, not a re-crystallization: the only port-affecting change upstream since the
`75507112` content pin is a new `speed` control on `filter/pondRipples`. Everything else in the
range is docs, dependency bumps, or reference-only engine work (see below).

- **`filter/pondRipples`: new `speed` param** (int, `-5..5`, default `0`). The phase term becomes
  `r*ridges*2*PI - time*2*PI*speed`, so integer speeds shift the wave by whole cycles per
  normalized time loop and the animation is loop-seamless in either direction (positive travels
  outward, negative inward). `time` needs no JSON entry — it is an engine-provided global already
  present in the synthesized no-layout UBO header (`data[0].z`). Definition JSON regenerated with
  `tools/convert-definitions.mjs`; the shader is hand-maintained and was edited to match.
- **Parity:** 10/10 pondRipples fixtures PASS at max-abs-diff 1.000 / ssim 0.99996 — the eight
  pre-existing style/wrap/amount fixtures plus two new ones covering animation in both directions
  (`pondRipplesSpeed` at `+3`, `pondRipplesSpeedNeg` at `-5`). The `speed=0` goldens re-mint
  **byte-identically**, confirming the addition is a true no-op at the default; the `speed≠0`
  fixtures differ from their `speed=0` counterparts by max-abs-diff 239/253 (reference) and
  238/253 (Godot), so they genuinely exercise the new path rather than passing vacuously.
- **Pick animated fixture speeds that are not multiples of 4.** The harness pins `time` to 0.25, so
  a speed of ±4 shifts the phase by exactly one 2*PI cycle and aliases onto the static `speed=0`
  image — such a fixture passes while proving nothing (measured at `-4`: mean-abs-diff 0.0001,
  ssim 1.00000 against `speed=0`). `-5` was chosen for the negative fixture for this reason.
- **Gotcha worth keeping:** a stale committed graph JSON will now mis-render this effect. The DSL
  chain `noise(...).pondRipples(...)` puts `noise`'s own `speed: 25` in scope; previously
  pondRipples declared no `speed` global so the value was inert, but once it does, the reference
  expander resolves the pass uniform to pondRipples' **own default (0)** and shadows the inherited
  value. Graphs exported before this change still carry `speed: 25` and render an animated frame
  against a static golden (observed: max-abs-diff 148). Re-export graph JSON alongside goldens.
- Not ported: upstream's `asyncInit` overlay-recompile fix (`renderer/canvas.js`,
  `runtime/compiler.js`, `runtime/pipeline.js`). Those overlays are CPU-canvas products with no GPU
  program behind them, and the live-recompile path they fix does not exist in this port's offline
  render path.

### Crystallized against reference `75507112` (content-pinned; SHA unstable)

A **full parity re-verification** of the 26 Photoshop-parity artistic filters, not an incremental
sync. Upstream squashed the artistic-filter batch into a single amended-in-place commit and did a
release-readiness pass that *changed effects already ported*, so history correlation is dead: the
reference is pinned by **content** (a `git archive 75507112` snapshot), every effect and every
enum/define-selected mode re-minted from that snapshot and graded bit-exact, nothing trusted from
prior rounds. Result: effect×mode ledger **268 fixtures → 221 PASS / 40 NEAR / 0 FAIL / 7 SKIP**;
single-frame sweep **249/249, 4 skipped**; compiler gates green (lex/parse/validate/expand 230/230,
graph 263/263, registry 209 ops / 625 keys). Reference untouched, nothing pushed.

- **Re-ported drifted algorithms** (params matched by name; shader bodies had diverged in upstream's
  release pass): `strokes` (old hash-jitter comb → capsule/bristle `brushStrokeField` + coherent
  `strokeVariation` run-length + 4-neighbour-cross-min sumi-e; 5/5 modes), `photocopy`, `chrome`
  (self-distortion scale 0.03 → 0.5, a real strength bug), `wind`, `mosaicTiles` (both modes, reworked
  displaced-sample gap fill), `plasticWrap` (Blinn specular), `halftone` (single `angle` → five
  per-ink CMYK rotated-screen angles + full color path), `lensFlare` (per-lensType ghost-element
  table transcription), `spinBlur` (jitter formula), `median` (3-pass approximation → single-pass
  **exact quickselect**, radius 1/2/3 = 3×3/5×5/7×7).
- **Extended effects to current reference:** `texture` +10 material modes (regular…speckle, smooth
  quintic gradient fields; modes 0–4 preserved byte-identical), `dither` + `errorDiffusion` type
  (block Floyd-Steinberg), `emboss` + `gray` style + `colorAmount` (color default pinned), `edge` +
  `contourSide`, `plasticWrap` + `lightDirection` vec3.
- **Fixed a define-vs-uniform parity class** across `pondRipples` (style/wrap), `relief`, `scatter`,
  `morphology` (shape), `stipple` (mode), `extrude` (type/depthSource), `wind` (method): the port
  declared a compile-time-baked selector as a runtime `uniform`, so — because parity renders the
  reference's own graph, which serializes `define`s and never these as `uniforms` — the shader
  silently ran the *default* branch for every non-default mode. A mechanical registry-wide scan
  (0 mismatches after the fix) and a new PORTING-GUIDE.md section prevent recurrence. Also corrected
  several defaults baked into the reference graph (directionalBlur distance 20→60, photocopy darkness
  50→75, unsharpMask amount 60→220, scatter radius 5→12, wind strength/threshold).
- **Reverted `grain`:** upstream rolled back the round-1 grain-types feature to the pinned
  alpha/pause-only original (tile-aware bicubic value noise). The three grain-mode fixtures no longer
  even compile against the reference — the definitive revert signal — and were removed.
- **Full mode-matrix coverage:** ~37 new per-(effect, mode) fixtures mirroring upstream's
  `test_artistic_effect_release.mjs` enumeration, so every enum/define mode (not just defaults) has a
  minted golden. Chaos-gate routing corrected: `agentsPoints` and the `target`/`targetO0` north-star
  now SKIP with a `docs/CHAOS-GATE.md` reference (non-chaotic `agentsNoOklab` control stays bit-exact);
  `navTargetParams` moved to timed sampling. Registry effect count reconciled at **209** (one manifest
  key is not a registry effect).

### Added
- **In-engine DSL→graph compiler** (`godot/addons/noisemaker/compiler/`): a complete GDScript port of
  the reference compiler — `lang/` (lexer → parser → validator → effect-registry) and `graph/`
  (expander → orchestrator) — so the addon compiles the Polymorphic DSL with **no Node/reference/
  network** at runtime. Entry point `Orchestrator.new(EffectRegistry.new()).build_graph(source)`.
- **Self-contained render path:** `tools/render_graph.gd --dsl <file>` builds the graph in-engine and
  renders it; `tools/present.gd` composes the DSL beside the rendered canvas.
- **Compiler parity gates** (`parity/check_{lex,parse,validate,expand,graph,registry}.mjs`): each stage
  diffed against the reference over the (now 230-DSL) corpus — all **230/230** (registry 5/5 surfaces).
- **Integration docs:** addon README (`godot/addons/noisemaker/README.md`), `parity/README.md`, this
  changelog.
- Agents/points capability in the executor: MRT, procedural points/billboard deposit (`ONE,ONE`
  additive), repeat loops, ping-pong double-buffering, navierStokes, feedback.
- **Synced to reference `b7c1bc36`** (from `a27bf823`): 21 new Photoshop-parity `filter` effects —
  parallax, unsharpMask, highPass, median, morphology, directionalBlur, spinBlur, scatter, wind,
  pondRipples, extrude, halftone, stipple, oilPaint, watercolor, plasticWrap, relief, photocopy,
  stamp, chrome, hatch — plus extensions to existing filters: `lighting` height-map input, `emboss`
  angle/height controls, `invert` solarize mode, `edge` contour tracing, `grain` grain-types +
  intensity/contrast/mono. Backend fixes ported: repeated-pass ping-pong now adopts frame-local
  bindings instead of re-deriving them (fixes a desync after a non-repeat seed pass writes the same
  surface — verified via `navierStokes`'s pressure-solve pass, whose parity tightened from
  max-abs-diff ~5 to ~1 across its 30 s timed samples); `classicNoisedeck` `refract`/`cellRefract`
  mirror-wrap modes now actually reflect instead of no-op-ing. Tag hygiene: `uvRemap`
  "distortion"→"distort", `meshLoader` tags lowercased, 16 new curated tags registered. New
  PORTING-GUIDE.md finding: rotation of *position-derived* geometry (spinBlur, pondRipples, halftone,
  stipple, hatch) needs the **GLSL** rotation-matrix convention on this port, not WGSL's raw one —
  empirically established (spinBlur's own doctrine comment had this backwards; see PORTING-GUIDE.md's
  "Coordinate & sampling parity" section for the full writeup and the isolate-rotation-from-radial
  validation technique).
- **Synced to reference `36e7f3f5`** (from `b7c1bc36`): 5 new Photoshop-parity `filter` effects —
  strokes (directional brush-stroke smear engine: Angled/Sprayed/Dark Strokes, Sumi-e, Smudge Stick;
  two passes, stkSmear + stkPost unsharp), craquelure (cracked-plaster groove relief via Voronoi F1/F2
  + S8 bevel shading), mosaicTiles (wavy grouted ceramic tiles / Stylize Tiles via a runtime `mode`
  branch), patchwork (needlepoint raised-square relief with an analytic per-side bevel, not S8 —
  reuses filter/extrude's center-anchored-grid and cellAvgColor3x3 precedent), and lensFlare (additive
  ghost-chain lens flare, purely unrolled element tables, four lens types) — plus `lowPoly` extended
  with `borderWidth` (stained-glass cell "leading") and `lightIntensity` (radial center brightening),
  both exact no-ops at their zero defaults. Rotation doctrine applied and re-validated per-effect
  rather than assumed: strokes' rotate2D (fixed 45/135-degree fields) needed the GLSL/mat2 convention,
  confirmed bit-exact-class on all three fixed-angle modes; craquelure/mosaicTiles/patchwork/lensFlare
  turned out to have **no** rotation matrix at all despite superficially resembling the rotation-heavy
  class (Voronoi-cell math, axis-aligned grid math, and mirror-symmetric shape primitives respectively)
  — each effect's own WGSL/GLSL source headers were checked individually rather than trusting the
  broad "likely rotation-heavy" heuristic. New SSIM-gated tolerances (both <0.03% of pixels, ≥0.999,
  mechanism-traced in `parity/sweep.sh`): strokesSprayed's per-tap hash jitter landing bilinear taps on
  sub-pixel boundary ties, and strokesSmudge's `atan2`-based edge-following angle destabilizing at the
  Sobel gradient's near-zero singularity (same class as the pre-existing hatchPencil entry). Fixed one
  new-effect porting bug: lensFlare's local `aspectRatio` collided with the engine-injected reserved
  bare name of the same name (glslang "array size must be a positive integer"); renamed to `ar`
  (PORTING-GUIDE.md's reserved-name-collision section, now with a second worked example).

### Changed
- Render-graph executor consolidated into a single `runtime/nm_backend.gd`.
- Documentation brought up to date (the in-engine compiler is the production graph producer; the
  reference is parity/dev tooling only).

### Known limitations
- Verified on **Apple Silicon / Metal** only.
- Rendering needs a real `RenderingDevice` (null under `--headless`) — no headless/dedicated-server rendering.
- **3D** effects (`synth3d`/`filter3d`) ship definitions but no shaders yet.
- Chaotic agent flows (and `target.dsl`) render but as a different chaos instance — see
  `docs/CHAOS-GATE.md`.
- Integration is scripting-only (no editor `NMRenderer` node yet).

## [0.1.0]
- Initial Godot 4.7 `RenderingDevice` render-graph executor and per-effect GLSL ports; 2D effect
  catalog pixel-parity against the JS/WebGL2 reference on Apple Silicon/Metal.
