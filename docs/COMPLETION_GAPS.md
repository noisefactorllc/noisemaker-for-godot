# noisemaker-for-godot: completion gaps

Current compatibility matrix: [compatibility report](COMPATIBILITY.md).

## 1. Scope and source revisions

Audit date: 2026-09-23. Run ID: `20260923-godot-05`.
This audit does not approve port completion or release readiness.
It changes this register and its README link only. Implementation belongs to a separate job.

| Source | Revision |
| --- | --- |
| Reviewed local and remote `main` | `bbb2d0179c6e991bdeb2efba7ea733baae027f36` |
| Initial local checkout, before safe update | `00a2671866ec6e1c8ca6383808cb10d427615d31` |
| Latest upstream checkpoint named by the source commit | `44bc4ed4ac729bddaa95b083d64bee942ade35da` |
| Current upstream authority used by this audit | `893a9a558ad9fc1c8ae7b9849aa3b530cbc10d94` |
| Published shader runtime | `1.0.170`, source `e32a5a4a2e1f7b20e4b0db010ad41fd3a30b396b` |
| Published Godot kit | `0.1.16`, source `bbb2d0179c6e991bdeb2efba7ea733baae027f36` |

The intended contribution is a GDScript compiler and GPU renderer for procedural textures in Godot projects.
Its documented contract requires Godot 4.7, Forward+, and a window with a working `RenderingDevice`.
The addon registers no editor nodes. Applications integrate its scripts directly.
External texture, camera, and video workflows remain outside the documented contract.
Audio and MIDI state APIs exist, despite broader input exclusions in the addon README.

The audit compares current authority source, not merely the published runtime version.
An immutable authority archive supplied the checks. No authority images, fixtures, or tolerances changed in this repository.
The historical `75507112` content snapshot remains a separate, unreproduced claim in [STATUS.md](../STATUS.md).

Publication scope: `docs/COMPLETION_GAPS.md` and its root README link.
The existing workflow only matches addon, export-kit, license, and workflow paths.
These document changes do not dispatch CI, deploy a site, publish a package, create a tag, or move an alias.
The shared audit result records the publication commit and remote file hashes.

Daily review date: 2026-09-24 UTC. Review ID: `review-20260924-044918`.
The review checked worker result `20260923-godot-05`, including failed checks, retries, and unavailable workflows.
The earlier measurements remain evidence for their recorded revisions.

| Review source | Revision |
| --- | --- |
| Current local and remote `main` | `6335960ea16d7a1231355eafe5086ad3c73afd58` |
| Current published Godot kit | `0.1.17`, same source SHA |
| Latest upstream checkpoint named by the port | `5b81e04f8a4b53c2be43b8e328cee0c3365f352f` |
| Upstream head observed during review | `cc1ba2687f9a10d8aa8488323d155a5e0fccc338` |
| Published shader runtime observed during review | `1.0.175`, source `5b81e04f8a4b53c2be43b8e328cee0c3365f352f` |

Later source changes affect parser diagnostics, output deferral, and two classicNoisedeck shaders.
The export scene, playback instructions, and graph orchestrator remain unchanged.
This review does not qualify all upstream changes after the audit authority.

Sync date: 2026-09-25 UTC. Source commit: this register row lands with the sync commit itself.
The declared upstream range `fca611fd8f91..2f47612c2904` overlaps content the port had already
synced through `240740dd` (STATUS.md ledger ends at `9d3474dfdc6c`). Verified ancestor facts
(reproducible in the reference clone, `git merge-base --is-ancestor` / `git log`):
- `fca611fd` ("fix: derive numeric-coercion diagnostic coordinates from array positions") is a
  direct ANCESTOR of `240740dd` — `git log --oneline fca611fd..240740dd` lists exactly
  `8a21c9ca`, `bbdeb56c`, `60b90af3`, `3886ecfa`, `66b2c721` (GAP-027 P008/P009/P010 + docs),
  `240740dd`. All of that content was already ported in the 2026-09-25 `240740dd` sync
  (numeric coercion + GAP-027 subchain-argument contract + docs).
- `240740dd` is an ancestor of `2f47612c2904`, and `9d3474dfdc6c` is the merge base of `9d3474df`
  and `2f47612c` (the range is linear: `git log --oneline 9d3474dfdc6c..2f47612c2904` lists exactly
  7 commits). Therefore the effective not-yet-ported range is exactly
  `9d3474dfdc6c..2f47612c2904` — 7 commits: `7a643033`, `fa4b2f02`, `69d83b80`, `13a8a049`
  (docs-only) and `a021a283`, `62eb56fa`, `2f47612c` (the GAP-004 texture-policy work delivered
  by this sync). The earlier "pre-rebase SHA" wording was imprecise; the ancestor facts above are
  the verified statement.

Delivered-range diff (diffed directly in a local upstream checkout, not assumed):

| Upstream commit | Change | Port disposition |
| --- | --- | --- |
| `a021a283` | GAP-004 authorable texture policies (`filter` 3D, `mipmaps`/`persistent` 2D) across `compiler.js`, `effect-validator.js`, `pipeline.js`, both backends (+466-line `test_mip_controls.js`) | Ported: `orchestrator.gd` `_extract_texture_specs()` propagation, `nm_backend.gd` mip-chain allocation/regeneration/`refreshMipTargets`, mipmap sampler, persistent-texture resample preserve |
| `62eb56fa` | WebGL2 mip-chain allocation fix; WebGPU cached mip bind groups | Allocation-half ported above; bind-group caching is a WebGPU-perf detail with no RenderingDevice analogue |
| `2f47612c` | Stop double-creating global surfaces on allocation change | Port's `allocate_textures()` now keeps a matching mipmapped allocation ("matching allocation, preserve it"); the port had no double-create path |
| `6113da00` + `95743621` (delivered in the 2026-09-26 sync, `2f47612c2904..6a0af04d3c4f`) | GAP-006 texture pooling: consume the analyzer's physical allocation map (`graph.allocations`) behind a `texturePooling` opt-in; view/viewport passes without `clear` treated as partially written (unsafe to pool) | Ported: `nm_backend.gd` `set_texture_pooling()`/`texture_pooling` (default off), static `build_texture_pooling_plan()` over `graph.allocations` with all reference guards (globals, first-touch read, self-sampled, `drawMode`/`blend` partial writes, viewport-without-clear, `persistent`/`mipmaps`/`is3D`, raw width/height/format signature), `release_regrouped_textures()`, secondary-member allocation skip, `apply_texture_aliases()`, `get_resource_plan()`; wired through `render_graph.gd --texture-pooling` / batch `texture_pooling` requests |
| `fa83eeab` (in this range, descendant of `2f47612c`) | GAP-005 expander pass-field propagation (`name`/`type`/`clear`/`viewport`/`samplerTypes` copied onto expanded passes) | ALREADY PORTED in the 2026-09-25 sync: `expander.gd` carries all five fields; covered by `test_expander_propagates_gap005_pass_fields` and `test_expander_propagates_sampler_types_and_clear` (both pass). Upstream `expander.js` +12 lines diffed line-for-line against the port's existing propagation |
| `f83a427e` (same sync) | One structured diagnostic union for backend shader/compiler failures (`ShaderDiagnostic`, `parseGLSLInfoLog`, `parseDiagnosticText`) | Ported: new `runtime/shader_diagnostics.gd`; `nm_backend.gd` records `last_shader_diagnostic` on SPIR-V compile failure (stage 'compile', parsed messages + source), SPIR-V link failure (stage 'link'), and missing vertex/fragment sources (stage 'missing-source'); legacy `push_error` strings unchanged. WebGPU-only pieces (compilation-info parsing, bind-group retry, `ERR_NO_WGSL_SOURCE`) audited-inapplicable; the 'bind' parser is ported for contract parity |
| `63349a7d` (same sync) | Upstream CI: retire the per-push JS snapshot release workflow | Inapplicable: upstream-only CI plumbing (`.github/workflows/js.yml`); no `shaders/` content and this port has no such workflow |
| `919f653e`, `27590caa`, `85ded3a6`, `c6bc8e17`, `94fc880b`, `5e52a2a2`, `8eeb7b5a`, `6c3f9a26`, `428ea29b`, `ad17fd02`, `0b2866dd`, `93608f10`, `6a0af04d`, `01e9d620`, `3968f6c4`, `a651c075` (same sync) | Docs-only (GAP-004/005/006/007 closure records, texture-policy docs, llms-full.txt, Sphinx, checkpoint notes, CI evidence) | Nothing to port; verified `git diff 2f47612c2904..6a0af04d3c4f -- shaders/effects shaders/src/lang` is empty |
| `403c2a4b` (2026-09-27 sync, `6a0af04d3c4f..12b4d74fb4f2`) | GAP-008: `replaceEffect`/`getCompatibleReplacements` predict replacement compatibility before mutation (`transform.js` +377, read-only `getParamAliases()` in `paramAliases.js`, `predictReplacement` re-export) | Inapplicable: the port has no JS AST mutation surface (execution-only compiler frontend, same ruling as the `68d37721` `transform.js` sync); the port's oracle tooling imports only `registerParamAliases`, and registry parity is identical after the change (ops 210/210, paramAliases 44/44, effectKeys 628/628) |
| `b35361e0`, `9f85687d`, `7dc0f564`, `7443f6e6`, `c2252f0c`, `e73a44a3` (same sync) | GAP-009/010/011/012/015/014: upstream JS test-harness features only (temporal no-animation/low-variety metrics, `--strict-uniforms`, uniform deltas, WebGPU readback pin, metric mirror, explicit-time warm-up) confined to `shaders/tests/**` + `scripts/run-js-tests.js` | Nothing to port: upstream's JS harness is not a mirrored surface (the port's parity harness is its own Python/`export-and-render.mjs` stack); zero `shaders/src` changes in these commits |
| `12b4d74f` (same sync) | GAP-016: static effect preflight (`preflightEffect()`, additive read-only `Pipeline.preflight()`; `mrtFormatBytes()` delegates to the shared impl — observed byte-identical switch) | Inapplicable: webgl2/webgpu authorability has no RenderingDevice analogue and the report is never invoked by compilation/rendering; the port already applies device-limit demotions at runtime (`nm_backend.gd` `_max_texture_size_2d` clamp, MRT format budget in `nm_backend.gd`/`device_limits_probe.gd`) |
| `66b8ce7d`, `19fdcb56`, `132d1bf9`, `407eb7a7`, `0ac52500` (same sync) | Docs-only (upstream GAP-005..015 closure/checkpoint records, CI evidence) | Nothing to port; verified `git diff 6a0af04d3c4f..12b4d74fb4f2 -- shaders/effects` is empty and `shaders/src/lang` changes only as recorded above |
| `93229933` (2026-09-27 sync, `12b4d74fb4f2..93229933b102`) | GAP-017: complete lossless definition-schema introspection — new `shaders/tests/definition-schema.js` imports each definition live (Effect-instance and Effect-subclass exports) and pins the Shade-MCP projection loss via `auditSchemaLoss()`/`auditDefinitionLoss()`; +161 `test_definition_schema.js`, +60 `test-harness.js`, 1 registration line in `scripts/run-js-tests.js` | Nothing to port: upstream's JS test harness is not a mirrored surface (same ruling as the GAP-009..015 harness syncs); no `shaders/src` file changed and the port's oracle tooling (`tools/dump-registry.mjs`, `tools/dump-validate.mjs`, `tools/export-graph.mjs`) imports only from `shaders/src` |
| `ec457c2e`, `8fe3ccaf` (same sync) | Docs-only (AI-development-contract checkpoint through `12b4d74`, post-publication deployed-contract evidence) | Nothing to port; no `shaders/` paths touched |
| `a912749f` (2026-09-27 sync, `93229933b102..a912749fab5c`) | GAP-019: true input-passthrough probe — new `shaders/tests/passthrough-input.js` (reads the consumed input texture and render surface at time 0 under a determinism guard, mean-abs output-to-input diff at the 0.01 boundary, final write-blit positive control, `--passthrough-input` opt-in), +259 `test_passthrough_input.js`, +70 `test-harness.js`, 1 registration line in `scripts/run-js-tests.js` | Nothing to port: upstream's JS test harness is not a mirrored surface (same ruling as the GAP-009..015/017 harness syncs); no `shaders/src` file changed and no port tooling imports `shaders/tests` |
| `7c5f1765` (same sync) | Docs-only (AI-development-contract checkpoint through `9322993`) | Nothing to port; no `shaders/` paths touched |
| `296e0138` (2026-09-27 sync, observed non-contiguous range `11d7c69922f3..296e0138c474`; endpoint NOT an ancestor of the delivered end `a912749fab5c`) | GAP-021: report requested-vs-returned frame resolution on every `renderEffectFrame` result — `shaders/tests/frame-resolution.js`, +189 `test_frame_resolution.js`, +34 `test-harness.js`, 1 registration line | Nothing to port: upstream's JS test harness only, not a mirrored surface; no `shaders/src` file changed in the range |

Effect-catalog parity: no effect definition, effect shader, DSL lang, or registry file changed in the
range (upstream `shaders/effects` and `shaders/src/lang` diffs are empty for the delivered range);
definitions 210/210 and registries identical. No definition uses the new policy keys yet, so compiled
graphs are unchanged; the compiler/runtime propagation is exercised by smoke tests and activates only
on opt-in.

Reproducible audit commands (reference clone at `/state/cache/scratch/noisemaker-upstream`,
`origin/main` `6a0af04d`; re-runnable verbatim):
- `git diff --stat 13a8a049..2f47612c -- shaders/effects shaders/src/lang` → empty output
  (observed 2026-09-26): zero effect-definition, effect-shader, or DSL-lang changes in the range.
- `git diff --name-only 13a8a049..2f47612c` → the range touches only
  `llms-full.txt`, `package.json`, `scripts/run-js-tests.js`,
  `shaders/src/runtime/backends/{webgl2,webgpu}.js`, `shaders/src/runtime/compiler.js`,
  `shaders/src/runtime/effect-validator.js`, `shaders/src/runtime/pipeline.js`,
  `shaders/tests/test_mip_controls.js`.
- `git show a021a283 -- shaders/src/runtime/compiler.js` → the single `extractTextureSpecs()` hunk
  (3D truthy `filter`, 2D `mipmaps`/`persistent` `!== undefined`, `depth || width || 64`), mirrored
  line-for-line by `orchestrator.gd` `_extract_texture_specs()` (same defaults, same branch split).
- `RESAMPLE_WGSL` (`webgpu.js:58-95`) vs `MIP_FS` (`nm_backend.gd:47-69`): `fsMip` = texelFetch
  2x2 box average `* 0.25` with `(a+b+c+e)` order identical; `fsScale` = NEAREST nearest-neighbor
  `coord = min(vec2u(d * src/dst), maxCoord)` with identical clamp. The port adds a `mode` uniform
  to switch the two entry points (WGSL uses separate entry points); texel math is equivalent.
- `mipLevelSize` (`webgpu.js:41-44` `max(1, floor(dim / 2**level))`) vs `_mip_level_size` —
  identical; `mipLevelCount` integer-halving equals `Math.log2` for powers of two.
Limit: this clone is worker-maintained; a reviewer can reproduce these commands but no independent
party has yet re-run them — still flagged UNVERIFIED-BY-THIRD-PARTY below.

Observed outputs, committed verbatim so the claims are checkable from this repository alone
(observed 2026-09-26 in the reference clone at `origin/main` `6a0af04d`):

`git diff --stat 9d3474dfdc6c..2f47612c2904` (full range):

    LEDGER.md                               |  47 +++-
    docs/plans/active-framework-gap.md      |  46 +++-
    docs/shaders/effects.rst                |  15 +-
    docs/shaders/pipeline.rst               |  10 +-
    llms-full.txt                           |  95 ++++--
    package.json                            |   2 +-
    scripts/run-js-tests.js                 |   1 +
    shaders/src/runtime/backends/webgl2.js  | 121 +++++++-
    shaders/src/runtime/backends/webgpu.js  | 283 +++++++++++++++++-
    shaders/src/runtime/compiler.js         |  17 ++
    shaders/src/runtime/effect-validator.js |  27 +-
    shaders/src/runtime/pipeline.js         | 119 ++++++--
    shaders/tests/test_mip_controls.js      | 466 ++++++++++++++++
    13 files changed, 1163 insertions(+), 86 deletions(-)

`git diff --stat 6a0af04d3c4f..12b4d74fb4f2` (full delivered range of the 2026-09-27 sync; observed
2026-09-27 in a reference clone containing both endpoints):

    LEDGER.md                            | 351 +++++++++++++++++++++++++++++++-
    docs/shaders/compiler.rst            |  12 ++
    docs/shaders/pipeline.rst            |  58 +++++-
    llms-full.txt                        | 207 ++++++++++++++-----
    package.json                         |   2 +-
    scripts/run-js-tests.js              |   6 +
    shaders/src/index.js                 |   2 +-
    shaders/src/lang/index.js            |   4 +-
    shaders/src/lang/paramAliases.js     |  11 +
    shaders/src/lang/transform.js        | 377 ++++++++++++++++++++++++++++++++++-
    shaders/src/runtime/pipeline.js      |  40 +++-
    shaders/src/runtime/preflight.js     | 191 ++++++++++++++++++
    shaders/tests/frame-metrics.js       |  80 ++++++++
    shaders/tests/frame-readback.js      |  83 ++++++++
    shaders/tests/frame-warmup.js        |  61 ++++++
    shaders/tests/image-metrics.js       | 283 ++++++++++++++++++++++++++
    shaders/tests/test-harness.js        | 259 ++++++++++++++++++++++--
    shaders/tests/test_frame_metrics.js  |  71 ++++++++
    shaders/tests/test_frame_readback.js | 183 +++++++++++++++++
    shaders/tests/test_frame_warmup.js   | 144 +++++++++++++
    shaders/tests/test_image_metrics.js  | 164 +++++++++++++++
    shaders/tests/test_preflight.js      | 267 +++++++++++++++++++++++++
    shaders/tests/test_transform.js      | 200 ++++++++++++++++++++
    shaders/tests/test_uniform_deltas.js | 122 ++++++++++++
    shaders/tests/test_uniform_status.js | 116 ++++++++++++
    shaders/tests/uniform-deltas.js      | 282 ++++++++++++++++++++++++++
    shaders/tests/uniform-status.js      |  78 ++++++++
    27 files changed, 3561 insertions(+), 93 deletions(-)

`git diff 6a0af04d3c4f..12b4d74fb4f2 -- shaders/effects` → empty output (effect catalog unchanged).
`git diff --name-only 6a0af04d3c4f..12b4d74fb4f2 -- shaders/src` → exactly `index.js`,
`lang/index.js`, `lang/paramAliases.js`, `lang/transform.js`, `runtime/pipeline.js`,
`runtime/preflight.js`. `git merge-base --is-ancestor 403c2a4bf2cb 12b4d74fb4f2` → exit 0, and each
of the other observed range-ends (`9f85687d`, `7dc0f564`, `7443f6e6`, `c2252f0c`, `e73a44a3`) is
likewise an ancestor of `12b4d74fb4f2`, so the delivered range is the linear
`6a0af04d3c4f..12b4d74fb4f2` (17 commits). At observation time (2026-09-27)
`git log --oneline 12b4d74fb4f2..origin/main` listed only `ec457c2e` and `8fe3ccaf`, both docs-only;
origin/main has since advanced to `93229933` (GAP-017), outside this job's declared/observed ranges
and left for the next sync. Gates were re-run with `NM_REFERENCE_ROOT` at a clone
pinned exactly at `12b4d74fb4f2` (numbers in STATUS.md).

`git diff 9d3474dfdc6c..2f47612c2904 -- shaders/effects shaders/src/lang` → 0 bytes of output
(also 0 for `13a8a0491dcf..2f47612c2904 -- shaders/effects shaders/src/lang`): no effect
definition, effect shader, or DSL-lang change in the delivered range.
`git merge-base --is-ancestor fca611fd8f91 240740dd2d30` → exit 0 (ancestor).
`git merge-base --is-ancestor 240740dd2d30 2f47612c2904` → exit 0 (ancestor).
`git merge-base 9d3474dfdc6c 2f47612c2904` → `9d3474dfdc6c` (linear 7-commit range).

Reference `extractTextureSpecs()` GAP-004 hunk (`compiler.js`, verbatim, within the 17-line
`compiler.js` diff):

    if (effectSpec.is3D) {
        spec.depth = effectSpec.depth || effectSpec.width || 64
        spec.is3D = true
        spec.usage = ['storage', 'sample', 'copySrc', 'copyDst']
        // Definition-level filtering policy for 3D textures ('nearest' or
        // 'linear'). The backends read this when creating the 3D texture
        // and when selecting the sampling mode.
        if (effectSpec.filter) {
            spec.filter = effectSpec.filter
        }
    } else {
        // 2D-only allocation policies. `mipmaps` allocates a full mip chain
        // that the pipeline regenerates after each frame that renders to the
        // texture. `persistent` preserves contents when the texture is
        // recreated at a new size (resize / parameter-driven recreation).
        if (effectSpec.mipmaps !== undefined) {
            spec.mipmaps = effectSpec.mipmaps
        }
        if (effectSpec.persistent !== undefined) {
            spec.persistent = effectSpec.persistent
        }
    }

Reference resample shader (`webgpu.js RESAMPLE_WGSL`, verbatim texel bodies):

    fn fsMip(f: FsParams) -> @location(0) vec4f {
        let d = vec2u(f.frag.xy);
        let base = d * 2u;
        let a = textureLoad(src, base, 0u);
        let b = textureLoad(src, base + vec2u(1u, 0u), 0u);
        let c = textureLoad(src, base + vec2u(0u, 1u), 0u);
        let e = textureLoad(src, base + vec2u(1u, 1u), 0u);
        return (a + b + c + e) * 0.25;
    }

    fn fsScale(f: FsParams) -> @location(0) vec4f {
        let d = vec2u(f.frag.xy);
        let ratio = vec2f(dims.x, dims.y) / vec2f(dims.z, dims.w);
        let scaled = vec2f(d) * ratio;
        let maxCoord = vec2u(max(dims.x - 1.0, 0.0), max(dims.y - 1.0, 0.0));
        let coord = min(vec2u(scaled), maxCoord);
        return textureLoad(src, coord, 0u);
    }

    function mipLevelSize(dim, level) {
        return Math.max(1, Math.floor(dim / Math.pow(2, level)))
    }

Port counterparts: `MIP_FS` (`nm_backend.gd:47-69`, mode 0 = fsMip texel math identical incl.
summand order and `* 0.25`; mode 1 = fsScale NEAREST — the port's `ratio = vec2(p.xy)/vec2(d.xy)`
is the same src/dst ratio as WGSL's `dims.xy/dims.zw`, with the identical `maxCoord` clamp and
`min` before `texelFetch`), `_mip_level_size` (identical formula), `_mip_level_count` (integer
halving).

Test evidence for this commit (Linux container, Godot `4.7.stable.official.5b4e0cb0f` `--headless`,
`NM_REFERENCE_ROOT` at the upstream clone `/state/cache/scratch/noisemaker-upstream`, refreshed to
`origin/main` `6a0af04d` — `2f47612c` and `8eeb7b5a` are both ancestors; the expand gate needs the
GAP-005 pass-name expander, present only from `8eeb7b5a` on): smoke 85/85 (23 new _expect
assertions in this candidate), lex/parse/validate/graph 352/352
each, registry pass (ops 210/210, enums 8/8, paramAliases 44/44, effectKeys 628/628), definitions
210/210, expand 344/352 (exactly the 8 pre-existing, documented pass-defines differences; normalized
graphs match), unittest 79/84 (79 passed). The 5 failures are the windowed-Godot tests (device limits, frame
export, mesh pipeline, formerly-missing effects, shader-compile sweep): this container has no
X11/Wayland display or Vulkan device; they fail identically on the unmodified baseline — baseline
identity re-verified 2026-09-26 by checking out `55c3c92` and running the same five tests
(`.venv/bin/python -m pytest -q test_device_limits.py test_mesh_pipeline.py
test_missing_effects_live.py test_shader_compile.py test_frame_export.py`): the identical five test
IDs fail at the base with the identical error (`ERROR: Unable to create DisplayServer, all display
drivers failed`), and `check_expand.mjs` at the base reports the same 344/352 with the same 8
documented diffs — none of the 5 failures or 8 diffs are introduced by this candidate.
Limits: no pixel-parity re-sweep, no
windowed GPU run, no editor interaction, and no CI run exists for this commit yet — this sync does
not qualify rendering parity and does not close any gap below.

2026-09-26 sync (upstream `2f47612c2904..6a0af04d3c4f`) — observed outputs, committed verbatim so
the claims are checkable from this repository alone (reference clone refreshed to `origin/main`,
head `a651c075`, which contains `6a0af04d`):

`git log --oneline 2f47612c2904..6a0af04d3c4f` (full remaining delta, 18 commits):

    6a0af04d docs: narrow GAP-007 register row to state what remains unstructured
    93608f10 docs: close GAP-007 with structured backend diagnostic union evidence
    f83a427e fix(shaders): normalize backend shader/compiler failures to one structured diagnostic union
    95743621 fix(shaders): treat viewport passes without clear as partially written for texture pooling
    0b2866dd docs: document viewport-write pooling guard in llms-full.txt
    ad17fd02 docs: close GAP-006 with runtime allocation-plan consumption evidence
    6113da00 feat(shaders): consume the resource allocation plan behind texturePooling opt-in with a queryable runtime plan (GAP-006)
    428ea29b docs: advance Documentation checkpoint through 6c3f9a26
    6c3f9a26 docs: record verified GAP-005 publication evidence for 8eeb7b5
    8eeb7b5a docs: close GAP-005 with pass-field propagation evidence for fa83eeab
    fa83eeab feat(shaders): copy name/viewport/clear/samplerTypes/type onto expanded passes (GAP-005)
    27590caa docs(shaders): correct 3D filter defaults in texture-policy documentation
    919f653e docs(shaders): document texture allocation policies (mipmaps/persistent/3D filter)
    94fc880b docs: advance AI development contract checkpoint through 5e52a2a2 / 00340b1
    5e52a2a2 docs: record observed docs-site CI runs and deployment for doc pass
    c6bc8e17 docs: advance Documentation checkpoint through 69d83b80
    85ded3a6 docs: close GAP-004 with verified publication evidence
    63349a7d ci(js): retire the per-push snapshot release

`git merge-base 2f47612c2904 6a0af04d3c4f` → `2f47612c29045c1b91af94887a8ff20106e980ef` (linear
18-commit range). `git merge-base --is-ancestor 2f47612c2904 6a0af04d3c4f` → exit 0;
`git merge-base --is-ancestor fca611fd8f91 6a0af04d3c4f` → exit 0 (the declared force-pushed range
`fca611fd..6a0af04d` spans this and the earlier 2026-09-25 syncs).

`git diff --stat 2f47612c2904..6a0af04d3c4f`:

    .github/workflows/js.yml                    |  54 ----
    LEDGER.md                                   | 100 +++++-
    docs/plans/active-framework-gap.md          | 368 +++++++++++++++++++-
    docs/releases.rst                           |  16 +-
    docs/shaders/effects.rst                    |  32 +-
    docs/shaders/pipeline.rst                   |  59 +++-
    llms-full.txt                               | 144 ++++++---
    package.json                                |   2 +-
    scripts/run-js-tests.js                     |   3 +
    shaders/src/runtime/backends/diagnostics.js | 185 +++++++++++
    shaders/src/runtime/backends/webgl2.js      |  45 ++-
    shaders/src/runtime/backends/webgpu.js      | 103 +++---
    shaders/src/runtime/expander.js             |  12 +
    shaders/src/runtime/pipeline.js             | 279 +++++++++++++++-
    shaders/tests/test_backend_diagnostics.js   | 338 +++++++++++++++++++
    shaders/tests/test_pass_fields.js           | 323 ++++++++++++++++++++
    shaders/tests/test_resource_pooling.js      | 483 ++++++++++++++++++++++++++++
    17 files changed, 2379 insertions(+), 167 deletions(-)

`git diff 2f47612c2904..6a0af04d3c4f -- shaders/effects shaders/src/lang` → 0 bytes of output: NO
effect-definition, effect-shader, or DSL-lang change in the range. The `expander.js` +12 is
`fa83eeab`'s pass-field propagation, already ported (see the range table above). `webgl2.js`
(+45)/`webgpu.js` (+103) diffs are the pooling/diagnostics backend wiring audited-inapplicable
beyond what was ported; `pipeline.js` (+279) is the pooling plan/alias/getResourcePlan logic ported
into `nm_backend.gd`; `diagnostics.js` (+185) is the diagnostic union ported into
`runtime/shader_diagnostics.gd`.

Gate outputs for the 2026-09-26 sync commit (Linux headless, Godot
`4.7.stable.official.5b4e0cb0f`, `NM_REFERENCE_ROOT` at the refreshed reference clone), verbatim:

    $ node parity/check_definitions.mjs
      PASS  210 definition(s) match the reference exactly
    $ node parity/check_lex.mjs
    LEX PARITY: 352/352 pass
    $ node parity/check_parse.mjs
    PARSE PARITY: 352/352 pass
    $ node parity/check_validate.mjs
    VALIDATE PARITY: 352/352 pass
    $ node parity/check_graph.mjs
    GRAPH PARITY: 352/352 pass
    $ node parity/check_registry.mjs
      PASS  ops            (ref 210 / mine 210 keys)
      PASS  enums          (ref 8 / mine 8 keys)
      PASS  paramAliases   (ref 44 / mine 44 keys)
      PASS  effectAliases  (ref 0 / mine 0 keys)
      PASS  effectKeys     (ref 628 / mine 628 keys)
    $ node parity/check_expand.mjs | grep -c DIFF
    8
    $ GODOT --headless --path godot --script res://addons/noisemaker/compiler/_smoke.gd
    SMOKE: ALL PASS
    $ python3 -m unittest discover -s parity -p 'test_*.py'
    Ran 88 tests in 26.298s
    FAILED (failures=5)

The 5 failures are the same five display-dependent windowed tests recorded for the previous
baseline (`test_device_limits`, `test_frame_export`, `test_mesh_pipeline`,
`test_missing_effects_live`, `test_shader_compile`) — this container has no X11/Wayland display or
Vulkan device; each fails with `Unable to create DisplayServer, all display drivers failed`
identically on the unmodified baseline (verified for the 2026-09-25 candidate at `55c3c92`,
recorded above).

Full declared-range audit, 2026-09-26 (reference clone re-cloned from
`https://github.com/noisefactorllc/noisemaker`, HEAD `a651c075`):

    $ git merge-base --is-ancestor fca611fd8f91424661d4e531d39313d24ea21134 \
        6a0af04d3c4f345ffab5e9f8e54e532216b4cdaa; echo $?
    0
    $ git diff fca611fd8f91..6a0af04d3c4f -- shaders/effects
    (empty — 0 bytes: no effect definitions changed anywhere in the declared range)
    $ git diff --stat 428ea29bf8fb..6a0af04d3c4f -- shaders/   (tail)
        shaders/tests/test_backend_diagnostics.js   | 338 +++++++++++++++++++
        shaders/tests/test_resource_pooling.js      | 483 ++++++++++++++++++++++++++++
        6 files changed, 1305 insertions(+), 44 deletions(-)
    $ git diff 428ea29bf8fb..6a0af04d3c4f -- shaders/effects shaders/src/lang
    (empty — 0 bytes)
    $ git log --oneline fca611fd8f91..6a0af04d3c4f -- shaders/
    f83a427e fix(shaders): normalize backend shader/compiler failures to one structured diagnostic union
    95743621 fix(shaders): treat viewport passes without clear as partially written for texture pooling
    6113da00 feat(shaders): consume the resource allocation plan behind texturePooling opt-in with a queryable runtime plan (GAP-006)
    fa83eeab feat(shaders): copy name/viewport/clear/samplerTypes/type onto expanded passes (GAP-005)
    2f47612c fix(shaders): stop double-creating global surfaces on allocation change
    62eb56fa fix(shaders): allocate the WebGL2 mip chain and cache WebGPU mip bind groups
    a021a283 feat(shaders): authorable mipmaps/persistent/3D filter texture policies (GAP-004)
    9d3474df fix(shaders): complete GAP-003 validator contract, corpus gate, and test wiring
    ba87ffae feat(shaders): validate effect definitions against spec at runtime (GAP-003)
    240740dd test: register committed subchain differential gate vs recorded baseline
    66b2c721 feat: subchain-argument validation contract (P008/P009/P010, strict opt-in)

Reading: the declared range `fca611fd..6a0af04d` spans the earlier 2026-09-25 syncs (`66b2c721`
through `2f47612c` — GAP-003/GAP-004/GAP-005, all present in the port and gated) plus the code
commits ported in this sync (`6113da00`, `95743621`, `f83a427e`) and docs-only commits. The full
range's only `shaders/src/lang` delta (shown when diffing from `fca611fd` rather than
`13a8a049`) is the already-ported GAP-027 subchain-argument contract (`66b2c721`/`240740dd`:
P008/P009/P010, strict opt-in — present in `godot/addons/noisemaker/compiler/lang/parser.gd`,
`validator.gd`, and `_smoke.gd` assertions P008/P010/P009/strict-P008).

Ledger namespace correction (same date): the review found `parity/ledger.json` attributing
`alphaMask`/`blendMode` and 31 other rows to `filter/<fn>` where the definitions live under
`mixer/` or `render/`. All 33 rows were corrected by checking each row's `<namespace>/<fn>`
against `godot/addons/noisemaker/effects/<namespace>/<fn>.json`; no golden, candidate, verdict,
or tolerance fields were touched. This is metadata only and does not affect comparisons.

Native-cases gating note: the required `godot-parity` native cases (`adjust`, `alphaMask`,
`bitwise`) run through `parity/run.sh` — one program per Godot invocation, a standalone render
followed by `compare.py`. They do not execute the full ~345-program sweep batch, so the recorded
`heightGrid_billboard_alpha` full-batch anomaly (STATUS.md, open, root cause unfound) cannot gate
or mask the required cases. The anomaly itself remains open in STATUS.md.

2026-09-27 second sync of the day (`12b4d74fb4f2..93229933b102`; declared job range
`403c2a4bf2cb..93229933b102`, forced, one observed non-contiguous range `8fe3ccaf2cc8..93229933b102`).
Ancestry observed verbatim (fresh full clone, both endpoints present):
`git merge-base --is-ancestor 403c2a4bf2cb56307448ea2fc1d6fa3cd74b7d6e 12b4d74fb4f2` → exit 0;
`git merge-base --is-ancestor 12b4d74fb4f2 93229933b102ba82e713402be19db57207698850` → exit 0.
The already-audited prefix `6a0af04d..12b4d74f` carries over, so the effective new delta is the
linear 3-commit `12b4d74fb4f2..93229933b102` (`git log --oneline` → `93229933`, `8fe3ccaf`,
`ec457c2e`).

    $ git diff --stat 12b4d74fb4f2..93229933b102
        LEDGER.md                               |  94 +++++++++++++-
        llms-full.txt                           |  27 +++-
        scripts/run-js-tests.js                 |   1 +
        shaders/tests/definition-schema.js      | 220 ++++++++++++++++++++++++++++++++
        shaders/tests/test-harness.js           |  60 ++++++++-
        shaders/tests/test_definition_schema.js | 161 ++++++++++++++++++++++++
        6 files changed, 553 insertions(+), 10 deletions(-)
    $ git diff --stat 403c2a4bf2cb..93229933b102 -- shaders/effects
    (empty — 0 bytes: no effect definition, effect shader, or DSL-lang change anywhere in the
    declared job range)
    $ git diff --name-only 403c2a4bf2cb..93229933b102 -- shaders/src
        shaders/src/runtime/pipeline.js
        shaders/src/runtime/preflight.js
    (exactly the two GAP-016 files already ruled inapplicable in the previous sync)
    $ git log -1 --format='%H %s' 93229933b102
    93229933b102ba82e713402be19db57207698850 feat(harness): complete, lossless definition-schema introspection with an upstream-loss audit (GAP-017)

Gate re-run at `NM_REFERENCE_ROOT` pinned exactly at `93229933b102` (Godot
`4.7.stable.official.5b4e0cb0f`, Linux headless; numbers in STATUS.md): definitions 210/210,
registry ops 210/210 / enums 8/8 / paramAliases 44/44 / effectAliases 0/0 / effectKeys 628/628,
lex/parse/validate/graph 352/352 each, expand 344/352 (the same 8 documented pass-defines diffs),
`SMOKE: ALL PASS`, unittest 96 tests / 12 failures — all 12 Godot display-server-init
environmental failures ("X11 Display is not available / Can't create the Wayland display
server"), the identical set recorded for the previous sync.

2026-09-27 third sync of the day (`93229933b102..a912749fab5c`; declared job range
`403c2a4bf2cb..a912749fab5c`, forced, observed non-contiguous ranges `7c5f17658d8c..a912749fab5c`
and `11d7c69922f3..296e0138c474`).
Ancestry observed verbatim (fresh full clone, all endpoints present):
`git merge-base --is-ancestor 403c2a4bf2cb56307448ea2fc1d6fa3cd74b7d6e 93229933b102` → exit 0;
`git merge-base --is-ancestor 93229933b102 a912749fab5c3819e56a8abde664ff30e40870f4` → exit 0.
The already-audited prefix `93229933` carries over, so the effective new delta is the linear
2-commit `93229933b102..a912749fab5c` (`git log --oneline` → `a912749f`, `7c5f1765`).
The second observed range `11d7c69922f3..296e0138c474` is one commit (`296e0138`, GAP-021,
harness/docs only: `shaders/tests/frame-resolution.js`, `test_frame_resolution.js`,
`test-harness.js`, `scripts/run-js-tests.js`, `llms-full.txt`) whose endpoint is NOT an ancestor of
the delivered end; audited separately with the same harness-only ruling.

    $ git diff --stat 93229933b102..a912749fab5c
        LEDGER.md                               |  75 ++++-
        llms-full.txt                           |  29 ++-
        scripts/run-js-tests.js                 |   1 +
        shaders/tests/passthrough-input.js      | 489 ++++++++++++++++++++++
        shaders/tests/test-harness.js           |  70 +++++-
        shaders/tests/test_passthrough_input.js | 259 +++++++++++++++++
        6 files changed, 918 insertions(+), 5 deletions(-)
    $ git diff --stat 403c2a4bf2cb..a912749fab5c -- shaders/effects
    (empty — 0 bytes: no effect definition, effect shader, or DSL-lang change anywhere in the
    declared job range)
    $ git diff --name-only 93229933b102..a912749fab5c -- shaders/src
    (empty — 0 files)
    $ git log -1 --format='%H %s' a912749fab5c
    a912749fab5c3819e56a8abde664ff30e40870f4 feat(harness): true input-passthrough probe with a live write-blit control (GAP-019)

Gate re-run at `NM_REFERENCE_ROOT` pinned exactly at `a912749fab5c` (Godot
`4.7.stable.official.5b4e0cb0f`, Linux headless; numbers in STATUS.md): definitions 210/210,
registry ops 210/210 / enums 8/8 / paramAliases 44/44 / effectAliases 0/0 / effectKeys 628/628,
lex/parse/validate/graph 352/352 each, expand 344/352 (the same 8 documented pass-defines diffs),
`SMOKE: ALL PASS`, unittest 96 tests / 12 failures — all 12 Godot display-server-init
environmental failures ("X11 Display is not available / Can't create the Wayland display
server"), the identical set recorded for the previous syncs.

## 2. Completion claims

| Claim ID | Claim source | Claimed scope | Finding | Evidence |
| --- | --- | --- | --- | --- |
| C-001 | README, first render | Self-contained useful texture output | supported | Published kit creates a visible-content 512×512 texture. Public API returns non-square images and responds to seed changes. |
| C-002 | STATUS, compiler gates | All compiler gates match the authority | partial | Definitions match 210/210. Lex, parse, validate, and graph pass 352/352 each. Expansion passes 344/352. |
| C-003 | README, STATUS parity summaries | Catalog rendering and pixel parity | contradicted | Retained ledger has two failures. Current perspective-points probe fails unchanged tolerance. Whole-catalog current parity remains unverified. |
| C-004 | Published README, Run it and Editing it | Sampled animation playback and editable frame controls | supported | (2026-09-26) Kit `main.gd` now steps `FRAMES`, samples every `SAMPLE_EVERY`, and loops stills at `PLAYBACK_FPS`; all controls verified on Godot 4.7 with `navierStokes.dsl` (see GAP-001 closure evidence). Historical finding: published 0.1.16/0.1.17 rendered one frame with no controls. |
| C-005 | Addon README, troubleshooting | Developers receive useful errors and can recover | partial | Missing-device error explains recovery. Invalid effect reports a missing surface. Corrected DSL renders successfully. |
| C-006 | Addon README, integration | Useful Godot scripting integration | partial | Public compiler, renderer, and `ImageTexture` path work. Cleanup reports resource warnings. Editor interaction remains unverified. |
| C-007 | Export kit workflow and artifact | Release readiness | partial | Exact-source release succeeds. All 882 file hashes match the 2026-09-23 audit authority (`893a9a558ad9...`) only; the delivered upstream range (`9d3474df..2f47612c`) is later than that authority, so hash identity does not evidence the ported changes (see the 2026-09-25 sync row in section 1). Rebuild inventory matches. CI does not run Godot behavior or pixel comparisons. |
| C-008 | README and STATUS platform limits | Apple Silicon qualification | partial | Audit checks cover M2 and Godot 4.7.2. Review checks cover bounded M4 workflows on Godot 4.7. Other platforms remain unverified. |
| C-009 | Root README, Install | Standalone addon distribution | contradicted | The instructed addon copy omits license notices. The export kit includes both notices. See GAP-008. |

## 3. Methods and evidence

Raw evidence resides in the shared automation store under `evidence-20260923-godot-05`.
The run result indexes commands, exit codes, source hashes, logs, and probes.
This identifier is an operational reference, not an installed package dependency.

Environment: macOS 14.8.3, arm64, Apple M2, Metal 3.1, Forward+, Godot `4.7.2.stable.official.ed1daf0bf`.
Tools: Python 3.14.3 and Node 26.9.0. Image comparison used an isolated environment with NumPy 2.5.3 and Pillow 12.3.0.
Godot came from the official download into the isolated audit directory. No global installation occurred.

`GODOT` identifies that executable. `NM_REFERENCE_ROOT` identifies the immutable authority snapshot from section 1.
`AUDIT_EVIDENCE` identifies this run's evidence directory.

| Check | Command or method | Result and scope |
| --- | --- | --- |
| Initial tests | `python3 -m unittest discover -s parity -p 'test_*.py' -v` | Exit 0, 66 discovered, 35 passed, 31 skipped because Godot was absent. |
| Tests with Godot | Same command with `GODOT` set | Exit 0, 66/66 passed in 72.321 seconds, no skips. Includes live shader, device, frame-export, mesh, and missing-effect checks. |
| Definition authority | `node parity/check_definitions.mjs` | Exit 0, 210/210 exact matches. Current authority census also contains 210 definitions. |
| Compiler gates | `node parity/check_lex.mjs`, `check_parse.mjs`, `check_validate.mjs`, `check_graph.mjs` | Each exits 0 with 352/352. Corpus includes 342 program files and 10 nested corpus files. |
| Expansion gate | `node parity/check_expand.mjs` | Exit 1, 344/352. Eight differences contain candidate pass defines absent from reference expansion. Normalized graphs still match. |
| Registry gate | `node parity/check_registry.mjs` | Exit 0. Ops 210/210, enums 8/8, parameter aliases 44/44, effect aliases 0/0, effect keys 628/628. |
| Independent pixels | Existing `export-and-render.mjs`, `render_graph.gd --dsl`, and `compare.py` | Noise and alpha billboards pass. Perspective points fail. See measurements below. |
| Batch sensitivity | Existing `render_graph.gd --batch-manifest` with 99 ordered programs through alpha billboards | Exit 0, 99 outputs, no logged errors. Alpha output passes. This is a prefix probe, not the full historical sweep. |
| Installed first result | Published `main.tscn`, unchanged scripts, injected `program.dsl` | Exit 0. A scene observer obtains a 512×512 texture. The image contains colored noise. |
| Playback | Same observer across 120 process frames | Texture hash remains identical. Source calls `render_samples(graph, 1, 1)` once. |
| Public host API | `consumer-api.gd` calls registry, compiler, backend, and `ImageTexture` | Exit 0. Two seeds produce different images at 64×32 and 128×64. Each case returns three samples. Teardown reports unreleased resources. |
| Invalid DSL | Published renderer with `notAnEffect().write(o0)` | Exit 1, no PNG. Error reports `render surface missing: global_o0`, without the unknown-effect diagnostic. |
| Recovery | Same renderer with valid noise DSL | Exit 0, valid 64×64 PNG. |
| Missing device | Same renderer with `--headless` | Exit 1, explicit `RD_NULL` instruction to use a window. |
| Artifact integrity | Fetch every manifest entry from Godot kit 0.1.16 and compare bytes and SHA-256 | 882/882 match. Initial concurrent retrieval hit HTTP 429. A slower continuation completed the inventory. |
| Rebuild | Existing Scaffold `apps/export-kit-builder/build.mjs`, same source and version | Exit 0. All 882 inventory entries and the complete `kit.json` match the published artifact. |
| Editor interaction | Start isolated editor, then inspect with computer-use tools | Mac lock prevents interaction. Plugin toggling, Play, keyboard access, focus, and readability remain unverified. |

The first authority extraction omitted `share/palettes.json`.
Validation, expansion, and graph checks initially failed before comparison.
Logs retain those setup failures. The table reports reruns against the complete archive.

Independent reference images use current authority source, WebGL2, 256×256 pixels, normalized time 0.25, and each existing fixture's parameters.
Candidate images use the public GDScript compilation path and the same dimensions and time.
RGBA8 comparisons use maximum channel difference ≤2.001 and global luminance SSIM ≥0.98.
SSIM is the existing comparator's single-window statistic.

| Program | Maximum difference | Mean difference | SSIM | Result |
| --- | ---: | ---: | ---: | --- |
| `noise` | 1.000 | 0.3756 | 0.99996 | pass |
| `heightGrid_billboard_alpha`, standalone | 1.000 | 0.3770 | 0.99998 | pass |
| `heightGrid_billboard_alpha`, 99-program prefix | 1.000 | 0.3770 | 0.99998 | pass |
| `heightGrid_pointsRender_perspective` | 243.000 | 0.7143 | 0.99785 | fail |

The retained ledger contains 342 rows: 291 PASS, 49 NEAR, and two FAIL.
Its referenced images are absent from this checkout. This audit did not recreate or replace that historical evidence.
The ledger does not identify source hashes for each candidate and reference image.
Its verdict counts are historical records, not current-source measurements.

[Source CI run 35810075402](https://github.com/noisefactorllc/noisemaker-for-godot/actions/runs/35810075402) passed for the reviewed SHA.
It only dispatches the release.
[Release run 35810082616](https://github.com/noisefactorllc/scaffold/actions/runs/35810082616) passed and identifies the exact Godot source.
Its builder tests report 99 passes. They do not execute Godot's parity gates.

The kit includes both Noisemaker MIT license texts. Its inventory contains 210 compatible effect IDs and 317 mirrored shader files.
Shader presence does not prove support for every input, mode, or platform.
The addon-only copy path does not include the root license file. That distribution needs a separate packaging check.
This source addon does not ship a native binary, so binary signing and ABI checks do not apply to it.
Exported games, upgrades, uninstall behavior, and additional operating systems remain unqualified.

Official ecosystem references, checked on 2026-09-23:

- [Godot macOS download](https://godotengine.org/download/macos/) identifies 4.7.2 and portable installation.
- [Godot 4.7 plugin installation](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/installing_plugins.html) defines the `addons` layout and plugin enablement.
- [Godot 4.7 compute shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html) describes RenderingDevice integration and supported renderers.
- [Godot 4.7 system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html) defines the host qualification baseline.

The daily review retained evidence under `review-20260924-044918` in the same automation store.
All 71 recorded evidence hashes matched. All 985 historical source hashes matched Git objects at the worker's source SHA.
The review read raw compiler, runtime, installation, recovery, batch, and CI logs. It also checked the changed document against source.

Review environment: macOS 26.5, arm64, Apple M4, Metal 4.0, Forward+, Godot `4.7.stable.official.5b4e0cb0f`.
The review used the installed Godot executable without changing its installation.
The existing scene observer and consumer probe ran against isolated kit copies.
The copies matched all 882 entries in each version's manifest before execution.
For kit 0.1.17, nine changed files came from immutable URLs. Other bytes matched the retained artifact and current manifest.
Fresh responses also matched `main.gd`, `README.template.md`, and `project.godot`.
This verifies the reconstructed candidate. It does not repeat every remote file download or the current build.

| Review check | Result and evidence |
| --- | --- |
| Current source tests | `GODOT=/Applications/Godot.app/Contents/MacOS/Godot python3 -m unittest discover -s parity -p 'test_*.py' -v`: exit 0, 68/68 pass, no skips. `current-unit.log`. |
| Installed kits 0.1.16 and 0.1.17 | Existing `kit-observe.gd`: exit 0, colored 512×512 output, unchanged texture across 120 process frames. `kit-observe-floor.log`, `current-kit-observe.log`. |
| Current public API | Existing `consumer-api.gd`: exit 0, three samples per case, seed changes, 64×32 and 128×64 textures. Resource warnings remain. `current-consumer-api.log`. |
| Current invalid input and recovery | Existing installed renderer: unknown effect exits 1 with missing-surface error and no image. Corrected DSL exits 0. `invalid-current.log`, `recovery-current.log`. |
| Current missing device | Same renderer under `--headless`: exit 1 with `RD_NULL` recovery instruction. `no-device-current.log`. |
| Retained pixel evidence | Existing comparator reproduces both passes and the perspective-point failure. No reference images changed. `runtime-checks.json`. |
| Current perspective points | Kit 0.1.17 renders against the retained audit reference. Maximum difference 243.000, mean 0.7198, SSIM 0.99776. Comparator exits 1. `points-current-report.json`. |
| Standalone addon notices | Documented copy includes no license filenames or complete MIT notice text. `addon-distribution.json`. |

The current perspective comparison retains authority `893a9a558ad9fc1c8ae7b9849aa3b530cbc10d94`, time 0.25, and 256×256 dimensions.
It does not measure parity against the latest upstream head.
The review did not repeat full compiler comparisons, full catalog pixels, editor interaction, upgrades, removal, or other operating systems.
External media remain outside the documented contract. Audio and MIDI claims still require explicit acceptance boundaries.

[Current source CI 35951202302](https://github.com/noisefactorllc/noisemaker-for-godot/actions/runs/35951202302) passed for `6335960ea16d7a1231355eafe5086ad3c73afd58`.
[Current release CI 35951211347](https://github.com/noisefactorllc/scaffold/actions/runs/35951211347) identifies that source and passes 99 builder tests.
These jobs still do not execute Godot behavior or pixel comparisons.
The review checked both earlier CI records and their retained logs. Their packaging success does not close GAP-006.

The review checked the official Godot 4.7 references again on 2026-09-24.
The official macOS download remains 4.7.2. Local floor checks cover only the stated M4 workflows.
[Godot's resource guidance](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html#freeing-memory) requires explicit RID cleanup.
The observed warnings therefore remain relevant to normal host integration. They do not establish long-term memory growth.

### Native observations, 2026-09-24

Godot 4.7, Forward+, Metal 4.0, Apple M4. 2 selected fixtures rendered. Exact comparison: 0 passes and 2 differences.
The candidate source is the source listed in the [compatibility report](COMPATIBILITY.md#1-source-and-authority-revisions).
These probes compare retained historical goldens. They do not establish full current-authority parity.
340 of 342 tracked fixtures did not execute in this bounded pass.
[Per-case measurements](COMPATIBILITY.md#native-observations-2026-09-24) retain every difference and the unexecuted fixture inventory.
No gap closes. The next rendered gate must include all missing fixtures and resolve authority provenance without replacing goldens.

## 4. Known gaps

P1 means false completion or a major correctness gap. P2 means missing coverage or integration. P3 means documentation inconsistency.
The worker checked GAP-001 through GAP-007 on 2026-09-23.
The reviewer checked all entries on 2026-09-24, with the coverage limits in section 3. No gaps closed.

### GAP-001: Published project does not implement documented playback

- Status: closed (2026-09-26). Priority: P1. Category: implementation.
- Scope: `export-kit/kit/main.gd`, its README template, and published kits 0.1.16 and 0.1.17. The fix also touches `godot/addons/noisemaker/runtime/nm_backend.gd` — a Godot 4.7 `mip_filter` sampler-compat set required for any pipeline to run on 4.7; `render_samples` itself is pre-existing and unchanged. This preserves the effect checkpoint (no effect or pass definitions touched).
- Expected: The exported project plays sampled animation and exposes the documented frame controls.
- Observed (pre-fix): The project created one image. It had no playback loop or the documented frame constants.
- Historical evidence: `kit-observe.log` recorded identical texture hashes across 120 frames. `current-kit-observe.log` reproduced static output on Godot 4.7 while the scene called `render_samples(graph, 1, 1)`.
- Fix (2026-09-26, two causes): (1) `export-kit/kit/main.gd` now steps `FRAMES` simulated 60 fps frames via `render_samples(graph, FRAMES, SAMPLE_EVERY)`, captures one still every `SAMPLE_EVERY` frames, and loops the stills in `_process` at `PLAYBACK_FPS`; all four documented constants (`SIZE`, `FRAMES`, `SAMPLE_EVERY`, `PLAYBACK_FPS`) exist and a `Status` label shows the frozen-window warning before the blocking compute pass; `FRAMES=1` renders a single still immediately. README template documents the four constants and the `SAMPLE_EVERY` interval semantics. (2) `nm_backend.gd` assigned `RDSamplerState.mipmap_filter`, which Godot 4.7 renamed to `mip_filter`; `setup()` aborted there, every pipeline creation failed, and the kit could only show one static surface. Fixed with a both-names compat set (works on 4.5/4.6 and 4.7+).
- Verification evidence (Linux container, Godot `4.7.stable.official.5b4e0cb0f`, Forward+ over llvmpipe, kit template rebuilt into an installed-kit layout with addon, `program.dsl` = the known temporal fixture `parity/programs/navierStokes.dsl`, 512×512, committed observer `parity/kit-observe.gd`: 120 process frames, first displayed frame saved as PNG). Verbatim observer summaries, reproducible with the committed suite (`GODOT=<godot> python3 -m unittest parity.test_kit_playback`, 7/7 pass on this environment — 2+2+3 cases per invocation, in one session; `SMOKE: ALL PASS` for `res://addons/noisemaker/compiler/_smoke.gd`). The observer hashes the full displayed-image bytes (`hash(PackedByteArray)`), not a sampled subset, and the suite fails loudly (`RuntimeError` at import, negative control re-run: `GODOT=/nonexistent python3 -m unittest parity.test_kit_playback` aborts with "kit playback gate requires a Godot binary") instead of silently passing when the engine is absent:
  - `FRAMES=120 SAMPLE_EVERY=20 PLAYBACK_FPS=5`: `NM_OBSERVE frames=120 distinct=6 first=-1 last=2714295116 transitions=13` — differing displayed frames; the 6-still loop is fully traversed.
  - `PLAYBACK_FPS=30`: `NM_OBSERVE frames=120 distinct=6 first=-1 last=1160425466 transitions=73` — 73 vs 13 transitions over the same 120 observed frames (PLAYBACK_FPS changes its stated behavior).
  - `FRAMES=120 SAMPLE_EVERY=30 PLAYBACK_FPS=5`: `NM_OBSERVE frames=120 distinct=4 first=-1 last=2566010941 transitions=13` — 4 vs 6 distinct stills at FRAMES=120 against the baseline above (same FPS=5 timing; SAMPLE_EVERY changes its stated behavior). The committed suite asserts the same contrast at PLAYBACK_FPS=30 (`test_sample_every_changes_the_still_count`).
  - `FRAMES=1`: `NM_OBSERVE frames=120 distinct=1 first=-1 last=1342908084 transitions=0` — immediate single still for still-only programs.
  - The committed test also gates the Godot 4.7 `mip_filter` compat: SCRIPT ERROR and "render pipeline creation failed" fail the suite; cancellation mid-render (killed run at shipped constants) then a fresh run completes playback; a kit without `program.dsl` fails cleanly (`cannot read res://program.dsl`, 0 displayed frames) and recovers after the DSL is restored.
  - Limits, stated openly: gate coverage — the job's declared native cases (`adjust`, `alphaMask`, `bitwise`) run the parity harness, not the installed kit, and no declared check executes the kit-observer executable check post-publication. The machine-enforcing coverage is the committed suite `parity/test_kit_playback.py` (it now fails loudly without a Godot binary, so it cannot pass as a silent 0-test run); no repository workflow invokes it, because workflow changes require explicit job authority this implementation job lacks — the next action is an actor with workflow authority adding a CI step running `GODOT=<godot> python3 -m unittest parity.test_kit_playback` on the published source. `SIZE` variant: `parity/test_kit_playback.py` builds a `SIZE=64` kit and asserts the observer's `first.png` is 64×64 with differing displayed frames. A full-length run at shipped `FRAMES=1800/SAMPLE_EVERY=60` is blocked by this container's 4 GB cgroup, not by the kit: three attempts on the software Vulkan renderer were killed (two by host restarts, one by the OOM killer — `/sys/fs/cgroup/memory.events` records `oom_kill 1` under a `memory.max` of 4 GiB, godot exited with signal 9); the same code path is verified at scaled-down constants and runs ~1 minute on the documented desktop hardware. Rollout: kit tags ≤0.1.32 ship the pre-fix static `main.gd`; the export-kit pipeline rebuilt and tagged kit-godot-v0.1.33 from the implementation commit `aea0c958825bc95194aac0d1336648550de35fcf`, and the tagged tree was inspected directly: its `export-kit/kit/main.gd` contains the playback implementation and its `godot/addons/noisemaker/runtime/nm_backend.gd` line 230 is the `mip_filter` compat set, so published kit 0.1.33 renders on Godot 4.7. This commit's kit changes reach the kit on the next export-kit-triggered rebuild — already dispatched by this push: the export-kit pipeline rebuilt and tagged kit-godot-v0.1.34 at exactly `5f63ce386597e28f730cb98cf945edc110e66c28`, and the tagged tree was inspected: `export-kit/kit/main.gd` contains the final-frame fallback (`max(FRAMES, 1)`) and the `Failed:` Status texts, and `godot/addons/noisemaker/runtime/nm_backend.gd` carries the `mip_filter` compat. kit-godot-v0.1.33 (`aea0c958825bc95194aac0d1336648550de35fcf`) was likewise tree-inspected (playback main.gd, `mip_filter` compat at nm_backend.gd line 230). Machine receipts for the published-kit scope (2026-09-27): Export kit workflow runs completed successfully at `aea0c95` (run 36258756539), `5f63ce3` (run 36274298592, kit-godot-v0.1.34), and `1c0d8e6` (run 36277057849, kit 0.1.35). The deployment serving `https://kits.noisedeck.app/godot/0/deployment-meta.json` reports version 0.1.35 with source git_hash `1c0d8e65bb04e515a2eca836ed04d9c1daf570a2`; its `kit.json` inventory (883 files) was fetched and every kit-relevant file byte-compared against this commit's trees: served `main.gd` sha256 `2b62a1deef0397ecd93572f4ed1e23cef11ef02df38d3f9dfcfddb237151975c`, `main.tscn` `f4b8cbeafbbfd27ae34434738670312f1e50dd9558417045bce0142d6c850ff1`, `project.godot` `2a4ba884a8f585fc8542895bb08c0877ff139b9e3ebc229c577eec3ca6f65866`, `addons/noisemaker/runtime/nm_backend.gd` `fcf3377d80c5160bf59c1c096ce78813094d00a06c305742319e19ca59d6f96f` — each matches both the served inventory digest and `git show 6f333bcf411eb3b3baa4e8b5c46a7e082258dcca:<path>` exactly, so the served 0.1.35 kit ships the playback `main.gd` and the `mip_filter` compat. No Export kit run exists at `6f333bc` itself, and none is owed: `6f333bc` touches only `docs/COMPLETION_GAPS.md` and `parity/*`, which are outside the workflow's push-path filter (`export-kit/**`, `LICENSE`, `godot/addons/noisemaker/**`, the workflow file), and its kit-path trees are byte-identical to `1c0d8e6`'s (diff covers no filtered path). Docs/parity-only commits dispatch no kit rebuild. Remaining open human requirements (not automatable here): install the published artifact and exercise desktop-editor Play, ordinary parameter edits, and editor interaction (cancellation/recovery of a killed run is covered by the committed test; window-close interaction is not). Receipt extension for this commit (`204cd77`): it is docs-only — its sole change is this file (`docs/COMPLETION_GAPS.md`), outside the workflow's push-path filter, so no Export kit run is owed at it; its kit-path trees are byte-identical to `6f333bc`/`1c0d8e6`, so the served kit 0.1.35 evidence above applies unchanged.
- Acceptance: A temporal program visibly evolves as documented. Every documented control exists and changes its stated behavior. (Shown on Godot 4.7 over llvmpipe by the committed suite; the declared native verify cases gate parity fixtures, not the kit observer.)

### GAP-002: Rendered parity retains unresolved failures

- Status: blocked (2026-09-27). Priority: P1. Category: verification.
- Scope: Perspective points, alpha billboards, and the full retained pixel ledger.
- Expected: Claimed parity satisfies the existing thresholds for the identified source and workload.
- Observed: Perspective points fail the independent current-authority comparison with maximum difference 243.
- Evidence: `differential/heightGrid_pointsRender_perspective.report.json`. The retained alpha row reports SSIM approximately 0.00001239.
- Review evidence: Recomputed retained metrics agree. Kit 0.1.17 also fails against that reference with maximum difference 243.000.
- Source-bound reproduction (2026-09-27, Linux container): Godot `4.7.stable.official.5b4e0cb0f` Forward+ over Vulkan lavapipe/llvmpipe, reference goldens minted fresh from the reference engine (`NM_REFERENCE_ROOT` at upstream `a912749fab5c`, webgl2 backend, 256×256, time 0.25). Red-before against the published base `5cd72ea`: `heightGrid_pointsRender_perspective` max-abs-diff 243.000 / mean 3.0537 / ssim 0.96037; `heightGrid_billboard_alpha` max-abs-diff 215.000 / mean 0.4720 / ssim 0.99975. Both comparator runs exit 1 at tolerance 2.001 / ssim-min 0.98. Rejected cases and raw images are preserved in-tree under `parity/receipts/GAP-002/` (per case: `.golden.png`, `.candidate.png` with fixes, `.candidate.red.png` at base, `.report.json` / `.report.red.json`); the golden is minted from the pinned reference revision, so the candidate/golden pair is source-bound. The declared native trio passes in this environment's local run (`adjust` 1.000, `alphaMask` 1.000, `bitwise` 0.000 max-abs-diff); the declared native_checks run post-publication and are not established by this record.
- Two port defects found and fixed this round:
  1. `runtime/nm_backend.gd::_snapshot_surface` quantized float surfaces through `Image.set_pixel`, which TRUNCATES on RGBA8 (micro-test: 0.5→127, 0.253→64) while the reference capture uses JS `Math.round(v*255)`. Every float-surface candidate PNG was biased 1 LSB low on ~half the pixels. Fixed with explicit `floori(v*255.0+0.5)` byte quantization (half-up, matching the reference's Math.round; clamped to [0,255] like the reference's `Math.max(0, Math.min(255, ...))`, so negative inputs clamp to 0 on both sides). Effect: `heightGrid_billboard_alpha` mean 0.4720→0.1093, ssim 0.99975→0.99977; `heightGrid_pointsRender_perspective` mean 3.0537→2.3499, ssim 0.96037→0.96241.
  2. `render/pointsRender/deposit.vert.glsl` and `render/pointsBillboardRender/deposit.vert.glsl` computed the density-cull random with a hi/lo "exact" split that computes a DIFFERENT f32 value than the reference's verbatim `fract(pid*GR)` the golden uses (8 agents flip at threshold 0.5, 3 at 0.65 for 65536 agents). Reverted to the reference expression. The known ~1M-agent float32-precision hazard (CHAOS-GATE) is reference-inherited and documented in-file.
- Residual failures WITH both fixes (comparator exit 1, tolerance 2.001 / ssim-min 0.98): perspective max-abs-diff 242.000 / mean 2.3499 / ssim 0.96241; billboard_alpha max-abs-diff 215.000 / mean 0.1093 / ssim 0.99977.
- Residual root cause — engine toolchain domain, unreachable from the addon (same class as the pinned `pow` in docs/CHAOS-GATE.md):
  - First isolation round: the port's perlin `o0` dumped through a forced RGBA32F RENDER SURFACE still differed from the golden by a systematic −1 half-ULP on 98,928/262,144 channel values — but those values were half-exact, proving the INTERNAL node texture (rgba16f) still sat in the chain and the measurement captured storage conversion, not shader math.
  - Corrected isolation (both the node texture and the surface forced to rgba32f, so the dump holds the shader's true f32 output): round-to-nearest-half of the port's f32 differs from the golden's stored half on 5,973/262,144 channel values (2.3%), with MIXED direction (lower: 3,369; higher: 2,604) and magnitudes ≤1 half-ULP. The mixed sign and sub-half-ULP scale exclude any systematic port defect: this is spec-legal shader-compiler evaluation divergence (Godot's GLSL→SPIR-V glslang codegen vs the golden's ANGLE→GL lowering) — the documented chaos-gate class. The port's perlin GLSL main body matches the reference's algorithm (one benign difference: the port's `res` guard reads `resolution` where the reference reads `fullResolution`; both divide `st` by the same 256 here).
  - Storage conversion attribution (compute probe, Godot 4.7 over lavapipe): storing f32 0.50068359375 into an RGBA16F image yields 0.5 — 1–2 ULP below round-to-nearest — so the driver's fp16 storage conversion under-rounds (it produced the earlier 37.7% systematic bias). The golden side (ANGLE→GL→llvmpipe) stores round-to-nearest: RTNE(port f32) matches the golden's stored half on 97.7% of texels while RTZ misses 37.7%.
  - Consequence for closure: even a perfect fp16-storage fix (in-shader RTNE pre-quantization) would leave the 2.3% sub-half-ULP codegen residual, which the height grid (heightScale 25) + perspective projection amplifies into dozens of single-pixel point flips of inherently 243-magnitude (point-vs-background), and the billboard's steep circle-edge alpha ramp into 215-magnitude single-pixel diffs — both far outside tolerance 2.001. The residual is therefore not removable from the addon, the shader, the driver, or the environment.
  - WebGPU reference-self comparison (the documented cross-backend budget method) is unavailable in this container: Chromium reports `navigator.gpu` unavailable over lavapipe (Vulkan 1.1.230 ICD; Dawn requires newer). This evidence is therefore missing, not negative.
- Limit: both gates remain FAILING closed; no exception was budgeted. Standalone regressions checked: local battery on this environment = definitions 210/210, registry PASS (628/628 effectKeys), lex/parse/validate/graph 352/352, expand 344/352 (the 8 documented pass-defines baseline diffs), smoke `SMOKE: ALL PASS`, unittest 96 tests / 5 failures — the identical 5 live-render suites fail identically on the published base in this environment (device-limits MRT, async readback, mesh pipeline, missing-effects live, shader-compile sweep), so no regression is attributable to this round's fixes. Full-order execution is bounded by the same residual: the two cases fail regardless of batch position.
- Next action: an actor with engine/toolchain authority must match ANGLE's fp lowering in glslang/spirv-cross (or force precise transcendentals in Godot's shader compile) so the port's noise f32 matches the golden's before fp16 storage; same close condition as docs/CHAOS-GATE.md. After that, re-run the executable check below under standalone and full-order execution.
- Dependencies: Identify the original reference snapshot and full batch order before evaluating the historical alpha failure. (Done: goldens are content-minted by `parity/export-and-render.mjs` at a pinned reference revision; batch order is `parity/ledger.json`.)
- Acceptance: Both failures pass their existing gates under source-bound reproductions, including standalone and full-order execution.
- Required checks: Run the existing comparator with tolerance 2.001 and SSIM minimum 0.98. Preserve rejected cases and raw images.
- Executable check: `python3 parity/compare.py "$GOLDEN" "$CANDIDATE" --tolerance 2.001 --ssim-min 0.98 --report "$OUT/report.json"`.
- Pass condition: Exit 0 with both thresholds satisfied. A high SSIM alone cannot excuse the failing maximum difference.

### GAP-003: Backend teardown leaves GPU resources allocated

- Status: open. Priority: P2. Category: ecosystem.
- Scope: `runtime/nm_backend.gd`, consumer examples, and long-lived Godot projects.
- Expected: A developer can release backend-owned GPU resources while following a documented ownership contract.
- Observed: `close()` closes sinks but does not release backend GPU handles. Freeing the device then reports resource leaks.
- Evidence: `consumer-api.log` reports pipeline, uniform-set, buffer, shader, sampler, and texture warnings after `close()` and `rd.free()`.
- Review evidence: `current-consumer-api.log` reproduces warnings with kit 0.1.17 on the Godot 4.7 floor.
- Limit: The audit did not measure long-term memory growth. Device destruction ends the probe's resource lifetime.
- Next action: Define backend and device ownership. Reproduce repeated creation, rendering, resize, and disposal with resource accounting.
- Dependencies: Preserve output-sink and asynchronous export semantics.
- Acceptance: Repeated lifecycle operations produce no leaked-handle warnings or increasing retained resource counts.
- Required checks: Run lifecycle probes and existing frame-export tests. Exercise active export cancellation before device destruction.

### GAP-004: Public compilation loses useful error diagnostics

- Status: open. Priority: P2. Category: usability.
- Scope: `compiler/graph/orchestrator.gd`, `tools/render_graph.gd`, and exported project startup.
- Expected: Invalid DSL identifies the offending effect and location before rendering starts.
- Observed: `notAnEffect()` reaches rendering and reports only a missing output surface.
- Evidence: `invalid.log`, exit 1, no PNG. `recovery.log` records valid DSL success through the same installed renderer.
- Review evidence: `invalid-current.log` and `recovery-current.log` reproduce both results with kit 0.1.17.
- Cause evidence: `build_graph()` obtains validation diagnostics but does not expose or reject them before expansion.
- Next action: Preserve the failing input. Trace diagnostic propagation through the public compiler and host entry points.
- Dependencies: Preserve the structured lexer and validator contracts already covered by tests.
- Acceptance: The unknown-effect input produces an actionable diagnostic without rendering. Correcting it restores output.
- Required checks: Test unknown effects, malformed syntax, missing files, and missing devices through both public entry points.

### GAP-005: Current behavior and host qualification are incomplete

- Status: blocked. Priority: P2. Category: verification.
- Scope: Current authority, Godot editor workflows, lifecycle, package upgrades, and supported platforms.
- Expected: Completion evidence covers the stated modes, inputs, workflows, and host versions.
- Observed: Three current pixel probes and a batch prefix do not qualify the catalog. Historical image provenance is incomplete.
- Evidence: `checks.json`, `source-hashes.json`, `gui-blocker.json`, the retained ledger, and section 3.
- Blockers: Historical source-bound images and other host platforms remain unavailable. The worker's Mac lock prevented editor interaction.
- Review limit: The reviewer did not repeat editor interaction. Bounded Godot 4.7 floor checks do not qualify the full host workflow.
- Additional limit: Expansion differs in eight pass-define cases. Normalized graphs match, so these differences do not alone prove rendering defects.
- Next action: Define accepted expansion differences. Recover historical image provenance. Qualify the current landscape filtering modes and representative stateful chains.
- Dependencies: GAP-001 through GAP-004 define required behavior checks.
- Acceptance: Evidence binds candidate, reference, inputs, time, seed, dimensions, exclusions, and thresholds to exact source revisions.
- Required checks: Run public installation, Play, parameter edits, error recovery, keyboard access, upgrade, and removal on each supported host.
- Packaging checks: Resolve the standalone notice omission under GAP-008. Test a packaged Godot game when the supported contract includes it.
- Editor evidence: `editor.log` contains repeated `ShaderFile` thread-access errors. The Mac lock prevents checks of their user impact.

### GAP-006: Release CI does not qualify Godot behavior

- Status: open. Priority: P2. Category: release.
- Scope: Existing export-kit dispatch and Scaffold release checks.
- Expected: Release evidence identifies which runtime and parity requirements passed for the shipped source.
- Observed: Both exact-source jobs pass, but their checks validate packaging rather than Godot execution or rendered parity.
- Evidence: Source run `35810075402`, release run `35810082616`, and retained logs.
- Review evidence: Source run `35951202302` and release run `35951211347` still qualify packaging only.
- Next action: Define release acceptance through the existing systems. Keep package integrity, runtime correctness, and human usability separate.
- Dependencies: GAP-001 through GAP-005. This audit does not authorize workflow changes.
- Acceptance: The release record includes exact-source compiler and runtime results, platform limits, and unresolved parity failures.
- Required checks: Check the immutable artifact and source containment. Reject a green packaging summary as whole-port approval.

### GAP-007: Current documentation mixes incompatible historical claims

- Status: open. Priority: P3. Category: contract.
- Scope: Root README, addon README, STATUS, and parity README.
- Expected: Current guidance separates present behavior from historical measurements and explicit exclusions.
- Observed: Counts include approximately 180 effects, 216/216 programs, 209 definitions, and 214/214 compiler cases.
- Evidence: Current source contains 210 definitions and 352 compiler fixtures. STATUS still calls some shipped shader namespaces staged with zero shaders.
- Additional inconsistency: The addon excludes audio input broadly while runtime state APIs and tests support bounded audio behavior.
- Next action: Correct current summaries through scoped documentation work. Preserve historical measurements with their dates and source qualifications.
- Dependencies: GAP-001, GAP-002, and GAP-005 establish the acceptance boundaries.
- Acceptance: Current summaries agree with the supported contract and explicitly retain failures, exclusions, and unavailable qualification.
- Required checks: Cross-check every numerical claim against its source-bound evidence. Do not convert compiler passes into pixel-parity claims.

### GAP-008: Documented standalone addon copy omits license notices

- Status: open. Priority: P1. Category: release.
- Scope: Root README installation steps and `godot/addons/noisemaker/`. The complete export kit is not affected.
- Expected: The documented standalone distribution carries the required notices with the copied code.
- Observed: The copied addon contains no license files or complete MIT notice text. The root license remains outside the instructed copy.
- Evidence: `addon-distribution.json`, the root `LICENSE`, and the README installation steps at `6335960ea16d7a1231355eafe5086ad3c73afd58`.
- Next action: Include the port and upstream notices in the standalone distribution through the separate implementation job.
- Dependencies: Establish the copied directory as the distribution boundary. Preserve the export kit's existing `LICENSES/` entries.
- Acceptance: A fresh installation contains both complete notices and produces the documented texture without repository files outside the addon.
- Required checks: Copy the documented addon into an empty project. Compare each installed notice with its source text.
- Executable check: `cmp LICENSE "$ADDON/LICENSE"` for the port notice. Use the same byte comparison for the identified upstream notice.
- Runtime check: Execute the documented first render in that project. Require a nonempty texture and no missing dependencies.
- Last verification: 2026-09-24. The review confirmed the notice omission. The corrected distribution does not yet exist.

## 5. Ordered next actions

1. Preserve both source checkpoints, immutable kit manifests, raw images, and the worker's authority before implementation.
2. Resolve GAP-001 in `export-kit/kit/main.gd` and its template. Execute the scene observer with a temporal fixture.
   Require changing displayed frames and working documented controls. Then check cancellation and recovery from the installed artifact.
3. Diagnose GAP-002 using the retained failing point images and the comparator command above. Require both existing thresholds.
   Recover the historical reference and full execution order before evaluating the separate alpha failure.
4. Correct GAP-008's standalone distribution independently of playback work. Require exact notice comparisons and the isolated first render.
5. Define ownership under GAP-003. Repeat `consumer-api.gd` across creation, resize, rendering, and disposal.
   Require no leaked-handle warnings or growing retained counts. Preserve frame-export cancellation and the existing runtime tests.
6. Trace GAP-004 through `compiler/graph/orchestrator.gd` and both public entry points.
   Require an unknown-effect diagnostic before rendering. Then require successful output from corrected DSL in the same installation.
7. Resolve GAP-005's evidence dependencies after the behavior checks. Qualify filtering modes, stateful chains, editor operation, upgrades, and supported hosts.
8. Define GAP-006's acceptance through existing CI after required behavior and distribution checks. Preserve failures and platform exclusions.
9. Correct GAP-007's current summaries after the supported behavior is clear. Preserve historical status evidence.

`KIT` identifies the installed candidate. `WORKER` identifies `evidence-20260923-godot-05` in the automation store.
`OUT` identifies an isolated evidence directory. `ADDON` identifies the installed standalone addon.
`GOLDEN` and `CANDIDATE` identify the preserved reference and candidate PNGs.

These actions specify acceptance work. They do not authorize new effect ports or advancement beyond the current parity checkpoint.

## 6. Pass history

| Date | Source | Changes and evidence | Remaining limits |
| --- | --- | --- | --- |
| 2026-09-23 | `bbb2d0179c6e991bdeb2efba7ea733baae027f36` | Created this register and README link. Ran 66 tests, compiler gates, three differential probes, batch prefix, and installed-artifact checks. | Seven gaps remain. No completion approval. Full historical parity, editor interaction, additional platforms, upgrades, and removal remain unqualified. |
| 2026-09-24 | `6335960ea16d7a1231355eafe5086ad3c73afd58` | Reviewed all available worker results. Passed 68 current tests. Reproduced playback, pixel, lifecycle, and diagnostic findings. Added GAP-008 and executable acceptance checks. | Eight gaps remain. No verified closures. Full compiler comparisons, latest-authority pixels, editor workflows, other platforms, upgrades, and removal remain unqualified. |
| 2026-09-25 | This sync commit (upstream `9d3474dfdc6c..2f47612c2904`; see the 2026-09-25 sync row in section 1) | Ported GAP-004 texture-allocation policies with the mip/persistent runtime, fixed STATUS coverage counts, audited the force-push range by content. Candidate range for review: base `55c3c92` (published `origin/main` head) → current head of this branch
(run `git log --oneline --reverse 55c3c92..main` for the exact chain). The CODE-bearing commits end at
`dc3c2dc`; the chain is: `4090c0f` sync upstream `9d3474dfdc6c..2f47612c`; `e2b5a2a` record range audit
in COMPLETION_GAPS; `edd799a` snapshot prior allocation state in `allocate_textures`; `05296f9` GLSL
identifier regex backslash fix; `59cfa59` resample uniform set → single UBO binding; `776ea3b`
working-tree sync; `39e1517` hard-wrap STATUS ledger lines; `a2b0a26` mipmap-sampler selection keyed
by READ texId + ledger corrections; `4811110` reproducible audit commands + baseline identity;
`d4ddf3c` record this candidate range; `dc3c2dc` persistent pingpong halves + mip-scratch close()
frees + corrected ancestor facts. Any commit after `dc3c2dc` is a REGISTER-ONLY edit of this row
plus, in this row's own update commit, the per-spec `is3D` policy split in
`tools/convert-definitions.mjs` (regenerated definitions byte-identical; definitions/graph/expand/
smoke re-run after it, counts unchanged). Gates on Linux headless: smoke 85/85, lex/parse/validate/graph 352/352, registry pass, definitions 210/210, expand 344/352 (documented diffs), unittest 79/84 (5 display-dependent failures, identical on baseline). Review fixes folded in: mipmap-sampler selection now keys `_tex_mip` by the resolved READ texId (`_read_tex_id`) instead of `_resolve_read`'s RID (previous lookup never matched — dead path), the mip sampler sets `mipmap_filter` explicitly, `convert-definitions.mjs` drops the pre-branch unconditional policy projections, the 3D `filter` staging comment no longer claims runtime consumption, `_alloc_pingpong` now honors the `persistent` policy for double-buffered global surfaces (both halves resampled via `_resample_tex`, matching reference `createSurfaces`→`recreateTexturePreserving`), and `close()` frees the mip scratch texture, resample pipelines, and resample shader. CI: `export-kit.yml` run 36215382144 (attempt 1) PASSED on the published head
`76b4dac0d21c8cd265a635d7942a91b98a991fd7` (refs/heads/main; machine-verified receipt
`8addaf72-3d63-4fb4-bf4b-afeda4b91320`, 2026-09-26) — the first CI run covering this candidate. | No gap closes. No pixel-parity re-sweep, windowed GPU run, or editor interaction evidence for this commit yet; upstream runtime fidelity (`fsMip`/`fsScale`, `extractTextureSpecs`, `recreateTexturePreserving`, the `13a8a049..2f47612c` empty-diff claim) is audited by content against the reference clone with the reproducible commands AND committed observed outputs recorded in section 1 (no independent party has re-run them in its own environment); the 5 display-dependent test failures are baseline-identical at `55c3c92` (verified, recorded in section 1); the post-audit upstream changes remain unqualified pending windowed checks. |
| 2026-09-26 | This sync commit (upstream `2f47612c2904..6a0af04d3c4f`; see the 2026-09-26 rows in section 1) | Closed the remaining delta to upstream `6a0af04d`: ported GAP-006 opt-in texture pooling (`6113da00`+`95743621` — plan build from `graph.allocations` with all reference safety guards, alias application, regroup release with per-unique-RID free dedupe, `get_resource_plan`, default OFF, wired through `render_graph.gd --texture-pooling`/batch requests which now actually call `set_texture_pooling` and print `NM_RESOURCE_PLAN`) and the structured backend diagnostic union (`f83a427e` — new `runtime/shader_diagnostics.gd`, `last_shader_diagnostic` on compile/link/missing-source failures with unchanged legacy `push_error` text); `fa83eeab` confirmed already ported; docs-only/CI-only commits audited with outputs committed verbatim in section 1 (empty `shaders/effects`/`shaders/src/lang` diff). Gates on Linux headless (Godot `4.7.stable.official.5b4e0cb0f`, reference clone at upstream `6a0af04d`): definitions 210/210, lex/parse/validate/graph 352/352, registry pass, expand 344/352 (the same 8 documented diffs), smoke ALL PASS, unittest 83/88 (4 new tests incl. headless alias/release bookkeeping with a counting free callable; the 5 failures are the same display-dependent windowed tests as the baseline). | No gap closes. No pixel-parity re-sweep and no windowed GPU run for this commit (pooling is default-off and shader math untouched; the opt-in runtime path is exercised headless at the plan/alias/release bookkeeping level and via the now-live `--texture-pooling` CLI, but not yet under a real windowed RenderingDevice); the 5 windowed test failures and the historical GAP-001..GAP-008 findings remain open. |

Post-sync native-run note (2026-09-26): the first `godot-parity` native run of `59c1a6f` FAILED on
its first required case (`compare-adjust` exit 1, `parity/out/adjust.report.json` written on the
runner host but not attached to the check result — no local GPU/display exists to re-render or
compare). `parity/run.sh` now surfaces the full report JSON, artifact sizes/hashes, and a one-line
metrics summary on any compare failure, so the next native run is diagnosable from its output tail
alone. No tolerance, fixture, or render behavior was changed by this diagnostic (the runner's
failure could not be reproduced or attributed locally: the retained ledger records adjust PASS at
max-abs-diff 1.000 / SSIM 0.99996 under the strict default tolerance, and the reviewed commit's
runtime changes all early-return with texture pooling off).

The third native run (candidate `35c56c6`, first with the tail fix) FAILED `compare-adjust` with
`max-abs-diff=255.000 mean-abs-diff=147.1240 ssim=0.00001` — an uncorrelated image, consistent
with one artifact rendering degenerate (black/garbage) rather than a tolerance miss, and matching
the signature of the pre-existing `heightGrid_billboard_alpha` full-batch anomaly (also
ssim≈0.00001). Attribution for the next native run comes from tooling already published in
`2563652` and `0ad915b` (not from this doc commit): `compare.py` prints the verdict line LAST on
stdout and stderr (introduced in `2563652`), `run.sh`'s failure path prints per-image
mean/std/nonzero-alpha (`DIAG image golden/candidate`) and `render_graph.gd` prints
`NM_SHADER_DIAG code/stage/program/detail` from the structured diagnostic union (both introduced
in `0ad915b`). The next native run should therefore attribute which artifact is degenerate and
whether a pass silently failed to compile/link on the runner GPU.

Fourth native run (candidate `ea745f0`, first with the degenerate guard): `compare-adjust` failed
with the tail `error: degenerate candidate artifact is all-zero (no pixels written by the Godot
renderer)` — the GOLDEN mint is fine; the Godot candidate render produced an all-zero PNG on the
native runner while exiting 0 with a valid RenderingDevice (otherwise `RD_NULL`/renderer-exit
would have failed run.sh earlier). No `NM_SHADER_DIAG` reached the tail, so either no compile/link
diagnostic was set or the tail truncated it. The fifth run (`3d4444e`) adds `NM_PASS_STATS
executed/skipped/surface_valid` on stdout AND stderr plus a missing-output structured diagnostic
and a stderr-only DIAG block, so its tail must show how many passes executed and whether the
render surface RID is valid before the compare fails. Working hypothesis: an environment-specific
rendering failure on the `native-spare` runner (historical ledger PASSes are macOS; the anomalous
signature matches the pre-existing `heightGrid_billboard_alpha` batch anomaly), not the sync's
pooling-off allocation path, which is byte-identical to the pre-sync baseline (`git diff
fc4e6d0..59c1a6f` on `nm_backend.gd` removes only the relocated `var texs` declaration).

The audit preserved implementation, tests, generators, fixtures, tolerances, workflows, and historical documents.
It verified source identity before document publication. The shared result records remote publication verification.

2026-09-24 report initialization: added the maintained compatibility report and bounded native measurements. No full-parity closure.
