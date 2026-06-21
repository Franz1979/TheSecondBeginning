extends Node2D

var world: World
var renderer: WorldRenderer

@onready var back_to_menu_button: Button = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var save_map_button: Button = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/SaveMapButton

func _ready() -> void:
	if GameSettings.selected_save_file != "":
		var load_service := WorldLoadService.new()
		world = load_service.load_world_from_json(GameSettings.selected_save_file)

		if world == null:
			print("Caricamento fallito. Genero una nuova mappa.")
			world = World.new()
			world.generate_empty_world()
	else:
		world = World.new()
		world.generate_empty_world()

	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)

	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	save_map_button.pressed.connect(_on_save_map_pressed)

func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_save_map_pressed() -> void:
	var save_service := WorldSaveService.new()

	save_service.save_world_to_json(
		world,
		"user://small_island.json"
	)
