# Changelog

All notable changes to Noisemaker for Godot. Versions track `godot/addons/noisemaker/plugin.cfg`.

## [Unreleased]

### Added
- An in-engine GDScript compiler (`compiler/lang`, `compiler/graph`): DSL programs compile to the
  render graph with no Node.js, reference engine or network. Invalid programs return structured
  diagnostics instead of a graph.
- The full reference effect catalog, synced to Noisemaker 1.0.262: 210 effect definitions generated
  from the reference, with GPU programs for the 3D (`synth3d`, `filter3d`), points and render effects.
- Executor support for MRT, points, billboards, mesh triangles, repeat loops, ping-pong buffers and
  feedback.
- Oscillator (including `oscKind.noise2d`), MIDI and audio automation, fed through `set_midi_state`,
  `set_audio_state` and `set_audio_samples`.
- Asynchronous frame export, backend shader diagnostics and opt-in texture pooling.
- The addon folder carries its own `LICENSE` and the upstream engine's notice.

### Changed
- The render-graph executor is one file, `runtime/nm_backend.gd`.
- Shaders follow the reference GLSL. `classicNoisedeck/effects` rotated, and `classicNoisedeck/coalesce`
  mixed and wrapped, the way the WGSL backend once did.

## [0.1.0]
- Initial Godot 4.7 `RenderingDevice` render-graph executor and per-effect GLSL ports; 2D effect
  catalog pixel-parity against the JS/WebGL2 reference on Apple Silicon/Metal.
