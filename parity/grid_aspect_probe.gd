# grid_aspect_probe.gd — headless image probe for the heightGrid aspect test.
# Loads PNGs given as repeated --png arguments, finds the bounding box of pixels
# that differ from the corner background color, and prints one NM_BBOX line per
# image with the min/max x and y of that box.
extends SceneTree

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var paths := []
	var i := 0
	while i < a.size():
		if a[i] == "--png" and i + 1 < a.size():
			paths.append(a[i + 1])
			i += 2
		elif not a[i].begins_with("-"):
			paths.append(a[i])
			i += 1
		else:
			i += 1
	if paths.is_empty():
		printerr("usage: -- --png <abs.png> [--png <abs.png> ...]")
		quit(1)
		return
	var ok := true
	for path in paths:
		var img := Image.new()
		var err := img.load(path)
		if err != OK:
			printerr("probe: cannot load ", path)
			ok = false
			continue
		var w := img.get_width()
		var h := img.get_height()
		var corners := [
			img.get_pixel(0, 0), img.get_pixel(w - 1, 0),
			img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1),
		]
		var bg := Color(0.0, 0.0, 0.0)
		for c: Color in corners:
			bg += c
		bg /= 4.0
		var x0 := w
		var x1 := -1
		var y0 := h
		var y1 := -1
		for y in h:
			for x in w:
				var p := img.get_pixel(x, y)
				var d: float = max(absf(p.r - bg.r), max(absf(p.g - bg.g), absf(p.b - bg.b)))
				if d > 12.0 / 255.0:
					if x < x0: x0 = x
					if x > x1: x1 = x
					if y < y0: y0 = y
					if y > y1: y1 = y
		if x1 < 0:
			print("NM_BBOX path=", path, " empty=1")
			ok = false
			continue
		print("NM_BBOX path=", path, " x0=", x0, " x1=", x1, " y0=", y0, " y1=", y1)
	quit(0 if ok else 1)
