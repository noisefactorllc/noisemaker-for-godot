extends RefCounted

var stats := {"accepted": 0, "dropped": 0, "completed": 0, "failed": 0}
var available: bool:
	get:
		if not _configured or _closed:
			return false
		for record in _slots:
			if not record["pending"]:
				return true
		return false

var adapter
var _on_error := Callable()
var _slots := []
var _configured := false
var _closed := false


func _init(p_adapter, options := {}) -> void:
	adapter = p_adapter
	var reporter = options.get("onError", Callable())
	if reporter is Callable:
		_on_error = reporter
	var slot_count = options.get("slots", 3)
	if not (slot_count is int) or slot_count < 2 or slot_count > 8:
		push_error("Frame export slots must be an integer from 2 through 8")
		_closed = true
		return
	if not _valid_adapter(adapter):
		push_error("Frame export adapter must implement create_slot, begin, poll, read, and destroy_slot")
		_closed = true
		return
	for _index in slot_count:
		_slots.append(_empty_record())


func configure(descriptor: Dictionary) -> int:
	if _closed:
		return ERR_UNAVAILABLE
	var destroy_error := _destroy_slots()
	_configured = false
	if destroy_error != OK:
		return destroy_error

	for index in _slots.size():
		var adapter_slot = adapter.call("create_slot", index, descriptor)
		if adapter_slot == null:
			var cleanup_error := _destroy_slots()
			if cleanup_error != OK:
				_report(cleanup_error)
			return ERR_CANT_CREATE
		_slots[index]["adapter_slot"] = adapter_slot
		_slots[index]["created"] = true
	_configured = true
	return OK


func enqueue(texture, timestamp: float, on_frame: Callable, context = null) -> bool:
	if not on_frame.is_valid():
		push_error("Frame export callback must be a valid Callable")
		return false
	if not _configured or _closed:
		stats["dropped"] += 1
		return false

	var record = null
	for candidate in _slots:
		if not candidate["pending"]:
			record = candidate
			break
	if record == null:
		stats["dropped"] += 1
		return false

	record["pending"] = true
	record["texture"] = texture
	record["timestamp"] = timestamp
	record["on_frame"] = on_frame
	record["context"] = context
	var begin_error = adapter.call("begin", record["adapter_slot"], texture, timestamp)
	if begin_error is int and begin_error != OK:
		_release(record)
		stats["failed"] += 1
		_report(begin_error)
		return false

	stats["accepted"] += 1
	return true


func poll() -> void:
	if not _configured or _closed:
		return
	for record in _slots:
		if not record["pending"]:
			continue
		var ready = adapter.call("poll", record["adapter_slot"])
		if not (ready is bool):
			_release(record)
			stats["failed"] += 1
			_report(ERR_INVALID_DATA)
			continue
		if not ready:
			continue
		var frame = adapter.call("read", record["adapter_slot"])
		if frame == null:
			_release(record)
			stats["failed"] += 1
			_report(ERR_CANT_ACQUIRE_RESOURCE)
			continue
		var timestamp = record["timestamp"]
		var on_frame: Callable = record["on_frame"]
		var context = record["context"]
		_release(record)
		if not on_frame.is_valid():
			stats["failed"] += 1
			_report(ERR_INVALID_PARAMETER)
			continue
		on_frame.call(frame, timestamp, context)
		stats["completed"] += 1


func close(options := {}) -> void:
	if _closed:
		return
	_closed = true
	_configured = false
	if options.get("backendLost", false):
		_abandon_slots()
	else:
		var destroy_error := _destroy_slots()
		if destroy_error != OK:
			_report(destroy_error)
	adapter = null


func _valid_adapter(candidate) -> bool:
	if not (candidate is Object):
		return false
	for method in ["create_slot", "begin", "poll", "read", "destroy_slot"]:
		if not candidate.has_method(method):
			return false
	return true


func _empty_record() -> Dictionary:
	return {
		"adapter_slot": null,
		"created": false,
		"pending": false,
		"texture": null,
		"timestamp": 0.0,
		"on_frame": Callable(),
		"context": null,
	}


func _release(record: Dictionary) -> void:
	record["pending"] = false
	record["texture"] = null
	record["timestamp"] = 0.0
	record["on_frame"] = Callable()
	record["context"] = null


func _destroy_slots() -> int:
	var first_error := OK
	for record in _slots:
		if not record["created"]:
			continue
		var adapter_slot = record["adapter_slot"]
		record["created"] = false
		record["adapter_slot"] = null
		_release(record)
		var destroy_error = adapter.call("destroy_slot", adapter_slot)
		if destroy_error is int and destroy_error != OK and first_error == OK:
			first_error = destroy_error
	return first_error


func _abandon_slots() -> void:
	for record in _slots:
		record["created"] = false
		record["adapter_slot"] = null
		_release(record)


func _report(error_value) -> void:
	if _on_error.is_valid():
		_on_error.call(error_value)
