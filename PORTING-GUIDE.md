# Noisemaker for Godot — GLSL Shader Porting Guide

How to port a Noisemaker effect shader to Godot `RenderingDevice` GLSL so it matches the reference
pixel for pixel. The rules derive from the reference specs (`reference/07`, `reference/08`). Each one
is a parity requirement, not a style preference.

## Golden rules

1. **Port the reference GLSL (`shaders/effects/<ns>/<effect>/glsl/`).** The goldens are rendered by
   the WebGL2 backend, so its GLSL is the authority. Port its math as written, including
   `gl_FragCoord` arithmetic and rotation matrices. Godot's pipeline is top-left throughout and the
   backend flips once at readback. That is the GL frame mirrored consistently, so no effect needs its
   own flip and no orientation-dependent expression changes.
2. **Treat the WGSL as a second backend, not a source.** It has diverged from the GLSL more than once:
   `classicNoisedeck/effects` rotated the opposite way, `classicNoisedeck/coalesce` mixed the wrong
   input in cloak mode and did not wrap refracted samples, and `grime`, `wobble`, `texture` and the
   points passthroughs sampled upside down. Shaders this port once translated from the WGSL carried
   the reversed rotation into `bulge`, `pinch`, `spiral`, `waves`, `skew`, `julia` and
   `classicNoisedeck/effects`; it went unnoticed because every parity program used rotation 0. Read
   the WGSL, or the Unity/HLSL port, only to cross-check, and give every rotation, wrap and mode a
   parity program that exercises it.
3. **Port helpers verbatim, per effect.** Only the primitives in `include/nm_core.glsl` are shared
   (`pcg`, `prng`, `random`, `map`, `periodicFunction`, `positiveModulo`, `PI`, `TAU`). Helpers with the
   same name often differ between effects: `synth/shape`'s `periodicFunction` uses `sin` where
   `nm_core`'s uses `cos`. Inline each effect's own version, renamed if it differs from a shared one,
   and use full-precision constants (`3.141592653589793`) where the effect does.
4. **Do not simplify or reassociate arithmetic.** Reproduce deliberately redundant expressions (for
   example `catmullRom3`'s partially cancelling terms) literally.
5. **Full 32-bit floats only.** `pcg` and `floatBitsToUint(fract(s))` are bit-sensitive.

## Shader skeleton

Two shapes, depending on whether the effect has a `uniformLayout` (see
`addons/noisemaker/effects/<ns>/<func>.json`).

**Layout effect** (declares its own UBO and reads `data[]` at the layout's slots):
```glsl
#version 450
#include "include/nm_core.glsl"
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[N]; };   // N = max slot + 1
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;
// ... the effect's helpers, inlined ...
void main() { /* read data[i].comp; gl_FragCoord for position; frag = ...; */ }
```

**No-layout effect** (the backend injects the UBO and the `#define`s; use the reference's bare names):
```glsl
#version 450
#include "include/nm_core.glsl"            // omit if no shared primitive is used
layout(set = 0, binding = 1) uniform sampler2D inputTex;   // inputs only, bindings 1.. in pass.inputs order
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;
void main() { /* bare names: resolution, time, st, radiusX, mode, ...; frag = ...; */ }
```

In a no-layout shader, declare no `Params` UBO and no `uniform` or `#define` for parameters or engine
globals. The engine names are `resolution`, `time`, `aspectRatio`, `tileOffset`, `fullResolution`,
`renderScale`, `deltaTime` and `frame`. Parameter names are the `uniform` fields in the effect's JSON
globals.

## From GLSL ES 3.00 to Godot GLSL 4.50

| GLSL ES 3.00 (reference) | Godot GLSL 4.50 | Notes |
|---|---|---|
| `#version 300 es`, `precision highp float;` | `#version 450` | drop precision qualifiers |
| `uniform float amount;` | injected `#define`, or `data[i].comp` | Vulkan has no loose uniforms |
| `uniform sampler2D inputTex;` | `layout(set = 0, binding = N) uniform sampler2D inputTex;` | N from 1, in `pass.inputs` order |
| `in vec2 v_texCoord;` | `layout(location = 0) in vec2 v_uv;` | same frame as `gl_FragCoord / resolution` |
| `out vec4 fragColor;` | `layout(location = 0) out vec4 frag;` | |
| `texture`, `texelFetch`, `textureSize`, `gl_FragCoord` | unchanged | |
| `#define` / `#if` on compile-time defines | unchanged | the runtime injects the values |

The samplers are linear and clamp to edge. Where the reference wraps a coordinate (`fract`, `mod`, a
repeat-mode sampler), the port must wrap it explicitly.

When an existing shader was ported from the WGSL, these translations apply: `select(a, b, c)` is
`c ? b : a` (operands reversed); `bitcast<u32>(f)` is `floatBitsToUint(f)`; `u32(f)` truncates;
`atan2(a, b)` is `atan(a, b)`; WGSL float `%` is not GLSL `mod`; `textureDimensions` is
`textureSize`.

## Reserved names

Every engine name and parameter name is injected as `#define <name> data[slot].comp`. A local variable
or helper parameter with one of those names expands to garbage (`float data[0].w = …` fails with
glslang's "array size must be a positive integer"). Rename such locals and parameters (`aspectRatio`
to `ar`, `resolution` to `res`, a helper's `time` to `timeArg`); keep the bare name only where the
`#define` must resolve. `filter/lensFlare` computes its own `aspectRatio` and passes it to a helper
parameter of the same name; both are renamed, and the value is recomputed from `fullResolution`.

Single-letter parameters such as `x` and `y` are worse: `#define x data[3].x` rewrites every `.x`
swizzle. Copy them into locals at the top of `main`, `#undef` them, or index components (`st[0]`).
`repeat`, `scroll` and `translate` do this.

## `define` versus `uniform`

A global that the reference declares with `define:` is a compile-time define in the port too, never a
`uniform`. A define is baked into the program name and never appears in `pass.uniforms`, so a port that
reads it as a uniform falls back to its JSON default on every pass. The symptom is that the default
value passes and every other value fails, which looks like a bug in the non-default branch.
`check_definitions.mjs` keeps the JSONs identical to what `tools/convert-definitions.mjs` generates
from the reference, so a hand edit that turns a define into a uniform fails the gate.

## Compile-time defines

`NOISE_TYPE`, `LOOP_OFFSET`, `LOOP_A_OFFSET` and the like are injected as `#define`s from the pass's
`defines`. Keep them bare (`if (NOISE_TYPE == 3)`); never declare or hardcode them. Narrow at a call
site that takes an `int` (`int(NOISE_TYPE)`).

## Metal

On macOS Godot cross-compiles SPIR-V to MSL. A function or variable named after an MSL keyword passes
glslang and then fails the Metal stage, so the pass draws nothing. `synth/shape`'s `constant()` is
renamed `constantValue()` for this reason.

## Multi-program effects

An effect with several programs (`filter/blur` → `blurH`, `blurV`) has one `<program>.glsl` per
program. The runtime routes by the pass's program name, and all programs share the effect's JSON and
synthesized layout.

## Per-effect checklist

1. Check `effects/<ns>/<func>.json` for a `uniformLayout` and pick the skeleton.
2. Port the reference GLSL body as written, with its helpers inlined.
3. Write `addons/noisemaker/shaders/effects/<ns>/<effect>/<program>.glsl`.
4. Add a program to `parity/programs/` and `parity/ledger.json` if none exercises the effect.
5. Run `GODOT=… scripts/parity-summary <case>`. The contract is fixed at tolerance 2.001 and SSIM
   0.98; a case that cannot meet it stays a failure with its measured numbers.
