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
			_:
				i += 1
	if batch_manifest_path != "":
		_run_batch(batch_manifest_path)
		return
	if (graph_path == "" and dsl_path == "") or out_path == "":
		printerr("usage: -- (--dsl <dsl> | --graph <json>) --out <png> [--size 256] [--run-seconds N --sample-every S] | --batch-manifest <json>")
		quit(1); return
	var ok := _render_request(graph_path, dsl_path, out_path, size, run_seconds, sample_every_sec, texture_pooling)
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
		run_seconds: int, sample_every_sec: int, texture_pooling: bool = false) -> bool:
	if (graph_path == "" and dsl_path == "") or out_path == "":
		printerr("bad render request: graph/dsl and out are required")
		return false
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("RD_NULL: RenderingDevice unavailable (run non-headless, with a window)")
		return false

	var graph
	if dsl_path != "":
		# Self-contained path: compile the DSL to a render graph in-engine.
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

	var Backend = preload("res://addons/noisemaker/runtime/nm_backend.gd")
	var backend = Backend.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(size, size))
	# GAP-006 opt-in texture pooling (--texture-pooling / batch request key).
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
	# Surface the last structured shader/compile diagnostic (GAP-006 sync, reference
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
