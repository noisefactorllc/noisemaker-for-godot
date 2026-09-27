extends SceneTree
# Measures nm_backend._capture_byte (the quantizer used by _snapshot_surface)
# across a value sweep and emits "QUANT <i> <byte>" lines. The pytest wrapper
# judges the bytes against a Python transliteration of the reference capture
# spec (JS Math.round(v*255): half-up, clamped to [0,255]); end-to-end PNG
# capture equivalence is evidenced by the committed comparator receipts
# (GAP-002 round 2026-09-27).
func _init():
	var Backend = preload("res://addons/noisemaker/runtime/nm_backend.gd")
	for i in range(0, 20001):
		var v := float(i) / 20000.0
		var got: int = Backend._capture_byte(v)
		print("QUANT %d %d" % [i, got])
	quit(0)
