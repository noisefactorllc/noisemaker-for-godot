# edge_face_probe.gd — windowed GPU unit probe for the landscape edge-face rule.
# Extracts voxelOccupied() and exposedFace() verbatim from the live landscape.glsl
# (render/renderLandscape3d), evaluates them on fixed tie cases in a fragment shader
# on the real GPU, and asserts the returned face normal per case. Prints
# "NM_EDGE_FACE_PROBE: PASS cases=N" or FAIL detail lines.
extends SceneTree

const SHADER_PATH := "res://addons/noisemaker/shaders/effects/render/renderLandscape3d/landscape.glsl"
const VOLUME := 8

# Occupied cells of the 8^3 test volume (texel alpha 1.0), chosen so each case's
# neighbors split occupied/empty/out-of-range exactly as the case needs.
const OCCUPIED := [
	[4, 5, 4], [5, 4, 4], [4, 4, 3], [7, 6, 7], [6, 7, 7], [7, 7, 6],
	[0, 5, 4], [5, 4, 5], [4, 5, 5], [2, 3, 2],
]

# Each case: cell, crossed flags, toward step direction, fallback normal, expected face.
# Hand-derived from the ported rule: fewer than two crossed boundaries returns the
# fallback; a crossed boundary whose neighbor voxel is empty or outside the volume
# returns that face; otherwise the fallback stays.
const CASES := [
	{"cell": [4, 4, 4], "crossed": [1, 0, 0], "toward": [-1, -1, -1], "normal": [0, 0, 1], "expect": [0, 0, 1]},
	{"cell": [2, 2, 2], "crossed": [1, 1, 0], "toward": [-1, -1, 0], "normal": [0, 0, 1], "expect": [1, 0, 0]},
	{"cell": [4, 4, 4], "crossed": [1, 1, 0], "toward": [1, 1, 0], "normal": [1, 0, 0], "expect": [0, -1, 0]},
	{"cell": [4, 4, 4], "crossed": [1, 1, 1], "toward": [-1, -1, -1], "normal": [0, 1, 0], "expect": [0, 0, 1]},
	{"cell": [4, 4, 4], "crossed": [1, 1, 1], "toward": [-1, -1, -1], "normal": [0, 0, 1], "expect": [0, 0, 1]},
	{"cell": [0, 4, 4], "crossed": [1, 1, 0], "toward": [-1, -1, 0], "normal": [0, 0, 1], "expect": [1, 0, 0]},
	{"cell": [7, 7, 7], "crossed": [1, 1, 1], "toward": [1, 1, 1], "normal": [0, 1, 0], "expect": [0, 1, 0]},
	{"cell": [5, 5, 5], "crossed": [1, 1, 1], "toward": [1, 1, 1], "normal": [1, 0, 0], "expect": [0, 0, -1]},
]


func _extract_functions(src: String) -> String:
	var start := src.find("bool voxelOccupied")
	var fn := src.find("vec3 exposedFace")
	if start < 0 or fn < start:
		printerr("probe: functions not found in ", SHADER_PATH)
		return ""
	var brace := src.find("{", fn)
	if brace < 0:
		printerr("probe: exposedFace body not found")
		return ""
	var depth := 0
	var i := brace
	while i < src.length():
		match src[i]:
			"{":
				depth += 1
			"}":
				depth -= 1
				if depth == 0:
					return src.substr(start, i - start + 1)
		i += 1
	printerr("probe: exposedFace body not closed")
	return ""


func _build_fragment(extracted: String, case_count: int) -> String:
	return "#version 450\n" \
		+ "layout(set = 0, binding = 0) uniform sampler2D analyticalGeo;\n" \
		+ "const float threshold = 0.5;\n" \
		+ "const int volumeSize = %d;\n" % VOLUME \
		+ extracted + "\n" \
		+ "layout(set = 0, binding = 1) uniform Cases { ivec4 cdata[%d]; };\n" % (case_count * 3) \
		+ "layout(location = 0) out vec4 fragColor;\n" \
		+ "void main() {\n" \
		+ "    int i = int(gl_FragCoord.x);\n" \
		+ "    int q = i * 3;\n" \
		+ "    ivec3 cell = cdata[q].xyz;\n" \
		+ "    ivec3 toward = ivec3(cdata[q].w, cdata[q + 1].x, cdata[q + 1].y);\n" \
		+ "    bvec3 crossed = bvec3(cdata[q + 1].z != 0, cdata[q + 1].w != 0, cdata[q + 2].x != 0);\n" \
		+ "    vec3 normal = vec3(cdata[q + 2].y, cdata[q + 2].z, cdata[q + 2].w);\n" \
		+ "    vec3 r = exposedFace(cell, crossed, toward, normal);\n" \
		+ "    fragColor = vec4(r * 0.5 + 0.5, 1.0);\n" \
		+ "}\n"


func _make_tex(rd: RenderingDevice, w: int, h: int, usage: int, data: PackedByteArray) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = w
	fmt.height = h
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = usage
	var view := RDTextureView.new()
	if data.is_empty():
		data.resize(fmt.width * fmt.height * 4)
	return rd.texture_create(fmt, view, [data])


func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("RD_NULL: RenderingDevice unavailable (run non-headless, with a window)")
		quit(1)
		return
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	var extracted := _extract_functions(src)
	if extracted == "":
		rd.free()
		quit(1)
		return
	var count := CASES.size()
	var frag_src := _build_fragment(extracted, count)
	var ssrc := RDShaderSource.new()
	ssrc.source_vertex = "#version 450\nlayout(location = 0) in vec2 position;\nvoid main() { gl_Position = vec4(position, 0.0, 1.0); }\n"
	ssrc.source_fragment = frag_src
	var spirv := rd.shader_compile_spirv_from_source(ssrc)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var e := spirv.get_stage_compile_error(stage)
		if e != "":
			printerr("probe: shader compile failed: ", e)
			rd.free()
			quit(1)
			return
	var shader := rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		printerr("probe: shader link failed")
		rd.free()
		quit(1)
		return

	# Volume atlas: width = volumeSize, height = volumeSize * volumeSize; texel
	# (cell.x, cell.y + cell.z * volumeSize) holds the cell's alpha.
	var atlas := PackedByteArray()
	atlas.resize(VOLUME * VOLUME * VOLUME * 4)
	var occupied := {}
	for c in OCCUPIED:
		occupied[Vector3i(c[0], c[1], c[2])] = true
	for z in VOLUME:
		for y in VOLUME:
			for x in VOLUME:
				var idx := (y + z * VOLUME) * VOLUME + x
				atlas.encode_u8(idx * 4 + 3, 255 if occupied.has(Vector3i(x, y, z)) else 0)
	var volume_tex := _make_tex(rd, VOLUME, VOLUME * VOLUME,
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT, atlas)

	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var sampler := rd.sampler_create(ss)

	# The uniform block is std140: each ivec4 occupies 16 bytes. Per case: three
	# ivec4s holding cell, toward, crossed flags, and the fallback normal.
	var case_bytes := PackedByteArray()
	case_bytes.resize(count * 3 * 16)
	for idx in count:
		var c: Dictionary = CASES[idx]
		var vecs: Array = [
			[c["cell"][0], c["cell"][1], c["cell"][2], c["toward"][0]],
			[c["toward"][1], c["toward"][2], c["crossed"][0], c["crossed"][1]],
			[c["crossed"][2], c["normal"][0], c["normal"][1], c["normal"][2]],
		]
		for vec in 3:
			for comp in 4:
				case_bytes.encode_s32(idx * 3 * 16 + vec * 16 + comp * 4, int(vecs[vec][comp]))
	var ubo := rd.uniform_buffer_create(case_bytes.size(), case_bytes)

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u0.binding = 0
	u0.add_id(sampler)
	u0.add_id(volume_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u1.binding = 1
	u1.add_id(ubo)
	var set0 := rd.uniform_set_create([u0, u1], shader, 0)

	var target := _make_tex(rd, count, 1,
			RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT, PackedByteArray())
	var fb := rd.framebuffer_create([target])

	var verts := PackedFloat32Array([-1.0, -1.0, 3.0, -1.0, -1.0, 3.0])
	var vbuf := rd.vertex_buffer_create(verts.size() * 4, verts.to_byte_array())
	var attr := RDVertexAttribute.new()
	attr.location = 0
	attr.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	attr.stride = 8
	attr.offset = 0
	var vfmt := rd.vertex_format_create([attr])
	var varr := rd.vertex_array_create(3, vfmt, [vbuf])

	var blend := RDPipelineColorBlendState.new()
	blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())
	var pipeline := rd.render_pipeline_create(shader, rd.framebuffer_get_format(fb),
			vfmt, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, RDPipelineRasterizationState.new(),
			RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
	var dl := rd.draw_list_begin(fb, RenderingDevice.DRAW_CLEAR_COLOR_ALL,
			PackedColorArray([Color(0, 0, 0, 0)]))
	if dl == -1:
		printerr("probe: draw_list_begin failed")
		rd.free()
		quit(1)
		return
	rd.draw_list_bind_render_pipeline(dl, pipeline)
	rd.draw_list_bind_uniform_set(dl, set0, 0)
	rd.draw_list_bind_vertex_array(dl, varr)
	rd.draw_list_draw(dl, false, 1)
	rd.draw_list_end()

	var bytes := rd.texture_get_data(target, 0)
	var failures := []
	for idx in count:
		var c: Dictionary = CASES[idx]
		var got := []
		for f in 3:
			var v: float = bytes.decode_u8(idx * 4 + f) / 255.0 * 2.0 - 1.0
			got.append(int(round(v)))
		if got != c["expect"]:
			failures.append({"case": idx, "got": got, "expect": c["expect"]})
	print("NM_EDGE_FACE_PROBE: ", "PASS" if failures.is_empty() else "FAIL", " cases=", count)
	for f in failures:
		print("NM_EDGE_FACE_PROBE_FAIL case=", f["case"], " got=", f["got"], " expect=", f["expect"])
	rd.free()
	quit(0 if failures.is_empty() else 1)
