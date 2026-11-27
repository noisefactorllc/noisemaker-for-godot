extends SceneTree

const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")


func _float_texture(backend, values: PackedFloat32Array) -> RID:
	return backend.call("_make_sampled_float_tex", values.size() / 4, 1, values)


func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("MESH_PIPELINE_TEST: RenderingDevice unavailable")
		quit(1)
		return

	var registry := EffectRegistry.new()
	registry.load_all()
	var source := """search render, synth

meshLoader().meshRender().write(o0)

render(o0)
"""
	var graph: Dictionary = Orchestrator.new(registry).build_graph(source)
	var backend = Backend.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(64, 64))
	backend.allocate_textures(graph)

	var triangle_pass: Dictionary
	for pass_spec in graph["passes"]:
		if pass_spec.get("drawMode") == "triangles":
			triangle_pass = pass_spec
		for key in ["ambientColor", "specularColor", "specularIntensity", "rimIntensity"]:
			if pass_spec.get("func") == "meshRender":
				pass_spec["uniforms"][key] = [0.0, 0.0, 0.0] if key.ends_with("Color") else 0.0
		if pass_spec.get("func") == "meshRender":
			pass_spec["uniforms"]["bgColor"] = [0.1, 0.2, 0.3]
			pass_spec["uniforms"]["bgAlpha"] = 1.0
			pass_spec["uniforms"]["lightDirection"] = [0.0, 0.0, 1.0]
			pass_spec["uniforms"]["diffuseColor"] = [1.0, 1.0, 1.0]
			pass_spec["uniforms"]["diffuseIntensity"] = 1.0
			pass_spec["uniforms"]["meshColor"] = [1.0, 1.0, 1.0]

	if triangle_pass.is_empty():
		printerr("MESH_PIPELINE_TEST: triangle pass missing")
		quit(1)
		return

	# Overlapping CCW triangles on the left test depth. The clockwise triangle on the
	# right tests culling; a later CCW copy makes the resolved mesh count observable.
	var positions := PackedFloat32Array([
		-0.9, -0.6, -1.0, 1.0,  -0.1, -0.6, -1.0, 1.0,  -0.5, 0.6, -1.0, 1.0,
		-0.9, -0.6,  1.0, 1.0,  -0.1, -0.6,  1.0, 1.0,  -0.5, 0.6,  1.0, 1.0,
		 0.1, -0.6,  0.0, 1.0,   0.5,  0.6,  0.0, 1.0,   0.9, -0.6,  0.0, 1.0,
		 0.1, -0.6,  0.0, 1.0,   0.9, -0.6,  0.0, 1.0,   0.5,  0.6,  0.0, 1.0,
	])
	var normals := PackedFloat32Array()
	normals.resize(positions.size())
	for vertex in positions.size() / 4:
		normals[vertex * 4 + 2] = -1.0 if vertex >= 3 and vertex < 6 else 1.0

	var position_id := str(triangle_pass["inputs"]["meshPositions"])
	var normal_id := str(triangle_pass["inputs"]["meshNormals"])
	var textures: Dictionary = backend.get("_textures")
	textures[position_id] = _float_texture(backend, positions)
	textures[normal_id] = _float_texture(backend, normals)
	backend.set("_textures", textures)
	var dimensions: Dictionary = backend.get("_tex_dims")
	dimensions[position_id] = Vector2i(12, 1)
	dimensions[normal_id] = Vector2i(12, 1)
	backend.set("_tex_dims", dimensions)

	for mode in ["depth-cull", "auto", "screen", "fallback"]:
		triangle_pass["count"] = 9 if mode == "depth-cull" else "screen" if mode == "fallback" else mode
		triangle_pass["countUniform"] = "vertices"
		triangle_pass["uniforms"]["vertices"] = 0
		if mode == "fallback":
			dimensions.erase(position_id)
			backend.set("_tex_dims", dimensions)
		backend.call("_begin_frame")
		for pass_spec in graph["passes"]:
			if not backend.execute_pass(pass_spec):
				printerr("MESH_PIPELINE_TEST: pass failed ", mode)
				quit(1); return
			backend.call("_update_frame_bindings", pass_spec)
		backend.call("_end_frame")
		rd.submit()
		rd.sync()

		var image: Image = backend.call("_snapshot_surface")
		var left := image.get_pixel(18, 32)
		var right := image.get_pixel(46, 32)
		var depth_ok: bool = left.r > 0.9 and left.g > 0.9 and left.b > 0.9
		var right_ok: bool
		if mode == "auto" or mode == "screen":
			right_ok = right.r > 0.9 and right.g > 0.9 and right.b > 0.9
		else:
			right_ok = abs(right.r - 0.1) < 0.02 and abs(right.g - 0.2) < 0.02 and abs(right.b - 0.3) < 0.02
		if not depth_ok or not right_ok:
			printerr("MESH_PIPELINE_TEST: FAIL ", mode, " left=", left, " right=", right)
			quit(1); return
		print("MESH_PIPELINE_TEST: PASS ", mode, " left=", left, " right=", right)
	backend.close()
	rd.free()
	quit(0)
