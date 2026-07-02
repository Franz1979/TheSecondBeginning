extends Node2D

var world: World
var game_data: GameData
var renderer: WorldRenderer
var game_controller: MapEditorController

@onready var back_to_menu_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var save_game_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/SaveGameButton
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/MacroCellInfoPanel

func _ready() -> void:
	save_game_button.text = tr("save_game")
	back_to_menu_button.text = tr("back_to_menu")
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	save_game_button.pressed.connect(_on_save_game_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	_load_world()
	game_data = GameData.new()
	_create_renderer()
	
	game_controller = MapEditorController.new()
	game_controller.setup(world, renderer)
	game_controller.set_terrain_brush(MapEditorController.TerrainBrush.NONE)
	game_controller.cell_selected.connect(_on_cell_selected)

	macro_cell_info_panel.visible = true

func _load_world() -> void:
	if GameSettings.selected_save_file != "":
		var load_service := GameLoadService.new()
		var loaded_game := load_service.load_game_from_json(GameSettings.selected_save_file)

		if loaded_game == null:
			print("Caricamento partita fallito. Genero mondo vuoto.")
			game_data = GameData.new()
			world = World.new()
			world.generate_empty_world()
			return

		world = loaded_game.world
		game_data = loaded_game.game_data
		return

	if GameSettings.selected_map_type == "saved" and GameSettings.selected_map_file != "":
		var load_service := WorldLoadService.new()
		world = load_service.load_world_from_json(GameSettings.selected_map_file)

		if world == null:
			print("Caricamento mappa fallito. Genero mondo vuoto.")
			world = World.new()
			world.generate_empty_world()

	elif GameSettings.selected_map_type == "random":
		world = World.new()
		world.generate_empty_world()

	else:
		world = World.new()
		world.generate_empty_world()

	if game_data == null:
		game_data = GameData.new()


func _create_renderer() -> void:
	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)

func _input(event: InputEvent) -> void:
	if game_controller != null:
		game_controller.handle_input(event)
		
func _on_cell_selected(cell: MacroCellData) -> void:
	macro_cell_info_panel.show_cell(cell)
	
func _on_save_game_pressed() -> void:
	save_game_file_dialog.popup_centered()
	
func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()

	save_service.save_game_to_json(
		world,
		game_data,
		path
	)
	
func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/NewGameMenu.tscn")
