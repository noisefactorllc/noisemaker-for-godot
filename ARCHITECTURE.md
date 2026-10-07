# Noisemaker for Godot — Architecture

A port of the Noisemaker shader engine to Godot 4.7 `RenderingDevice` GLSL. The goal is live
procedural textures from the Noisemaker DSL that match the reference engine (the JS engine's WebGL2
backend) pixel for pixel. Program state and UI bindings are out of scope.

## The seam: the render graph

The reference compiles a DSL program in stages: `lex → parse → validate → expand →
allocateResources → Pipeline`. The seam between data logic and GPU work is the **render graph**, the
normalized JSON that `compileGraph(dsl)` produces (`reference/03`, `reference/04`,
`docs/GRAPH-JSON-SCHEMA.md`):

```
graph = { passes[], programs{}, textures{}, allocations{}, renderSurface, ... }
```

Everything upstream of the graph is pure data logic. Everything downstream (texture allocation,
double-buffering, pass execution, presentation) is backend work. The graph has two producers:

- **In-engine (production).** The GDScript compiler under `addons/noisemaker/compiler/`: `lang/`
  (lexer → parser → validator, effect registry, enums) and `graph/` (expander → orchestrator, resource
  allocation, dimensions, palette expansion). `Orchestrator.new(reg).build_graph(source)` returns the
  normalized graph with no Node.js, reference engine or network. Invalid programs return a
  `compileError` with structured diagnostics instead of a graph.
- **Reference (parity only).** `tools/export-graph.mjs` runs the unchanged reference `compileGraph`
  from a checkout named by `NM_REFERENCE_ROOT` and writes the graph JSON. It exists to check the
  in-engine compiler; the seven `parity/check_*.mjs` gates compare the two stage by stage.

Both producers feed the same executor and the same shaders.

## Runtime — `addons/noisemaker/runtime/`

`nm_backend.gd` executes the graph on a `RenderingDevice`. It mirrors the WebGL2 backend's GPGPU
model: every pass, including the definitions' `compute` passes, is a draw into color attachments.

| Reference | Noisemaker for Godot |
|---|---|
| `resources.js` liveness and linear-scan pool | `compiler/graph/resources.gd` (`allocate_resources`, run inside `build_graph`) and `compiler/graph/dim.gd`. `nm_backend.gd::allocate_textures` creates the textures; `set_texture_pooling(true)` reuses virtual textures from the allocation plan. |
| `pipeline.js` surfaces (`o0..o7`, geometry, volumes) | `global_*` surfaces as `RDTexture`s, with ping-pong double-buffering for state and feedback surfaces. |
| `backend.executePass` | Draw lists for fullscreen passes, MRT, points, billboards, mesh triangles, repeat loops, blending and feedback. |
| `Pipeline.render(time)` | `render(graph, normalized_time)`; stateful programs step through `render_samples(graph, total_frames, sample_every)`. |
| automation (`osc`, `midi`, `audio`) | `resolve_uniform_value`, fed by `set_midi_state`, `set_audio_state` and `set_audio_samples`. |
| frame export | `frame_export.gd` and `rendering_device_frame_export.gd` (`create_frame_export_queue`). |
| backend diagnostics | `shader_diagnostics.gd`: shader compile failures and silent fallbacks become structured records. |

The host API is scripting-only: `setup`, `render`, `render_samples`, `save_surface_png`, `close`. The
command-line tools `tools/render_graph.gd` and `tools/present.gd` build on it. There is no editor
node.

## Shaders — `addons/noisemaker/shaders/`

- `include/nm_core.glsl` holds the primitives that are bit-identical across effects (`pcg`, `prng`,
  `random`, `map`, `periodicFunction`, `positiveModulo`, `PI`, `TAU`).
- `effects/<ns>/<effect>/<program>.glsl` holds one fragment shader per reference program (an effect may
  have several, for example `blur → blurH, blurV`). Every program named by the 210 effect definitions
  has a shader.
- The fullscreen vertex stage, the present blit and the mip generator are built into `nm_backend.gd`.

The backend resolves `#include`s textually, prepends the vertex stage and compiles with
`rd.shader_compile_spirv_from_source`. Shaders are cached per program and define set. The raw GLSL
files carry Keep File import metadata so the editor does not import them as standalone shaders.

## Uniform model — one packed `vec4 data[N]` UBO per pass (set 0, binding 0)

Vulkan has no loose named uniforms, so every pass binds one packed UBO.

- **Effects with a reference `uniformLayout`** declare `Params { vec4 data[N]; }` and read
  `data[i].comp` at the slots the layout names. Four points effects (`flow`, `pointsEmit`,
  `pointsRender`, `pointsBillboardRender`) carry layouts written for this port, because the reference
  binds several programs per effect with loose WebGL2 uniforms; `tools/convert-definitions.mjs`
  preserves them on regeneration.
- **Effects without one** get a synthesized layout: an engine header in slots 0–2 (`resolution`,
  `time`, `aspectRatio`, `tileOffset`, `fullResolution`, `renderScale`, `deltaTime`, `frame`), then
  each `uniform` global from slot 3. The backend injects the `Params` declaration and a
  `#define <name> data[slot].comp` for every name, so the shader uses the reference's bare names.

Compile-time defines (`NOISE_TYPE`, `LOOP_OFFSET`, …) are injected as `#define`s. Input textures bind
as combined `sampler2D`s at set 0, bindings 1.. in `pass.inputs` order.

## Coordinates and color

- `RenderingDevice` has a top-left origin with Vulkan's Y-down clip space, so `texture_get_data` rows
  are top-down. One global Y-flip at readback reconciles the pipeline with the reference's
  bottom-left WebGL2 output. Orientation is consistent across passes, so no effect needs its own flip.
- Render targets are linear `rgba16f` by default (`rgba32f` and `rgba8` where a definition asks),
  never sRGB. Definition formats may use either the WebGL2 or the WebGPU spelling.
- Readback quantizes with `floor(v*255 + 0.5)` clamped to 0–255, the reference capture's
  `Math.round`.

## Validation — `parity/`

- `scripts/test` runs the engine-free suites; `scripts/test --godot-headless` runs the suites that need
  a Godot binary but no GPU. CI runs both.
- The seven compiler gates (`parity/check_*.mjs`) compare tokens, ASTs, validated plans, expanded
  passes, normalized graphs, the effect registry and the effect definitions with the reference.
- `scripts/parity-summary` renders every program in `parity/ledger.json` with Godot and compares it
  with a golden minted from the reference at the revision pinned in that script (WebGL2 in headless
  Chromium, 256×256, normalized time 0.25), under tolerance 2.001 and SSIM 0.98.
- `parity/sweep.sh` renders every program in one Godot process and rewrites `parity/ledger.json`.

## Not implemented

- Content the reference draws on the CPU or receives from the host: `filter/text` glyphs, `synth/media`
  images and video, the `filter/fibers`, `filter/scratches` and `filter/strayHair` overlays, and mesh
  files for `render/meshLoader` (a built-in triangle stands in). Those effects run their GPU passes
  over an empty texture.
- An editor node; integration is from GDScript.
- Rendering under `--headless`, where `RenderingDevice` is null. Compilation works headless.
