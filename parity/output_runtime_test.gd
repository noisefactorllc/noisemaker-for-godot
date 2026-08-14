extends SceneTree

const SinkManager := preload("res://addons/noisemaker/runtime/sink.gd")
const FrameExportQueue := preload("res://addons/noisemaker/runtime/frame_export.gd")
const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")


class FakeSink extends RefCounted:
	var configured := []
	var submitted := []
	var closes := 0
	var on_submit := Callable()
	var accept := true

	func configure(descriptor: Dictionary) -> void:
		configured.append(descriptor)

	func submit(texture, timestamp: float) -> bool:
		submitted.append([texture, timestamp])
		if on_submit.is_valid():
			on_submit.call()
		return accept

	func close() -> void:
		closes += 1


class FakeAdapter extends RefCounted:
	var slots := []

	func create_slot(index: int, descriptor: Dictionary):
		var slot := {
			"index": index,
			"descriptor": descriptor,
			"ready": false,
			"frame": null,
			"destroyed": 0,
		}
		slots.append(slot)
		return slot

	func begin(slot: Dictionary, texture, timestamp: float) -> int:
		slot["texture"] = texture
		slot["timestamp"] = timestamp
		slot["ready"] = false
		return OK

	func poll(slot: Dictionary) -> bool:
		return slot["ready"]

	func read(slot: Dictionary):
		return slot["frame"]

	func destroy_slot(slot: Dictionary) -> int:
		slot["destroyed"] += 1
		return OK

	func complete(index: int, frame) -> void:
		slots[index]["frame"] = frame
		slots[index]["ready"] = true


class CallbackTarget extends Node:
	var frames := []

	func receive(frame, timestamp, context) -> void:
		frames.append([frame, timestamp, context])


var _ok := true


func _init() -> void:
	_test_sink_manager()
	_test_frame_export_queue()
	_test_backend_api()
	print("OUTPUT_RUNTIME_TEST: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _test_sink_manager() -> void:
	var manager = SinkManager.new()
	var descriptor := {
		"width": 16,
		"height": 8,
		"format": "rgba8unorm",
		"colorSpace": "srgb",
		"alphaMode": "straight",
		"fps": 60.0,
	}
	manager.configure(descriptor)

	var first := FakeSink.new()
	var second := FakeSink.new()
	second.accept = false
	var remove_first: Callable = manager.add(first)
	manager.add(second)
	first.on_submit = func(): remove_first.call()

	_expect(first.configured == [descriptor] and second.configured == [descriptor], "late sinks receive the active descriptor")
	manager.submit("frame-a", 12.5)
	_expect(first.submitted.size() == 1 and first.closes == 1, "a sink can remove itself during submission")
	_expect(second.submitted == [["frame-a", 12.5]], "removal does not skip later sinks")
	_expect(manager.stats[second] == {"accepted": 0, "dropped": 1, "failed": 0}, "sink outcomes are counted")

	remove_first.call()
	manager.close()
	manager.close()
	_expect(first.closes == 1 and second.closes == 1, "removal and manager close are idempotent")


func _test_frame_export_queue() -> void:
	var adapter := FakeAdapter.new()
	var queue = FrameExportQueue.new(adapter, {"slots": 2})
	var received := []
	var descriptor := {
		"width": 4,
		"height": 2,
		"format": "rgba8unorm",
		"colorSpace": "srgb",
		"alphaMode": "straight",
		"fps": 60.0,
	}

	_expect(not queue.enqueue("unconfigured", 0.0, func(_frame, _timestamp, _context): pass), "unconfigured exports drop")
	_expect(queue.configure(descriptor) == OK and queue.available, "queue configures a bounded reusable ring")
	_expect(queue.enqueue("first", 10.0, func(frame, timestamp, context): received.append([frame, timestamp, context]), {"sequence": 1}), "first frame is accepted")
	_expect(queue.enqueue("second", 20.0, func(_frame, _timestamp, _context): pass), "second frame is accepted")
	_expect(not queue.available and not queue.enqueue("overflow", 30.0, func(_frame, _timestamp, _context): pass), "full queue drops without blocking")

	adapter.complete(0, "frame-one")
	queue.poll()
	_expect(received == [["frame-one", 10.0, {"sequence": 1}]], "poll preserves frame metadata and context")
	_expect(queue.available and queue.stats == {"accepted": 2, "dropped": 2, "completed": 1, "failed": 0}, "completed slots are reusable with stable stats")

	queue.close()
	queue.close()
	_expect(adapter.slots[0]["destroyed"] == 1 and adapter.slots[1]["destroyed"] == 1, "queue destroys every slot exactly once")
	_expect(not queue.enqueue("closed", 40.0, func(_frame, _timestamp, _context): pass), "closed queue is terminal")

	var invalid_adapter := FakeAdapter.new()
	var delivery_errors := []
	var invalid_queue = FrameExportQueue.new(invalid_adapter, {
		"slots": 2,
		"onError": func(error): delivery_errors.append(error),
	})
	invalid_queue.configure(descriptor)
	var target := CallbackTarget.new()
	invalid_queue.enqueue("orphaned", 50.0, Callable(target, "receive"))
	target.free()
	invalid_adapter.complete(0, "orphaned-frame")
	invalid_queue.poll()
	_expect(invalid_queue.available and invalid_queue.stats["completed"] == 0 \
		and invalid_queue.stats["failed"] == 1 and delivery_errors == [ERR_INVALID_PARAMETER],
		"a callback invalidated during readback fails delivery without stranding its slot")
	invalid_queue.close()


func _test_backend_api() -> void:
	var backend = Backend.new()
	_expect(backend.has_method("add_sink"), "backend exposes sink registration")
	_expect(backend.has_method("create_frame_export_queue"), "backend exposes asynchronous frame export")
	_expect(backend.has_method("close"), "backend exposes terminal sink cleanup")


func _expect(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_ok = false
