# nm_backend.gd — RenderingDevice executor for the Noisemaker render graph.
# Mirrors the WebGL2 GPGPU model (reference/04 §5 backend contract): every pass is
# a fullscreen fragment draw into a color attachment; "compute" passes are render
# passes with MRT. Ported structurally from the Unity NMRenderBackend.cs.
#
# Two uniform models, both a single packed `vec4 data[N]` UBO at set 0, binding 0:
#   - Effects WITH a reference uniformLayout (noise/cell/gradient/...): the shader
#     declares `data[N]` and reads `data[i].comp` verbatim from the WGSL. The backend
#     packs engine globals + params by that layout.
#   - Effects WITHOUT one (solid/osc2d/blur/...): the backend SYNTHESIZES a layout
#     (fixed engine header in slots 0-2, params from slot 3) and INJECTS the UBO decl
#     plus `#define <name> data[slot].comp` after #version, so the shader uses bare
#     reference names (ports near-verbatim from the GLSL). Same packer either way.
# Input textures bind at set 0, binding 1.. in pass.inputs order. blit is special:
# sampler `src` at binding 0, no UBO.
#
# Compile-time defines (NOISE_TYPE, LOOP_OFFSET) are injected after #version; shaders
# are cached per (program, define-set).
#
# Coordinates: Godot RenderingDevice is top-left origin / Vulkan Y-down clip, same as
# WGSL — port from WGSL, NO per-effect Y-flip. A single global flip at present (see
# save_surface_png) reconciles to the webgl2/GLSL golden.
extends RefCounted

const SinkManager := preload("res://addons/noisemaker/runtime/sink.gd")
const FrameExportQueue := preload("res://addons/noisemaker/runtime/frame_export.gd")
const RenderingDeviceFrameExport := preload("res://addons/noisemaker/runtime/rendering_device_frame_export.gd")
const ShaderDiagnostics := preload("res://addons/noisemaker/runtime/shader_diagnostics.gd")

const FULLSCREEN_VS := """#version 450
layout(location = 0) in vec2 vpos;
layout(location = 0) out vec2 v_uv;
void main() { v_uv = vpos * 0.5 + 0.5; gl_Position = vec4(vpos, 0.0, 1.0); }
"""

const BLIT_FS := """#version 450
layout(set = 0, binding = 0) uniform sampler2D src;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;
void main() { frag = texture(src, v_uv); }
"""

# Shared resample shader (reference webgpu.js RESAMPLE_WGSL, mode 0 = fsMip):
# a fullscreen triangle reading the source with texelFetch (works for filterable
# and unfilterable float formats alike). Mode 0 downsamples the bound mip level
# by a 2x2 box average into the destination mip level; mode 1 (fsScale) resamples
# the source to the destination size (persistent-texture recreation at a new size).
# Params = (srcWidth, srcHeight, srcMip, mode); Dims = (dstWidth, dstHeight, _, _).
const MIP_FS := """#version 450
layout(set = 0, binding = 0) uniform sampler2D src;
layout(set = 0, binding = 1) uniform Params { ivec4 p; ivec4 d; };
layout(location = 0) out vec4 frag;
void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	if (p.w == 0) {
		ivec2 base = px * 2;
		vec4 a = texelFetch(src, base, p.z);
		vec4 b = texelFetch(src, base + ivec2(1, 0), p.z);
		vec4 c = texelFetch(src, base + ivec2(0, 1), p.z);
		vec4 e = texelFetch(src, base + ivec2(1, 1), p.z);
		frag = (a + b + c + e) * 0.25;
	} else {
		vec2 ratio = vec2(p.x, p.y) / vec2(d.x, d.y);
		vec2 scaled = vec2(px) * ratio;
		ivec2 maxCoord = ivec2(max(vec2(p.x - 1.0, p.y - 1.0), vec2(0.0)));
		frag = texelFetch(src, min(ivec2(scaled), maxCoord), p.z);
	}
}
"""

# Engine-provided globals (reference/04 §10.1), sourced from the runtime.
const ENGINE_GLOBALS := {
	"resolution": true, "time": true, "aspectRatio": true, "tileOffset": true,
	"fullResolution": true, "renderScale": true, "deltaTime": true, "frame": true,
}

# Fixed engine header for synthesized (no-layout) effect layouts.
const ENGINE_SYNTH := {
	"resolution": {"slot": 0, "components": "xy"},
	"time": {"slot": 0, "components": "z"},
	"aspectRatio": {"slot": 0, "components": "w"},
	"tileOffset": {"slot": 1, "components": "xy"},
	"fullResolution": {"slot": 1, "components": "zw"},
	"renderScale": {"slot": 2, "components": "x"},
	"deltaTime": {"slot": 2, "components": "y"},
	"frame": {"slot": 2, "components": "z"},
}

const AUTOMATION_FIELD_RANGES := {
	"unit": {"min": 0.0, "max": 1.0},
	"oscillatorSpeed": {"min": -20.0, "max": 20.0},
	"oscillatorOffset": {"min": -1.0, "max": 1.0},
	"oscillatorSeed": {"min": 1.0, "max": 9999.0},
	"midiSensitivity": {"min": 0.0, "max": 10.0},
}
const MAX_AUTOMATION_DEPTH := 8
const INTEGRATION_RULES := [
	{
		"nodes": [-0.9894009349916499, -0.9445750230732326, -0.8656312023878318, -0.755404408355003,
			-0.6178762444026438, -0.4580167776572274, -0.2816035507792589, -0.0950125098376374,
			0.0950125098376374, 0.2816035507792589, 0.4580167776572274, 0.6178762444026438,
			0.755404408355003, 0.8656312023878318, 0.9445750230732326, 0.9894009349916499],
		"weights": [0.0271524594117541, 0.0622535239386479, 0.0951585116824928, 0.1246289712555339,
			0.1495959888165767, 0.1691565193950025, 0.1826034150449236, 0.1894506104550685,
			0.1894506104550685, 0.1826034150449236, 0.1691565193950025, 0.1495959888165767,
			0.1246289712555339, 0.0951585116824928, 0.0622535239386479, 0.0271524594117541],
	},
	{
		"nodes": [-0.9602898564975363, -0.7966664774136267, -0.525532409916329,
			-0.1834346424956498, 0.1834346424956498, 0.525532409916329,
			0.7966664774136267, 0.9602898564975363],
		"weights": [0.1012285362903763, 0.2223810344533745, 0.3137066458778873,
			0.362683783378362, 0.362683783378362, 0.3137066458778873,
			0.2223810344533745, 0.1012285362903763],
	},
	{
		"nodes": [-0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526],
		"weights": [0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538],
	},
	{"nodes": [-0.5773502691896257, 0.5773502691896257], "weights": [1.0, 1.0]},
]

var rd: RenderingDevice
var addon_dir: String
var screen: Vector2i
var _sampler: RID
var _vfmt: int
var _varr: RID
var _vfmt_empty: int        # no vertex format for procedural point/billboard/mesh draws
var _shaders := {}
var _pipelines := {}
var _textures := {}
var _depth_textures := {}
var _tex_dims := {}         # texId -> Vector2i(w,h); count:"input" deposit draws derive agent count = w*h
var _tex_fmt := {}          # texId -> RenderingDevice DATA_FORMAT_*; lets the snapshot read the render surface in its real format (rgba8 vs rgba16f)
var _effect_defs := {}
var _synth_cache := {}      # "ns/fn" -> synthesized layout
var render_surface_tex := ""
var _time := 0.25
var _render_scale := 1.0
# Timed-sampling mode (stateful-sim parity, reference 30s/5s): real per-frame deltaTime
# and frame index, threaded into _engine_value. Both stay 0 on the default single-frame
# path, so the 90 isolation effects render byte-identically.
var _delta_time := 0.0
var _frame_index := 0
var sink_manager := SinkManager.new()
var _closed := false

# Double-buffered "ping-pong" surfaces (reference/04 §6/§8/§10). A `global_<name>`
# texId that is BOTH read and written by passes gets a physical read/write texture
# pair; inputs resolve to the current read buffer, outputs to the current write
# buffer, swapped within-frame after each write and at end-of-frame (state surfaces
# persist their final binding, display surfaces toggle). Write-only globals (o0, the
# present target) stay as flat single textures — see allocate_textures.
var _surfaces := {}        # bareName -> {"read": texId, "write": texId}
var _frame_read := {}      # bareName -> texId (this frame's read buffer)
var _frame_write := {}     # bareName -> texId (this frame's write target)
var _pingpong := {}        # global texId -> bareName (the double-buffered set)
var _black_tex: RID        # 1x1 zero texture bound for "none" inputs (reference BlackTex)
var _samplers := {}        # shader cache_key -> [{"name":String,"binding":int}]
var _sampler_re: RegEx
var _state_node_re: RegEx  # matches particle state-node surface names (isStateSurface)
var _audio_waveform := PackedFloat32Array()
var _audio_spectrum := PackedFloat32Array()
var _audio_layouts := {}
var _midi_state = null
var _audio_state = null
var _max_texture_size_2d := 0
var _max_color_bytes_per_sample := 0
# Texture allocation policies (reference GAP-004, compiler.js extractTextureSpecs):
# `mipmaps: true` allocates a full mip chain regenerated after each frame's passes;
# `persistent: true` preserves contents when a texture is recreated at a new size.
var _mip_sampler: RID     # linear + linear mipmap filtering for mipmapped inputs
var _tex_mip := {}        # texId -> mip level count (1 = no chain)
var _mip_targets: Array = []  # texture ids whose chains regenerate each frame
var _mip_shader: RID
var _mip_pipelines := {}  # fb format -> render pipeline
var _mip_scratch := {}    # Vector2i -> RID temp textures for mip-level renders

# Texture pooling (reference GAP-006, pipeline.js consumeResourceAllocationPlan).
# Opt-in via set_texture_pooling(true): virtual (non-global) textures the
# analyzer grouped onto one physical id (graph.allocations) share a single
# backend texture. Default off preserves the historical one-texture-per-virtual
# behavior for every existing program.
var texture_pooling := false
var _texture_aliases := {}  # virtualId -> storageId for pooled textures (rebuilt per allocate_textures)
# Structured shader/compiler diagnostics (reference f83a427e, backends/diagnostics.js).
# Last failure normalized to the one diagnostic union; empty until a failure.
var last_shader_diagnostic: Dictionary = {}
var _shader_diag = ShaderDiagnostics.new()
var _passes_executed := 0
var _passes_skipped := 0

func get_pass_stats() -> Dictionary:
	return {"executed": _passes_executed, "skipped": _passes_skipped}

func render_surface_texture() -> RID:
	return _textures.get(render_surface_tex, RID())

func setup(p_rd: RenderingDevice, p_addon_dir: String, p_screen: Vector2i) -> void:
	if _closed:
		push_error("Noisemaker backend is closed")
		return
	rd = p_rd
	addon_dir = p_addon_dir
	screen = p_screen
	_max_texture_size_2d = rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D)
	_max_color_bytes_per_sample = _probe_color_bytes_per_sample()
	# NEAREST + clamp-to-edge — matches the reference WebGL2 backend's effect render
	# targets (webgl2.js:130-131/221-222 set gl.NEAREST). Effects sample at texel centers
	# or integer-texel offsets (where NEAREST == LINEAR), so this is invisible to them;
	# but coord-resampling filters (pixels, warps, polar, lens…) that sample BETWEEN texels
	# need NEAREST to fetch one texel rather than blending two. (3D volumes use LINEAR —
	# add a separate sampler when 3D lands.)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(ss)
	# Mipmap-capable sampler for inputs to textures authored with `mipmaps: true`
	# (reference webgpu.js 'mipmap' sampler: linear min/mag/mipmap, clamp-to-edge).
	var ms := RDSamplerState.new()
	ms.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ms.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ms.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ms.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	# Godot 4.7 renamed RDSamplerState.mipmap_filter to mip_filter; keep both
	# engines working (4.5/4.6 ship mipmap_filter, 4.7+ ships mip_filter).
	ms.set("mip_filter" if "mip_filter" in ms else "mipmap_filter",
			RenderingDevice.SAMPLER_FILTER_LINEAR)
	_mip_sampler = rd.sampler_create(ms)
	# 1x1 zero texture bound for "none" sampler inputs so binding indices stay aligned
	# with the shader's declared samplers (matches the reference backend's BlackTex).
	_black_tex = _make_tex(1, 1, _data_format("rgba16f"))
	# Parses `layout(... binding = N) uniform sampler2D NAME;` so set-0 inputs can be
	# bound BY NAME (both reference backends bind by name) — a pass may list more inputs
	# than the shader uses (e.g. cellularAutomata's render pass), and the SPIR-V compiler
	# strips unused samplers, so only declared+used names may be bound.
	_sampler_re = RegEx.new()
	_sampler_re.compile("binding\\s*=\\s*(\\d+)\\s*\\)\\s*uniform\\s+sampler2D\\s+(\\w+)")
	_state_node_re = RegEx.new()
	_state_node_re.compile("^(xyz|vel|rgba|points_trail)_node_\\d+$")
	var verts := PackedFloat32Array([-1.0, -1.0, 3.0, -1.0, -1.0, 3.0])
	var vb := verts.to_byte_array()
	var vbuf := rd.vertex_buffer_create(vb.size(), vb)
	var attr := RDVertexAttribute.new()
	attr.location = 0
	attr.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	attr.stride = 8
	attr.offset = 0
	_vfmt = rd.vertex_format_create([attr])
	_varr = rd.vertex_array_create(3, _vfmt, [vbuf])
	# No-vertex-input format: agent deposit passes draw N procedural vertices (gl_VertexIndex
	# indexes the agent state textures) with NO vertex buffer. A pipeline built with
	# INVALID_FORMAT_ID does not expect a bound vertex array — see execute_pass custom-draw path.
	# (An empty vertex_format_create([]) still makes the pipeline demand a vertex array.)
	_vfmt_empty = RenderingDevice.INVALID_FORMAT_ID
	_ensure_audio_storage()
	sink_manager.configure({
		"width": screen.x,
		"height": screen.y,
		"format": "rgba8unorm",
		"colorSpace": "srgb",
		"alphaMode": "straight",
		"fps": 60.0,
	})


func set_texture_pooling(enabled: bool) -> void:
	texture_pooling = enabled


func add_sink(sink) -> Callable:
	return sink_manager.add(sink)


func should_defer_render() -> bool:
	return sink_manager.should_defer_render()


func shouldDeferRender() -> bool:
	return should_defer_render()


func create_frame_export_queue(options := {}):
	if _closed or rd == null:
		push_error("Noisemaker backend must be set up before creating a frame export queue")
		return null
	return FrameExportQueue.new(RenderingDeviceFrameExport.new(rd), options)


func close(options := {}) -> void:
	if _closed:
		return
	_closed = true
	# Free the mip-regeneration scratch allocations (bounded per (dims, format)
	# but still device memory): the scratch texture, per-fb-format pipelines,
	# and the shared resample shader. Main textures stay with the RenderingDevice.
	if rd != null:
		for key in _mip_scratch:
			var scratch: RID = _mip_scratch[key]
			if scratch.is_valid():
				rd.free_rid(scratch)
		_mip_scratch.clear()
		for fmt_key in _mip_pipelines:
			var pipe: RID = _mip_pipelines[fmt_key]
			if pipe.is_valid():
				rd.free_rid(pipe)
		_mip_pipelines.clear()
		if _mip_shader.is_valid():
			rd.free_rid(_mip_shader)
		_mip_shader = RID()
	sink_manager.close(options)

# Runtime-fed 128-sample audio buffers used by synth/scope and synth/spectrum. Callers may
# update either side independently by passing an empty array for the side to preserve.
func set_audio_samples(waveform, spectrum) -> void:
	_ensure_audio_storage()
	if waveform.size() > 0:
		_audio_waveform.fill(0.5)
		for i in range(min(128, waveform.size())):
			_audio_waveform[i] = float(waveform[i])
	if spectrum.size() > 0:
		_audio_spectrum.fill(0.0)
		for i in range(min(128, spectrum.size())):
			_audio_spectrum[i] = float(spectrum[i])

func set_midi_state(state) -> void:
	_midi_state = state

func set_audio_state(state) -> void:
	_audio_state = state

func _ensure_audio_storage() -> void:
	if _audio_waveform.size() != 128:
		_audio_waveform.resize(128)
		_audio_waveform.fill(0.5)
	if _audio_spectrum.size() != 128:
		_audio_spectrum.resize(128)
		_audio_spectrum.fill(0.0)

# --- textures -------------------------------------------------------------

func _data_format(fmt: String) -> int:
	match fmt:
		"rgba32f", "rgba32float":
			return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		"rgba8", "rgba8unorm":
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		_:
			return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

func _probe_color_bytes_per_sample() -> int:
	var rgba32f := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	var rgba16f := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var combinations := [
		{"bytes": 64, "formats": [rgba32f, rgba32f, rgba32f, rgba32f]},
		{"bytes": 48, "formats": [rgba32f, rgba32f, rgba32f]},
		{"bytes": 40, "formats": [rgba32f, rgba32f, rgba16f]},
		{"bytes": 32, "formats": [rgba32f, rgba16f, rgba16f]},
	]
	for combination in combinations:
		var textures := []
		var supported := true
		for format in combination["formats"]:
			var usage := RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
			if not rd.texture_is_format_supported_for_usage(format, usage):
				supported = false
				break
			var texture_format := RDTextureFormat.new()
			texture_format.width = 2
			texture_format.height = 2
			texture_format.format = format
			texture_format.usage_bits = usage
			var texture := rd.texture_create(texture_format, RDTextureView.new())
			if not texture.is_valid():
				supported = false
				break
			textures.append(texture)
		var framebuffer := RID()
		if supported:
			framebuffer = rd.framebuffer_create(textures)
		var valid := framebuffer.is_valid() and rd.framebuffer_is_valid(framebuffer)
		if framebuffer.is_valid():
			rd.free_rid(framebuffer)
		for texture in textures:
			if texture.is_valid():
				rd.free_rid(texture)
		if valid:
			return int(combination["bytes"])
	return 16

func _is_volume_size_uniform(name: String) -> bool:
	return name == "volumeSize" or name.begins_with("volumeSize_chain_") \
		or name.begins_with("volumeSize_node_")

func _clamp_volume_size(value, max_texture_size: int):
	if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) \
			or max_texture_size <= 0 or float(value) * float(value) <= max_texture_size:
		return value
	var clamped := 16
	while (clamped * 2) * (clamped * 2) <= max_texture_size and clamped * 2 < float(value):
		clamped *= 2
	return clamped

func _clamp_graph_volume_sizes(graph: Dictionary, max_texture_size: int) -> void:
	if max_texture_size <= 0:
		return
	for pass_data in graph.get("passes", []):
		var uniforms: Dictionary = pass_data.get("uniforms", {})
		for name in uniforms:
			if _is_volume_size_uniform(str(name)):
				uniforms[name] = _clamp_volume_size(uniforms[name], max_texture_size)

func _mrt_format_bytes(format: String) -> int:
	match format:
		"rgba32f", "rgba32float":
			return 16
		"rgba8", "rgba8unorm":
			return 4
		_:
			return 8

func _apply_mrt_format_budget(graph: Dictionary, max_color_bytes_per_sample: int) -> void:
	if max_color_bytes_per_sample <= 0:
		return
	var textures: Dictionary = graph.get("textures", {})
	for pass_data in graph.get("passes", []):
		var outputs: Dictionary = pass_data.get("outputs", {})
		if outputs.size() <= 1:
			continue
		var texture_ids := outputs.values()
		var total := 0
		for texture_id in texture_ids:
			var spec: Dictionary = textures.get(str(texture_id), {})
			total += _mrt_format_bytes(str(spec.get("format", "rgba16f")))
		if total <= max_color_bytes_per_sample:
			continue
		for index in range(texture_ids.size() - 1, -1, -1):
			if total <= max_color_bytes_per_sample:
				break
			var texture_id := str(texture_ids[index])
			if not textures.has(texture_id):
				continue
			var spec: Dictionary = textures[texture_id]
			var format := str(spec.get("format", "rgba16f"))
			if format == "rgba32f" or format == "rgba32float":
				spec["format"] = "rgba16f"
				textures[texture_id] = spec
				total -= 8

func _make_tex(w: int, h: int, fmt: int, mip_levels: int = 1) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = w
	tf.height = h
	tf.format = fmt
	tf.mipmaps = mip_levels
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var rid := rd.texture_create(tf, RDTextureView.new())
	# Zero-init (matches the reference's null-data textures). Deterministic first-frame
	# read for feedback/state surfaces; harmless for transients (fully overwritten).
	rd.texture_clear(rid, Color(0, 0, 0, 0), 0, mip_levels, 0, 1)
	return rid

# Full mip chain length for a 2D texture dimension pair (reference mipLevelCount,
# webgpu.js: Math.max(1, Math.floor(Math.log2(maxDim)) + 1)). Counted by integer
# halving instead of a float log ratio, which can land just under the integer for
# power-of-two sizes and produce a one-level-short chain.
static func _mip_level_count(w: int, h: int) -> int:
	var d := max(1, max(w, h))
	var count := 1
	while d > 1:
		d = d >> 1
		count += 1
	return count

# Size (>= 1) of one mip level for a dimension (reference mipLevelSize).
static func _mip_level_size(dim: int, level: int) -> int:
	return max(1, int(floor(float(dim) / pow(2.0, level))))

func _make_sampled_float_tex(w: int, h: int, values: PackedFloat32Array) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = w
	tf.height = h
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return rd.texture_create(tf, RDTextureView.new(), [values.to_byte_array()])

func _depth_texture(size: Vector2i) -> RID:
	if _depth_textures.has(size):
		return _depth_textures[size]
	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	var texture := rd.texture_create(tf, RDTextureView.new())
	_depth_textures[size] = texture
	return texture

func _ensure_default_mesh_texture(tex_id: String) -> bool:
	var base_id := tex_id.get_slice("_chain_", 0)
	if base_id != "global_mesh0_positions" and base_id != "global_mesh0_normals":
		return false
	if not _textures.has(tex_id):
		var values: PackedFloat32Array
		if base_id.ends_with("_positions"):
			values = PackedFloat32Array([
				-0.6, -0.5, 0.0, 1.0,
				 0.6, -0.5, 0.0, 1.0,
				 0.0,  0.6, 0.0, 1.0,
			])
		else:
			values = PackedFloat32Array([
				0.0, 0.0, 1.0, 0.0,
				0.0, 0.0, 1.0, 0.0,
				0.0, 0.0, 1.0, 0.0,
			])
		_textures[tex_id] = _make_sampled_float_tex(3, 1, values)
	_tex_dims[tex_id] = Vector2i(3, 1)
	_tex_fmt[tex_id] = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	return true

func _resolve_dim(d, screen_size: int, uniforms: Dictionary = {}) -> int:
	# Subset of reference/04 §9 resolveDimension. number | "screen"/"auto"/"input" |
	# "N%" | {screenDivide,default} | {scale,clamp} | {param,paramDefault}. True per-pass
	# "input" sizing is staged; at top level the input is screen-sized so "input" == screen.
	# PARITY: screenDivide uses ROUND; param/scale use FLOOR (§9). Divisor/param values come
	# from the merged pass uniforms (e.g. zoom_chain_0).
	if typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT:
		return max(1, int(d))
	if typeof(d) == TYPE_STRING:
		var s := str(d)
		if s == "screen" or s == "auto" or s == "input":
			return screen_size
		if s.ends_with("%"):
			return max(1, int(floor(screen_size * s.substr(0, s.length() - 1).to_float() / 100.0)))
	if typeof(d) == TYPE_DICTIONARY:
		if d.has("screenDivide"):
			var key := str(d["screenDivide"])
			var div = uniforms[key] if uniforms.has(key) else d.get("default", 1)
			if div == null or float(div) == 0.0:
				div = d.get("default", 1)
			return max(1, int(round(screen_size / float(div))))
		if d.has("scale"):
			var c := int(floor(screen_size * float(d["scale"])))
			if d.has("clamp"):
				var cl: Dictionary = d["clamp"]
				if cl.has("min"):
					c = max(c, int(cl["min"]))
				if cl.has("max"):
					c = min(c, int(cl["max"]))
			return max(1, c)
		if d.has("param"):
			var pk := str(d["param"])
			var has_param := uniforms.has(pk) and uniforms[pk] != null
			var val = uniforms[pk] if has_param else d.get("paramDefault", 64)
			var has_transform: bool = d.has("multiply") or d.has("power")
			if d.has("multiply"):
				val = float(val) * float(d["multiply"])
			if d.has("power"):
				val = pow(float(val), float(d["power"]))
			# A transformed dimension's `default` is already the final resolved size
			# (for example volumeSize² defaults to 4096), not the base to transform.
			if has_transform and not has_param and d.has("default"):
				val = d["default"]
			return max(1, int(floor(float(val))))
	return screen_size

func allocate_textures(graph: Dictionary) -> void:
	_clamp_graph_volume_sizes(graph, _max_texture_size_2d)
	_apply_mrt_format_budget(graph, _max_color_bytes_per_sample)
	_surfaces.clear()
	_frame_read.clear()
	_frame_write.clear()
	_pingpong.clear()
	var merged := _merge_uniforms(graph)
	var pp := _pingpong_surfaces(graph)
	# Rebuild the pooling plan from the analyzer's allocation map. Must run
	# after _apply_mrt_format_budget() so demoted formats are seen here
	# (reference pipeline.js recreateTextures -> buildTexturePoolingPlan).
	var texs: Dictionary = graph.get("textures", {})
	var previous_aliases: Dictionary = _texture_aliases
	_texture_aliases = {}
	if texture_pooling:
		_texture_aliases = build_texture_pooling_plan(
			graph.get("allocations", {}), texs, graph.get("passes", []))
	_release_regrouped_textures(previous_aliases, _texture_aliases)
	# Prior allocation state, snapshotted BEFORE the maps are cleared: the
	# "matching allocation, preserve it" decision (reference createSurfaces /
	# recreateTextures) and persistent-content resampling compare against what
	# this texture previously had, even across render() re-invocations.
	var prev_dims: Dictionary = _tex_dims.duplicate()
	var prev_fmt: Dictionary = _tex_fmt.duplicate()
	var prev_mip: Dictionary = _tex_mip.duplicate()
	_tex_dims.clear()
	_tex_fmt.clear()
	_tex_mip.clear()
	_mip_targets.clear()
	for tex_id in texs:
		var spec: Dictionary = texs[tex_id]
		var w := _resolve_dim(spec.get("width", "screen"), screen.x, merged)
		var h := _resolve_dim(spec.get("height", "screen"), screen.y, merged)
		var fmt := _data_format(str(spec.get("format", "rgba16f")))
		var prior_dims: Vector2i = prev_dims.get(tex_id, Vector2i())
		_tex_dims[tex_id] = Vector2i(w, h)
		_tex_fmt[tex_id] = fmt
		if pp.has(tex_id):
			# Persistent global surfaces preserve contents across recreation
			# (reference Pipeline.createSurfaces -> recreateTexturePreserving on
			# BOTH halves). Prior half RIDs are captured before the allocation
			# replaces them; _alloc_pingpong resamples old -> new when opted in.
			var persistent_pp: bool = spec.get("persistent", false) == true and not spec.get("is3D", false)
			var prior_read: RID = _textures.get(tex_id + "_read", RID())
			var prior_write: RID = _textures.get(tex_id + "_write", RID())
			_alloc_pingpong(tex_id, w, h, fmt, _mip_levels_for(spec, w, h), persistent_pp, prior_read, prior_write, prior_dims)
		else:
			var levels := _mip_levels_for(spec, w, h)
			var persistent: bool = spec.get("persistent", false) == true and not spec.get("is3D", false)
			# Pooled secondary member skips its own allocation: the storage
			# texture is created once under the group's primary id and aliased
			# below (_apply_texture_aliases). Reference recreateTextures
			# `const storageId = this._textureAliases.get(texId); if (storageId && storageId !== texId) continue`.
			var storage_id: String = str(_texture_aliases.get(tex_id, ""))
			if storage_id != "" and storage_id != tex_id:
				_tex_mip[tex_id] = 1
				continue
			var existing: RID = _textures.get(tex_id, RID())
			if levels > 1 and prev_mip.get(tex_id, 1) == levels \
						and prior_dims == Vector2i(w, h) \
						and int(prev_fmt.get(tex_id, fmt)) == fmt and existing.is_valid():
				# Matching allocation: keep the texture (reference createSurfaces
				# "matching allocation, preserve it" / recreateTextures "no change
				# needed"). Only opt-in policies keep state; plain textures are
				# recreated fresh as before (deterministic zero-init).
				pass
			else:
				var new_rid := _make_tex(w, h, fmt, levels)
				if persistent and existing.is_valid() and prior_dims.x > 0:
					# Persistent textures preserve their contents across recreation
					# (reference Pipeline.recreateTexturePreserving): resample the
					# previous contents into the replacement through a NEAREST blit.
					_resample_tex(existing, new_rid, prior_dims, Vector2i(w, h), fmt)
				_textures[tex_id] = new_rid
			_tex_mip[tex_id] = levels
	var rs = graph.get("renderSurface", null)
	if rs != null:
		render_surface_tex = "global_" + str(rs)
	# Point every pooled secondary member's map entry at its group's shared
	# storage texture, so pass execution binds the same texture through either
	# id (reference Pipeline.applyTextureAliases). Runs BEFORE the undeclared-id
	# fallback below, so an aliased member (allocation skipped) is already
	# present and _ensure_tex never creates a spurious standalone texture for it.
	_apply_texture_aliases()
	# Any output/input texId not declared in graph.textures (e.g. global_o0/o1, the user
	# surfaces) gets a screen-sized rgba16f flat texture — the reference's o0..o7 are HDR
	# (an rgba8 default clamps intermediates to [0,1] and regressed distortion/focusBlur/
	# rotate/step/thresholdMix, whose o0 carries out-of-[0,1] values the reference preserves).
	# Ping-pong surfaces are already allocated above; _ensure_tex skips them.
	for p in graph.get("passes", []):
		for k in p.get("outputs", {}):
			_ensure_tex(str(p["outputs"][k]))
		for k in p.get("inputs", {}):
			var t := str(p["inputs"][k])
			if t != "none":
				_ensure_tex(t)
	_refresh_mip_targets(graph)

# ---- Texture pooling (reference GAP-006, pipeline.js) ----

# Build the pooling plan consumed from the analyzer's physical allocation map
# (graph.allocations). Returns a Dictionary of virtualId -> storageId for every
# poolable texture; members of a physical group share one backend texture
# created under the group's primary (first) member id.
#
# A group is poolable only when every member carries an identical plain 2D
# spec: persistent textures must keep their cross-frame contents, and
# mipmapped/3D textures carry policy state a shared record must not absorb.
# Groups with mismatched dimensions or formats fall back to standalone
# textures.
#
# First-read safety: a member whose first touch in the pass list is an input
# read (or that is sampled by its own producing pass) expects the
# zero-initialized/previous-frame contents a standalone texture would hold, so
# it is never pooled into a slot a group-mate writes earlier in the same
# frame. The same protection excludes textures written by partial/non-clearing
# passes — any explicit `drawMode` (points, billboards, triangles) scatters
# geometry without covering the surface, and `blend` makes the result depend
# on the destination's previous contents. A `viewport` pass that does not
# declare `clear: true` renders into a sub-region: unwritten regions expose
# whatever was there before (a group-mate's content under pooled storage).
# Full clears (`clear: true`, no viewport) overwrite the whole texture and
# stay poolable. (Reference 95743621.)
static func build_texture_pooling_plan(allocations: Dictionary, textures: Dictionary,
		passes: Array) -> Dictionary:
	var aliases := {}
	if allocations.is_empty() or textures.is_empty():
		return aliases

	# First-touch classification from the pass list
	var first_touch_is_write := {}
	var self_sampled := {}
	var partially_written := {}
	for pass_data in passes:
		var inputs := {}
		for k in pass_data.get("inputs", {}):
			inputs[str(pass_data["inputs"][k])] = true
		var outputs: Array = []
		for k in pass_data.get("outputs", {}):
			outputs.append(str(pass_data["outputs"][k]))
		var dm = pass_data.get("drawMode")
		var bl = pass_data.get("blend")
		if _js_truthy(dm) or _js_truthy(bl):
			for tex_id in outputs:
				partially_written[tex_id] = true
		elif pass_data.has("viewport") and not pass_data.get("clear", false):
			for tex_id in outputs:
				partially_written[tex_id] = true
		for tex_id in outputs:
			if not first_touch_is_write.has(tex_id):
				first_touch_is_write[tex_id] = true
			if inputs.has(tex_id):
				self_sampled[tex_id] = true
		for tex_id in inputs:
			if not first_touch_is_write.has(tex_id):
				first_touch_is_write[tex_id] = false

	var groups := {}  # physicalId -> [virtualIds]
	for tex_id in allocations:
		var physical_id = allocations[tex_id]
		if str(physical_id).is_empty() or not textures.has(tex_id):
			continue
		# Global surfaces are double-buffered and never pooled
		if str(tex_id).begins_with("global"):
			continue
		if first_touch_is_write.get(tex_id) == false:
			continue
		if self_sampled.has(tex_id) or partially_written.has(tex_id):
			continue
		if not groups.has(physical_id):
			groups[physical_id] = []
		groups[physical_id].append(tex_id)

	for physical_id in groups:
		var members: Array = groups[physical_id]
		if members.size() < 2:
			continue
		var specs: Array = []
		var poolable := true
		for id in members:
			var spec: Dictionary = textures[id]
			if spec.is_empty() or spec.get("persistent", false) == true \
					or spec.get("mipmaps", false) == true \
					or spec.get("is3D", false) == true:
				poolable = false
				break
			specs.append(spec)
		if not poolable:
			continue
		var signature := _pooling_signature(specs[0])
		var same := true
		for spec in specs:
			if _pooling_signature(spec) != signature:
				same = false
				break
		if not same:
			continue
		var storage_id: String = members[0]
		for member in members:
			aliases[member] = storage_id
	return aliases


# Plain 2D spec signature: raw (width, height, format) values, exactly the
# reference's JSON.stringify([width, height, format]) — raw spec values, not
# resolved dimensions.
static func _pooling_signature(spec: Dictionary) -> String:
	return JSON.stringify([spec.get("width"), spec.get("height"), spec.get("format")])


# JavaScript truthiness for pass fields (`pass.drawMode || pass.blend` in the
# reference): null/false/""/0 are falsy, everything else truthy.
static func _js_truthy(value) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return value != null and value != false
		TYPE_STRING:
			return value != ""
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		_:
			return true


# Destroy backend textures of pooling groups whose membership changed since
# the previous plan, so the recreation loop rebuilds them with the correct
# (standalone or re-grouped) sharing (reference releaseRegroupedTextures).
# Static over an injected textures map + free callable so the RID-sharing
# dedupe logic is testable headless.
static func release_regrouped_textures(textures: Dictionary, previous_aliases: Dictionary,
		next_aliases: Dictionary, free_rid: Callable) -> void:
	if previous_aliases.is_empty():
		return
	var groups := {}  # storage -> [members]
	for member in previous_aliases:
		var storage = previous_aliases[member]
		if not groups.has(storage):
			groups[storage] = []
		groups[storage].append(member)
	# RIDs still owned by an unchanged group must not be freed (RIDs are
	# shared only within one group, so this protects exactly those).
	var protected := {}
	for storage in groups:
		if _group_unchanged(groups[storage], storage, next_aliases):
			for m in groups[storage]:
				var keep: RID = textures.get(m, RID())
				if keep.is_valid():
					protected[keep] = true
	for storage in groups:
		if _group_unchanged(groups[storage], storage, next_aliases):
			continue
		# Members of one group share a single RID — free each unique RID once.
		var freed := {}
		for m in groups[storage]:
			var rid: RID = textures.get(m, RID())
			textures.erase(m)
			if rid.is_valid() and not protected.has(rid) and not freed.has(rid):
				freed[rid] = true
				free_rid.call(rid)


func _release_regrouped_textures(previous_aliases: Dictionary, next_aliases: Dictionary) -> void:
	release_regrouped_textures(_textures, previous_aliases, next_aliases,
		func(rid: RID) -> void: rd.free_rid(rid))


static func _group_unchanged(members: Array, storage, next_aliases: Dictionary) -> bool:
	for m in members:
		if str(next_aliases.get(m, "")) != str(storage):
			return false
	return true


# Point every pooled secondary member's map entry at its group's shared
# storage record, so pass execution binds the same texture through either id
# (reference applyTextureAliases). Static over an injected textures map +
# free callable so the RID-sharing dedupe logic is testable headless.
static func apply_texture_aliases(textures: Dictionary, texture_aliases: Dictionary,
		free_rid: Callable) -> void:
	if texture_aliases.is_empty():
		return
	var freed := {}  # members of one group share records — free each old RID once
	for member in texture_aliases:
		var storage = texture_aliases[member]
		if member == storage:
			continue
		var record: RID = textures.get(storage, RID())
		if not record.is_valid():
			continue
		var existing: RID = textures.get(member, RID())
		textures[member] = record
		if existing.is_valid() and existing != record and not freed.has(existing):
			freed[existing] = true
			free_rid.call(existing)


func _apply_texture_aliases() -> void:
	apply_texture_aliases(_textures, _texture_aliases,
		func(rid: RID) -> void: rd.free_rid(rid))


# Query the actual runtime texture allocation/reuse plan (reference
# getResourcePlan): the analyzer's physical allocation map and the sharing the
# renderer actually materialized — non-global graph textures grouped by
# identical backend texture record.
func get_resource_plan(graph: Dictionary) -> Dictionary:
	var textures: Dictionary = graph.get("textures", {})
	var records := {}  # RID -> {"id": String, "members": Array}
	var order: Array = []
	for tex_id in textures:
		if str(tex_id).begins_with("global"):
			continue
		var record: RID = _textures.get(tex_id, RID())
		if not record.is_valid():
			continue
		if not records.has(record):
			records[record] = {"id": str(tex_id), "members": []}
			order.append(record)
		records[record]["members"].append(str(tex_id))
	var texture_records: Array = []
	var shared: Array = []
	for record in order:
		var entry: Dictionary = records[record]
		var dims: Vector2i = _tex_dims.get(entry["id"], Vector2i())
		texture_records.append({
			"id": entry["id"],
			"width": dims.x,
			"height": dims.y,
			"virtualTextures": entry["members"],
		})
		if entry["members"].size() > 1:
			shared.append(entry["members"])
	return {
		"pooling": texture_pooling,
		"allocations": graph.get("allocations", {}).duplicate(true),
		"sharedTextures": shared,
		"textures": texture_records,
	}

# A global_<name> surface needs double-buffering ONLY when a pass reads it AT OR BEFORE
# its first write (same-pass read+write, or a prior-frame/feedback read) — i.e. there is a
# read/write hazard. A surface written THEN read in a later pass (a forward dependency, e.g.
# channelCombine reading global_o0 after its blit) is safe with a single flat texture and is
# NOT double-buffered; nor are write-only globals (o0 / the present target). Mirrors the
# _has_feedback condition, per-surface.
func _pingpong_surfaces(graph: Dictionary) -> Dictionary:
	var passes = graph.get("passes", [])
	var first_write := {}
	for i in passes.size():
		for k in passes[i].get("outputs", {}):
			var t := str(passes[i]["outputs"][k])
			if t.begins_with("global_") and not first_write.has(t):
				first_write[t] = i
	var out := {}
	for i in passes.size():
		# (a) Same-pass IN-PLACE read+write (nsPressure Jacobi, nsAdvect): a pass that
		# samples a global surface it ALSO writes is a read-after-write hazard needing a
		# read/write pair, regardless of where the surface's first write lands. Missing this
		# raced the nav pressure/velocity solves into run-to-run nondeterminism (the
		# first-write test below only catches reads AT OR BEFORE the first write).
		var in_set := {}
		for k in passes[i].get("inputs", {}):
			var t := str(passes[i]["inputs"][k])
			if t.begins_with("global_"):
				in_set[t] = true
		for k in passes[i].get("outputs", {}):
			var t := str(passes[i]["outputs"][k])
			if in_set.has(t):
				out[t] = true
		# (b) Read at-or-before the surface's first write (feedback / same-pass seed hazard).
		for k in passes[i].get("inputs", {}):
			var t := str(passes[i]["inputs"][k])
			if t != "none" and t.begins_with("global_") and first_write.has(t) and i <= first_write[t]:
				out[t] = true
	return out

func _alloc_pingpong(tex_id: String, w: int, h: int, fmt: int, mip_levels: int = 1,
		persistent: bool = false, prior_read: RID = RID(), prior_write: RID = RID(),
		prior_dims: Vector2i = Vector2i()) -> void:
	var read_key := tex_id + "_read"
	var write_key := tex_id + "_write"
	_textures[read_key] = _make_tex(w, h, fmt, mip_levels)
	_textures[write_key] = _make_tex(w, h, fmt, mip_levels)
	if persistent and prior_dims.x > 0 and prior_read.is_valid() and prior_write.is_valid():
		# Persistent surfaces preserve contents across recreation at a new size
		# (reference Pipeline.recreateTexturePreserving on both halves): NEAREST
		# resample of each old half into its replacement.
		_resample_tex(prior_read, _textures[read_key], prior_dims, Vector2i(w, h), fmt)
		_resample_tex(prior_write, _textures[write_key], prior_dims, Vector2i(w, h), fmt)
	_tex_mip[read_key] = mip_levels
	_tex_mip[write_key] = mip_levels
	var bare := tex_id.substr("global_".length())
	_surfaces[bare] = {"read": read_key, "write": write_key}
	_pingpong[tex_id] = bare

# The parent graph texId behind a double-buffered half key ("global_x_read" /
# "global_x_write" -> "global_x"). Mip regeneration and dims/format lookups use
# the parent, whose allocation is recorded in _tex_dims/_tex_fmt.
static func _mip_owner_tex(tex_id: String) -> String:
	for suffix in ["_read", "_write"]:
		if tex_id.ends_with(suffix):
			return tex_id.substr(0, tex_id.length() - suffix.length())
	return tex_id

# Base mip level (level 0) dims + data format for a mip target, resolving
# double-buffered half keys through their parent surface. [Vector2i, int]
func _mip_dims_fmt(tex_id: String) -> Array:
	var owner := _mip_owner_tex(tex_id)
	return [
		_tex_dims.get(owner, _tex_dims.get(tex_id, screen)),
		_tex_fmt.get(owner, _tex_fmt.get(tex_id,
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)),
	]

# Mip chain level count a texture spec requests at these resolved dimensions.
# Only 2D textures may opt in (reference validateTextureMap: `mipmaps` is 2D-only).
func _mip_levels_for(spec: Dictionary, w: int, h: int) -> int:
	if spec.get("is3D", false):
		return 1
	return _mip_level_count(w, h) if spec.get("mipmaps", false) == true else 1

# Recompute the list of texture ids whose mip chains regenerate after each frame
# (reference Pipeline.refreshMipTargets): global surfaces map their single graph
# spec to both halves of the double-buffered surface.
func _refresh_mip_targets(graph: Dictionary) -> void:
	_mip_targets.clear()
	var texs: Dictionary = graph.get("textures", {})
	for tex_id in texs:
		var spec: Dictionary = texs[tex_id]
		if spec.get("mipmaps", false) != true or spec.get("is3D", false):
			continue
		if _pingpong.has(tex_id):
			var bare: String = _pingpong[tex_id]
			var s: Dictionary = _surfaces.get(bare, {})
			if s.has("read") and s.has("write"):
				_mip_targets.append(s["read"])
				_mip_targets.append(s["write"])
		else:
			_mip_targets.append(tex_id)

# Render a fullscreen NEAREST resample of `src` (mip level `src_mip`) into `dst`.
# mode 0 = 2x2 box downsample (mip chain regeneration), mode 1 = scaled resample
# (persistent-texture recreation). Mirrors reference webgpu.js fsMip/fsScale.
func _draw_resample(src: RID, dst: RID, src_dims: Vector2i, dst_dims: Vector2i,
		src_mip: int, mode: int) -> void:
	var shader: RID = _mip_shader
	if not shader.is_valid():
		shader = _get_shader("__mip", FULLSCREEN_VS, MIP_FS)
		if not shader.is_valid():
			return
		_mip_shader = shader
	var fb := rd.framebuffer_create([dst])
	var fmt := rd.framebuffer_get_format(fb)
	var pipeline: RID = _mip_pipelines.get(fmt, RID())
	if not pipeline.is_valid():
		var blend := RDPipelineColorBlendState.new()
		blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())
		pipeline = rd.render_pipeline_create(shader, fmt, _vfmt,
			RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, RDPipelineRasterizationState.new(),
			RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
		_mip_pipelines[fmt] = pipeline
	var pbytes := PackedByteArray()
	pbytes.resize(32)
	pbytes.encode_s32(0, src_dims.x)
	pbytes.encode_s32(4, src_dims.y)
	pbytes.encode_s32(8, src_mip)
	pbytes.encode_s32(12, mode)
	pbytes.encode_s32(16, dst_dims.x)
	pbytes.encode_s32(20, dst_dims.y)
	var ubo := rd.uniform_buffer_create(pbytes.size(), pbytes)
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u0.binding = 0
	u0.add_id(_sampler)
	u0.add_id(src)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u1.binding = 1
	u1.add_id(ubo)
	var set0 := rd.uniform_set_create([u0, u1], shader, 0)
	var dl := rd.draw_list_begin(fb, RenderingDevice.DRAW_CLEAR_COLOR_ALL, PackedColorArray([Color(0, 0, 0, 0)]))
	rd.draw_list_bind_render_pipeline(dl, pipeline)
	rd.draw_list_bind_uniform_set(dl, set0, 0)
	rd.draw_list_bind_vertex_array(dl, _varr)
	rd.draw_list_draw(dl, false, 1)
	rd.draw_list_end()

# Scratch texture for one mip-level render, cached per (size, format).
func _scratch_tex(size: Vector2i, fmt: int) -> RID:
	var key := Vector3i(size.x, size.y, fmt)
	var rid: RID = _mip_scratch.get(key, RID())
	if not rid.is_valid():
		rid = _make_tex(size.x, size.y, fmt, 1)
		_mip_scratch[key] = rid
	return rid

# Copy/resample a source texture into `dst` (level 0) — same dimensions use a
# direct copy, differing dimensions go through the NEAREST scale blit.
func _resample_tex(src: RID, dst: RID, src_dims: Vector2i, dst_dims: Vector2i, fmt: int) -> void:
	if src_dims == dst_dims:
		rd.texture_copy(src, dst, Vector3(0, 0, 0), Vector3(0, 0, 0),
			Vector3(dst_dims.x, dst_dims.y, 1), 0, 0, 0, 0)
	else:
		var tmp := _scratch_tex(dst_dims, fmt)
		_draw_resample(src, tmp, src_dims, dst_dims, 0, 1)
		rd.texture_copy(tmp, dst, Vector3(0, 0, 0), Vector3(0, 0, 0),
			Vector3(dst_dims.x, dst_dims.y, 1), 0, 0, 0, 0)

# Regenerate the mip chains of every mipmapped texture from the level-0 contents
# written by this frame's passes (reference backend.generateMipmaps, called before
# endFrame). Each level renders a 2x2 box downsample of the previous level into a
# scratch texture, then copies it into that mip level (RenderingDevice framebuffers
# attach mip 0 only, so the level write goes through texture_copy).
func _generate_mipmaps() -> void:
	if _mip_targets.is_empty():
		return
	for tex_id in _mip_targets:
		var levels: int = _tex_mip.get(tex_id, 1)
		var rid: RID = _textures.get(tex_id, RID())
		if levels <= 1 or not rid.is_valid():
			continue
		# Double-buffered half keys ("global_x_read"/"_write") have no direct
		# _tex_dims/_tex_fmt entry — resolve through the parent surface so the
		# chain is computed from the graph spec's real dims/format.
		var dims_fmt := _mip_dims_fmt(tex_id)
		var dims: Vector2i = dims_fmt[0]
		var fmt: int = dims_fmt[1]
		for level in range(1, levels):
			var dw := _mip_level_size(dims.x, level)
			var dh := _mip_level_size(dims.y, level)
			var sw := _mip_level_size(dims.x, level - 1)
			var sh := _mip_level_size(dims.y, level - 1)
			var tmp := _scratch_tex(Vector2i(dw, dh), fmt)
			if sw == dw * 2 and sh == dh * 2:
				_draw_resample(rid, tmp, Vector2i(sw, sh), Vector2i(dw, dh), level - 1, 0)
			else:
				_draw_resample(rid, tmp, Vector2i(sw, sh), Vector2i(dw, dh), level - 1, 1)
			rd.texture_copy(tmp, rid, Vector3(0, 0, 0), Vector3(0, 0, 0),
				Vector3(dw, dh, 1), 0, level, 0, 0)

# Merge every pass.uniforms (last write wins) — the divisor/param source for sub-resolution
# texture sizing (reference collectDefaultUniforms, §9).
func _merge_uniforms(graph: Dictionary) -> Dictionary:
	var out := {}
	for p in graph.get("passes", []):
		var u: Dictionary = p.get("uniforms", {})
		var specs: Dictionary = p.get("uniformSpecs", {})
		for k in u:
			out[k] = resolve_uniform_value(u[k], _time, specs.get(k))
	return out

func _ensure_tex(tex_id: String) -> void:
	if _pingpong.has(tex_id):
		return
	if _ensure_default_mesh_texture(tex_id):
		return
	if not _textures.has(tex_id):
		var f16 := _data_format("rgba16f")
		_textures[tex_id] = _make_tex(screen.x, screen.y, f16)
		_tex_dims[tex_id] = screen
		_tex_fmt[tex_id] = f16

# --- shader assembly ------------------------------------------------------

func _resolve_includes(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#include"):
			var inc := t.get_slice('"', 1)
			var ip := addon_dir + "/shaders/" + inc
			var f := FileAccess.open(ip, FileAccess.READ)
			if f:
				out += f.get_as_text() + "\n"
				f.close()
			else:
				push_error("missing include: " + ip)
		else:
			out += line + "\n"
	return out

# Insert text right after the #version line (defines/UBO decl must precede use).
func _inject_after_version(src: String, inject: String) -> String:
	if inject == "":
		return src
	var out := ""
	var injected := false
	for line in src.split("\n"):
		out += line + "\n"
		if not injected and line.strip_edges().begins_with("#version"):
			out += inject
			injected = true
	return out

func _defines_key(defines: Dictionary) -> String:
	if defines.is_empty():
		return ""
	var keys := defines.keys()
	keys.sort()
	var s := ""
	for k in keys:
		s += "__%s_%s" % [k, str(defines[k])]
	return s

# Remove comments for boolean-context scanning only; assembled shader text is untouched.
# A state machine avoids false positives from `if (KEY)` examples in line/block comments.
func _strip_glsl_comments_for_scan(source: String) -> String:
	var out := ""
	var i := 0
	while i < source.length():
		if source[i] == "/" and i + 1 < source.length() and source[i + 1] == "/":
			i += 2
			while i < source.length() and source[i] != "\n":
				i += 1
			out += " "
		elif source[i] == "/" and i + 1 < source.length() and source[i + 1] == "*":
			i += 2
			while i + 1 < source.length() and not (source[i] == "*" and source[i + 1] == "/"):
				if source[i] == "\n":
					out += "\n"
				i += 1
			i = min(i + 2, source.length())
			out += " "
		else:
			out += source[i]
			i += 1
	return out

func _define_needs_bool(key: String, shader_source: String) -> bool:
	var scan := _strip_glsl_comments_for_scan(shader_source)
	var escaped := key  # Graph define keys are validated GLSL identifiers.
	var patterns := [
		"#define\\s+%s\\s+(?:true|false)\\b" % escaped,
		"\\bif\\s*\\(\\s*!?\\s*%s\\s*\\)" % escaped,
		"\\b!?\\s*%s\\s*\\?" % escaped,
		"\\b!?\\s*%s\\s*(?:&&|\\|\\|)" % escaped,
	]
	for pattern in patterns:
		var regex := RegEx.new()
		if regex.compile(pattern) == OK and regex.search(scan) != null:
			return true
	return false

# Graph JSON serializes compile-time booleans as numeric 0/1. GLSL 450 requires a
# real bool literal in a bare condition (`if (RIDGES)`, `if (INVERT)`), but some
# boolean metadata is consumed numerically (`if (RIDGES != 0)` in curl). Require
# both the declared boolean type and a comment-stripped boolean source context.
func _format_define_value(key: String, value, def: Dictionary, shader_source: String) -> String:
	for global_spec in def.get("globals", {}).values():
		if str(global_spec.get("define", "")) == key \
				and str(global_spec.get("type", "")) == "boolean" \
				and _define_needs_bool(key, shader_source):
			var truthy := bool(value) if typeof(value) == TYPE_BOOL else float(value) != 0.0
			return "true" if truthy else "false"
	return str(int(value))

func _load_fragment(ns: String, fn: String, prog: String) -> String:
	# Shaders live func-qualified at effects/<ns>/<func>/<prog>.glsl, mirroring the
	# reference <ns>/<func>/glsl/<prog> layout. This disambiguates funcs that share a
	# namespace + progName but have different shaders (pointsRender vs pointsBillboardRender:
	# both render/deposit, render/diffuse, render/blend — distinct programs).
	var path := addon_dir + "/shaders/effects/%s/%s/%s.glsl" % [ns, fn, prog]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing shader: " + path)
		last_shader_diagnostic = _shader_diag.make({
			"code": "ERR_SHADER_MISSING",
			"backend": "renderingdevice",
			"stage": "missing-source",
			"program": prog,
			"detail": "missing shader: " + path,
		})
		return ""
	var s := f.get_as_text()
	f.close()
	return _resolve_includes(s)

func _get_shader(cache_key: String, vert_src: String, frag_src: String) -> RID:
	if _shaders.has(cache_key):
		return _shaders[cache_key]
	var src := RDShaderSource.new()
	src.source_vertex = vert_src
	src.source_fragment = frag_src
	var spirv := rd.shader_compile_spirv_from_source(src)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var e := spirv.get_stage_compile_error(stage)
		if e != "":
			push_error("[shader %s] %s" % [cache_key, e])
			last_shader_diagnostic = _shader_diag.make({
				"code": "ERR_SHADER_COMPILE",
				"backend": "renderingdevice",
				"stage": "compile",
				"program": cache_key,
				"detail": e,
				"messages": _shader_diag.parse_glsl_info_log(e),
				"source": vert_src if stage == RenderingDevice.SHADER_STAGE_VERTEX else frag_src,
			})
			return RID()
	var sh := rd.shader_create_from_spirv(spirv)
	if not sh.is_valid():
		# SPIR-V accepted the source but the driver-side link/linkage failed.
		var link_detail := "shader link failed: %s" % cache_key
		push_error("[shader %s] %s" % [cache_key, link_detail])
		last_shader_diagnostic = _shader_diag.make({
			"code": "ERR_SHADER_LINK",
			"backend": "renderingdevice",
			"stage": "link",
			"program": cache_key,
			"detail": link_detail,
		})
		return RID()
	_shaders[cache_key] = sh
	return sh

# Reference blend-factor name -> Godot RenderingDevice.BLEND_FACTOR_*. The reference
# per-pass `blend: ['src','dst']` array (e.g. pointsBillboardRender's alpha deposit
# 'ONE'/'ONE_MINUS_SRC_ALPHA') names a WebGL blendFunc pair; map both color and alpha.
func _blend_factor(name: String) -> int:
	match name.to_upper():
		"ONE":
			return RenderingDevice.BLEND_FACTOR_ONE
		"ZERO":
			return RenderingDevice.BLEND_FACTOR_ZERO
		"SRC_ALPHA":
			return RenderingDevice.BLEND_FACTOR_SRC_ALPHA
		"ONE_MINUS_SRC_ALPHA":
			return RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		"DST_ALPHA":
			return RenderingDevice.BLEND_FACTOR_DST_ALPHA
		"ONE_MINUS_DST_ALPHA":
			return RenderingDevice.BLEND_FACTOR_ONE_MINUS_DST_ALPHA
		"SRC_COLOR":
			return RenderingDevice.BLEND_FACTOR_SRC_COLOR
		"ONE_MINUS_SRC_COLOR":
			return RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_COLOR
		"DST_COLOR":
			return RenderingDevice.BLEND_FACTOR_DST_COLOR
		"ONE_MINUS_DST_COLOR":
			return RenderingDevice.BLEND_FACTOR_ONE_MINUS_DST_COLOR
	push_error("unknown blend factor: " + name)
	return RenderingDevice.BLEND_FACTOR_ONE

# Resolve a pass's `blend` field to a blend descriptor + a stable pipeline-cache token.
#   blend: true            -> additive ONE/ONE on both color+alpha (agent deposit default)
#   blend: ['src','dst']   -> the named factor pair (premultiplied OVER etc.)
#   absent / false         -> no blend (replace)
func _resolve_blend(p: Dictionary) -> Dictionary:
	var b = p.get("blend", false)
	if typeof(b) == TYPE_ARRAY and b.size() == 2:
		var src := _blend_factor(str(b[0]))
		var dst := _blend_factor(str(b[1]))
		return {"enable": true, "src": src, "dst": dst, "key": "%d_%d" % [src, dst]}
	if typeof(b) == TYPE_BOOL and b:
		var one := RenderingDevice.BLEND_FACTOR_ONE
		return {"enable": true, "src": one, "dst": one, "key": "add"}
	return {"enable": false, "src": 0, "dst": 0, "key": "rep"}

func _get_pipeline(cache_key: String, shader: RID, fb_format: int, n_attach: int,
		primitive: int, blend_spec: Dictionary, vfmt: int, is_mesh: bool) -> RID:
	var key := "%s:%d:%d:%d:%s:%s" % [
		cache_key, fb_format, n_attach, primitive, str(blend_spec.get("key", "rep")), str(is_mesh),
	]
	if _pipelines.has(key):
		return _pipelines[key]
	var blend := RDPipelineColorBlendState.new()
	for _i in n_attach:
		var a := RDPipelineColorBlendStateAttachment.new()
		if blend_spec.get("enable", false):
			# Named factors applied to both color and alpha. The default deposit case is
			# ONE/ONE (the reference notes Babylon's ALPHA_ADD (SRC_ALPHA,ONE) crushes
			# accumulation — additive must be straight ONE,ONE on both color and alpha).
			a.enable_blend = true
			a.src_color_blend_factor = blend_spec["src"]
			a.dst_color_blend_factor = blend_spec["dst"]
			a.color_blend_op = RenderingDevice.BLEND_OP_ADD
			a.src_alpha_blend_factor = blend_spec["src"]
			a.dst_alpha_blend_factor = blend_spec["dst"]
			a.alpha_blend_op = RenderingDevice.BLEND_OP_ADD
		blend.attachments.push_back(a)
	var raster := RDPipelineRasterizationState.new()
	var depth := RDPipelineDepthStencilState.new()
	if is_mesh:
		raster.cull_mode = RenderingDevice.POLYGON_CULL_BACK
		# Source mesh vertices are CCW in OpenGL's Y-up clip space. RenderingDevice's
		# Y-down viewport reverses their raster-space winding, so CLOCKWISE preserves
		# the reference's CCW-facing triangles and culls the same back faces.
		raster.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
		depth.enable_depth_test = true
		depth.enable_depth_write = true
		depth.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS
	var p := rd.render_pipeline_create(shader, fb_format, vfmt, primitive, raster,
		RDPipelineMultisampleState.new(), depth, blend)
	if not p.is_valid():
		# execute_pass (the only caller) records the enriched
		# ERR_PIPELINE_CREATE diagnostic and bails before drawing; do not
		# cache the invalid RID either (caching it would make every retry
		# with the same key bind a dead pipeline).
		return p
	_pipelines[key] = p
	return p

# Vertex shader for a custom-draw program (agent deposit or mesh triangles):
# effects/<ns>/<func>/<prog>.vert.glsl.
func _load_vertex(ns: String, fn: String, prog: String) -> String:
	var path := addon_dir + "/shaders/effects/%s/%s/%s.vert.glsl" % [ns, fn, prog]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing vertex shader: " + path)
		last_shader_diagnostic = _shader_diag.make({
			"code": "ERR_SHADER_MISSING",
			"backend": "renderingdevice",
			"stage": "missing-source",
			"program": prog,
			"detail": "missing vertex shader: " + path,
		})
		return ""
	var s := f.get_as_text()
	f.close()
	return _resolve_includes(s)

# Draw-vertex count for a custom pass. count:number is literal; count:"input"/"auto"/"screen"
# derives the count from the mesh-position or agent-state input texture. Billboards expand ×6
# (two tris/quad) at the call site.
func _resolve_count(p: Dictionary) -> int:
	var c = p.get("count", 1)
	if typeof(c) == TYPE_STRING:
		var inputs: Dictionary = p.get("inputs", {})
		var src_id := str(inputs.get("meshPositions", inputs.get("xyzTex", "")))
		if src_id == "" or src_id == "none":
			for k in inputs:
				var t := str(inputs[k])
				if t != "none" and t != "":
					src_id = t
					break
		var d: Vector2i = _tex_dims.get(src_id, Vector2i(0, 0))
		return d.x * d.y
	return max(0, int(c))

# --- effect definitions + uniform packing ---------------------------------

func _load_effect_def(ns: String, fn: String) -> Dictionary:
	var key := ns + "/" + fn
	if _effect_defs.has(key):
		return _effect_defs[key]
	var base_dir := addon_dir if not addon_dir.is_empty() else "res://addons/noisemaker"
	var path := base_dir + "/effects/%s/%s.json" % [ns, fn]
	var def := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			def = parsed
	_effect_defs[key] = def
	return def

func _type_width(t: String) -> int:
	match t:
		"vec2":
			return 2
		"vec3", "color":
			return 3
		"vec4":
			return 4
		_:
			return 1

# Synthesize a packed layout for a no-layout effect: fixed engine header (slots 0-2)
# then each `uniform` global from slot 3 in declaration order (multi-component values
# never straddle a vec4).
func _synth_layout(ns: String, fn: String, globals: Dictionary) -> Dictionary:
	var key := ns + "/" + fn
	if _synth_cache.has(key):
		return _synth_cache[key]
	var layout := {}
	for k in ENGINE_SYNTH:
		layout[k] = ENGINE_SYNTH[k]
	var letters := ["x", "y", "z", "w"]
	var slot := 3
	var cursor := 0
	for gk in globals:
		var g = globals[gk]
		if not g.has("uniform"):
			continue
		if str(g.get("type", "")) == "mat3":
			if cursor > 0:
				slot += 1
				cursor = 0
			layout[str(g["uniform"])] = {"slot": slot, "components": "xyz", "columns": 3}
			slot += 3
			continue
		var w := _type_width(str(g.get("type", "float")))
		if cursor + w > 4:
			slot += 1
			cursor = 0
		var comps := ""
		for i in range(w):
			comps += letters[cursor + i]
		layout[str(g["uniform"])] = {"slot": slot, "components": comps}
		cursor += w
		if cursor >= 4:
			slot += 1
			cursor = 0
	# lensWarp's reference shader consumes the preceding pipeline's `speed` uniform,
	# even though its own definition does not redeclare it. Keep that inherited value
	# in the synthesized layout without introducing definition drift.
	if ns == "filter" and fn == "lensWarp":
		layout["speed"] = {"slot": slot, "components": letters[cursor]}
	_synth_cache[key] = layout
	return layout

# UBO decl + #define block injected for synthesized (no-layout) effects.
func _synth_header(layout: Dictionary) -> String:
	var max_slot := 0
	for k in layout:
		max_slot = max(max_slot, int(layout[k]["slot"]) + int(layout[k].get("columns", 1)) - 1)
	var s := "layout(set=0,binding=0,std140) uniform Params { vec4 data[%d]; };\n" % (max_slot + 1)
	for k in layout:
		if int(layout[k].get("columns", 1)) == 3:
			var slot := int(layout[k]["slot"])
			s += "#define %s mat3(data[%d].xyz, data[%d].xyz, data[%d].xyz)\n" % [k, slot, slot + 1, slot + 2]
		else:
			s += "#define %s data[%d].%s\n" % [k, int(layout[k]["slot"]), str(layout[k]["components"])]
	return s

func _engine_value(name: String) -> Array:
	match name:
		"resolution", "fullResolution":
			return [float(screen.x), float(screen.y)]
		"tileOffset":
			return [0.0, 0.0]
		"time":
			return [_time]
		"aspectRatio":
			return [float(screen.x) / float(screen.y) if screen.y != 0 else 1.0]
		"renderScale":
			return [_render_scale]
		"deltaTime":
			return [_delta_time]
		"frame":
			return [float(_frame_index)]
	return [0.0]

func _comp_offsets(components: String) -> Array:
	var m := {"x": 0, "y": 1, "z": 2, "w": 3}
	var out := []
	for c in components:
		out.append(m[c])
	return out

func _finite_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _automation_type(value) -> String:
	if not (value is Dictionary):
		return ""
	var kind := str(value.get("type", ""))
	if kind in ["Oscillator", "Midi", "Audio"]:
		return kind
	var ast = value.get("_ast")
	if ast is Dictionary:
		kind = str(ast.get("type", ""))
		if kind in ["Oscillator", "Midi", "Audio"]:
			return kind
	return ""

func _is_automation_value(value) -> bool:
	return _automation_type(value) != ""

func _scale_automation_value(value: float, value_range) -> float:
	if not (value_range is Dictionary) or not _finite_number(value_range.get("min")) \
			or not _finite_number(value_range.get("max")):
		return value
	return float(value_range["min"]) + value * (float(value_range["max"]) - float(value_range["min"]))

func _resolve_automation_field(value, normalized_time: float, value_range: Dictionary,
		depth: int, fallback: float, wall_time: float, stack: Array) -> float:
	if _is_automation_value(value):
		return _evaluate_automation(value, normalized_time, value_range, depth + 1, wall_time, stack)
	return float(value) if _finite_number(value) else fallback

func _has_dynamic_automation_fields(config: Dictionary) -> bool:
	var fields := ["min", "max", "sensitivity"] if _automation_type(config) == "Midi" else ["min", "max"]
	for field in fields:
		if _is_automation_value(config.get(field)):
			return true
	return false

func _osc_sine(t: float) -> float:
	return (1.0 - cos(t * TAU)) * 0.5

func _osc_tri(t: float) -> float:
	var fraction: float = t - floor(t)
	return 1.0 - abs(fraction * 2.0 - 1.0)

func _osc_saw(t: float) -> float:
	return t - floor(t)

func _osc_saw_inverse(t: float) -> float:
	return 1.0 - (t - floor(t))

func _osc_square(t: float) -> float:
	return 1.0 if t - floor(t) >= 0.5 else 0.0

func _automation_hash21(px: float, py: float, seed: float) -> float:
	var x := fmod(px * 234.34 + seed, 1.0)
	var y := fmod(py * 435.345 + seed, 1.0)
	if x < 0.0:
		x += 1.0
	if y < 0.0:
		y += 1.0
	var p := x + y + (x + y) * 34.23
	return fmod(x * y * p, 1.0)

func _automation_noise2d(px: float, py: float, seed: float) -> float:
	var ix := floor(px)
	var iy := floor(py)
	var fx: float = px - ix
	var fy: float = py - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _automation_hash21(ix, iy, seed)
	var b := _automation_hash21(ix + 1.0, iy, seed)
	var c := _automation_hash21(ix, iy + 1.0, seed)
	var d := _automation_hash21(ix + 1.0, iy + 1.0, seed)
	return a * (1.0 - fx) * (1.0 - fy) + b * fx * (1.0 - fy) \
		+ c * (1.0 - fx) * fy + d * fx * fy

func _osc_noise(t: float, seed: float) -> float:
	var angle := fmod(t, 1.0) * TAU
	var loop_x := cos(angle) * 2.0
	var loop_y := sin(angle) * 2.0
	var first := _automation_noise2d(loop_x + seed, loop_y + seed, seed)
	var second := _automation_noise2d(loop_x + seed * 2.0, loop_y + seed * 2.0, seed)
	return (first + second) * 0.5

func _osc_primitive(kind: int, x: float):
	var whole := floor(x)
	var fraction: float = x - whole
	match kind:
		0:
			return x * 0.5 - sin(x * TAU) / (2.0 * TAU)
		1:
			var partial: float = fraction * fraction if fraction < 0.5 \
				else 2.0 * fraction - fraction * fraction - 0.5
			return whole * 0.5 + partial
		2:
			return whole * 0.5 + fraction * fraction * 0.5
		3:
			return x - (whole * 0.5 + fraction * fraction * 0.5)
		4:
			return whole * 0.5 + max(0.0, fraction - 0.5)
	return null

func _can_integrate_oscillator_exactly(config: Dictionary) -> bool:
	var kind = config.get("oscType")
	if not _finite_number(kind) or kind < 0 or kind > 4:
		return false
	for field in ["min", "max", "speed", "offset", "seed"]:
		if not _finite_number(config.get(field)):
			return false
	return true

func _integrate_simple_oscillator(config: Dictionary, normalized_time: float, wall_time: float) -> float:
	var speed := float(config.get("speed"))
	if speed == 0.0:
		return _evaluate_oscillator(config, 0.0, 0, wall_time, []) * normalized_time
	var start = _osc_primitive(int(config.get("oscType")), float(config.get("offset")))
	var finish = _osc_primitive(int(config.get("oscType")),
		float(config.get("offset")) + speed * normalized_time)
	var raw_integral: float = (finish - start) / speed
	return float(config.get("min")) * normalized_time \
		+ (float(config.get("max")) - float(config.get("min"))) * raw_integral

func _integrate_automation(config: Dictionary, normalized_time: float, value_range: Dictionary,
		depth: int, wall_time: float, stack: Array) -> float:
	var integral: float
	var kind := _automation_type(config)
	if kind == "Oscillator" and _can_integrate_oscillator_exactly(config):
		integral = _integrate_simple_oscillator(config, normalized_time, wall_time)
	elif (kind == "Midi" or kind == "Audio") and not _has_dynamic_automation_fields(config):
		integral = _evaluate_automation(config, normalized_time, null, depth + 1, wall_time, stack) * normalized_time
	else:
		var rule: Dictionary = INTEGRATION_RULES[min(depth, INTEGRATION_RULES.size() - 1)]
		var midpoint := normalized_time * 0.5
		var half_width := normalized_time * 0.5
		var total := 0.0
		for i in range(rule["nodes"].size()):
			var sample_time: float = midpoint + half_width * float(rule["nodes"][i])
			total += float(rule["weights"][i]) * _evaluate_automation(
				config, sample_time, null, depth + 1, wall_time, stack)
		integral = half_width * total
	if value_range is Dictionary and _finite_number(value_range.get("min")) \
			and _finite_number(value_range.get("max")):
		return float(value_range["min"]) * normalized_time \
			+ integral * (float(value_range["max"]) - float(value_range["min"]))
	return integral

func _state_field(state, field: String, fallback = 0.0):
	if state is Dictionary:
		return state.get(field, fallback)
	if state is Object:
		var value = state.get(field)
		return fallback if value == null else value
	return fallback

func _selected_midi_state(config: Dictionary):
	if _midi_state == null:
		return null
	var has_selector := config.has("name") or config.has("id")
	if not has_selector:
		return _midi_state
	if _midi_state is Object:
		for method in ["get_port_state", "getPortState"]:
			if _midi_state.has_method(method):
				return _midi_state.call(method, config)
	if not (_midi_state is Dictionary) or not (_midi_state.get("ports") is Dictionary):
		return null
	var ports: Dictionary = _midi_state["ports"]
	if config.has("id"):
		var entry = ports.get(config["id"])
		return entry.get("state") if entry is Dictionary and entry.get("connected", true) else null
	var matched_state = null
	for entry in ports.values():
		if entry is Dictionary and entry.get("connected", true) and entry.get("name") == config.get("name"):
			if matched_state != null:
				return null
			matched_state = entry.get("state")
	return matched_state

func _midi_channel(state, channel_number: int):
	if state is Object:
		for method in ["get_channel", "getChannel"]:
			if state.has_method(method):
				return state.call(method, channel_number)
	if state is Dictionary and state.get("channels") is Dictionary:
		var channels: Dictionary = state["channels"]
		return channels.get(channel_number, channels.get(str(channel_number),
			channels.get(1, channels.get("1", {}))))
	return null

func _evaluate_midi(config: Dictionary, midi_state, wall_time: float,
		minimum: float, maximum: float, sensitivity: float) -> float:
	if config.get("_invalid", false) or midi_state == null:
		return minimum
	var mode: int = int(config.get("mode", 4))
	var has_zone := config.has("zone")
	if has_zone and (config.has("channel") or not _integer_in(config.get("zone"), 0, 1)):
		return minimum
	if config.has("members") and (not has_zone or not _integer_in(config["members"], 1, 15)):
		return minimum
	if not has_zone and mode >= 5 and not _integer_in(config.get("channel"), 1, 16):
		return minimum
	var voice = null
	if has_zone:
		if midi_state is Object:
			for method in ["get_zone_voice", "getZoneVoice"]:
				if midi_state.has_method(method):
					voice = midi_state.call(method, config)
					break
		if voice == null:
			return minimum
	var channel = _state_field(voice, "channel", null) if has_zone \
		else _midi_channel(midi_state, int(config.get("channel", 1)))
	if channel == null:
		return minimum
	var note = voice if voice != null else channel
	var note_key = _state_field(note, "key", 0)
	if mode == 5 or mode == 6:
		var cc = config.get("cc", 1)
		if not _integer_in(cc, 0, 31 if mode == 6 else 127):
			return minimum
		var raw := _midi_index(_state_field(channel, "cc14" if mode == 6 else "cc", null), int(cc))
		return minimum + raw / (16383.0 if mode == 6 else 127.0) * (maximum - minimum)
	if mode == 7:
		if not _integer_in(config.get("nrpn"), 0, 16382):
			return minimum
		return minimum + _midi_index(_state_field(channel, "nrpn", null), int(config["nrpn"])) \
			/ 16383.0 * (maximum - minimum)
	if mode == 8:
		return minimum + float(_state_field(channel, "pitchBend", 8192)) / 16383.0 * (maximum - minimum)
	if mode == 9:
		return minimum + float(_state_field(channel, "pressure", 0)) / 127.0 * (maximum - minimum)
	if mode == 10:
		return minimum + _midi_index(_state_field(channel, "polyPressure", null), int(note_key)) \
			/ 127.0 * (maximum - minimum)
	var raw_value := 0.0
	var gate := 1.0 if voice != null else float(_state_field(note, "gate", 0.0))
	match mode:
		0:
			raw_value = float(note_key)
		1:
			if gate == 1.0:
				raw_value = float(note_key)
		2:
			if gate == 1.0:
				raw_value = float(_state_field(note, "velocity", 0.0))
		3:
			if gate == 1.0:
				raw_value = float(note_key)
				var decay := min(1.0, (wall_time - float(_state_field(note, "time", 0.0))) \
					* sensitivity * 0.001)
				raw_value *= 1.0 - decay
		_:
			if gate == 1.0:
				raw_value = float(_state_field(note, "velocity", 0.0))
				var decay := min(1.0, (wall_time - float(_state_field(note, "time", 0.0))) \
					* sensitivity * 0.001)
				raw_value *= 1.0 - decay
	return minimum + raw_value / 127.0 * (maximum - minimum)

func _integer_in(value, minimum: int, maximum: int) -> bool:
	return _finite_number(value) and floorf(float(value)) == float(value) \
		and value >= minimum and value <= maximum

func _midi_index(values, key: int) -> float:
	if values is Dictionary:
		return float(values.get(key, values.get(str(key), 0)))
	if values is Array or values is PackedByteArray or values is PackedInt32Array \
			or values is PackedFloat32Array or values is PackedFloat64Array:
		return float(values[key]) if key >= 0 and key < values.size() else 0.0
	return 0.0

func _has_audio_selector(config: Dictionary) -> bool:
	var source = config.get("_ast")
	if not (source is Dictionary) or source.get("type") != "Audio":
		source = config
	for field in ["name", "id", "channel"]:
		if config.has(field) or source.has(field):
			return true
	return false

func _valid_audio_selector(config: Dictionary) -> bool:
	var source = config.get("_ast")
	if not (source is Dictionary) or source.get("type") != "Audio":
		source = config
	for field in ["name", "id", "channel"]:
		if source.has(field) and not config.has(field):
			return false
	if config.has("name") and (not (config["name"] is String) or config["name"].is_empty()):
		return false
	if config.has("id") and (not (config["id"] is String) or config["id"].is_empty() or not config.has("name")):
		return false
	return _integer_in(config.get("channel"), 1, 32)

func _selected_audio_state(config: Dictionary):
	if _audio_state == null:
		return null
	var has_selector := _has_audio_selector(config)
	if not has_selector:
		return _audio_state
	if not _valid_audio_selector(config):
		return null
	if _audio_state is Object:
		for method in ["get_device_channel_state", "getDeviceChannelState"]:
			if _audio_state.has_method(method):
				return _audio_state.call(method, config)
	if not (_audio_state is Dictionary) or not (_audio_state.get("devices") is Dictionary):
		return null
	var devices: Dictionary = _audio_state["devices"]
	var entry = devices.get(config.get("id")) if config.has("id") else null
	if not config.has("id") and config.has("name"):
		for candidate in devices.values():
			if candidate is Dictionary and candidate.get("connected", true) \
					and candidate.get("name") == config.get("name"):
				if entry != null:
					return null
				entry = candidate
	if not (entry is Dictionary) or not entry.get("connected", true):
		return null
	var channels = entry.get("channels")
	if channels is Dictionary:
		return channels.get(config.get("channel"), channels.get(str(config.get("channel"))))
	return null

func _evaluate_audio(config: Dictionary, audio_state, minimum: float, maximum: float) -> float:
	if config.get("_invalid", false) or audio_state == null:
		return minimum
	var raw_value := 0.0
	match int(config.get("band", -1)):
		0:
			raw_value = float(_state_field(audio_state, "low", 0.0))
		1:
			raw_value = float(_state_field(audio_state, "mid", 0.0))
		2:
			raw_value = float(_state_field(audio_state, "high", 0.0))
		3:
			raw_value = float(_state_field(audio_state, "vol", 0.0))
		4:
			if _state_field(audio_state, "rawReady", false) != true \
					and _state_field(audio_state, "raw_ready", false) != true:
				return minimum
			raw_value = (clampf(float(_state_field(audio_state, "raw", 0.0)), -1.0, 1.0) + 1.0) * 0.5
	return minimum + clampf(raw_value, 0.0, 1.0) * (maximum - minimum)

func _evaluate_oscillator(config: Dictionary, normalized_time: float, depth: int,
		wall_time: float, stack: Array) -> float:
	var minimum := _resolve_automation_field(config.get("min"), normalized_time,
		AUTOMATION_FIELD_RANGES["unit"], depth, 0.0, wall_time, stack)
	var maximum := _resolve_automation_field(config.get("max"), normalized_time,
		AUTOMATION_FIELD_RANGES["unit"], depth, 1.0, wall_time, stack)
	var offset := _resolve_automation_field(config.get("offset"), normalized_time,
		AUTOMATION_FIELD_RANGES["oscillatorOffset"], depth, 0.0, wall_time, stack)
	var seed := _resolve_automation_field(config.get("seed"), normalized_time,
		AUTOMATION_FIELD_RANGES["oscillatorSeed"], depth, 1.0, wall_time, stack)
	var speed = config.get("speed")
	var phase := _integrate_automation(speed, normalized_time,
		AUTOMATION_FIELD_RANGES["oscillatorSpeed"], depth, wall_time, stack) \
		if speed is Dictionary and _is_automation_value(speed) \
		else normalized_time * (float(speed) if _finite_number(speed) else 1.0)
	var t := phase + offset
	var raw_value := 0.0
	match int(config.get("oscType", -1)):
		0:
			raw_value = _osc_sine(t)
		1:
			raw_value = _osc_tri(t)
		2:
			raw_value = _osc_saw(t)
		3:
			raw_value = _osc_saw_inverse(t)
		4:
			raw_value = _osc_square(t)
		5:
			raw_value = _osc_noise(t, seed)
	return minimum + raw_value * (maximum - minimum)

func _automation_stack_has(stack: Array, config: Dictionary) -> bool:
	for active in stack:
		if is_same(active, config):
			return true
	return false

func _evaluate_automation(config: Dictionary, normalized_time: float, value_range = null,
		depth: int = 0, wall_time: float = -1.0, stack: Array = []) -> float:
	if not _is_automation_value(config) or depth > MAX_AUTOMATION_DEPTH \
			or _automation_stack_has(stack, config):
		return _scale_automation_value(0.0, value_range)
	if wall_time < 0.0:
		wall_time = float(Time.get_ticks_msec())
	stack.push_back(config)
	var value := 0.0
	match _automation_type(config):
		"Oscillator":
			value = _evaluate_oscillator(config, normalized_time, depth, wall_time, stack)
		"Midi":
			var minimum := _resolve_automation_field(config.get("min"), normalized_time,
				AUTOMATION_FIELD_RANGES["unit"], depth, 0.0, wall_time, stack)
			var maximum := _resolve_automation_field(config.get("max"), normalized_time,
				AUTOMATION_FIELD_RANGES["unit"], depth, 1.0, wall_time, stack)
			var sensitivity := _resolve_automation_field(config.get("sensitivity"), normalized_time,
				AUTOMATION_FIELD_RANGES["midiSensitivity"], depth, 1.0, wall_time, stack)
			value = _evaluate_midi(config, _selected_midi_state(config), wall_time,
				minimum, maximum, sensitivity)
		"Audio":
			if config.get("_invalid", false):
				value = float(config.get("min")) if _finite_number(config.get("min")) else 0.0
			else:
				var minimum := _resolve_automation_field(config.get("min"), normalized_time,
					AUTOMATION_FIELD_RANGES["unit"], depth, 0.0, wall_time, stack)
				var maximum := _resolve_automation_field(config.get("max"), normalized_time,
					AUTOMATION_FIELD_RANGES["unit"], depth, 1.0, wall_time, stack)
				value = _evaluate_audio(config, _selected_audio_state(config), minimum, maximum)
	stack.pop_back()
	return _scale_automation_value(value, value_range)

func resolve_uniform_value(value, normalized_time: float, param_spec = null):
	if not _is_automation_value(value):
		return value
	return _evaluate_automation(value, normalized_time, param_spec)

func _visit_audio_requirements(value, result: Dictionary, selected_keys: Dictionary,
		depth: int = 0) -> void:
	if depth > 64:
		return
	if value is Dictionary and _automation_type(value) == "Audio":
		var source = value.get("_ast")
		if not (source is Dictionary) or source.get("type") != "Audio":
			source = value
		var has_selector_intent: bool = value.has("name") or value.has("id") or value.has("channel") \
			or source.has("name") or source.has("id") or source.has("channel")
		var band = value.get("band")
		var has_valid_band: bool = not value.get("_invalid", false) and _finite_number(band) \
			and floorf(float(band)) == float(band) and band >= 0 and band <= 4
		if not has_valid_band:
			return
		_visit_audio_requirements(value.get("min"), result, selected_keys, depth + 1)
		_visit_audio_requirements(value.get("max"), result, selected_keys, depth + 1)
		if has_selector_intent and _valid_audio_selector(value):
			var requirement := {
				"id": value.get("id") if value.get("id") is String and not str(value.get("id")).is_empty() else null,
				"name": value.get("name"),
				"channel": value.get("channel"),
				"needsRaw": int(band) == 4,
			}
			var key := JSON.stringify([requirement["id"], requirement["name"], requirement["channel"]])
			if selected_keys.has(key):
				var index: int = selected_keys[key]
				if requirement["needsRaw"]:
					result["selected"][index]["needsRaw"] = true
			else:
				selected_keys[key] = result["selected"].size()
				result["selected"].append(requirement)
		elif not has_selector_intent:
			result["needsLegacy"] = true
			if int(band) == 4:
				result["needsLegacyRaw"] = true
		return
	if value is Array:
		for item in value:
			_visit_audio_requirements(item, result, selected_keys, depth + 1)
	elif value is Dictionary:
		for key in value:
			if key != "_ast":
				_visit_audio_requirements(value[key], result, selected_keys, depth + 1)

func get_audio_input_requirements(graph: Dictionary) -> Dictionary:
	var result := {"needsLegacy": false, "needsLegacyRaw": false, "selected": []}
	var selected_keys := {}
	for pass_data in graph.get("passes", []):
		if pass_data is Dictionary:
			var effect_def := _load_effect_def(str(pass_data.get("namespace", "")),
				str(pass_data.get("func", "")))
			if effect_def.get("tags") is Array and effect_def["tags"].has("audio"):
				result["needsLegacy"] = true
			_visit_audio_requirements(pass_data.get("uniforms", {}), result, selected_keys)
	return result

func _value_floats(v) -> Array:
	if typeof(v) == TYPE_BOOL:
		return [1.0 if v else 0.0]
	if typeof(v) == TYPE_ARRAY:
		var out := []
		for x in v:
			out.append(float(x))
		return out
	return [float(v)]

func _default_for_uniform(globals: Dictionary, uniform_name: String):
	if globals.has(uniform_name) and globals[uniform_name].has("default"):
		return globals[uniform_name]["default"]
	for global_spec in globals.values():
		if global_spec is Dictionary and str(global_spec.get("uniform", "")) == uniform_name:
			return global_spec.get("default")
	return null

func _audio_values(name: String) -> Array:
	_ensure_audio_storage()
	var source := _audio_waveform if name.begins_with("audioWaveform_") else _audio_spectrum
	var group := int(name.get_slice("_", 1))
	var start := group * 4
	return [source[start], source[start + 1], source[start + 2], source[start + 3]]

func _audio_layout(fn: String) -> Dictionary:
	if _audio_layouts.has(fn):
		return _audio_layouts[fn]
	var prefix := "audioWaveform" if fn == "scope" else "audioSpectrum"
	var layout := {
		"resolution": {"slot": 0, "components": "xy"},
		"time": {"slot": 0, "components": "z"},
		"tileOffset": {"slot": 1, "components": "xy"},
		"fullResolution": {"slot": 1, "components": "zw"},
		"lineColor": {"slot": 2, "components": "xyz"},
		"lineThickness": {"slot": 2, "components": "w"},
		"gain": {"slot": 3, "components": "x"},
	}
	for group in 32:
		layout["%s_%d" % [prefix, group]] = {"slot": 4 + group, "components": "xyzw"}
	_audio_layouts[fn] = layout
	return layout

func pack_with_layout(layout: Dictionary, globals: Dictionary, p: Dictionary) -> PackedByteArray:
	var max_slot := 0
	for name in layout:
		max_slot = max(max_slot, int(layout[name]["slot"]) + int(layout[name].get("columns", 1)) - 1)
	var data := PackedFloat32Array()
	data.resize((max_slot + 1) * 4)
	var pass_u: Dictionary = p.get("uniforms", {})
	var uniform_specs: Dictionary = p.get("uniformSpecs", {})
	for name in layout:
		var slot := int(layout[name]["slot"])
		var offs := _comp_offsets(str(layout[name]["components"]))
		var vals: Array
		if str(name).begins_with("audioWaveform_") or str(name).begins_with("audioSpectrum_"):
			vals = _audio_values(str(name))
		elif ENGINE_GLOBALS.has(name):
			vals = _engine_value(name)
		elif pass_u.has(name):
			vals = _value_floats(resolve_uniform_value(pass_u[name], _time, uniform_specs.get(name)))
		else:
			var default_value = _default_for_uniform(globals, str(name))
			vals = _value_floats(default_value) if default_value != null else [0.0]
		var columns := int(layout[name].get("columns", 1))
		if columns == 3:
			for column in 3:
				for row in 3:
					var source_index := column * 3 + row
					if source_index < vals.size():
						data[(slot + column) * 4 + row] = vals[source_index]
		else:
			for i in range(min(offs.size(), vals.size())):
				data[slot * 4 + offs[i]] = vals[i]
	return data.to_byte_array()

func _pack_pass(p: Dictionary) -> PackedByteArray:
	var ns := str(p.get("namespace"))
	var fn := str(p.get("func"))
	var def := _load_effect_def(ns, fn)
	var globals: Dictionary = def.get("globals", {})
	# A DECLARED layout (uniformLayout, or uniformLayouts[prog]) is used verbatim even when
	# it is empty {} — that means "the .glsl declares its own UBO with no mapped params"
	# (e.g. filter/invert). Only effects with NO layout declaration get a synthesized one.
	if _has_layout(def, p):
		return pack_with_layout(_layout_for(def, p), globals, p)
	return pack_with_layout(_synth_layout(ns, fn, globals), globals, p)

# Whether the effect DECLARES a uniform layout for this pass: a single `uniformLayout`
# (any value, including empty {}), or a per-program `uniformLayouts[progName]` (multi-
# program effects like cellularAutomata's ca/caFb). Drives both the synth-header decision
# and packing. An empty {} still counts as declared — do NOT confuse "empty" with "absent".
func _has_layout(def: Dictionary, p: Dictionary) -> bool:
	if str(def.get("namespace", "")) == "synth" and str(def.get("func", "")) in ["scope", "spectrum"]:
		return true
	if def.has("uniformLayout"):
		return true
	if def.has("uniformLayouts"):
		return def["uniformLayouts"].has(str(p.get("progName", p.get("func"))))
	return false

# The declared layout dict for a pass (only meaningful when _has_layout is true).
func _layout_for(def: Dictionary, p: Dictionary) -> Dictionary:
	if str(def.get("namespace", "")) == "synth" and str(def.get("func", "")) in ["scope", "spectrum"]:
		return _audio_layout(str(def["func"]))
	if def.has("uniformLayouts"):
		return def["uniformLayouts"].get(str(p.get("progName", p.get("func"))), {})
	return def.get("uniformLayout", {})

# --- execution ------------------------------------------------------------

# A pass is one of five draws, dispatched on outputs + drawMode:
#   fullscreen  — 1 output, fullscreen triangle (the 93 isolation effects + blit)
#   MRT         — N outputs (drawBuffers>1), fullscreen triangle into N attachments
#                 (agent state updates: pointsEmit/init, flow/agent write xyz+vel+rgba)
#   points      — drawMode "points": N procedural point primitives, one per agent, custom
#                 vertex shader fetching agent position from the state textures (deposit)
#   billboards  — drawMode "billboards": N×6 procedural triangles (agent quads)
#   triangles   — drawMode "triangles": N procedural mesh vertices from texture inputs
# Custom draws do not clear. Point/billboard passes accumulate onto the trail the copy
# pass just produced; triangle passes preserve the preceding background clear pass.
func execute_pass(p: Dictionary) -> bool:
	var ptype := str(p.get("passType", "effect"))
	var draw_mode := str(p.get("drawMode", ""))
	var is_custom_draw := draw_mode == "points" or draw_mode == "billboards" or draw_mode == "triangles"
	var cache_key := ""
	var frag_src := ""
	var vert_src := FULLSCREEN_VS
	if ptype == "blit":
		cache_key = "blit"
		frag_src = BLIT_FS
	else:
		var ns := str(p.get("namespace"))
		var fn := str(p.get("func"))
		# Shaders are keyed by progName (an effect may have several programs, e.g.
		# blur -> blurH/blurV); the effect DEFINITION (globals/layout) is keyed by func.
		var prog := str(p.get("progName", fn))
		var defs: Dictionary = p.get("defines", {})
		var def := _load_effect_def(ns, fn)
		var raw_frag := _load_fragment(ns, fn, prog)
		var inject := ""
		for k in defs:
			inject += "#define %s %s\n" % [k, _format_define_value(str(k), defs[k], def, raw_frag)]
		# Synthesize + inject the UBO only for true no-layout effects. Effects that DECLARE
		# a layout (uniformLayout — even empty {} — or uniformLayouts[prog]) declare their
		# own Params block in the .glsl; injecting one too would duplicate it.
		if not _has_layout(def, p):
			inject += _synth_header(_synth_layout(ns, fn, def.get("globals", {})))
		cache_key = ns + "/" + fn + "/" + prog + _defines_key(defs)
		frag_src = _inject_after_version(raw_frag, inject)
		# Agent deposit passes carry a custom vertex stage (gl_VertexIndex scatter); the
		# same UBO/defines are injected into it so the VS can read params + sample state.
		if is_custom_draw:
			vert_src = _inject_after_version(_load_vertex(ns, fn, prog), inject)
	var shader := _get_shader(cache_key, vert_src, frag_src)
	if not shader.is_valid():
		return false

	# Resolve every output to its write RID, in declaration order (= shader layout(location=i)).
	# Double-buffered surfaces render into the current WRITE buffer; everything else flat.
	var outputs: Dictionary = p.get("outputs", {})
	var out_rids := []
	var output_size := screen
	for k in outputs:
		var output_id := str(outputs[k])
		var rid := _resolve_write(output_id)
		if not rid.is_valid():
			var miss := "pass output texture missing: " + output_id
			push_error(miss)
			last_shader_diagnostic = _shader_diag.make({
				"code": ShaderDiagnostics.DIAGNOSTIC_CODES["MISSING_SOURCE"],
				"stage": "missing-source",
				"program": str(p.get("progName", p.get("func", ""))),
				"detail": miss,
			})
			return false
		out_rids.append(rid)
		output_size = _tex_dims.get(output_id, screen)
	if out_rids.is_empty():
		return false
	var framebuffer_rids := out_rids.duplicate()
	var is_mesh := draw_mode == "triangles"
	if is_mesh:
		framebuffer_rids.append(_depth_texture(output_size))
	var fb := rd.framebuffer_create(framebuffer_rids)
	if not fb.is_valid():
		var fbmsg := "framebuffer creation failed: " + cache_key + " attachments=" + str(out_rids.size())
		push_error(fbmsg)
		last_shader_diagnostic = _shader_diag.make({
			"code": ShaderDiagnostics.DIAGNOSTIC_CODES["PIPELINE"],
			"backend": "renderingdevice",
			"stage": "framebuffer",
			"program": cache_key,
			"detail": fbmsg,
		})
		return false
	var fb_format := rd.framebuffer_get_format(fb)
	var n_attach := out_rids.size()
	var primitive := RenderingDevice.RENDER_PRIMITIVE_POINTS if draw_mode == "points" \
		else RenderingDevice.RENDER_PRIMITIVE_TRIANGLES
	var blend_spec := _resolve_blend(p)
	var vfmt := _vfmt_empty if is_custom_draw else _vfmt
	var pipeline := _get_pipeline(cache_key, shader, fb_format, n_attach, primitive, blend_spec, vfmt, is_mesh)
	if not pipeline.is_valid():
		# _get_pipeline recorded a minimal ERR_PIPELINE_CREATE diagnostic; this
		# OVERWRITES last_shader_diagnostic with the fuller record (same code,
		# detail now carries the actual per-attachment texture formats) so the
		# harness side-car quotes the enriched failure. Then bail instead of
		# binding a dead pipeline into a doomed draw list.
		var fmts := PackedStringArray()
		for rid in out_rids:
			# texture_get_format returns an RDTextureFormat struct, not a
			# DataFormat int; print its .format so the attachment DataFormats
			# are readable instead of object reprs.
			fmts.append(str(rd.texture_get_format(rid).format))
		var rich := ("render pipeline creation failed: " + cache_key
			+ " fb_format=" + str(fb_format)
			+ " attachment_formats=" + " ".join(fmts))
		push_error(rich)
		last_shader_diagnostic = _shader_diag.make({
			"code": ShaderDiagnostics.DIAGNOSTIC_CODES["PIPELINE"],
			"backend": "renderingdevice",
			"stage": "pipeline",
			"program": cache_key,
			"detail": rich,
		})
		return false

	var set0_uniforms := []
	if ptype == "blit":
		var src_id := str(p.get("inputs", {}).get("src", "none"))
		var su := RDUniform.new()
		su.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		su.binding = 0
		# Mipmapped inputs sample through the mipmap-capable sampler
		# (reference legacyDefault 'mipmap' for textures with a mip chain).
		# _tex_mip is keyed by texId — select via the resolved READ texId
		# (_read_tex_id), not _resolve_read's RID.
		var blit_read_id := _read_tex_id(src_id)
		su.add_id(_mip_sampler if _tex_mip.get(blit_read_id, 1) > 1 else _sampler)
		su.add_id(_resolve_read(src_id))
		set0_uniforms.append(su)
	else:
		var ubytes := _pack_pass(p)
		var ubo := rd.uniform_buffer_create(ubytes.size(), ubytes)
		var u0 := RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		u0.binding = 0
		u0.add_id(ubo)
		set0_uniforms.append(u0)
		# Bind set-0 samplers BY NAME to the shader's declared bindings. A pass may list
		# more inputs than the shader uses (e.g. cellularAutomata's render pass lists 4,
		# uses 1); the SPIR-V compiler strips the unused ones, so we bind exactly the
		# declared+surviving samplers. "none"/missing inputs resolve to the black texture.
		# Deposit samplers (xyzTex/rgbaTex) live in the VERTEX stage, so parse BOTH sources.
		var inputs: Dictionary = p.get("inputs", {})
		for s in _samplers_for(cache_key, frag_src + "\n" + vert_src):
			var tid := str(inputs.get(s["name"], "none"))
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			u.binding = int(s["binding"])
			# Mipmapped inputs sample through the mipmap-capable sampler
			# (reference legacyDefault 'mipmap' for textures with a mip chain).
			# _tex_mip is keyed by texId — select via the resolved READ texId.
			var read_id := _read_tex_id(tid)
			u.add_id(_mip_sampler if _tex_mip.get(read_id, 1) > 1 else _sampler)
			u.add_id(_resolve_read(tid))
			set0_uniforms.append(u)
	var set0 := rd.uniform_set_create(set0_uniforms, shader, 0)

	# Custom draws preserve the previous attachment contents: point/billboard deposits
	# accumulate and mesh triangles draw over their preceding background clear pass.
	var dl: int
	if is_custom_draw:
		var draw_flags := RenderingDevice.DRAW_CLEAR_DEPTH if is_mesh else 0
		dl = rd.draw_list_begin(fb, draw_flags, PackedColorArray(), 1.0)
	else:
		var clears := PackedColorArray()
		for _i in n_attach:
			clears.append(Color(0, 0, 0, 0))
		dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_CLEAR_COLOR_ALL, clears)
	if dl == -1:
		# draw_list_begin returns -1 on failure (validation/format rejection on
		# some drivers); every draw_list_* call would then be a silent no-op and
		# the surface would read back all-zero. Name it instead.
		var dlmsg := "draw_list_begin failed (-1): " + cache_key
		push_error(dlmsg)
		last_shader_diagnostic = _shader_diag.make({
			"code": ShaderDiagnostics.DIAGNOSTIC_CODES["DRAW_LIST"],
			"backend": "renderingdevice",
			"stage": "draw",
			"program": cache_key,
			"detail": dlmsg,
		})
		return false
	rd.draw_list_bind_render_pipeline(dl, pipeline)
	rd.draw_list_bind_uniform_set(dl, set0, 0)
	if is_custom_draw:
		# Procedural draw: N (or N×6) vertices, no vertex buffer — gl_VertexIndex indexes
		# either agent state textures or mesh position/normal textures in the custom VS.
		var count := _resolve_count(p)
		if draw_mode == "billboards":
			count *= 6
		rd.draw_list_draw(dl, false, 1, count)
	else:
		rd.draw_list_bind_vertex_array(dl, _varr)
		rd.draw_list_draw(dl, false, 1)
	rd.draw_list_end()
	return true

# --- ping-pong resolution -------------------------------------------------

# Texture an input texId samples FROM. Double-buffered surfaces resolve to this frame's
# read buffer; "none"/unknown resolve to the black texture (reference BlackTex).
func _resolve_read(tex_id: String) -> RID:
	if tex_id == "none" or tex_id == "":
		return _black_tex
	if _pingpong.has(tex_id):
		return _textures[_frame_read[_pingpong[tex_id]]]
	if _textures.has(tex_id):
		return _textures[tex_id]
	return _black_tex

# texId of the buffer an input texId samples FROM ("" for none/unknown → black tex).
# Mirrors _resolve_read but returns the texId STRING so mipmap-sampler selection can
# key _tex_mip (texId -> level count) — _resolve_read's RID must not be used as a
# _tex_mip key (it would never match and the mip sampler would never be selected).
func _read_tex_id(tex_id: String) -> String:
	if tex_id == "none" or tex_id == "":
		return ""
	if _pingpong.has(tex_id):
		return str(_frame_read[_pingpong[tex_id]])
	if _textures.has(tex_id):
		return tex_id
	return ""

# Texture an output texId renders INTO. Double-buffered surfaces resolve to this frame's
# write buffer. Returns an invalid RID if the target is genuinely missing.
func _resolve_write(tex_id: String) -> RID:
	if _pingpong.has(tex_id):
		return _textures[_frame_write[_pingpong[tex_id]]]
	if _textures.has(tex_id):
		return _textures[tex_id]
	return RID()

# Declared set-0 samplers for an assembled shader, parsed once and cached by cache_key.
func _samplers_for(cache_key: String, frag_src: String) -> Array:
	if _samplers.has(cache_key):
		return _samplers[cache_key]
	var out := []
	for m in _sampler_re.search_all(frag_src):
		out.append({"name": m.get_string(2), "binding": int(m.get_string(1))})
	_samplers[cache_key] = out
	return out

# True if any pass reads a texId at or before the pass that first writes it — the read
# depends on a prior frame's content (feedback/state). Such graphs need a multi-frame
# settle. (Same-surface read+write in ONE pass also trips this; those are now double-
# buffered — see _pingpong_surfaces / the frame swap hooks below. Separate read/write
# passes, e.g. feedback's selfTex, work with persistent textures + the frame loop alone.)
func _has_feedback(graph: Dictionary) -> bool:
	var passes = graph.get("passes", [])
	var first_write := {}
	for i in passes.size():
		for k in passes[i].get("outputs", {}):
			var t := str(passes[i]["outputs"][k])
			if not first_write.has(t):
				first_write[t] = i
	for i in passes.size():
		for k in passes[i].get("inputs", {}):
			var t := str(passes[i]["inputs"][k])
			if t != "none" and first_write.has(t) and i <= first_write[t]:
				return true
	return false

func render(graph: Dictionary, normalized_time: float = 0.25, presentation_timestamp: float = -1.0) -> void:
	if _closed:
		push_error("Noisemaker backend is closed")
		return
	_time = normalized_time
	allocate_textures(graph)
	# Feedback/state graphs (read-before-write, or any double-buffered surface) need the
	# reference's settle count (8 frames at the pinned time, reference/04 §10). Otherwise a
	# single deterministic pass.
	var frames := 8 if (_has_feedback(graph) or not _pingpong.is_empty()) else 1
	_passes_executed = 0
	_passes_skipped = 0
	for _frame in frames:
		_begin_frame()
		for p in graph.get("passes", []):
			if _should_skip_pass(p):
				_passes_skipped += 1
				continue
			_passes_executed += 1
			# A pass may repeat within the frame (reference §10.5, e.g. reactionDiffusion's
			# `repeat: "iterations"` solver). Each iteration ping-pongs so it reads the prior
			# iteration's output (§10.6) — distinct from the within-frame and end-of-frame swaps.
			var rc := _repeat_count(p)
			for _iter in rc:
				if not execute_pass(p):
					# execute_pass failed (missing shader/output, dead
					# framebuffer/pipeline/draw list) and recorded a diagnostic;
					# it drew nothing, so don't count it as executed.
					_passes_executed -= 1
					continue
				_update_frame_bindings(p)
				if rc > 1:
					_adopt_iteration_bindings(p)
		# Regenerate mip chains of mipmapped textures from this frame's level-0
		# contents (reference Pipeline.render -> backend.generateMipmaps).
		_generate_mipmaps()
		_end_frame()
	rd.submit()
	rd.sync()
	_submit_render_surface(presentation_timestamp)

# Timed multi-sample render for stateful sims (reference 30s/5s sampling). Steps a real
# per-frame deltaTime (1/600 normalized = one 60fps frame in the 10s loop) so fluid/feedback
# sims actually EVOLVE — the single-frame render() pins deltaTime=0, freezing them at the seed.
# Snapshots the render surface every `sample_every` frames; returns the sampled Images in order.
func render_samples(graph: Dictionary, total_frames: int, sample_every: int) -> Array:
	if _closed:
		push_error("Noisemaker backend is closed")
		return []
	allocate_textures(graph)
	var dt := 1.0 / 600.0
	var samples := []
	for frame in range(1, total_frames + 1):
		_time = fposmod(float(frame) * dt, 1.0)
		_delta_time = dt
		_frame_index = frame
		_begin_frame()
		for p in graph.get("passes", []):
			if _should_skip_pass(p):
				continue
			var rc := _repeat_count(p)
			for _iter in rc:
				execute_pass(p)
				_update_frame_bindings(p)
				if rc > 1:
					_adopt_iteration_bindings(p)
		# Regenerate mip chains of mipmapped textures from this frame's level-0
		# contents (reference Pipeline.render -> backend.generateMipmaps).
		_generate_mipmaps()
		_end_frame()
		# Submit/sync each frame: keeps command buffers small (a 40-iteration nsPressure
		# solve over hundreds of accumulated frames would otherwise overflow one buffer) and
		# serializes frame N before N+1. Determinism comes from correct ping-pong pairs
		# (see _pingpong_surfaces), not from batching.
		rd.submit()
		rd.sync()
		_submit_render_surface(float(frame) * (1000.0 / 60.0))
		if frame % sample_every == 0:
			samples.append(_snapshot_surface())
	return samples


func _submit_render_surface(presentation_timestamp: float) -> void:
	if not _textures.has(render_surface_tex):
		return
	var timestamp := presentation_timestamp
	if timestamp < 0.0:
		timestamp = float(Time.get_ticks_usec()) / 1000.0
	sink_manager.submit(_textures[render_surface_tex], timestamp)

# reference Pipeline.shouldSkipPass: a pass with conditions.{skipIf|runIf}:[{uniform,equals}]
# runs conditionally on a resolved uniform. skipIf -> skip when ANY matches; runIf -> skip
# when ANY does NOT match. The condition value resolves from the pass's flattened uniforms
# (the compiler bakes every global's resolved value into pass.uniforms), with the effect-def
# global default as fallback.
#
# As of reference 0ed489ec, expander.js sets `conditions: passDef.conditions` on every graph
# pass it builds (pointsRender/pointsBillboardRender's per-viewMode deposit variants, and
# pointsBillboardRender's `deposit` (additive) vs `deposit_alpha` (premult-over) blendMode
# split, are what actually exercises this) — expander.gd mirrors that, so `p["conditions"]` IS
# populated at runtime for any effect whose definition carries one.
func _condition_value(p: Dictionary, name: String):
	var u: Dictionary = p.get("uniforms", {})
	if u.has(name):
		return u[name]
	var def := _load_effect_def(str(p.get("namespace")), str(p.get("func")))
	var globals: Dictionary = def.get("globals", {})
	if globals.has(name) and globals[name] is Dictionary and globals[name].has("default"):
		return globals[name]["default"]
	return null

func _cond_equals(a, b) -> bool:
	# Compare loosely across the int/float/bool the JSON/compiler may produce.
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	return a == b

func _should_skip_pass(p: Dictionary) -> bool:
	var cond = p.get("conditions", null)
	if not (cond is Dictionary):
		return false
	var skip_if = cond.get("skipIf", null)
	if skip_if is Array:
		for c in skip_if:
			if c is Dictionary and _cond_equals(_condition_value(p, str(c.get("uniform"))), c.get("equals")):
				return true
	var run_if = cond.get("runIf", null)
	if run_if is Array:
		for c in run_if:
			if c is Dictionary and not _cond_equals(_condition_value(p, str(c.get("uniform"))), c.get("equals")):
				return true
	return false

# reference §10.5 resolveRepeatCount: no repeat -> 1; number -> max(1,floor); string ->
# look it up in the pass uniforms (the iteration count is a pass uniform, e.g. iterations=8).
func _repeat_count(p: Dictionary) -> int:
	var r = p.get("repeat", null)
	if r == null:
		return 1
	if typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT:
		return max(1, int(floor(float(r))))
	if typeof(r) == TYPE_STRING:
		var u: Dictionary = p.get("uniforms", {})
		if u.has(r):
			var v = u[r]
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return max(1, int(floor(float(v))))
	return 1

# reference §10.6 adoptIterationBindings (formerly swapIterationBuffers -- reference
# commits d3453b55, af9298ad): between iterations of a repeated pass, ADOPT the
# frame-local ping-pong bindings that _update_frame_bindings() already advanced for
# this iteration into the cross-frame surface record, so end-of-frame persistence and
# the surface read/write fallback stay consistent. Do NOT recompute the swap from the
# surface record here: a preceding non-repeat pass (e.g. a seed pass) advances only
# the frame-local maps, so the surface record can be stale on the first iteration, and
# re-deriving from it would clobber the correct binding.
func _adopt_iteration_bindings(p: Dictionary) -> void:
	for k in p.get("outputs", {}):
		var t := str(p["outputs"][k])
		if not _pingpong.has(t):
			continue
		var bare: String = _pingpong[t]
		var rec: Dictionary = _surfaces[bare]
		if _frame_read.has(bare):
			rec["read"] = _frame_read[bare]
		if _frame_write.has(bare):
			rec["write"] = _frame_write[bare]

# reference/04 §10 step 4 / BeginFrame: seed each surface's read/write bindings from its
# record at the start of the frame.
func _begin_frame() -> void:
	for bare in _surfaces:
		_frame_read[bare] = _surfaces[bare]["read"]
		_frame_write[bare] = _surfaces[bare]["write"]

# Within-frame ping-pong (reference §10.2): after a pass writes a double-buffered surface,
# subsequent reads see the just-written buffer and the next write targets the old read
# buffer. Keyed on outputs only.
func _update_frame_bindings(p: Dictionary) -> void:
	for k in p.get("outputs", {}):
		var t := str(p["outputs"][k])
		if not _pingpong.has(t):
			continue
		var bare: String = _pingpong[t]
		if not _frame_write.has(bare):
			continue
		var write_id = _frame_write[bare]
		var cur_read = _frame_read.get(bare, null)
		_frame_read[bare] = write_id
		if cur_read != null:
			_frame_write[bare] = cur_read

# End-of-frame swap (reference §10.7): state surfaces persist their final frame bindings
# (the sim continues from the latest buffers — NO toggle); display surfaces toggle
# read<->write. (Per-iteration binding adoption for repeat>1 passes: see
# _adopt_iteration_bindings — reactionDiffusion's `repeat: "iterations"` solver pass.)
func _end_frame() -> void:
	for bare in _surfaces:
		var rec: Dictionary = _surfaces[bare]
		if _is_state_surface(bare):
			if _frame_read.has(bare) and _frame_write.has(bare):
				rec["read"] = _frame_read[bare]
				rec["write"] = _frame_write[bare]
		else:
			var tmp = rec["read"]
			rec["read"] = rec["write"]
			rec["write"] = tmp

# reference §10.7 isStateSurface (case-sensitive): exact/suffix xyz|vel|rgba|trail, the
# substring state/State, or ^(xyz|vel|rgba|points_trail)_node_\d+$. State surfaces persist
# across frames (sims/particles); display surfaces double-buffer with a per-frame toggle.
func _is_state_surface(name: String) -> bool:
	if name == "":
		return false
	if name == "xyz" or name == "vel" or name == "rgba" or name == "trail":
		return true
	if name.ends_with("_xyz") or name.ends_with("_vel") or name.ends_with("_rgba") or name.ends_with("_trail"):
		return true
	if name.find("state") >= 0 or name.find("State") >= 0:
		return true
	return _state_node_re.search(name) != null

# Snapshot the current render surface to an 8-bit Image (per-sample / per-frame capture).
func _snapshot_surface() -> Image:
	if not _textures.has(render_surface_tex):
		return null
	var bytes := rd.texture_get_data(_textures[render_surface_tex], 0)
	# Read the render surface in its ACTUAL format. User surfaces (o0/o1) are rgba8 like the
	# reference; declared HDR surfaces are rgba16f. Misreading rgba8 bytes as half-float is
	# garbage, so pick the Image format from the tracked RD format.
	var rdfmt := int(_tex_fmt.get(render_surface_tex, _data_format("rgba16f")))
	var img_fmt := Image.FORMAT_RGBAH
	if rdfmt == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM:
		img_fmt = Image.FORMAT_RGBA8
	elif rdfmt == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
		img_fmt = Image.FORMAT_RGBAF
	var src := Image.create_from_data(screen.x, screen.y, false, img_fmt, bytes)
	# Single global Y reconciliation (present point, like the Unity NMBlit flip): the
	# webgl2/GLSL golden is bottom-left flipped to a top-down PNG; our pipeline is
	# uniformly top-left, so the result is one vertical flip away.
	src.flip_y()
	# rgba8 surfaces are already 8-bit — return directly. For half/float surfaces, save_png
	# clobbers alpha to opaque, so quantize to 8-bit ourselves (round, clamp, NO sRGB),
	# preserving alpha and matching the reference's round(v*255).
	if img_fmt == Image.FORMAT_RGBA8:
		return src
	var out := Image.create(screen.x, screen.y, false, Image.FORMAT_RGBA8)
	for y in screen.y:
		for x in screen.x:
			out.set_pixel(x, y, src.get_pixel(x, y))
	return out

func save_surface_png(path: String) -> bool:
	var img := _snapshot_surface()
	if img == null:
		push_error("render surface missing: " + render_surface_tex)
		return false
	img.save_png(path)
	return true
