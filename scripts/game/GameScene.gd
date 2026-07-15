extends Node2D

var world: World
var game_data: GameData
var renderer: WorldRenderer
var game_controller: CellSelectorController

@onready var back_to_menu_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var save_game_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/SaveGameButton
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/MacroCellInfoPanel
@onready var year_title_label: Label = $CanvasLayer/YearPanelContainer/HBoxContainer/YearTitleLabel
@onready var year_label: Label = $CanvasLayer/YearPanelContainer/HBoxContainer/YearLabel
@onready var advance_year_button: Button = $CanvasLayer/YearPanelContainer/HBoxContainer/AdvanceYearButton

func _ready() -> void:
	save_game_button.text = tr("save_game")
	back_to_menu_button.text = tr("back_to_menu")
	
	year_title_label.text = tr("current_year")
	advance_year_button.text = "+1"
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	save_game_button.pressed.connect(_on_save_game_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	_load_world()
	_create_renderer()
	_update_year_label()

	game_controller = CellSelectorController.new()
	game_controller.setup(world, renderer)
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
		else:
			world.ensure_cell_states()
	elif GameSettings.selected_map_type == "random":
		world = World.new()
		world.generate_empty_world()
	else:
		world = World.new()
		world.generate_empty_world()

	if game_data == null:
		game_data = GameData.new()

	var resource_service := InitialResourceSetupService.new()
	resource_service.populate_resources(world)

func _create_renderer() -> void:
	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)

func _input(event: InputEvent) -> void:
	if game_controller != null:
		game_controller.handle_input(event)
		
func _on_cell_selected(cell: MacroCellData, state: MacroCellState) -> void:
	macro_cell_info_panel.show_cell(cell, state)
	renderer.set_selected_cell(cell)
	
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
	
func _on_advance_year_pressed() -> void:
	game_data.advance_year()
	var growth_service := ResourceGrowthService.new()
	growth_service.grow_resources(world)
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(world)
	var migration_service := ResourceMigrationService.new()
	var transfers := migration_service.compute_transfers(world, leftover_surplus)
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(world)
	migration_service.apply_transfers(world, transfers)
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(world, game_data.year)
	_update_year_label()
	renderer.queue_redraw()

	if renderer.selected_cell != null:
		var state := world.get_cell_state_at(renderer.selected_cell.x, renderer.selected_cell.y)
		macro_cell_info_panel.show_cell(renderer.selected_cell, state)

func _update_year_label() -> void:
	year_label.text = str(game_data.year)
