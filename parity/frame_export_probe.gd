extends SceneTree

const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")


class CaptureSink extends RefCounted:
	var descriptor := {}
	var submissions := []
	var closes := 0

	func configure(value: Dictionary) -> void:
		descriptor = value

	func submit(texture: RID, timestamp: float) -> bool:
		submissions.append([texture, timestamp])
		return true

	func close(_options := {}) -> void:
		closes += 1


func _texture(rd: RenderingDevice, format: int, data: PackedByteArray) -> RID:
	var texture_format := RDTextureFormat.new()
	texture_format.width = 4
	texture_format.height = 2
	texture_format.format = format
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(texture_format, RDTextureView.new(), [data])


func _descriptor(alpha_mode: String) -> Dictionary:
	return {
		"width": 4,
		"height": 2,
		"format": "rgba8unorm",
		"colorSpace": "srgb",
		"alphaMode": alpha_mode,
		"fps": 60.0,
	}


func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("FRAME_EXPORT_TEST: RenderingDevice unavailable")
		quit(1)
		return

	var backend = Backend.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(4, 2))
	var values := PackedFloat32Array()
	for _pixel in 4:
		values.append_array([2.0, 0.002, 0.5, 0.25])
	for _pixel in 4:
		values.append_array([0.0, 1.0, 0.0, 1.0])
	var float_source := _texture(rd, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, values.to_byte_array())
	var byte_values := PackedByteArray()
	for _pixel in 4:
		byte_values.append_array(PackedByteArray([200, 100, 50, 64]))
	for _pixel in 4:
		byte_values.append_array(PackedByteArray([10, 20, 30, 128]))
	var byte_source := _texture(rd, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, byte_values)
	var half_image := Image.create(4, 2, false, Image.FORMAT_RGBAH)
	for x in 4:
		half_image.set_pixel(x, 0, Color(0.0, 0.0, 1.0, 0.25))
		half_image.set_pixel(x, 1, Color(0.25, 0.5, 0.75, 0.125))
	var half_source := _texture(rd, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, half_image.get_data())
	var capture_sink := CaptureSink.new()
	var remove_sink: Callable = backend.add_sink(capture_sink)
	var textures: Dictionary = backend.get("_textures")
	textures["probe"] = float_source
	backend.set("_textures", textures)
	backend.render_surface_tex = "probe"
	backend.call("_submit_render_surface", 456.25)
	var sink_ok: bool = capture_sink.descriptor.get("width") == 4 \
		and capture_sink.descriptor.get("height") == 2 \
		and capture_sink.submissions == [[float_source, 456.25]]
	remove_sink.call()
	sink_ok = sink_ok and capture_sink.closes == 1
	var premultiplied_queue = backend.create_frame_export_queue({"slots": 2})
	var straight_queue = backend.create_frame_export_queue({"slots": 2})
	var opaque_queue = backend.create_frame_export_queue({"slots": 2})
	if premultiplied_queue.configure(_descriptor("premultiplied")) != OK \
		or straight_queue.configure(_descriptor("straight")) != OK \
		or opaque_queue.configure(_descriptor("opaque")) != OK:
		printerr("FRAME_EXPORT_TEST: queue configuration failed")
		quit(1)
		return

	var premultiplied := {"frame": null, "timestamp": -1.0, "context": null}
	var straight := {"frame": null}
	var opaque := {"frame": null}
	var enqueued: bool = premultiplied_queue.enqueue(float_source, 123.5, func(frame, timestamp, context):
		premultiplied["frame"] = frame
		premultiplied["timestamp"] = timestamp
		premultiplied["context"] = context,
		{"sequence": 7})
	enqueued = straight_queue.enqueue(byte_source, 234.5, func(frame, _timestamp, _context): straight["frame"] = frame) and enqueued
	enqueued = opaque_queue.enqueue(half_source, 345.5, func(frame, _timestamp, _context): opaque["frame"] = frame) and enqueued
	if not enqueued:
		printerr("FRAME_EXPORT_TEST: enqueue failed")
		quit(1)
		return

	for _frame in 120:
		rd.submit()
		rd.sync()
		await process_frame
		premultiplied_queue.poll()
		straight_queue.poll()
		opaque_queue.poll()
		if premultiplied["frame"] != null and straight["frame"] != null and opaque["frame"] != null:
			break

	var premultiplied_image: Image = premultiplied["frame"]
	var straight_image: Image = straight["frame"]
	var opaque_image: Image = opaque["frame"]
	var premultiplied_bytes := PackedByteArray() if premultiplied_image == null else premultiplied_image.get_data()
	var straight_bytes := PackedByteArray() if straight_image == null else straight_image.get_data()
	var opaque_bytes := PackedByteArray() if opaque_image == null else opaque_image.get_data()
	var metadata_ok: bool = premultiplied["timestamp"] == 123.5 and premultiplied["context"] == {"sequence": 7}
	var pixels_ok: bool = premultiplied_image != null and straight_image != null and opaque_image != null \
		and premultiplied_bytes.slice(0, 4) == PackedByteArray([0, 255, 0, 255]) \
		and premultiplied_bytes.slice(16, 20) == PackedByteArray([128, 0, 32, 64]) \
		and straight_bytes.slice(0, 4) == PackedByteArray([10, 20, 30, 128]) \
		and straight_bytes.slice(16, 20) == PackedByteArray([200, 100, 50, 64]) \
		and opaque_bytes.slice(0, 4) == PackedByteArray([64, 128, 191, 255]) \
		and opaque_bytes.slice(16, 20) == PackedByteArray([0, 0, 255, 255])
	premultiplied_queue.close()
	straight_queue.close()
	opaque_queue.close()
	backend.close()
	rd.free_rid(float_source)
	rd.free_rid(byte_source)
	rd.free_rid(half_source)

	if sink_ok and metadata_ok and pixels_ok:
		print("FRAME_EXPORT_TEST: PASS premultiplied=", premultiplied_bytes.slice(16, 20),
			" straight=", straight_bytes.slice(16, 20), " opaque=", opaque_bytes.slice(0, 4))
		quit(0)
	else:
		printerr("FRAME_EXPORT_TEST: FAIL premultiplied=", premultiplied_bytes,
			" straight=", straight_bytes, " opaque=", opaque_bytes, " metadata=", premultiplied)
		quit(1)
