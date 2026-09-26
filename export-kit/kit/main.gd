# Godot project exported from Noisedeck.
#
# The preloads below are the addon's documented consumer surface, from the
# port's README. RenderingDevice is null under --headless, so run with a window.
#
# Playback model (see README, "Editing it"):
#   1. The program is stepped FRAMES simulated frames at 60 fps, capturing one
#      still of the render surface every SAMPLE_EVERY frames.
#   2. The captured stills then loop in the window at PLAYBACK_FPS.
# The compute pass is one blocking call, so the window is frozen while it runs;
# the scene shows a warning first (the Status label) before it starts.
extends Control

const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")

const SIZE := 512
const FRAMES := 1800
const SAMPLE_EVERY := 60
const PLAYBACK_FPS := 5

var _stills: Array = []
var _index := 0
var _accumulator := 0.0

func _ready() -> void:
	var dsl := FileAccess.get_file_as_string("res://program.dsl")
	if dsl.is_empty():
		push_error("cannot read res://program.dsl")
		return

	$Status.text = "Rendering %d frames — the window is frozen until this finishes." % FRAMES
	# Paint the warning before the blocking compute pass.
	await get_tree().process_frame

	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("RenderingDevice unavailable")
		return
	var reg := EffectRegistry.new()
	reg.load_all()
	var graph = Orchestrator.new(reg).build_graph(dsl)

	var backend := Backend.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(SIZE, SIZE))
	# One still every SAMPLE_EVERY frames of simulated 60 fps time. Programs
	# made only of still effects can set FRAMES to 1; when no interval boundary
	# falls inside the run (e.g. FRAMES=1), fall back to the single still frame.
	_stills = backend.render_samples(graph, FRAMES, SAMPLE_EVERY)
	if _stills.is_empty():
		_stills = backend.render_samples(graph, 1, 1)
	if _stills.is_empty():
		push_error("render produced no frames")
		return

	$Status.text = ""
	_show_frame(0)

func _process(delta: float) -> void:
	if _stills.size() < 2:
		return
	_accumulator += delta
	var frame_time := 1.0 / max(PLAYBACK_FPS, 1)
	while _accumulator >= frame_time:
		_accumulator -= frame_time
		_index = (_index + 1) % _stills.size()
		_show_frame(_index)

func _show_frame(index: int) -> void:
	$TextureRect.texture = ImageTexture.create_from_image(_stills[index])
