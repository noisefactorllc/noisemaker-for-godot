extends RefCounted

var rd: RenderingDevice


func _init(p_rd: RenderingDevice) -> void:
	rd = p_rd


func create_slot(index: int, descriptor: Dictionary):
	if not _valid_descriptor(descriptor):
		return null
	return {
		"index": index,
		"width": int(descriptor["width"]),
		"height": int(descriptor["height"]),
		"alpha_mode": str(descriptor["alphaMode"]),
		"source_format": -1,
		"data": PackedByteArray(),
		"pending": false,
		"ready": false,
		"destroyed": false,
		"generation": 0,
	}


func begin(slot: Dictionary, texture: RID, _timestamp: float) -> int:
	if not _usable(slot) or slot["pending"]:
		return ERR_UNAVAILABLE
	if not texture.is_valid() or not rd.texture_is_valid(texture):
		return ERR_DOES_NOT_EXIST
	var texture_format: RDTextureFormat = rd.texture_get_format(texture)
	if texture_format.width != slot["width"] or texture_format.height != slot["height"]:
		return ERR_INVALID_PARAMETER

	slot["source_format"] = texture_format.format
	slot["data"] = PackedByteArray()
	slot["pending"] = true
	slot["ready"] = false
	slot["generation"] += 1
	var generation: int = slot["generation"]
	var error := rd.texture_get_data_async(texture, 0, Callable(self, "_on_data").bind(slot, generation))
	if error != OK:
		slot["pending"] = false
		return error
	return OK


func poll(slot: Dictionary) -> bool:
	return _usable(slot) and slot["pending"] and slot["ready"]


func read(slot: Dictionary) -> Image:
	if not poll(slot):
		return null
	var image: Image = _convert(slot)
	slot["data"] = PackedByteArray()
	slot["pending"] = false
	slot["ready"] = false
	return image


func destroy_slot(slot: Dictionary) -> int:
	if slot == null or slot.get("destroyed", false):
		return OK
	slot["destroyed"] = true
	slot["generation"] += 1
	slot["pending"] = false
	slot["ready"] = false
	slot["data"] = PackedByteArray()
	return OK


func _on_data(data: PackedByteArray, slot: Dictionary, generation: int) -> void:
	if not _usable(slot) or slot["generation"] != generation or not slot["pending"]:
		return
	slot["data"] = data
	slot["ready"] = true


func _convert(slot: Dictionary) -> Image:
	var image_format := -1
	var bytes_per_pixel := 0
	match int(slot["source_format"]):
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM:
			image_format = Image.FORMAT_RGBA8
			bytes_per_pixel = 4
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			image_format = Image.FORMAT_RGBAH
			bytes_per_pixel = 8
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
			image_format = Image.FORMAT_RGBAF
			bytes_per_pixel = 16
		_:
			return null
	var expected_size: int = slot["width"] * slot["height"] * bytes_per_pixel
	if slot["data"].size() != expected_size:
		return null

	var source := Image.create_from_data(slot["width"], slot["height"], false, image_format, slot["data"])
	source.flip_y()
	var output_data := PackedByteArray()
	output_data.resize(slot["width"] * slot["height"] * 4)
	for y in slot["height"]:
		for x in slot["width"]:
			var color := source.get_pixel(x, y)
			if slot["alpha_mode"] == "opaque":
				color.a = 1.0
			elif slot["alpha_mode"] == "premultiplied":
				color.r *= color.a
				color.g *= color.a
				color.b *= color.a
			var offset: int = (y * slot["width"] + x) * 4
			output_data[offset] = _byte_from_float(color.r)
			output_data[offset + 1] = _byte_from_float(color.g)
			output_data[offset + 2] = _byte_from_float(color.b)
			output_data[offset + 3] = _byte_from_float(color.a)
	return Image.create_from_data(slot["width"], slot["height"], false, Image.FORMAT_RGBA8, output_data)


func _byte_from_float(value: float) -> int:
	return int(round(clampf(value, 0.0, 1.0) * 255.0))


func _valid_descriptor(descriptor: Dictionary) -> bool:
	if not descriptor.get("width") is int or descriptor["width"] <= 0:
		push_error("Frame export width must be a positive integer")
		return false
	if not descriptor.get("height") is int or descriptor["height"] <= 0:
		push_error("Frame export height must be a positive integer")
		return false
	if descriptor.get("format") != "rgba8unorm":
		push_error("RenderingDevice frame export format must be 'rgba8unorm'")
		return false
	if descriptor.get("colorSpace") not in ["srgb", "display-p3"]:
		push_error("RenderingDevice frame export colorSpace must be 'srgb' or 'display-p3'")
		return false
	if descriptor.get("alphaMode") not in ["opaque", "straight", "premultiplied"]:
		push_error("RenderingDevice frame export alphaMode must be 'opaque', 'straight', or 'premultiplied'")
		return false
	var fps = descriptor.get("fps")
	if not (fps is int or fps is float) or not is_finite(float(fps)) or fps <= 0:
		push_error("Frame export fps must be finite and positive")
		return false
	return true


func _usable(slot) -> bool:
	return slot is Dictionary and not slot.get("destroyed", true)
