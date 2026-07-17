extends Node2D

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]

var world: World
var macro_world: World
var macro_cell: MacroCellData
var macro_state: MacroCellState
var game_data: GameData
var renderer: MicroCellRenderer

@onready var save_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SaveButton
@onready var back_to_world_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/BackToWorldButton
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var year_title_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/HBoxContainer/YearTitleLabel
@onready var year_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/HBoxContainer/YearLabel
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/HBoxContainer/AdvanceYearButton
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellInfoPanel

func _ready() -> void:
	save_button.text = tr("save_game")
	back_to_world_button.text = tr("back_to_world")
	year_title_label.text = tr("current_year")
	advance_year_button.text = "+1"
	save_button.pressed.connect(_on_save_pressed)
	back_to_world_button.pressed.connect(_on_back_to_world_pressed)
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	macro_world = GameSettings.active_world
	game_data = GameSettings.active_game_data
	if game_data == null:
		push_warning("Nessun game_data condiviso: creo un anno locale di riserva.")
		game_data = GameData.new()

	if macro_world != null:
		macro_cell = macro_world.get_cell_at(GameSettings.selected_macro_cell_x, GameSettings.selected_macro_cell_y)

	world = World.new()
	if macro_cell != null:
		world.generate_uniform_terrain(macro_cell.terrain_base, macro_cell.water_type, macro_cell.coast_type)
	else:
		push_warning("Macrocella non trovata: genero un mondo vuoto di riserva.")
		world.generate_empty_world()

	# Niente InitialResourceSetupService qui: è logica di test pensata per il mondo macro
	# (stone random al centro, trees/grass/shrub forzati in 50,50) e non ha senso per la
	# vista microcella finché non esiste un vero modello di risorse per microcella.

	renderer = MicroCellRenderer.new()
	add_child(renderer)
	renderer.setup(world)
	if macro_cell != null and macro_world != null:
		renderer.set_neighbors(_get_neighbor_cells(macro_cell), _get_neighbor_states(macro_cell))

		macro_state = macro_world.get_cell_state_at(macro_cell.x, macro_cell.y)
		if macro_state != null:
			if macro_cell.water_type == GameTypes.WaterType.RIVER:
				var thickness_ratio: float = float(macro_state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
				renderer.set_river(macro_cell.river_shape, thickness_ratio)

			var stone_service := StonePositionService.new()
			stone_service.generate_if_needed(macro_state)
			renderer.set_stone_positions(macro_state.stone_positions)

			_refresh_resource_visuals()

	_update_year_label()

# Grass/shrub/tree non sono persistite (a differenza di stone): vanno ricalcolate ogni
# volta che la loro quantità può essere cambiata, cioè all'apertura della scena e a ogni
# avanzamento anno fatto da qui, così la vegetazione "cresce"/cambia a vista mentre si
# resta dentro MacroCellScene, non solo riaprendola. Lo stesso vale per i numeri nel
# pannello info, che vanno tenuti aggiornati insieme.
func _refresh_resource_visuals() -> void:
	if macro_state == null:
		return

	var occupied: Dictionary = {}
	for pos in macro_state.stone_positions:
		occupied[pos] = true

	var vegetation_service := VegetationPositionService.new()
	renderer.set_vegetation_positions(vegetation_service.generate_positions(macro_state, occupied))

	macro_cell_info_panel.show_cell(macro_cell, macro_state)

func _get_neighbor_cells(macro_cell: MacroCellData) -> Dictionary:
	var neighbors: Dictionary = {}
	for offset in NEIGHBOR_OFFSETS:
		neighbors[offset] = macro_world.get_cell_at(macro_cell.x + offset.x, macro_cell.y + offset.y)
	return neighbors

func _get_neighbor_states(macro_cell: MacroCellData) -> Dictionary:
	var states: Dictionary = {}
	for offset in NEIGHBOR_OFFSETS:
		states[offset] = macro_world.get_cell_state_at(macro_cell.x + offset.x, macro_cell.y + offset.y)
	return states

func _on_save_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo macro condiviso: impossibile salvare.")
		return
	save_game_file_dialog.popup_centered()

func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()
	save_service.save_game_to_json(macro_world, game_data, path)

func _on_advance_year_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo macro condiviso: impossibile avanzare l'anno.")
		return

	game_data.advance_year()
	var growth_service := ResourceGrowthService.new()
	growth_service.grow_resources(macro_world)
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(macro_world)
	var migration_service := ResourceMigrationService.new()
	var transfers := migration_service.compute_transfers(macro_world, leftover_surplus)
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(macro_world)
	migration_service.apply_transfers(macro_world, transfers)
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(macro_world, game_data.year)
	_refresh_resource_visuals()
	_update_year_label()

func _update_year_label() -> void:
	year_label.text = str(game_data.year)

func _on_back_to_world_pressed() -> void:
	GameSettings.returning_to_game_scene = true
	get_tree().change_scene_to_file("res://scenes/game/GameScene.tscn")
