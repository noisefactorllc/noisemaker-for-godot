extends SceneTree

const EFFECTS_DIR := "res://addons/noisemaker/effects"
const SHADERS_DIR := "res://addons/noisemaker/shaders/effects"


func _read_json(path: String):
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed


func _default_defines(definition: Dictionary) -> Dictionary:
	var defines := {}
	for global_spec in definition.get("globals", {}).values():
		if global_spec is Dictionary and global_spec.has("define") and global_spec.get("default") != null:
			defines[str(global_spec["define"])] = global_spec["default"]
	return defines


# Compile the default define set plus every individual selector value with all other
# selectors held at default. This covers every inactive #if branch without a Cartesian
# explosion across unrelated selectors.
func _define_variants(definition: Dictionary) -> Array:
	var defaults := _default_defines(definition)
	var variants := [defaults]
	var seen := {JSON.stringify(defaults): true}
	for global_spec in definition.get("globals", {}).values():
		if not (global_spec is Dictionary) or not global_spec.has("define"):
			continue
		var values := []
		var choices = global_spec.get("choices")
		if choices is Dictionary:
			for value in choices.values():
				if value != null:
					values.append(value)
		elif str(global_spec.get("type", "")) == "boolean":
			values = [false, true]
		for value in values:
			var variant := defaults.duplicate()
			variant[str(global_spec["define"])] = value
			var variant_key := JSON.stringify(variant)
			if not seen.has(variant_key):
				seen[variant_key] = true
				variants.append(variant)
	return variants


func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("SHADER_SWEEP: RenderingDevice unavailable")
		quit(1)
		return

	var backend_script = load("res://addons/noisemaker/runtime/nm_backend.gd")
	var backend = backend_script.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(32, 32))
	var missing := []
	var failed := []
	var compiled := 0
	var attempted := 0
	var probe_frames := {}

	for namespace_name in DirAccess.get_directories_at(EFFECTS_DIR):
		var definition_dir := EFFECTS_DIR.path_join(namespace_name)
		for filename in DirAccess.get_files_at(definition_dir):
			if not filename.ends_with(".json"):
				continue
			var definition = _read_json(definition_dir.path_join(filename))
			if not (definition is Dictionary):
				failed.append("%s/%s: invalid definition JSON" % [namespace_name, filename])
				continue
			var effect := str(definition.get("func", filename.get_basename()))
			for pass_spec in definition.get("passes", []):
				var program := str(pass_spec.get("program", effect))
				var shader_key := "%s/%s/%s" % [namespace_name, effect, program]
				var fragment_path := SHADERS_DIR.path_join(shader_key + ".glsl")
				if not FileAccess.file_exists(fragment_path):
					missing.append(fragment_path)
					continue

				var raw_fragment = backend.call("_load_fragment", namespace_name, effect, program)
				var pass_defines: Dictionary = pass_spec.get("defines", {})
				for defines in _define_variants(definition):
					var merged_defines: Dictionary = defines.duplicate()
					for k in pass_defines:
						merged_defines[str(k)] = pass_defines[k]
					var inject := ""
					for define_name in merged_defines:
						inject += "#define %s %s\n" % [
							define_name,
							backend.call("_format_define_value", define_name, merged_defines[define_name], definition, raw_fragment),
						]
					var runtime_pass := {"progName": program}
					if not backend.call("_has_layout", definition, runtime_pass):
						inject += backend.call(
							"_synth_header",
							backend.call("_synth_layout", namespace_name, effect, definition.get("globals", {})),
						)
					var fragment = backend.call("_inject_after_version", raw_fragment, inject)
					var vertex = backend_script.FULLSCREEN_VS
					if str(pass_spec.get("drawMode", "")) in ["points", "billboards", "triangles"]:
						var vertex_path := SHADERS_DIR.path_join(shader_key + ".vert.glsl")
						if not FileAccess.file_exists(vertex_path):
							missing.append(vertex_path)
							continue
						var raw_vertex: String = backend.call("_resolve_includes", FileAccess.get_file_as_string(vertex_path))
						vertex = backend.call("_inject_after_version", raw_vertex, inject)

					var probe_key := "sweep/%s/%d" % [shader_key, attempted]
					attempted += 1
					var shader: RID = backend.call("_get_shader", probe_key, vertex, fragment)
					if not shader.is_valid():
						failed.append("%s %s" % [shader_key, merged_defines])
						continue

					# On Metal, shader creation can return a valid RID before the
					# backend compiles its library. Creating a pipeline checks that stage.
					var attachment_count := int(pass_spec.get("drawBuffers", 1))
					if not probe_frames.has(attachment_count):
						var textures := []
						for _i in attachment_count:
							textures.append(backend.call("_make_tex", 32, 32, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT))
						probe_frames[attachment_count] = rd.framebuffer_create(textures)
					var fb: RID = probe_frames[attachment_count]
					if not fb.is_valid():
						failed.append("%s %s: framebuffer" % [shader_key, merged_defines])
						continue
					var mode := str(pass_spec.get("drawMode", ""))
					var custom := mode in ["points", "billboards", "triangles"]
					var primitive := RenderingDevice.RENDER_PRIMITIVE_POINTS if mode == "points" else RenderingDevice.RENDER_PRIMITIVE_TRIANGLES
					var vfmt: int = backend.get("_vfmt_empty") if custom else backend.get("_vfmt")
					var pipeline: RID = backend.call("_get_pipeline", probe_key, shader,
						rd.framebuffer_get_format(fb), attachment_count, primitive,
						{"enable": false, "key": "rep"}, vfmt, false)
					if not pipeline.is_valid():
						failed.append("%s %s: pipeline" % [shader_key, merged_defines])
						continue
					compiled += 1

	if not missing.is_empty():
		printerr("SHADER_SWEEP missing=", missing)
	if not failed.is_empty():
		printerr("SHADER_SWEEP failed=", failed)
	var ok := missing.is_empty() and failed.is_empty()
	print("SHADER_SWEEP compiled=%d missing=%d failed=%d" % [compiled, missing.size(), failed.size()])
	quit(0 if ok else 1)
