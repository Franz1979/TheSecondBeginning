extends Node2D

var world: World
var renderer: WorldRenderer

@onready var save_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SaveButton
@onready var back_to_world_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/BackToWorldButton

func _ready() -> void:
	save_button.text = tr("save_game")
	back_to_world_button.text = tr("back_to_world")
	save_button.pressed.connect(_on_save_pressed)
	back_to_world_button.pressed.connect(_on_back_to_world_pressed)

	world = World.new()
	world.generate_empty_world()
	var resource_service := InitialResourceSetupService.new()
	resource_service.populate_resources(world)

	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)

func _on_save_pressed() -> void:
	print("Salvataggio vista macrocella non ancora implementato.")

func _on_back_to_world_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/GameScene.tscn")
