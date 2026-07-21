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
var clock: GameClockController
# Posizioni microcella coperte dal fiume (Array[Vector2i], vuoto se la macrocella non ha
# river). Calcolate una sola volta in _ready(): river_shape/river_space non cambiano mai
# durante la sessione (nessun service della pipeline annuale li tocca), quindi non serve
# ricalcolarle a ogni _refresh_resource_visuals(). Escludono grass/shrub/tree (vegetazione
# terrestre) via `occupied`, ma NON stone — le rocce nel letto/sulle rive del fiume restano
# plausibili e StonePositionService non riceve questo dizionario.
var river_positions: Array = []

@onready var save_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SaveButton
@onready var back_to_world_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/BackToWorldButton
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var year_title_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/YearTitleLabel
@onready var year_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/YearLabel
@onready var play_pause_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/PlayPauseButton
@onready var speed_buttons: Dictionary = {
	GameClockController.Speed.X1: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed1xButton,
	GameClockController.Speed.X2: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed2xButton,
	GameClockController.Speed.X3: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed3xButton,
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
}
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugControlsContainer/AdvanceYearButton
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellInfoPanel

func _ready() -> void:
	save_button.text = tr("save_game")
	back_to_world_button.text = tr("back_to_world")
	year_title_label.text = tr("calendar_label")
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
				river_positions = RiverMicrocellService.get_river_positions(macro_cell.river_shape, thickness_ratio)

			var stone_service := StonePositionService.new()
			stone_service.generate_if_needed(macro_state)
			renderer.set_stone_positions(macro_state.stone_positions)

			_refresh_resource_visuals()

	_setup_clock()
	_update_calendar_display()

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
	for pos in river_positions:
		occupied[pos] = true

	var vegetation_service := VegetationPositionService.new()
	renderer.set_vegetation_positions(vegetation_service.generate_positions(macro_state, occupied))
	renderer.set_shrub_fruit_ratio(_get_shrub_fruit_ratio())
	renderer.set_tree_fruit_ratios(_get_tree_subtype_ratio("wild_fruit"), _get_tree_subtype_ratio("domesticable_fruit"))
	# Dopo le posizioni: set_season ricostruisce anche il buffer erba (colore dipende dalla
	# stagione), così lo fa una volta sola con le posizioni già aggiornate invece di due volte.
	renderer.set_season(SeasonCalculator.get_season_for_day(game_data.current_day))

	macro_cell_info_panel.show_cell(macro_cell, macro_state, true)

# Quota di dedicated_space SHRUB classificata come sottotipo "fruit_bearing" nella macrocella
# corrente (0 se SHRUB non ha ancora sottotipi tracciati lì, es. cella senza shrub). Il nome
# stringa deve combaciare con subtype_name in data/resource_subtypes/shrub_fruit_bearing.tres.
func _get_shrub_fruit_ratio() -> float:
	var composition := macro_state.get_subtype_composition(GameTypes.WorldObjectType.SHRUB)
	if composition.is_empty():
		return 0.0

	var total: int = 0
	for amount in composition.values():
		total += int(amount)
	if total <= 0:
		return 0.0

	var fruit_count: int = int(composition.get("fruit_bearing", 0))
	return float(fruit_count) / float(total)

# Quota di dedicated_space TREE classificata come subtype_name nella macrocella corrente (0 se
# TREE non ha ancora sottotipi tracciati lì, es. cella senza tree). Un'unica funzione parametrica
# invece di una per sottotipo, dato che MicroCellRenderer ora vuole wild_fruit e
# domesticable_fruit come due rapporti indipendenti (vedi set_tree_fruit_ratios).
func _get_tree_subtype_ratio(subtype_name: String) -> float:
	var composition := macro_state.get_subtype_composition(GameTypes.WorldObjectType.TREE)
	if composition.is_empty():
		return 0.0

	var total: int = 0
	for amount in composition.values():
		total += int(amount)
	if total <= 0:
		return 0.0

	return float(int(composition.get(subtype_name, 0))) / float(total)

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

func _setup_clock() -> void:
	clock = GameClockController.new()
	add_child(clock)
	if macro_world == null:
		play_pause_button.disabled = true
		for speed in speed_buttons.keys():
			speed_buttons[speed].disabled = true
		return
	clock.setup(macro_world, game_data)
	clock.is_playing = GameSettings.active_clock_is_playing
	clock.speed = GameSettings.active_clock_speed
	clock.day_advanced.connect(_on_day_advanced)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	for speed in speed_buttons.keys():
		speed_buttons[speed].pressed.connect(_on_speed_button_pressed.bind(speed))
	_update_play_pause_button()
	speed_buttons[clock.speed].button_pressed = true

func _on_play_pause_pressed() -> void:
	clock.toggle_play_pause()
	_update_play_pause_button()

func _on_speed_button_pressed(speed: GameClockController.Speed) -> void:
	clock.set_speed(speed)

func _update_play_pause_button() -> void:
	play_pause_button.text = tr("pause") if clock.is_playing else tr("play")

func _on_day_advanced(simulation_ran: bool) -> void:
	_update_calendar_display()
	if not simulation_ran:
		return
	_refresh_resource_visuals()

func _on_advance_year_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo macro condiviso: impossibile avanzare l'anno.")
		return
	clock.force_advance_to_year_end()

func _update_calendar_display() -> void:
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)

func _on_back_to_world_pressed() -> void:
	GameSettings.returning_to_game_scene = true
	if clock != null and macro_world != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://scenes/game/GameScene.tscn")
