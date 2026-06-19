extends Node2D

var world: World
var renderer: WorldRenderer

func _ready() -> void:
	world = World.new()
	world.generate_empty_world()

	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)
