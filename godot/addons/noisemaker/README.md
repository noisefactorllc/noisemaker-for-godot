# Noisemaker for Godot

Live procedural textures from the Noisemaker DSL, compiled to a render graph and executed on Godot's
low-level `RenderingDevice`, built to match the reference engine (the JS engine's WebGL2 backend)
pixel for pixel. The addon is self-contained: it compiles the DSL and renders it with no Node.js, no
reference engine and no network.

This README is for integrators. Contributors porting shaders or engine code should read the
repository's `ARCHITECTURE.md`, `PORTING-GUIDE.md` and `parity/README.md`.

## Requirements

- **Godot 4.7** with the **Forward+** renderer.
- **A real `RenderingDevice`.** The backend renders through a local `RenderingDevice`, which is null
  under `--headless`, so rendering needs a window. For offscreen work, position the window off screen
  (`--position 5000,5000`), as `tools/render_graph.gd` does. Compiling a program works headless.
- **A Vulkan-class GPU** with `rgba16f` and `rgba32f` render targets. Parity is qualified on macOS (Apple
  Silicon, Metal). Windows (NVIDIA, Vulkan) renders but is not qualified.

## Installation

1. Copy the `addons/noisemaker/` folder into your project's `res://addons/`. It carries its own
   `LICENSE` and the upstream engine's `LICENSE-noisemaker.txt`.
2. Enable **Noisemaker** under *Project Settings ▸ Plugins*.

The plugin registers no editor nodes. Integration is from GDScript, as below.

## Getting started

- An `EffectRegistry` loads the bundled effect definitions.
- The `Orchestrator` compiles a DSL string to a normalized render graph.
- The `Backend` executes the graph on a `RenderingDevice`.

```gdscript
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator   := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const Backend        := preload("res://addons/noisemaker/runtime/nm_backend.gd")

func render_dsl_to_texture(dsl: String, size := 512) -> ImageTexture:
    # RenderingDevice is null under --headless, so this must run with a window.
    var rd := RenderingServer.create_local_rendering_device()
    if rd == null:
        push_error("RenderingDevice unavailable (run non-headless, with a window)")
        return null

    var reg := EffectRegistry.new()
    reg.load_all()                                  # load the bundled effect definitions (once)
    var graph = Orchestrator.new(reg).build_graph(dsl)
    if graph.has("compileError"):
        push_error(str(graph["compileError"]["diagnostics"]))
        rd.free()
        return null

    var backend := Backend.new()
    backend.setup(rd, "res://addons/noisemaker", Vector2i(size, size))
    var img: Image = backend.render_samples(graph, 1, 1)[0]   # render one frame
    backend.close()                                 # release every backend-owned GPU handle
    backend.free()
    rd.free()                                       # the device is yours: free it after close()
    return ImageTexture.create_from_image(img)
```

**Ownership.** The backend owns every GPU handle it derives from the device you pass in; you keep the
device. Call `backend.close()` (frees backend-owned handles, cancels active frame exports, leaves
textures you injected alone), then free the device. Freeing the device first leaks backend handles.
Closing twice is a no-op.

```gdscript
$TextureRect.texture = render_dsl_to_texture(
    "search synth\nnoise(scaleX: 60, scaleY: 60, seed: 1).write(o0)\nrender(o0)")
```

To write a PNG instead, render at a normalized time and save the render surface:

```gdscript
backend.setup(rd, "res://addons/noisemaker", Vector2i(512, 512))
backend.render(graph, 0.25)                 # normalized time 0..1
backend.save_surface_png("user://out.png")  # true on success
```

**Stateful programs** (navierStokes, feedback, cellularAutomata, agent sims) evolve over frames.
`render_samples(graph, total_frames, sample_every)` steps at 60 fps and returns the frames where
`frame % sample_every == 0`:

```gdscript
var frames := backend.render_samples(graph, 1800, 1800)   # 30 s of evolution, final frame only
```

From the command line, `tools/render_graph.gd --dsl <file.dsl> --out <file.png>` renders a program to
a PNG, and `tools/present.gd` shows the DSL beside the canvas. Both need a window.

## Inputs

- **Automation:** `osc()` oscillators, including `oscKind.noise2d`, are evaluated per frame.
- **MIDI:** `set_midi_state(state)` with per-channel `key`, `velocity`, `gate` and `time`.
- **Audio:** `set_audio_state(state)` for band levels (`low`, `mid`, `high`, `vol`, `raw`), and
  `set_audio_samples(waveform, spectrum)` (up to 128 values each) for `synth/scope` and
  `synth/spectrum`. `get_audio_input_requirements(graph)` lists the inputs a graph reads.
- **Not supported:** content the reference draws on the CPU or receives from the host. `filter/text`
  glyphs, `synth/media` images and video, and the `filter/fibers`, `filter/scratches` and
  `filter/strayHair` overlays render from an empty texture; `render/meshLoader` draws a built-in
  triangle instead of a loaded mesh.

## Host API

`EffectRegistry` (`compiler/lang/effect_registry.gd`):

| Member | Purpose |
|---|---|
| `load_all() -> void` | Load the bundled effect definitions (`effects/**/*.json`). Call once. |

`Orchestrator` (`compiler/graph/orchestrator.gd`), constructed with an `EffectRegistry`:

| Member | Purpose |
|---|---|
| `build_graph(source: String, options := {}) -> Dictionary` | Compile a DSL string to the normalized render graph. Invalid input (unknown effect, malformed syntax, lexer errors, any validator error) returns `{"compileError": {"stage", "diagnostics"}}` instead; check for it before rendering. Warnings do not reject. |

`Backend` (`runtime/nm_backend.gd`):

| Member | Purpose |
|---|---|
| `setup(rd, addon_dir, screen: Vector2i) -> void` | Initialize against a `RenderingDevice`. `addon_dir` is `"res://addons/noisemaker"`; `screen` is the render resolution. |
| `render(graph, normalized_time := 0.25) -> void` | Render one frame at normalized time 0..1. |
| `render_samples(graph, total_frames, sample_every) -> Array[Image]` | Step `total_frames` at 60 fps and return an `Image` at each `frame % sample_every == 0`. |
| `save_surface_png(path) -> bool` | Write the render surface as 8-bit RGBA PNG. |
| `render_surface_texture() -> RID` | The texture of the surface the graph presents. |
| `set_texture_pooling(enabled) -> void` | Reuse virtual textures from the graph's allocation plan. Off by default. |
| `set_midi_state`, `set_audio_state`, `set_audio_samples`, `get_audio_input_requirements` | External inputs; see *Inputs*. |
| `create_frame_export_queue(options := {})` | Asynchronous frame export. Returns `null` with an error before `setup` or after `close`; active exports are cancelled when the backend closes. |
| `close(options := {}) -> void` | Release every backend-owned GPU handle and cancel active frame exports. The device stays yours. |

Output is 8-bit RGBA, linear (no sRGB curve) and top-down.

## Performance

Performance is not optimized. The main costs:

- **Resolution** dominates raymarch, fluid and feedback effects. Start at 256² and scale up.
- **Points and agent effects** scale with `stateSize²` (capped at 2048, about 4.2M agents).
- **Stateful programs** run the whole graph once per frame: `render_samples(g, 1800, …)` runs it 1800
  times.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `create_local_rendering_device()` returns null | Running `--headless` or without a window | Run with a window; for offscreen use `--position 5000,5000`. |
| `build_graph` returns `compileError` | Invalid DSL | Read the diagnostics. Every program needs a `search` directive and a `write(oN)`. |
| A stateful program looks frozen | Only one frame rendered | Use `render_samples(graph, N, …)` with enough frames (60 per second). |
| A chaotic agent flow differs from the reference | Feedback amplifies a legal rounding difference | Expected; see the repository's `docs/CHAOS-GATE.md`. |

## How it works

DSL → in-engine compiler (`Orchestrator.build_graph`: lexer → parser → validator → expander →
normalize) → render graph (`passes`, `programs`, `textures`, `renderSurface`) → `nm_backend.gd` runs
the passes on `RenderingDevice` (fullscreen draws, MRT, points and billboards, ping-pong buffers,
repeat loops) into linear `rgba16f`/`rgba32f` surfaces and presents the render surface. See the
repository's `ARCHITECTURE.md` and `docs/GRAPH-JSON-SCHEMA.md`.

## License

MIT; see `LICENSE` in this folder. The upstream Noisemaker engine's notice is `LICENSE-noisemaker.txt`.
Use of the Noisemaker and Noise Factor names is subject to the repository's Trademark Policy.
