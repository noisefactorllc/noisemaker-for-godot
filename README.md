<!-- repo-hero -->
<a href="https://noisemaker.app/"><img src="docs/hero.jpg" alt="Noisemaker for Godot" width="100%"></a>

<sub>Open source from <a href="https://noisefactor.io">Noise Factor</a> &middot; <a href="https://github.com/noisefactorllc">more projects</a></sub>

# Noisemaker for Godot

> Run **Noisemaker**'s procedural visuals inside **Godot 4**.

> This package supports the "Export Shader Pipeline" feature in Noisedeck.app. The
> feature runs shader compositions on other platforms. Noise Factor derives this package
> from the upstream Noisemaker Engine project and tests it for pixel-level parity.

## What is this?

**Noisemaker** is a procedural visual engine. You write short text programs, chains of effects, and
it renders live, animated GPU textures:

```
search synth, filter
noise(scaleX: 60).bloom().write(o0)
render(o0)
```

That language is Noisemaker's **DSL**. The original engine runs in the browser at
[noisedeck.app](https://noisedeck.app).

**Noisemaker for Godot** runs the same programs inside Godot 4, with the 210 effects of Noisemaker
1.0.271 rendered on Godot's own GPU pipeline. Use it to make textures, materials and animated
backgrounds from code, with no image files.

It is self-contained: the addon compiles the DSL and renders it entirely in Godot, with no internet,
no Node.js and no separate engine to install.

## What you can do with it

- **Generate animated textures** from a short program: noise, gradients, patterns, color grades,
  blurs, warps, 3D volumes and raymarched scenes.
- **Run simulations on the GPU**: particle and agent systems (flocking, physarum, attractors),
  reaction-diffusion, cellular automata and fluids.
- **Drive parameters** with oscillators, MIDI and audio input.
- **Use the result anywhere a texture goes**: materials, `TextureRect`, shaders, backgrounds.
- **Render a `.dsl` file straight to a PNG** from the command line.

## Requirements

- **Godot 4.7** with the **Forward+** renderer.
- **A window** on a real GPU. Rendering uses Godot's low-level `RenderingDevice`, which is null under
  `--headless`, so there is no dedicated-server or CI rendering. Compiling works headless.
- Parity is qualified on macOS (Apple Silicon, Metal). Windows (NVIDIA, Vulkan) renders but is not
  qualified: its goldens come from ANGLE over Direct3D 11, and parity there is still being measured.

## Install

1. Copy `godot/addons/noisemaker/` into your project's `res://addons/`. The folder carries the license
   notices it needs.
2. Enable **Noisemaker** under **Project Settings ▸ Plugins**.

The [addon README](godot/addons/noisemaker/README.md) documents the host API, inputs and
troubleshooting.

## Your first render

```gdscript
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator   := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const Backend        := preload("res://addons/noisemaker/runtime/nm_backend.gd")

var rd := RenderingServer.create_local_rendering_device()
var reg := EffectRegistry.new(); reg.load_all()
var graph = Orchestrator.new(reg).build_graph(
    "search synth\nnoise(scaleX: 60).write(o0)\nrender(o0)")

var backend := Backend.new()
backend.setup(rd, "res://addons/noisemaker", Vector2i(512, 512))
var img: Image = backend.render_samples(graph, 1, 1)[0]   # one frame
$TextureRect.texture = ImageTexture.create_from_image(img)
```

Every DSL program has the same shape:

- Name the namespaces it uses (`search synth, filter`).
- Chain the effects.
- Write the result to an output surface (`.write(o0)`).
- Select a surface to show (`render(o0)`).

Render a `.dsl` file to a PNG from the command line (pass an absolute path to `--dsl`):

```bash
"$GODOT" --path godot --script res://addons/noisemaker/tools/render_graph.gd \
    --position 5000,5000 -- --dsl "$PWD/parity/programs/noise.dsl" --out "$PWD/noise.png" --size 256
```

## What works and what does not

- Every effect in the reference catalog has a definition generated from the reference and a GPU
  program for each of its passes, and the in-engine compiler matches the reference compiler stage by
  stage.
- Pixel parity is measured per program against goldens rendered by the reference at a pinned revision
  (see *How it is checked*). Most programs land within 1–2/255. Programs whose effects threshold or
  amplify noise (edge-following brushes, Kuwahara sector picks, error-diffusion dithering, specular
  `pow`) differ on isolated pixels across GPUs; open cases are tracked in the repository's issues.
- Chaotic feedback programs, such as agent flows feeding a fluid, render as a different instance of the
  same chaos: they match in look and behavior, not pixel for pixel. See
  [docs/CHAOS-GATE.md](docs/CHAOS-GATE.md).
- Not implemented: content the reference draws on the CPU or receives from the host. `text` glyphs,
  `media` images and video, the `fibers`, `scratches` and `strayHair` overlays, and `meshLoader`
  meshes render without that content. There is no editor node.

## How it works

Noisemaker turns a DSL program into a **render graph**, a normalized list of GPU passes. That graph is
the seam every Noisemaker port targets. Noisemaker for Godot ports the whole compiler to GDScript, so
it runs in-engine, and executes the graph on Godot's `RenderingDevice`.

→ **[ARCHITECTURE.md](ARCHITECTURE.md)** (how it maps onto Godot) ·
**[PORTING-GUIDE.md](PORTING-GUIDE.md)** (porting a shader).

## How it is checked

- `scripts/test` runs the engine-free suites and `scripts/test --godot-headless` the suites that need
  a Godot binary but no GPU. CI runs both on every push, the second against a pinned, checksum-verified
  Godot 4.7 build.
- Seven compiler gates (`parity/check_*.mjs`) compare each compiler stage and the effect definitions
  with the reference.
- `scripts/parity-summary` renders every program in `parity/ledger.json` and compares it with a golden
  minted from the reference at the pinned revision, at tolerance 2.001 and SSIM 0.98. It needs a GPU.

The goldens are not committed; the harness mints them from the reference. See
**[parity/README.md](parity/README.md)**. `reference/01`–`10` are the engine specs shared across all
Noisemaker ports.

## Contributing

Contributions follow the Noise Factor
[contributing policy](https://github.com/noisefactorllc/.github/blob/main/CONTRIBUTING.md) and
[Code of Conduct](https://github.com/noisefactorllc/.github/blob/main/CODE_OF_CONDUCT.md).

## Repo layout

```
godot/addons/noisemaker/   the addon: compiler, runtime, shaders, effect definitions
parity/                    parity harness, DSL programs, compiler gates, test suites
scripts/                   test and parity-summary entry points
tools/                     Node tooling: reference graph export, definition conversion, gate oracles
export-kit/                the exported-kit template served at kits.noisedeck.app
reference/                 engine specs shared across all Noisemaker ports
docs/                      graph schema and the chaos-gate explanation
```

## License

MIT (see [LICENSE](LICENSE)). Use of the Noisemaker and Noise Factor names in derivative products is
subject to the [Trademark Policy](TRADEMARK.md).

Copyright © 2026 Noise Factor LLC
