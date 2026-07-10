# Changelog

All notable changes to noisemaker-godot. Versions track `godot/addons/noisemaker/plugin.cfg`.
This is pre-1.0, WIP software — see the README's status banner.

## [Unreleased]

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
