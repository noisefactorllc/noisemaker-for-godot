extends RefCounted

var stats := {}

var _on_error := Callable()
var _registrations := []
var _registrations_by_sink := {}
var _descriptor := {}
var _configured := false
var _closed := false
var _iteration_depth := 0
var _has_tombstones := false


func _init(options := {}) -> void:
	var reporter = options.get("onError", Callable())
	if reporter is Callable:
		_on_error = reporter


func add(sink) -> Callable:
	if _closed:
		push_error("SinkManager is closed")
		return Callable()
	if not _valid_sink(sink):
		push_error("Sink must implement configure, submit, and close")
		return Callable()
	if _registrations_by_sink.has(sink):
		push_error("Sink is already registered")
		return Callable()

	if _configured:
		sink.call("configure", _descriptor)

	var registration := {
		"sink": sink,
		"stats": {"accepted": 0, "dropped": 0, "failed": 0},
		"active": true,
	}
	_registrations.append(registration)
	_registrations_by_sink[sink] = registration
	stats[sink] = registration["stats"]
	return Callable(self, "_remove_registration").bind(registration)


func remove(sink) -> void:
	_remove_registration(_registrations_by_sink.get(sink))


func configure(descriptor := {}) -> void:
	if _closed:
		return
	_descriptor = descriptor if descriptor != null else {}
	_configured = true
	_iteration_depth += 1
	for registration in _registrations:
		if registration["active"]:
			registration["sink"].call("configure", _descriptor)
	_iteration_depth -= 1
	if _iteration_depth == 0:
		_compact_registrations()


func submit(texture, timestamp: float) -> void:
	if _closed:
		return
	_iteration_depth += 1
	for registration in _registrations:
		if not registration["active"]:
			continue
		var sink = registration["sink"]
		var result = sink.call("submit", texture, timestamp)
		if result is bool:
			if result:
				registration["stats"]["accepted"] += 1
			else:
				registration["stats"]["dropped"] += 1
		else:
			registration["stats"]["failed"] += 1
			_report("Sink submit must return a boolean", sink)
	_iteration_depth -= 1
	if _iteration_depth == 0:
		_compact_registrations()


func close(options := {}) -> void:
	if _closed:
		return
	_closed = true
	for registration in _registrations:
		if not registration["active"]:
			continue
		var sink = registration["sink"]
		registration["active"] = false
		registration["sink"] = null
		_close_sink(sink, options)
	_registrations.clear()
	_registrations_by_sink.clear()
	stats.clear()
	_has_tombstones = false


func _valid_sink(sink) -> bool:
	return sink is Object and sink.has_method("configure") and sink.has_method("submit") and sink.has_method("close")


func _remove_registration(registration) -> void:
	if registration == null or not registration["active"]:
		return
	var sink = registration["sink"]
	registration["active"] = false
	registration["sink"] = null
	_has_tombstones = true
	if _registrations_by_sink.get(sink) == registration:
		_registrations_by_sink.erase(sink)
		stats.erase(sink)
	_close_sink(sink, {})
	if _iteration_depth == 0:
		_compact_registrations()


func _compact_registrations() -> void:
	if not _has_tombstones:
		return
	var active := []
	for registration in _registrations:
		if registration["active"]:
			active.append(registration)
	_registrations = active
	_has_tombstones = false


func _report(message: String, sink) -> void:
	if _on_error.is_valid():
		_on_error.call(message, sink)


func _close_sink(sink, options: Dictionary) -> void:
	for method in sink.get_method_list():
		if method["name"] != "close":
			continue
		var accepts_options: bool = not method["args"].is_empty() \
			or (int(method["flags"]) & METHOD_FLAG_VARARG) != 0
		if accepts_options:
			sink.call("close", options)
		else:
			sink.call("close")
		return
