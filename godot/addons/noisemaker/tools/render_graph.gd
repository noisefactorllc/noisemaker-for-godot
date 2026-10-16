# render_graph.gd — offline candidate renderer (the analog of Unity's NMParityRunner).
# Runs a normalized render-graph through the RenderingDevice executor and writes a PNG. MUST run
# non-headless (RenderingDevice is null under --headless); position the window offscreen.
#
# Graph source (one of):
#   --dsl <abs.dsl>     build the graph IN-ENGINE via the GDScript compiler (self-contained; no
#                       reference / export-graph.mjs). This is the production path.
#   --graph <abs.json>  read a pre-normalized graph JSON (e.g. a reference golden, for parity diffing).
#   --batch-manifest <abs.json>  render every request in one Godot application launch.
#
#   Godot --path godot --script res://addons/noisemaker/tools/render_graph.gd \
#         --position 5000,5000 -- (--dsl <abs.dsl> | --graph <abs.json>) --out <abs.png> --size 256
extends SceneTree

const Orchestrator := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var graph_path := ""
	var dsl_path := ""
	var batch_manifest_path := ""
	var out_path := ""
	var size := 256
	var run_seconds := 0       # >0 => timed-sampling mode for stateful sims
	var sample_every_sec := 5
	var texture_pooling := false
	var media_fixture := false
	var render_scale := 1
	var tiles := Vector2i.ZERO # nonzero => tiled-export mode: stitch tile canvases
	var tile_margin := 0
	var i := 0
	while i < a.size():
		match a[i]:
			"--batch-manifest":
				batch_manifest_path = a[i + 1]; i += 2
			"--graph":
				graph_path = a[i + 1]; i += 2
			"--dsl":
				dsl_path = a[i + 1]; i += 2
			"--out":
				out_path = a[i + 1]; i += 2
			"--size":
				size = int(a[i + 1]); i += 2
			"--run-seconds":
				run_seconds = int(a[i + 1]); i += 2
			"--sample-every":
				sample_every_sec = int(a[i + 1]); i += 2
			"--texture-pooling":
				texture_pooling = true; i += 1
			"--media-fixture":
				media_fixture = true; i += 1
			"--render-scale":
				render_scale = int(a[i + 1]); i += 2
			"--tiles":
				var parts: PackedStringArray = a[i + 1].split("x")
				tiles = Vector2i(int(parts[0]), int(parts[1])); i += 2
			"--tile-margin":
				tile_margin = int(a[i + 1]); i += 2
			_:
				i += 1
	if batch_manifest_path != "":
		_run_batch(batch_manifest_path)
		return
	if (graph_path == "" and dsl_path == "") or out_path == "":
		printerr("usage: -- (--dsl <dsl> | --graph <json>) --out <png> [--size 256] [--run-seconds N --sample-every S] | --batch-manifest <json>")
		quit(1); return
	var ok := _render_request(graph_path, dsl_path, out_path, size, run_seconds, sample_every_sec,
			texture_pooling, media_fixture, render_scale, tiles, tile_margin)
	quit(0 if ok else 1)


func _run_batch(manifest_path: String) -> void:
	var src := FileAccess.get_file_as_string(manifest_path)
	var manifest = JSON.parse_string(src)
	if not (manifest is Dictionary) or not (manifest.get("entries", null) is Array):
		printerr("bad batch manifest: ", manifest_path)
		quit(1); return
	var all_ok := true
	for request in manifest["entries"]:
		if not (request is Dictionary):
			printerr("bad batch request in: ", manifest_path)
			all_ok = false
			continue
		var ok := _render_request(
			str(request.get("graph", "")), str(request.get("dsl", "")),
			str(request.get("out", "")), int(request.get("size", 256)),
			int(request.get("run_seconds", 0)), int(request.get("sample_every", 5)),
			bool(request.get("texture_pooling", false)))
		print("NM_BATCH name=", request.get("name", "unknown"), " ok=", ok)
		all_ok = all_ok and ok
	quit(0 if all_ok else 1)


func _render_request(graph_path: String, dsl_path: String, out_path: String, size: int,
		run_seconds: int, sample_every_sec: int, texture_pooling: bool = false,
		media_fixture: bool = false, render_scale: int = 1,
		tiles: Vector2i = Vector2i.ZERO, tile_margin: int = 0) -> bool:
	if (graph_path == "" and dsl_path == "") or out_path == "":
		printerr("bad render request: graph/dsl and out are required")
		return false

	var graph
	if dsl_path != "":
		# Self-contained path: compile the DSL to a render graph in-engine. Compile
		# BEFORE the RenderingDevice check so an invalid program is reported as an actionable
		# NM_COMPILE_DIAG diagnostic without rendering, even in headless runs.
		var src := FileAccess.get_file_as_string(dsl_path)
		if src == "":
			printerr("cannot read dsl: ", dsl_path)
			return false
		var reg := EffectRegistry.new()
		reg.load_all()
		graph = Orchestrator.new(reg).build_graph(src)
	else:
		var f := FileAccess.open(graph_path, FileAccess.READ)
		if f == null:
			printerr("cannot read graph: ", graph_path)
			return false
		graph = JSON.parse_string(f.get_as_text())
		f.close()
	if typeof(graph) != TYPE_DICTIONARY:
		printerr("bad graph: ", graph_path if graph_path != "" else dsl_path)
		return false
	if graph.has("compileError"):
		# The compiler rejected the DSL before expansion; the orchestrator already
		# printed each NM_COMPILE_DIAG line to stderr. Nothing renders, and the request fails.
		printerr("compile failed (stage=", graph["compileError"].get("stage", ""), "): no render")
		return false

	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("RD_NULL: RenderingDevice unavailable (run non-headless, with a window)")
		return false

	if tiles != Vector2i.ZERO:
		# Tiled-export mode: the graph renders once untiled at the full render
		# size, then once per tile at the canvas size, and the tile interiors are
		# stitched into <out>. The untiled frame lands next to <out> so a checker
		# can compare stitched against untiled directly.
		var tiled_ok := _render_tiled(rd, graph, out_path, size, render_scale, tiles,
				tile_margin)
		rd.free()
		return tiled_ok

	var full_px := Vector2i(size * render_scale, size * render_scale)
	var backend := Backend.new()
	backend.setup(rd, "res://addons/noisemaker", full_px)
	if render_scale != 1:
		backend._render_scale = float(render_scale)
	if not _upload_external_overlays(backend, graph, out_path):
		backend.close()
		rd.free()
		return false
	if media_fixture and not _upload_media_fixture(backend, graph):
		backend.close()
		rd.free()
		return false
	var ok := _render_with_backend(backend, graph, out_path, run_seconds, sample_every_sec,
		texture_pooling)
	# Release the backend's GPU handles, then the device. A batch creates one device per
	# request, and leaked devices exhaust the driver (Vulkan device creation fails with
	# VK_ERROR_DEVICE_LOST after about 22 on NVIDIA).
	backend.close()
	rd.free()
	return ok


# Tiled-export renderer (the reference's calculateTileGrid): render the full frame
# untiled at full size * render_scale, then render the same graph per tile on a
# canvas of (tile + 2*margin) * render_scale with the backend's tile context set,
# crop each canvas's interior, and stitch the interiors into the full frame. The
# untiled frame lands at <out-base>.untiled.png; <out> receives the stitch.
func _render_tiled(rd: RenderingDevice, graph: Dictionary, out_path: String, size: int,
		render_scale: int, tiles: Vector2i, tile_margin: int) -> bool:
	var full := Vector2i(size, size)
	if full.x % tiles.x != 0 or full.y % tiles.y != 0:
		printerr("tiles: full size ", full, " must be a multiple of the tile size ", tiles)
		return false
	var full_px := Vector2i(full.x * render_scale, full.y * render_scale)
	var canvas_px := Vector2i((tiles.x + 2 * tile_margin) * render_scale,
			(tiles.y + 2 * tile_margin) * render_scale)
	var untiled_path := out_path.get_basename().trim_suffix(".candidate") + ".untiled.png"

	var ubackend := Backend.new()
	ubackend.setup(rd, "res://addons/noisemaker", full_px)
	if render_scale != 1:
		ubackend._render_scale = float(render_scale)
	if not _upload_external_overlays(ubackend, graph, out_path):
		ubackend.close()
		return false
	ubackend.render(graph)
	var untiled_ok := ubackend.save_surface_png(untiled_path)
	ubackend.close()
	if not untiled_ok:
		printerr("tiles: untiled reference render failed")
		return false

	var stitched := Image.create(full_px.x, full_px.y, false, Image.FORMAT_RGBA8)
	var cols := full.x / tiles.x
	var rows := full.y / tiles.y
	for j in rows:
		for i in cols:
			# tileOffset is the canvas origin in full-render pixels, GL space:
			# the canvas extends tile_margin pixels beyond the tile on every side.
			var origin := Vector2(float((i * tiles.x - tile_margin) * render_scale),
					float((j * tiles.y - tile_margin) * render_scale))
			var backend := Backend.new()
			backend.setup(rd, "res://addons/noisemaker", canvas_px)
			if render_scale != 1:
				backend._render_scale = float(render_scale)
			backend.set_tile_context(full_px, origin)
			if not _upload_external_overlays(backend, graph, out_path):
				backend.close()
				return false
			backend.render(graph)
			var canvas_img: Image = backend._snapshot_surface()
			backend.close()
			if canvas_img == null:
				printerr("tiles: canvas readback failed for tile ", i, ",", j)
				return false
			# _snapshot_surface is top-down; the canvas is symmetric around its
			# center, so the tile interior is the central (tile*rs) square on
			# both axes regardless of the flip.
			var crop := canvas_img.get_region(Rect2i(tile_margin * render_scale,
					tile_margin * render_scale, tiles.x * render_scale,
					tiles.y * render_scale))
			# GL rows run bottom-up; place tile row j so the stitch matches the
			# flipped untiled frame.
			var dst := Vector2i(i * tiles.x * render_scale,
					full_px.y - (j + 1) * tiles.y * render_scale)
			stitched.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), dst)
	var save_ok: bool = stitched.save_png(out_path) == OK
	print("NM_TILED tiles=", cols, "x", rows, " canvas=", canvas_px, " full=", full_px,
			" untiled=", untiled_path, " out=", out_path, " ok=", save_ok)
	return save_ok


func _upload_external_overlays(backend: Backend, graph: Dictionary, out_path: String) -> bool:
	var bindings := []
	for pass_data in graph.get("passes", []):
		var func_name := str(pass_data.get("func", ""))
		if func_name != "text" and func_name != "fibers" \
				and func_name != "scratches" and func_name != "strayHair":
			continue
		var inputs: Dictionary = pass_data.get("inputs", {})
		var uniform_name := "textTex" if inputs.has("textTex") else "overlayTex"
		var texture_id := str(inputs.get(uniform_name, ""))
		if texture_id != "":
			bindings.append({"uniform": uniform_name, "texture_id": texture_id})
	var prefix := out_path.get_basename().trim_suffix(".candidate")
	for index in range(bindings.size()):
		var binding: Dictionary = bindings[index]
		var path: String = prefix + ".external." + binding["uniform"] + "." + str(index) + ".png"
		if not FileAccess.file_exists(path):
			printerr("missing external overlay: ", path)
			return false
		var image := Image.new()
		if image.load(path) != OK or not backend.upload_external_texture(binding["texture_id"], image, false):
			printerr("external overlay upload failed: ", path)
			return false
	return true


func _upload_media_fixture(backend: Backend, graph: Dictionary) -> bool:
	var texture_ids := {}
	for pass_data in graph.get("passes", []):
		if pass_data.get("func", "") == "media":
			var texture_id := str(pass_data.get("inputs", {}).get("imageTex", ""))
			if texture_id != "":
				texture_ids[texture_id] = true
	if texture_ids.is_empty():
		printerr("media fixture: graph has no image texture")
		return false
	var pixels := PackedByteArray()
	pixels.resize(64 * 64 * 4)
	for y in 64:
		for x in 64:
			var i := (y * 64 + x) * 4
			pixels[i] = x * 4
			pixels[i + 1] = (63 - y) * 4
			pixels[i + 2] = (x ^ (63 - y)) * 4
			pixels[i + 3] = 255
	for texture_id in texture_ids:
		var format := RDTextureFormat.new()
		format.width = 64
		format.height = 64
		format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var rid: RID = backend.rd.texture_create(format, RDTextureView.new(), [pixels])
		if not rid.is_valid():
			printerr("media fixture: texture allocation failed")
			return false
		backend._owned_textures[rid] = true
		backend._textures[texture_id] = rid
		backend._tex_dims[texture_id] = Vector2i(64, 64)
	print("NM_MEDIA_FIXTURE textures=", texture_ids.size())
	return true


func _render_with_backend(backend: Backend, graph: Dictionary, out_path: String, run_seconds: int,
		sample_every_sec: int, texture_pooling: bool) -> bool:
	# Opt-in texture pooling (--texture-pooling / batch request key).
	if texture_pooling:
		backend.set_texture_pooling(true)
	if run_seconds > 0:
		# Timed-sampling mode (stateful sims): run run_seconds of sim-time at 60fps, capturing
		# every sample_every_sec into <out-basename>.t<sec>.png (e.g. navierStokes.candidate.t5.png).
		var total_frames := run_seconds * 60
		var every := max(1, sample_every_sec * 60)
		var imgs = backend.render_samples(graph, total_frames, every)
		var base := out_path.get_basename()
		var all_ok := imgs.size() > 0
		for idx in imgs.size():
			var sec := (idx + 1) * sample_every_sec
			var sp := "%s.t%d.png" % [base, sec]
			var simg = imgs[idx]
			var sok: bool = simg != null and simg.save_png(sp) == OK
			all_ok = all_ok and sok
			print("NM_SAMPLE t=", sec, " out=", sp, " ok=", sok)
		print("NM_RENDERED_SAMPLES n=", imgs.size(), " surface=", backend.render_surface_tex)
		return all_ok
	backend.render(graph)
	# Surface the last structured shader/compile diagnostic (reference
	# f83a427e): a black candidate on a runner usually means a pass silently failed
	# to compile/link; the diagnostic union names the stage and program.
	var diag = backend.last_shader_diagnostic
	if diag != null and not diag.is_empty():
		var dline := ("NM_SHADER_DIAG code=" + str(diag.get("code", ""))
			+ " severity=" + str(diag.get("severity", ""))
			+ " stage=" + str(diag.get("stage", ""))
			+ " program=" + str(diag.get("program", ""))
			+ " detail=" + str(diag.get("detail", "")).substr(0, 200))
		print(dline)
		# push_error goes to stderr, so the diagnostic survives harness tails
		# that keep only the last stderr lines of a native run.
		printerr(dline)
	var stats := backend.get_pass_stats()
	var sline := ("NM_PASS_STATS executed=" + str(stats.get("executed", 0))
		+ " skipped=" + str(stats.get("skipped", 0))
		+ " surface_valid=" + str(backend.render_surface_texture().is_valid()))
	print(sline)
	printerr(sline)
	# Side-car for native-runner attribution: harness tails keep only the last
	# line of the final (compare) command, so persist the render diagnostics
	# next to the candidate PNG where compare.py's degenerate handler can
	# quote them into its error line.
	var diag_lines := sline
	if diag != null and not diag.is_empty():
		diag_lines = ("NM_SHADER_DIAG code=" + str(diag.get("code", ""))
			+ " severity=" + str(diag.get("severity", ""))
			+ " stage=" + str(diag.get("stage", ""))
			+ " program=" + str(diag.get("program", ""))
			+ " detail=" + str(diag.get("detail", "")).substr(0, 200)) + "\n" + sline
	var stats_path := out_path.get_basename().trim_suffix(".candidate") + ".passstats.txt"
	var sf := FileAccess.open(stats_path, FileAccess.WRITE)
	if sf != null:
		sf.store_string(diag_lines + "\n")
		sf.close()
	if texture_pooling:
		# Observable evidence for the opt-in run: the materialized sharing plan.
		var plan: Dictionary = backend.get_resource_plan(graph)
		print("NM_RESOURCE_PLAN pooling=", plan["pooling"], " sharedTextures=", plan["sharedTextures"])
	var ok = backend.save_surface_png(out_path)
	print("NM_RENDERED out=", out_path, " surface=", backend.render_surface_tex, " ok=", ok)
	return ok
