extends SceneTree

# Lifecycle probe: repeated backend create/render/resize/dispose cycles over a
# live RenderingDevice with resource accounting, plus active export
# cancellation before device destruction.
#
# Usage (non-headless; RenderingDevice needs a real window + device):
#   $GODOT --path godot --script res://parity/lifecycle_probe.gd --position 5000,5000
#
# Exit 0 with LIFECYCLE_TEST: PASS when, across CYCLES backend lifecycles:
#   - tracked_handle_count() is flat across repeated same-size renders AND a
#     recreation at a new size (a flat count means re-renders and resizes
#     release every replaced allocation);
#   - an ACTIVE frame export (readback recorded, callback not yet delivered)
#     is cancelled by backend.close() with no late callback firing;
#   - after close() the retained count is 0 and the consumer's device free is
#     leak-free (the unit test scans the process output for engine leaked-handle
#     warnings, which is where the device free report lands).

const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")

const CYCLES := 4


func _fail(message: String) -> void:
	printerr("LIFECYCLE_TEST: FAIL ", message)
	quit(1)


func _init() -> void:
	var registry := EffectRegistry.new()
	registry.load_all()
	var adjust_graph: Dictionary = Orchestrator.new(registry).build_graph(
		"search synth, filter\nnoise(seed: 1, scaleX: 50, scaleY: 50).adjust().write(o0)\nrender(o0)\n")
	var feedback_graph: Dictionary = Orchestrator.new(registry).build_graph(
		"search synth, filter\nnoise(seed: 1, scaleX: 50, scaleY: 50).feedback().write(o0)\nrender(o0)\n")
	if adjust_graph.get("passes", []).is_empty() or feedback_graph.get("passes", []).is_empty():
		_fail("graph build failed")
		return

	for cycle in CYCLES:
		var rd := RenderingServer.create_local_rendering_device()
		if rd == null:
			_fail("RenderingDevice unavailable (cycle %d)" % cycle)
			return
		var backend = Backend.new()
		backend.setup(rd, "res://addons/noisemaker", Vector2i(64, 64))
		var counts := []
		for size in [[64, 64], [64, 64], [96, 64], [96, 64]]:
			backend.screen = Vector2i(int(size[0]), int(size[1]))
			backend.render(adjust_graph, 0.25)
			backend.render(feedback_graph, 0.25)
			counts.append(int(backend.tracked_handle_count()))
		if counts[0] != counts[1] or counts[2] != counts[3] or counts[0] != counts[2]:
			_fail("retained handle count not flat across repeated renders and a resize: " + str(counts))
			return

		# Consumer-owned texture injection (the frame-export probe's "probe"
		# scenario): a texture the consumer allocated is aliased into the
		# backend's texture map and survives teardown — the backend must free
		# only what it allocated, never an injected RID.
		var external_format := RDTextureFormat.new()
		external_format.width = 8
		external_format.height = 8
		external_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		external_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
		var external := rd.texture_create(external_format, RDTextureView.new())
		backend.render(adjust_graph, 0.25)
		var injected: Dictionary = backend.get("_textures")
		injected["consumer_probe"] = external
		backend.set("_textures", injected)
		backend.render_surface_tex = "consumer_probe"
		backend.call("_submit_render_surface", 789.0)

		# Active frame-export cancellation: record an async readback of the
		# render surface (in flight — not yet submitted, callback undelivered),
		# then tear the backend down and assert the close cancelled it with no
		# late callback.
		backend.render(adjust_graph, 0.25)
		var queue = backend.create_frame_export_queue({})
		var descriptor := {"width": 64, "height": 64, "format": "rgba8unorm",
			"colorSpace": "srgb", "alphaMode": "straight", "fps": 60.0}
		if int(queue.configure(descriptor)) != OK:
			_fail("frame export queue configure failed (cycle %d)" % cycle)
			return
		var late_frames := []
		var accepted: bool = queue.enqueue(backend.render_surface_texture(), 1.0,
			func(frame, timestamp, context) -> void: late_frames.append(timestamp))
		if not accepted:
			_fail("active frame export enqueue failed (cycle %d)" % cycle)
			return
		backend.close()
		if int(backend.tracked_handle_count()) != 0:
			_fail("backend close left %d retained handles (cycle %d)" % [
				int(backend.tracked_handle_count()), cycle])
			return
		# The consumer-owned injected texture survives teardown; the consumer
		# frees it itself (as the frame-export probe does after backend.close).
		if not rd.texture_is_valid(external):
			_fail("backend close freed a consumer-owned injected texture (cycle %d)" % cycle)
			return
		rd.free_rid(external)
		# Cancelled queue: no new export may be accepted after teardown, and no
		# late callback can have fired (close dropped the pending record).
		var dropped_after_close: bool = not queue.enqueue(
			backend.render_surface_texture(), 2.0,
			func(frame, timestamp, context) -> void: late_frames.append(timestamp))
		if not dropped_after_close or not late_frames.is_empty():
			_fail("active export not cancelled by close (cycle %d)" % cycle)
			return
		# Consumer-owned device destruction AFTER backend close: engine-side
		# leaked-handle warnings (if any backend-owned RID survived) print to
		# the process output and are scanned by parity/test_lifecycle.py.
		rd.free()

	print("LIFECYCLE_TEST: PASS cycles=%d" % CYCLES)
	quit(0)
