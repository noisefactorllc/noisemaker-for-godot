extends SceneTree

const Registry = preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator = preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const ADDON := "res://addons/noisemaker"

class ProbeBackend extends "res://addons/noisemaker/runtime/nm_backend.gd":
	func _load_vertex(ns: String, fn: String, prog: String) -> String:
		if fn == "blendProbe":
			return """#version 450
const vec2 corners[6] = vec2[6](vec2(-1,-1), vec2(1,-1), vec2(-1,1),
    vec2(-1,1), vec2(1,-1), vec2(1,1));
void main() { gl_Position = vec4(corners[gl_VertexIndex], 0, 1); }
"""
		return super._load_vertex(ns, fn, prog)

	func _load_fragment(ns: String, fn: String, prog: String) -> String:
		if fn == "blendProbe":
			var colour := "0.5, 0.25, 0.125, 0.25" if prog == "base" else "0.25, 0.5, 0.75, 0.5"
			return "#version 450\nlayout(location = 0) out vec4 fragColor;\nvoid main() { fragColor = vec4(" + colour + "); }"
		if fn == "clockProbe":
			return "#version 450\nlayout(location = 0) out vec4 fragColor;\nvoid main() { fragColor = vec4(deltaTime, time, 0.0, 1.0); }"
		if fn == "storageProbe":
			return "#version 450\nlayout(location = 0) out vec4 outputBuffer;\nvoid main() { outputBuffer = vec4(1.0, 0.5, 0.25, 1.0); }"
		if fn == "copyProbe":
			return "#version 450\nlayout(set = 0, binding = 1) uniform sampler2D inputTex;\nlayout(location = 0) out vec4 fragColor;\nvoid main() { fragColor = texelFetch(inputTex, ivec2(gl_FragCoord.xy), 0); }"
		return super._load_fragment(ns, fn, prog)

func _register(reg, backend, definition: Dictionary) -> void:
	reg._register_effect(definition)
	backend._effect_defs[definition.namespace + "/" + definition.func] = definition

func _check_pixels(backend, expected: Color, label: String) -> bool:
	var img: Image = backend._snapshot_surface()
	if img == null:
		printerr(label, ": no rendered image")
		return false
	for y in img.get_height():
		for x in img.get_width():
			var pixel := img.get_pixel(x, y)
			for channel in 4:
				if abs(pixel[channel] - expected[channel]) > 1.0 / 255.0:
					printerr(label, ": expected ", expected, " got ", pixel, " at ", Vector2i(x, y))
					return false
	return true

func _render(reg, backend, source: String, time: float, expected: Color, label: String) -> bool:
	var graph = Orchestrator.new(reg).build_graph("search synth\n" + source + ".write(o0)\nrender(o0)")
	if graph.has("compileError"):
		printerr(label, ": ", graph)
		return false
	backend.render(graph, time)
	return _check_pixels(backend, expected, label)

func _check_blending(reg, backend) -> bool:
	var source := Color(0.25, 0.5, 0.75, 0.5)
	var destination := Color(0.5, 0.25, 0.125, 0.25)
	var cases := [
		[["ONE", "ZERO"], source],
		[["one", "zero"], source],
		[["ONE", "ONE"], source + destination],
		[["SRC_COLOR", "ZERO"], source * source],
		[["src-color", "zero"], source * source],
		[["ZERO", "DST_COLOR"], destination * destination],
		[["zero", "dst-color"], destination * destination],
		[["ONE_MINUS_SRC_COLOR", "ZERO"], source * (Color(1, 1, 1, 1) - source)],
		[["one-minus-src-color", "zero"], source * (Color(1, 1, 1, 1) - source)],
		[["ZERO", "ONE_MINUS_DST_COLOR"], destination * (Color(1, 1, 1, 1) - destination)],
		[["zero", "one-minus-dst-color"], destination * (Color(1, 1, 1, 1) - destination)]]
	for item in cases:
		_register(reg, backend, {"namespace": "synth", "func": "blendProbe", "globals": {},
			"passes": [
				{"program": "base", "outputs": {"fragColor": "outputTex"}},
				{"program": "overlay", "drawMode": "billboards", "count": 1,
					"outputs": {"fragColor": "outputTex"}, "blend": item[0]}]})
		if not _render(reg, backend, "blendProbe()", 0.25, item[1], "blend " + str(item[0])):
			return false
	print("NM_BLEND_FACTORS: PASS")
	return true

func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("RD_NULL: runtime target probe needs a RenderingDevice")
		quit(1)
		return
	var backend := ProbeBackend.new()
	backend.setup(rd, ADDON, Vector2i(8, 8))
	var reg = Registry.new()
	reg.load_all()
	_register(reg, backend, {"namespace": "synth", "func": "clockProbe", "globals": {},
		"passes": [{"program": "main", "outputs": {"fragColor": "outputTex"}}]})
	var ok := true
	var times := [0.0, 0.125, 0.875, 0.0625, 0.0625, 0.0]
	var deltas := [0.0, 0.125, 0.75, 0.1875, 0.0, 0.9375]
	for i in times.size():
		ok = _render(reg, backend, "clockProbe()", times[i], Color(deltas[i], times[i], 0, 1), "clock frame %s" % i) and ok
	_register(reg, backend, {"namespace": "synth", "func": "copyProbe", "globals": {},
		"passes": [{"program": "main", "inputs": {"inputTex": "inputTex"}, "outputs": {"fragColor": "outputTex"}}]})
	for target in ["work", "outputTex"]:
		var definition := {"namespace": "synth", "func": "storageProbe", "globals": {},
			"passes": [{"program": "fill", "type": "compute", "storageTextures": {"outputBuffer": target}}]}
		if target == "work":
			definition["textures"] = {"work": {"width": "100%", "height": "100%", "format": "rgba8unorm"}}
			definition["outputTex"] = "work"
		_register(reg, backend, definition)
		for suffix in ["", ".copyProbe()"]:
			ok = _render(reg, backend, "solid(color: #404040)" + suffix, 0.25, Color(64.0 / 255, 64.0 / 255, 64.0 / 255, 1), "recompile precondition") and ok
			ok = _render(reg, backend, "storageProbe()" + suffix, 0.25, Color(1, 0.5, 0.25, 1), target + suffix) and ok
	ok = _check_blending(reg, backend) and ok
	backend.close()
	rd.free()
	print("NM_RUNTIME_TARGETS: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
