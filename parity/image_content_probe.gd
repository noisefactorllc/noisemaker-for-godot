extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("IMAGE_CONTENT_TEST: expected manifest path")
		quit(1)
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not (manifest is Dictionary):
		printerr("IMAGE_CONTENT_TEST: invalid manifest")
		quit(1)
		return

	var blank_fallbacks := {"media": true, "remap": true, "roll": true}
	var failures := []
	for entry in manifest.get("entries", []):
		var name := str(entry.get("name", ""))
		var expected_size := int(entry.get("size", 0))
		var image := Image.load_from_file(str(entry.get("out", "")))
		if image == null or image.is_empty():
			failures.append("%s did not decode" % name)
			continue
		if image.get_width() != expected_size or image.get_height() != expected_size:
			failures.append("%s dimensions=%dx%d expected=%d" % [
				name, image.get_width(), image.get_height(), expected_size,
			])
			continue

		var first := image.get_pixel(0, 0)
		var varies := false
		var max_rgb := 0.0
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				max_rgb = max(max_rgb, pixel.r, pixel.g, pixel.b)
				if not pixel.is_equal_approx(first):
					varies = true

		if blank_fallbacks.has(name):
			if max_rgb > 1.0 / 255.0:
				failures.append("%s no-input fallback was not black" % name)
		elif not varies:
			failures.append("%s rendered a constant image" % name)

		if name == "mesh":
			var background := image.get_pixel(0, 0)
			if abs(background.r - 0.1) > 0.02 \
					or abs(background.g - 0.1) > 0.02 \
					or abs(background.b - 0.15) > 0.02:
				failures.append("mesh background clear missing: %s" % background)

	if not failures.is_empty():
		printerr("IMAGE_CONTENT_TEST: FAIL ", failures)
		quit(1)
		return
	print("IMAGE_CONTENT_TEST: PASS entries=", manifest.get("entries", []).size())
	quit(0)
