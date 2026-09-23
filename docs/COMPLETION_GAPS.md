# noisemaker-for-godot: completion gaps

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

## 2. Completion claims

| Claim ID | Claim source | Claimed scope | Finding | Evidence |
| --- | --- | --- | --- | --- |
| C-001 | README, first render | Self-contained useful texture output | supported | Published kit creates a visible-content 512×512 texture. Public API returns non-square images and responds to seed changes. |
| C-002 | STATUS, compiler gates | All compiler gates match the authority | partial | Definitions match 210/210. Lex, parse, validate, and graph pass 352/352 each. Expansion passes 344/352. |
| C-003 | README, STATUS parity summaries | Catalog rendering and pixel parity | contradicted | Retained ledger has two failures. Current perspective-points probe fails unchanged tolerance. Whole-catalog current parity remains unverified. |
| C-004 | Published README, Run it and Editing it | Sampled animation playback and editable frame controls | contradicted | Published `main.gd` renders one frame. No `FRAMES`, `SAMPLE_EVERY`, or `PLAYBACK_FPS` controls exist. |
| C-005 | Addon README, troubleshooting | Developers receive useful errors and can recover | partial | Missing-device error explains recovery. Invalid effect reports a missing surface. Corrected DSL renders successfully. |
| C-006 | Addon README, integration | Useful Godot scripting integration | partial | Public compiler, renderer, and `ImageTexture` path work. Cleanup reports resource warnings. Editor interaction remains unverified. |
| C-007 | Export kit workflow and artifact | Release readiness | partial | Exact-source release succeeds. All 882 file hashes match. Rebuild inventory matches. CI does not run Godot behavior or pixel comparisons. |
| C-008 | README and STATUS platform limits | Apple Silicon qualification | partial | GPU checks pass on M2, Metal, and Godot 4.7.2. Other platforms and the 4.7 floor remain unverified. |

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

## 4. Known gaps

P1 means false completion or a major correctness gap. P2 means missing coverage or integration. P3 means documentation inconsistency.
Every gap below was last checked on 2026-09-23. No gaps closed during this pass.

### GAP-001: Published project does not implement documented playback

- Status: open. Priority: P1. Category: implementation.
- Scope: `export-kit/kit/main.gd`, its README template, and published kit 0.1.16.
- Expected: The exported project plays sampled animation and exposes the documented frame controls.
- Observed: The project creates one image. It has no playback loop or the documented frame constants.
- Evidence: `kit-observe.log` records identical texture hashes across 120 frames. Published source matches the local rebuild.
- Next action: Define the intended existing export behavior. Correct the mismatch in the separate implementation job.
- Dependencies: Preserve the current kit and reproduction. Do not expand the effect checkpoint.
- Acceptance: A temporal program visibly evolves as documented. Every documented control exists and changes its stated behavior.
- Required checks: Install the resulting artifact. Exercise Play, ordinary parameter edits, stateful evolution, cancellation, and recovery.

### GAP-002: Rendered parity retains unresolved failures

- Status: open. Priority: P1. Category: verification.
- Scope: Perspective points, alpha billboards, and the full retained pixel ledger.
- Expected: Claimed parity satisfies the existing thresholds for the identified source and workload.
- Observed: Perspective points fail the independent current-authority comparison with maximum difference 243.
- Evidence: `differential/heightGrid_pointsRender_perspective.report.json`. The retained alpha row reports SSIM approximately 0.00001239.
- Limit: Current standalone alpha and the 99-program prefix pass. They do not resolve the historical full-batch failure.
- Next action: Preserve the failing point images. Diagnose differing pixels before attributing them to harmless numerical variation.
- Dependencies: Identify the original reference snapshot and full batch order before evaluating the historical alpha failure.
- Acceptance: Both failures pass their existing gates under source-bound reproductions, including standalone and full-order execution.
- Required checks: Run the existing comparator with tolerance 2.001 and SSIM minimum 0.98. Preserve rejected cases and raw images.

### GAP-003: Backend teardown leaves GPU resources allocated

- Status: open. Priority: P2. Category: ecosystem.
- Scope: `runtime/nm_backend.gd`, consumer examples, and long-lived Godot projects.
- Expected: A developer can release backend-owned GPU resources while following a documented ownership contract.
- Observed: `close()` closes sinks but does not release backend GPU handles. Freeing the device then reports resource leaks.
- Evidence: `consumer-api.log` reports pipeline, uniform-set, buffer, shader, sampler, and texture warnings after `close()` and `rd.free()`.
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
- Blockers: Historical source-bound images are unavailable. The Mac lock prevents editor interaction. Other host platforms are unavailable.
- Additional limit: Expansion differs in eight pass-define cases. Normalized graphs match, so these differences do not alone prove rendering defects.
- Next action: Define accepted expansion differences. Recover historical image provenance. Qualify the current landscape filtering modes and representative stateful chains.
- Dependencies: GAP-001 through GAP-004 define required behavior checks.
- Acceptance: Evidence binds candidate, reference, inputs, time, seed, dimensions, exclusions, and thresholds to exact source revisions.
- Required checks: Run public installation, Play, parameter edits, error recovery, keyboard access, upgrade, and removal on each supported host.
- Packaging checks: Include required notices in the addon-only distribution. Test a packaged Godot game when the supported contract includes it.
- Editor evidence: `editor.log` contains repeated `ShaderFile` thread-access errors. The Mac lock prevents checks of their user impact.

### GAP-006: Release CI does not qualify Godot behavior

- Status: open. Priority: P2. Category: release.
- Scope: Existing export-kit dispatch and Scaffold release checks.
- Expected: Release evidence identifies which runtime and parity requirements passed for the shipped source.
- Observed: Both exact-source jobs pass, but their checks validate packaging rather than Godot execution or rendered parity.
- Evidence: Source run `35810075402`, release run `35810082616`, and retained logs.
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

## 5. Ordered next actions

1. Preserve this source checkpoint, the published kit, and all raw evidence before implementation.
2. Resolve GAP-001's playback contract in `main.gd` and its template. Require real temporal output from the installed artifact.
3. Diagnose GAP-002 with the existing comparator and retained failing images. Recover full-order evidence before closing the alpha failure.
4. Define ownership under GAP-003. Require warning-free repeated lifecycle checks and unchanged frame-export behavior.
5. Trace GAP-004 through the public compiler. Require actionable errors and successful recovery from the same installed artifact.
6. Resolve GAP-005's evidence dependencies. Qualify modes, stateful chains, editor operation, notices, upgrades, and supported hosts.
7. Define GAP-006's acceptance through existing CI. Preserve failures and platform exclusions in the release record.
8. Correct GAP-007's current summaries after the supported behavior is clear. Preserve historical status evidence.

These actions specify acceptance work. They do not authorize new effect ports or advancement beyond the current parity checkpoint.

## 6. Pass history

| Date | Source | Changes and evidence | Remaining limits |
| --- | --- | --- | --- |
| 2026-09-23 | `bbb2d0179c6e991bdeb2efba7ea733baae027f36` | Created this register and README link. Ran 66 tests, compiler gates, three differential probes, batch prefix, and installed-artifact checks. | Seven gaps remain. No completion approval. Full historical parity, editor interaction, additional platforms, upgrades, and removal remain unqualified. |

The audit preserved implementation, tests, generators, fixtures, tolerances, workflows, and historical documents.
It verified source identity before document publication. The shared result records remote publication verification.
