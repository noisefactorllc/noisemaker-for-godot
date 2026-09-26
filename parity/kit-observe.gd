# Committed kit observer for the GAP-001 executable check.
#
# Mirrors the worker kit-observe.gd contract: run against an installed kit
# project, it loads the kit's main.tscn, records the displayed texture hash
# across 120 process frames, writes the first displayed frame as a PNG, and
# prints a summary line:
#
#   NM_OBSERVE frames=<n> distinct=<d> first=<h0> last=<hN> transitions=<t>
#
# Usage (non-headless; RenderingDevice needs a real window):
#   $GODOT --path "$KIT" --script <this-file> --position 5000,5000 -- "$OUT/first.png"
#
# Exit 0 with distinct > 1 means the displayed program evolves. distinct == 1
# is legitimate only for still-only programs (FRAMES=1 or a still fixture).
extends SceneTree

const OBSERVE_FRAMES := 120

var _node: Node = null
var _n := 0
var _hashes: Array = []
var _out := ""
var _saved := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "first.png"
	var scene := load("res://main.tscn")
	if scene == null:
		push_error("kit-observe: cannot load res://main.tscn")
		quit(1)
		return
	_node = scene.instantiate()
	root.add_child(_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_n += 1
	if _n > OBSERVE_FRAMES:
		return
	var tr := _node.get_node_or_null("TextureRect") as TextureRect
	var h := -1
	if tr != null and tr.texture != null:
		var img: Image = tr.texture.get_image()
		if img != null:
			var data := img.get_data()
			h = data.size()
			for i in range(0, data.size(), 997):
				h = (h * 31 + data[i]) & 0x7FFFFFFF
			if not _saved:
				_saved = true
				if img.save_png(_out) != OK:
					push_error("kit-observe: cannot write %s" % _out)
	_hashes.append(h)
	if _n >= OBSERVE_FRAMES:
		var distinct := {}
		var transitions := 0
		for i in _hashes.size():
			if _hashes[i] >= 0:
				distinct[_hashes[i]] = true
			if i > 0 and _hashes[i] >= 0 and _hashes[i - 1] >= 0 and _hashes[i] != _hashes[i - 1]:
				transitions += 1
		print("NM_OBSERVE frames=", _hashes.size(), " distinct=", distinct.size(),
				" first=", _hashes[0], " last=", _hashes[-1], " transitions=", transitions)
		quit(0)
