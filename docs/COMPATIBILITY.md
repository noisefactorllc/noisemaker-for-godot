# noisemaker-for-godot: compatibility report

## 1. Source and authority revisions

Report date: 2026-09-29. Source inspected: [`5e215aee76797a419a41d6feedf810bc55052ccc`](https://github.com/noisefactorllc/noisemaker-for-godot/commit/5e215aee76797a419a41d6feedf810bc55052ccc).
Local `main` and remote `main` match at this SHA.
Full rendered parity at this SHA: **unverified**. This is not a release approval.
A later documentation-only commit does not change this tested source identity.
Any runtime, package, or authority update requires fresh evidence before this report can qualify it.

Godot 4.7 Forward+ compiler and GPU renderer. [Source contract](https://github.com/noisefactorllc/noisemaker-for-godot/blob/5e215aee76797a419a41d6feedf810bc55052ccc/README.md).

Historical tested authority revisions remain in the linked gap register. They are not relabeled as current qualification.
The goldens' bound reference revision is `a912749fab5c3819e56a8abde664ff30e40870f4`.
The port's last synced reference is `73c15be00d6888f4b5d2835d8e242ee9e840df45` (2026-09-28).
The delivered upstream end for the 2026-09-29 sync round is `682739066d3b74962febbdcdae85b5aa4d2e19f3`
(an ancestor of the previously observed `42843597e8ae…`; delivery order is not ancestry order).
The delta past the synced reference changes `shaders/src/runtime/external-input.js`
(audio capture, GAP-032 upstream) plus docs and dependency files; the 2026-09-29 sync round ruled
it never-ported/inapplicable to this port (browser host capture integration — the port's mirrored
graph-side `get_audio_input_requirements()` is unchanged upstream in the range) and re-ran all
gates at the pinned reference `682739066d3b` ([completion gaps](COMPLETION_GAPS.md) §1, STATUS.md).
The effect catalog is unchanged in that delta.
Published authority alias `1.0` serves a 210-ID manifest, SHA-256 `05c4d7b7744837ae90a3bb4c89e5403ff09448a74d9d7e824abb3d719ad3314e`.
The sampled releases `1.0.176`, `1.0.196`, `1.0.197`, and `1.0.198` serve byte-identical manifests.
Intermediate releases are unmeasured.
These IDs do not define complete parameter, state, input, or platform coverage.

Served kit `0.1.40` records `5e215aee76797a419a41d6feedf810bc55052ccc`. [Source metadata](https://kits.noisedeck.app/godot/0/deployment-meta.json).
Daily review 2026-09-29 verified it: 1517 of 1517 manifest entries match by SHA-256 and byte count.
All 883 source entries are verified. 882 are byte-identical to the commit tree.
`LICENSES/noisemaker-MIT.txt` is byte-identical to the reference `LICENSE` at `a912749f`.
The builder-generated `compat.json` holds 210 effect IDs that equal the repository effect set.
The 634 `.glsl.import` entries are Godot-editor-generated import metadata.
Historical measurements remain bound to their original revisions in [completion gaps](COMPLETION_GAPS.md).

## 2. Host and distribution matrix

| Dimension | Status | Measured scope or limit |
|---|---|---|
| Source-level checks | verified | Review 2026-09-29 re-ran engine-free 58/58, Godot-headless 49/49, and all compiler gates at `5e215ae`. The same batteries stayed green at the documents-only review candidates. |
| Actual host rendering | partial | The implementation job reports native Metal passes for the two GAP-002 gate cases and a green windowed battery. This review could not re-read those archived receipts. It verified the source-level implementation and the headless suites instead. |
| Minimum and current host versions | unverified | Declared requirements are not a tested version matrix. |
| Supported operating systems and backends | unverified | macOS Metal and Linux headless are measured. Windows and Linux windowed rendering are not measured. |
| Installed package and first useful result | verified for the served kit | Kit `0.1.40` fully byte-verified. 883 source entries: 882 match the commit tree, one matches the reference `LICENSE`. Kit playback evidence lives in the gap register. |
| Parameters, external inputs, state, and chains | unverified | Full current-authority combinations remain unmeasured. |
| Invalid input and recovery | partial | Missing-device, invalid-DSL, and recovery probes pass at recorded revisions. The unknown-effect diagnostic stays open under GAP-004. |
| Upgrade, removal, and resource cleanup | partial | The teardown ownership contract is implemented and gated (GAP-003 closed). Upgrade and removal remain unverified. |
| Accessibility of provided controls | unverified | Keyboard, focus, labels, and diagnostics need host observations where applicable. |
| Release readiness | blocked | Whole-port rendered parity, standalone notices (GAP-008), and release gating (GAP-006) remain open. |

## 3. Parity coverage

Full parity requires complete applicable coverage with no skips or missing cases.
Historical NEAR, CHAOS, and tolerated differences do not count as strict equality.
The existing numerical contracts remain separate from exact comparison. This report does not change tolerances or goldens.
Unknown values mean `not measured`, never zero.

| Gate | Expected cases | Executed | Strict passes | Failures | Skips | Status |
|---|---|---|---|---|---|---|
| Definitions versus reference `73c15be0` | 210 | 210 | 210 | 0 | 0 | Verified 2026-09-29. |
| Compiler language gates versus reference | 352 each | 352 each | 352 each | 0 | 0 | Verified 2026-09-29. |
| Registry (ops, enums, aliases, keys) | 210 / 8 / 44+0 / 628 | all | all | 0 | 0 | Verified 2026-09-29. |
| Expansion | 352 | 352 | 344 | 0 | 0 | 8 documented pass-define differences. Normalized graphs match. |
| Whole-port rendered parity | 342 | 0 | 0 | 0 | 342 | unexecuted in the check containers. Rendering needs a GPU-capable display, and none is present. |
| GAP-002 gate cases | 2 | 2 | 2 | 0 | 0 | reported passing on native Metal by the implementation job. Not independently re-checked. Supervisor summary pending. |

Served compatibility inventory declares 210 effect IDs. Declaration does not establish execution or parity.
No missing ID conclusion follows without reconciling fixture behavior and the source contract.
Missing effects remain visible toward the full-parity goal. Contract exclusions do not become successful tests.

Whole-port rendered parity is the qualification gap: `scripts/parity-summary` counts 342 expected ledger
programs and has not executed them in a check environment. The two GAP-002 gate cases
(`heightGrid_pointsRender_perspective`, `heightGrid_billboard_alpha`) are reported passing on the
qualified native host by the implementation job, with comparator tolerance 2.001 and SSIM minimum
0.98, standalone and in ledger order. This review could not re-read the archived receipts.
Eleven other native prefix cases still fail and stay recorded in the gap register.
The ledger derives its cases locally, so it does not by itself establish authority coverage:
review 2026-09-29 measured fixture coverage from the programs' normalized render graphs
(reference compiler, all 342 programs) — 183 of 210 authority effects are exercised, and 27
have no fixture (list in the series evidence).
No tolerance, golden, or deferral record exists in this repository.

### Effect inventory

| Effect ID | Declared in served kit | Current full parity |
|---|---|---|
| `classicNoisedeck/bitEffects` | yes | unverified |
| `classicNoisedeck/caustic` | yes | unverified |
| `classicNoisedeck/cellNoise` | yes | unverified |
| `classicNoisedeck/cellRefract` | yes | unverified |
| `classicNoisedeck/coalesce` | yes | unverified |
| `classicNoisedeck/colorLab` | yes | unverified |
| `classicNoisedeck/composite` | yes | unverified |
| `classicNoisedeck/effects` | yes | unverified |
| `classicNoisedeck/fractal` | yes | unverified |
| `classicNoisedeck/glitch` | yes | unverified |
| `classicNoisedeck/kaleido` | yes | unverified |
| `classicNoisedeck/lensDistortion` | yes | unverified |
| `classicNoisedeck/moodscape` | yes | unverified |
| `classicNoisedeck/noise` | yes | unverified |
| `classicNoisedeck/noise3d` | yes | unverified |
| `classicNoisedeck/refract` | yes | unverified |
| `classicNoisedeck/shapeMixer` | yes | unverified |
| `classicNoisedeck/shapes` | yes | unverified |
| `classicNoisedeck/shapes3d` | yes | unverified |
| `classicNoisedeck/splat` | yes | unverified |
| `filter/adjust` | yes | unverified |
| `filter/bloom` | yes | unverified |
| `filter/blur` | yes | unverified |
| `filter/bulge` | yes | unverified |
| `filter/celShading` | yes | unverified |
| `filter/channel` | yes | unverified |
| `filter/chroma` | yes | unverified |
| `filter/chromaticAberration` | yes | unverified |
| `filter/chrome` | yes | unverified |
| `filter/clouds` | yes | unverified |
| `filter/colorReplace` | yes | unverified |
| `filter/convolutionFeedback` | yes | unverified |
| `filter/corrupt` | yes | unverified |
| `filter/craquelure` | yes | unverified |
| `filter/crt` | yes | unverified |
| `filter/degauss` | yes | unverified |
| `filter/deriv` | yes | unverified |
| `filter/directionalBlur` | yes | unverified |
| `filter/dither` | yes | unverified |
| `filter/edge` | yes | unverified |
| `filter/emboss` | yes | unverified |
| `filter/extrude` | yes | unverified |
| `filter/feedback` | yes | unverified |
| `filter/fibers` | yes | unverified |
| `filter/flipMirror` | yes | unverified |
| `filter/fxaa` | yes | unverified |
| `filter/glowingEdge` | yes | unverified |
| `filter/glyphMap` | yes | unverified |
| `filter/grade` | yes | unverified |
| `filter/grain` | yes | unverified |
| `filter/grime` | yes | unverified |
| `filter/halftone` | yes | unverified |
| `filter/hatch` | yes | unverified |
| `filter/highPass` | yes | unverified |
| `filter/historicPalette` | yes | unverified |
| `filter/invert` | yes | unverified |
| `filter/lens` | yes | unverified |
| `filter/lensFlare` | yes | unverified |
| `filter/lensWarp` | yes | unverified |
| `filter/lightLeak` | yes | unverified |
| `filter/lighting` | yes | unverified |
| `filter/lowPoly` | yes | unverified |
| `filter/median` | yes | unverified |
| `filter/morphology` | yes | unverified |
| `filter/mosaicTiles` | yes | unverified |
| `filter/motionBlur` | yes | unverified |
| `filter/normalMap` | yes | unverified |
| `filter/normalize` | yes | unverified |
| `filter/octaveWarp` | yes | unverified |
| `filter/oilPaint` | yes | unverified |
| `filter/osd` | yes | unverified |
| `filter/outline` | yes | unverified |
| `filter/palette` | yes | unverified |
| `filter/parallax` | yes | unverified |
| `filter/patchwork` | yes | unverified |
| `filter/photocopy` | yes | unverified |
| `filter/pinch` | yes | unverified |
| `filter/pixelSort` | yes | unverified |
| `filter/pixels` | yes | unverified |
| `filter/plasticWrap` | yes | unverified |
| `filter/polar` | yes | unverified |
| `filter/pondRipples` | yes | unverified |
| `filter/posterize` | yes | unverified |
| `filter/prismaticAberration` | yes | unverified |
| `filter/reindex` | yes | unverified |
| `filter/relief` | yes | unverified |
| `filter/repeat` | yes | unverified |
| `filter/reverb` | yes | unverified |
| `filter/ridge` | yes | unverified |
| `filter/rotate` | yes | unverified |
| `filter/scale` | yes | unverified |
| `filter/scanlineError` | yes | unverified |
| `filter/scatter` | yes | unverified |
| `filter/scratches` | yes | unverified |
| `filter/scroll` | yes | unverified |
| `filter/seamless` | yes | unverified |
| `filter/sharpen` | yes | unverified |
| `filter/simpleAberration` | yes | unverified |
| `filter/sine` | yes | unverified |
| `filter/skew` | yes | unverified |
| `filter/smooth` | yes | unverified |
| `filter/smoothstep` | yes | unverified |
| `filter/snow` | yes | unverified |
| `filter/sobel` | yes | unverified |
| `filter/spatter` | yes | unverified |
| `filter/spinBlur` | yes | unverified |
| `filter/spiral` | yes | unverified |
| `filter/spookyTicker` | yes | unverified |
| `filter/stamp` | yes | unverified |
| `filter/step` | yes | unverified |
| `filter/stipple` | yes | unverified |
| `filter/strayHair` | yes | unverified |
| `filter/strokes` | yes | unverified |
| `filter/temporalAberration` | yes | unverified |
| `filter/tetraColorArray` | yes | unverified |
| `filter/tetraCosine` | yes | unverified |
| `filter/text` | yes | unverified |
| `filter/texture` | yes | unverified |
| `filter/threshold` | yes | unverified |
| `filter/tile` | yes | unverified |
| `filter/tint` | yes | unverified |
| `filter/translate` | yes | unverified |
| `filter/tunnel` | yes | unverified |
| `filter/unsharpMask` | yes | unverified |
| `filter/vaseline` | yes | unverified |
| `filter/vignette` | yes | unverified |
| `filter/warp` | yes | unverified |
| `filter/watercolor` | yes | unverified |
| `filter/waves` | yes | unverified |
| `filter/wind` | yes | unverified |
| `filter/wobble` | yes | unverified |
| `filter/wormhole` | yes | unverified |
| `filter/zoomBlur` | yes | unverified |
| `filter3d/flow3d` | yes | unverified |
| `filter3d/palette3d` | yes | unverified |
| `mixer/alphaMask` | yes | unverified |
| `mixer/applyMode` | yes | unverified |
| `mixer/blendMode` | yes | unverified |
| `mixer/cellSplit` | yes | unverified |
| `mixer/centerMask` | yes | unverified |
| `mixer/channelCombine` | yes | unverified |
| `mixer/distortion` | yes | unverified |
| `mixer/focusBlur` | yes | unverified |
| `mixer/mashup` | yes | unverified |
| `mixer/patternMix` | yes | unverified |
| `mixer/shadow` | yes | unverified |
| `mixer/shapeMask` | yes | unverified |
| `mixer/split` | yes | unverified |
| `mixer/thresholdMix` | yes | unverified |
| `mixer/uvRemap` | yes | unverified |
| `points/attractor` | yes | unverified |
| `points/buddhabrot` | yes | unverified |
| `points/dla` | yes | unverified |
| `points/flock` | yes | unverified |
| `points/flow` | yes | unverified |
| `points/heightGrid` | yes | unverified |
| `points/hydraulic` | yes | unverified |
| `points/lenia` | yes | unverified |
| `points/life` | yes | unverified |
| `points/physarum` | yes | unverified |
| `points/physical` | yes | unverified |
| `render/loopBegin` | yes | unverified |
| `render/loopEnd` | yes | unverified |
| `render/meshLoader` | yes | unverified |
| `render/meshRender` | yes | unverified |
| `render/pointsBillboardRender` | yes | unverified |
| `render/pointsEmit` | yes | unverified |
| `render/pointsRender` | yes | unverified |
| `render/render3d` | yes | unverified |
| `render/renderCubemap3d` | yes | unverified |
| `render/renderCubemapSurface` | yes | unverified |
| `render/renderLandscape3d` | yes | unverified |
| `render/renderLit3d` | yes | unverified |
| `synth/bitwise` | yes | unverified |
| `synth/cell` | yes | unverified |
| `synth/cellularAutomata` | yes | unverified |
| `synth/curl` | yes | unverified |
| `synth/gabor` | yes | unverified |
| `synth/gradient` | yes | unverified |
| `synth/julia` | yes | unverified |
| `synth/mandala` | yes | unverified |
| `synth/mandelbrot` | yes | unverified |
| `synth/media` | yes | unverified |
| `synth/mnca` | yes | unverified |
| `synth/modPattern` | yes | unverified |
| `synth/navierStokes` | yes | unverified |
| `synth/newton` | yes | unverified |
| `synth/noise` | yes | unverified |
| `synth/osc2d` | yes | unverified |
| `synth/pattern` | yes | unverified |
| `synth/perlin` | yes | unverified |
| `synth/polygon` | yes | unverified |
| `synth/reactionDiffusion` | yes | unverified |
| `synth/remap` | yes | unverified |
| `synth/roll` | yes | unverified |
| `synth/sacredGeometry` | yes | unverified |
| `synth/scope` | yes | unverified |
| `synth/shape` | yes | unverified |
| `synth/solid` | yes | unverified |
| `synth/spectrum` | yes | unverified |
| `synth/subdivide` | yes | unverified |
| `synth/testPattern` | yes | unverified |
| `synth3d/cell3d` | yes | unverified |
| `synth3d/cellularAutomata3d` | yes | unverified |
| `synth3d/flythrough3d` | yes | unverified |
| `synth3d/fractal3d` | yes | unverified |
| `synth3d/heightmap3d` | yes | unverified |
| `synth3d/noise3d` | yes | unverified |
| `synth3d/reactionDiffusion3d` | yes | unverified |
| `synth3d/shape3d` | yes | unverified |

### Native observations, 2026-09-24

Historical record. Evidence paths refer to files retained on the audit source host.

Godot 4.7, Forward+, Metal 4.0, Apple M4. 2 selected fixtures rendered. Exact comparison: 0 passes and 2 differences.
The graphs and goldens are retained historical inputs. Their full authority provenance remains unresolved in this pass.
These results do not qualify current upstream parity. Exact comparison uses zero byte tolerance.
Existing tolerance-based acceptance remains separate. No tolerance or golden changed.

| Inventory | Fixtures | Executed | Exact passes | Exact differences | Not executed | Full qualification |
|---|---|---|---|---|---|---|
| Tracked program files | 342 | 2 | 0 | 2 | 340 | unverified |

Every unexecuted fixture remains visible in the [fixture inventory](/Users/alex/.codex/automations/noisemaker-port-completion-audit/evidence-20260924-remaining-gap-documents/godot-fixture-inventory.json).
Fixture counts do not prove coverage of every current effect, parameter, or stateful workflow.

| Case | Exact result | Measurement | Evidence |
|---|---|---|---|
| `heightGrid_pointsRender_perspective` | failed | [FAIL] heightGrid_pointsRender_perspective: max-abs-diff=243.000 mean-abs-diff=0.7143 ssim=0.99785 (tol=0.0, ssim_min=0.98) | [Raw command](/Users/alex/.codex/automations/noisemaker-port-completion-audit/evidence-20260924-remaining-gap-documents/godot-heightGrid_pointsRender_perspective-comparison-command.json) |
| `noise` | failed | [FAIL] noise: max-abs-diff=1.000 mean-abs-diff=0.3756 ssim=0.99996 (tol=0.0, ssim_min=0.98) | [Raw command](/Users/alex/.codex/automations/noisemaker-port-completion-audit/evidence-20260924-remaining-gap-documents/godot-noise-comparison-command.json) |

## 4. Evidence

[Earlier audit and review evidence](COMPLETION_GAPS.md#3-methods-and-evidence). [Exact-source Actions](https://github.com/noisefactorllc/noisemaker-for-godot/actions?query=head_sha%3A5e215aee76797a419a41d6feedf810bc55052ccc).
Review 2026-09-29 (`review-20260929-050000`) re-ran the engine-free and Godot-headless suites and all
compiler gates, verified exact-source runs `36520432939` (Tests) and `36520432864` (Export kit) at the head,
and byte-verified served kit `0.1.40` against the commit. Series evidence: `/series/review-20260929-050000/result.json`.
Historical evidence paths recorded before the series migration refer to files retained on the audit source host.
Official host references and historical environment limits remain in the linked gap register.
Source CI, export dispatch, artifact delivery, and rendered parity are separate evidence dimensions.
A successful dispatch or unit-test summary does not establish a full rendered gate.

## 5. Open compatibility limits

See [GAP-002 and the complete gap register](COMPLETION_GAPS.md#4-known-gaps) for evidence, dependencies, and acceptance criteria.

1. Route the parity entrypoint repair through the implementation job: a nonzero render exit must never classify from an earlier run's report or candidate. Resolve the 11 native prefix failures and execute all 342 ledger programs. Reconcile ledger fixture coverage to the current authority manifest: 27 of 210 authority effects still lack any fixture. GAP-002 closure needs the supervisor-run `scripts/parity-summary` exact or strict for every expected case. Then close GAP-002 in a records-only commit.
2. Ruled (2026-09-29 sync): the upstream delta past the synced reference (`73c15be0..682739066d3b`, `external-input.js` audio capture plus docs and dependency files) is never-ported/inapplicable — browser host capture integration; the port's mirrored graph-side `get_audio_input_requirements()` is unchanged upstream in the range. Rulings in [completion gaps](COMPLETION_GAPS.md) §1 and STATUS.md.
3. Resolve GAP-004 diagnostics and GAP-008 standalone notices through the implementation job.
4. Continue GAP-005 catalog, editor, upgrade, and platform qualification. Define GAP-006 release acceptance.
5. Inspect exact-source CI and retain artifact hashes. Keep unresolved qualification failed or unverified.

All eligible ports have equal priority. Full parity and zero skipped cases remain the goal.
Implementation corrections remain with the separate job. This report does not advance the parity checkpoint.

## 6. History

| Date | Source | Result | Change |
|---|---|---|---|
| 2026-09-24 | `79e8a9794bccc04d2a29a40a7e21096b06115ccd` | Full qualification unverified | Created the requested maintained compatibility report. Preserved historical evidence and open gaps. |
| 2026-09-29 | `5e215aee76797a419a41d6feedf810bc55052ccc` | Full qualification unverified. GAP-001 and GAP-003 closed in the register | Daily review refreshed source, kit, gate, and matrix records to the current head. Whole-port rendered parity stays unverified. |

Run: `20260924-remaining-gap-documents`, then daily review `review-20260929-050000`. Later audits and reviews update this report with source-bound results.
