# Godot project exported from Noisedeck.
#
# The four calls below are the addon's documented consumer surface, from the
# port's README. RenderingDevice is null under --headless, so run with a window.
extends Control

const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Orchestrator := preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
const Backend := preload("res://addons/noisemaker/runtime/nm_backend.gd")

const SIZE := 512

func _ready() -> void:
	var dsl := FileAccess.get_file_as_string("res://program.dsl")
	if dsl.is_empty():
		push_error("cannot read res://program.dsl")
		return

	var rd := RenderingServer.create_local_rendering_device()
	var reg := EffectRegistry.new()
	reg.load_all()
	var graph = Orchestrator.new(reg).build_graph(dsl)

	var backend := Backend.new()
	backend.setup(rd, "res://addons/noisemaker", Vector2i(SIZE, SIZE))
	var img: Image = backend.render_samples(graph, 1, 1)[0]
	$TextureRect.texture = ImageTexture.create_from_image(img)
