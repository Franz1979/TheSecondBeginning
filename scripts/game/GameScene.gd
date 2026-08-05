extends Node2D

# Durata dell'evidenziazione lampeggiante (WorldRenderer.flash_cells) delle celle del territorio
# di un PopulationGroup, quando l'utente clicca la sua riga nella tab Fauna del pannello — più
# lunga del feedback-pennello del map editor (WorldRenderer.PAINT_FLASH_DURATION), qui l'utente
# deve avere il tempo di individuare le celle sulla mappa, non solo confermare un click.
const POPULATION_HIGHLIGHT_DURATION: float = 2.0

var world: World
var game_data: GameData
var renderer: WorldRenderer
var game_controller: CellSelectorController
var clock: GameClockController
# Gate sul redraw giornaliero costoso di WorldRenderer (griglia 100x100 immediate-mode) — vedi
# GameSettings.game_scene_world_redraw_enabled per il perché. Default true: comportamento
# invariato finché l'utente non lo disattiva esplicitamente.
var world_daily_redraw_enabled: bool = true
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""

@onready var primary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var secondary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SecondaryActionsBar
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellInfoPanel
@onready var year_title_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/YearTitleLabel
@onready var year_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/YearLabel
@onready var play_pause_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/PlayPauseButton
@onready var speed_buttons: Dictionary = {
	GameClockController.Speed.X1: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed1xButton,
	GameClockController.Speed.X2: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed2xButton,
	GameClockController.Speed.X3: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed3xButton,
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
}
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/AdvanceYearButton
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar
@onready var debug_rabbit_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer
@onready var debug_rabbit_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer/DebugRabbitSpinBox
@onready var debug_set_rabbit_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugRabbitContainer/DebugSetRabbitButton
@onready var debug_deer_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugDeerContainer
@onready var debug_deer_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugDeerContainer/DebugDeerSpinBox
@onready var debug_set_deer_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugDeerContainer/DebugSetDeerButton

func _ready() -> void:
	# Ripristina lo stato del toggle dalla sessione precedente (vedi GameSettings): senza questo,
	# uscendo e rientrando in questa scena (es. via MacroCellScene) tornerebbe sempre al default
	# "attivo", perdendo silenziosamente la scelta dell'utente — stesso principio già usato da
	# MacroCellScene per i suoi due toggle.
	world_daily_redraw_enabled = GameSettings.game_scene_world_redraw_enabled

	year_title_label.text = tr("calendar_label")
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = tr("advance_year_tooltip")
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	primary_actions_bar.configure_slot(
		0, "🗺️", tr("toggle_world_redraw_tooltip"), &"toggle_world_redraw",
		tr("toggle_world_redraw_description")
	)
	primary_actions_bar.set_slot_toggled(0, world_daily_redraw_enabled)
	primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))

	debug_rabbit_container.visible = DebugLogging.ENABLED
	debug_deer_container.visible = DebugLogging.ENABLED
	debug_set_rabbit_button.pressed.connect(_on_debug_set_rabbit_pressed)
	debug_set_deer_button.pressed.connect(_on_debug_set_deer_pressed)

	var returning_from_macro_cell := GameSettings.returning_to_game_scene
	if returning_from_macro_cell:
		GameSettings.returning_to_game_scene = false
		world = GameSettings.active_world
		game_data = GameSettings.active_game_data
	else:
		_load_world()
	_create_renderer()
	_setup_clock()
	_update_calendar_display()

	game_controller = CellSelectorController.new()
	game_controller.setup(world, renderer)
	game_controller.cell_selected.connect(_on_cell_selected)
	macro_cell_info_panel.visible = true
	# Nessuna cella selezionata ancora a inizio scena: senza questo, le tab Fauna (dati
	# world-level, indipendenti dalla cella) resterebbero vuote finché l'utente non clicca una
	# cella almeno una volta — show_cell(null, ...) imposta comunque il riferimento world del
	# pannello prima del controllo "cell == null" interno, lasciando il resto del pannello vuoto
	# come atteso quando non c'è selezione.
	macro_cell_info_panel.show_cell(null, null, world)
	macro_cell_info_panel.population_group_highlight_requested.connect(_on_population_group_highlight_requested)
	macro_cell_info_panel.population_species_highlight_requested.connect(_on_population_species_highlight_requested)

	if returning_from_macro_cell:
		var cell := world.get_cell_at(GameSettings.selected_macro_cell_x, GameSettings.selected_macro_cell_y)
		if cell != null:
			_on_cell_selected(cell, world.get_cell_state_at(cell.x, cell.y))


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
	renderer.setup(world, game_data)

func _setup_clock() -> void:
	clock = GameClockController.new()
	add_child(clock)
	clock.setup(world, game_data)
	clock.is_playing = GameSettings.active_clock_is_playing
	clock.speed = GameSettings.active_clock_speed
	clock.day_advanced.connect(_on_day_advanced)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	for speed in speed_buttons.keys():
		speed_buttons[speed].pressed.connect(_on_speed_button_pressed.bind(speed))
	_update_play_pause_button()
	speed_buttons[clock.speed].button_pressed = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_open_macro_cell_scene()
		return
	if game_controller != null:
		game_controller.handle_input(event)

func _open_macro_cell_scene() -> void:
	var mouse_pos: Vector2 = renderer.get_local_mouse_position()
	var cell_x := int(mouse_pos.x / WorldRenderer.CELL_SIZE)
	var cell_y := int(mouse_pos.y / WorldRenderer.CELL_SIZE)
	var cell := world.get_cell_at(cell_x, cell_y)
	if cell == null:
		return
	GameSettings.selected_macro_cell_x = cell.x
	GameSettings.selected_macro_cell_y = cell.y
	GameSettings.active_world = world
	GameSettings.active_game_data = game_data
	GameSettings.active_clock_is_playing = clock.is_playing
	GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://scenes/game/MacroCellScene.tscn")


func _on_population_group_highlight_requested(cells: Array) -> void:
	renderer.flash_cells(cells, POPULATION_HIGHLIGHT_DURATION)


func _on_population_species_highlight_requested(entries: Array) -> void:
	renderer.highlight_group_territories(entries, MacroCellInfoPanel.SPECIES_TERRITORY_HIGHLIGHT_DURATION)


func _on_cell_selected(cell: MacroCellData, state: MacroCellState) -> void:
	macro_cell_info_panel.show_cell(cell, state, world)
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

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_world_redraw":
			world_daily_redraw_enabled = not world_daily_redraw_enabled
			primary_actions_bar.set_slot_toggled(0, world_daily_redraw_enabled)
			GameSettings.game_scene_world_redraw_enabled = world_daily_redraw_enabled

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"menu":
			system_menu_dialog.open_menu()

func _on_blocking_dialog_visibility_changed(dialog: Window) -> void:
	if dialog.visible:
		if _open_dialog_count == 0:
			_clock_was_playing_before_dialogs = clock.is_playing
			if clock.is_playing:
				clock.toggle_play_pause()
				_update_play_pause_button()
		_open_dialog_count += 1
	else:
		_open_dialog_count -= 1
		if _open_dialog_count == 0 and _clock_was_playing_before_dialogs and not clock.is_playing:
			clock.toggle_play_pause()
			_update_play_pause_button()

func _on_system_menu_action_selected(action_id: StringName) -> void:
	match action_id:
		&"save":
			_on_save_game_pressed()
		&"back_to_main_menu":
			_pending_leave_action = &"back_to_main_menu"
			save_confirmation_dialog.open_dialog()
		&"exit_game":
			_pending_leave_action = &"exit_game"
			save_confirmation_dialog.open_dialog()

func _on_save_confirmation_option_selected(option: StringName) -> void:
	match option:
		&"save_and_leave":
			_on_save_game_pressed()
		&"leave_without_saving":
			_execute_pending_leave_action()
		&"cancel":
			_pending_leave_action = &""

func _execute_pending_leave_action() -> void:
	var action := _pending_leave_action
	_pending_leave_action = &""
	match action:
		&"back_to_main_menu":
			get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
		&"exit_game":
			get_tree().quit()

func _on_play_pause_pressed() -> void:
	clock.toggle_play_pause()
	_update_play_pause_button()

func _on_speed_button_pressed(speed: GameClockController.Speed) -> void:
	clock.set_speed(speed)

func _update_play_pause_button() -> void:
	if clock.is_playing:
		play_pause_button.text = "❚❚"
		play_pause_button.tooltip_text = tr("pause")
	else:
		play_pause_button.text = "▶"
		play_pause_button.tooltip_text = tr("play")

func _on_day_advanced(checkpoint_ran: bool, animals_changed: bool) -> void:
	_update_calendar_display()
	if not (checkpoint_ran or animals_changed):
		return
	# Il redraw completo di WorldRenderer (griglia 100x100 immediate-mode) è costoso e non serve
	# tutti i giorni: sempre ai veri checkpoint stagionali (variazioni visibili reali), ma nei
	# giorni con solo animals_changed (ormai quasi ogni giorno, vedi AnimalConsumptionService/
	# AnimalHungerService) solo se l'utente ha lasciato attivo il toggle — stesso schema già usato
	# da MacroCellScene per flora_daily_updates_enabled.
	if checkpoint_ran or world_daily_redraw_enabled:
		renderer.queue_redraw()
	if renderer.selected_cell != null:
		var state := world.get_cell_state_at(renderer.selected_cell.x, renderer.selected_cell.y)
		macro_cell_info_panel.show_cell(renderer.selected_cell, state, world)
	else:
		# Le tab Fauna sono dati world-level (non legati alla cella selezionata): senza una cella
		# selezionata, show_cell sopra non viene mai chiamata — vanno comunque rinfrescate qui se
		# l'utente le ha aperte, altrimenti restano ferme finché non seleziona/deseleziona una
		# cella (il bug segnalato: "si aggiornano solo entrando e uscendo da una cella").
		macro_cell_info_panel.refresh_fauna_tabs_if_active()

func _on_advance_year_pressed() -> void:
	clock.force_advance_to_year_end()

# Cella bersaglio per i pulsanti debug sotto: quella attualmente selezionata sulla mappa (singolo
# click, vedi renderer.selected_cell/set_selected_cell) — così l'utente sceglie dove rilasciare la
# popolazione invece di un fisso (50,50), e può creare più gruppi della stessa specie in celle
# diverse (world.find_population_group cerca per specie+cella: celle diverse => gruppi diversi,
# nessuna fusione). Fallback a (50,50) solo se non è ancora stata selezionata nessuna cella (es.
# subito dopo l'apertura della scena). Nessun blocco se si preme di nuovo sulla STESSA cella già
# usata: sovrascrive il gruppo lì esistente, comportamento voluto (vedi find_population_group).
func _debug_target_coords() -> Vector2i:
	if renderer.selected_cell != null:
		return Vector2i(renderer.selected_cell.x, renderer.selected_cell.y)
	return Vector2i(50, 50)

func _on_debug_set_rabbit_pressed() -> void:
	var coords := _debug_target_coords()
	var count := int(debug_rabbit_spin_box.value)

	var rabbit_rules := AnimalCalculator.get_animal_rules("rabbit")
	var group := world.find_population_group("rabbit", coords)
	if group == null:
		group = PopulationGroup.new("rabbit", _build_initial_territory(coords, rabbit_rules, "rabbit"), world.allocate_population_group_id())
		world.population_groups.append(group)
	group.set_population(count)
	# Riallinea age_composition al nuovo totale (vedi PopulationGroup.set_age_composition) —
	# senza questo, la maturazione delle age band non avrebbe mai dati su cui operare finché la
	# natalità (prompt futuro) non esiste ancora.
	var age_weights: Dictionary = rabbit_rules.initial_age_ratio if rabbit_rules != null else {}
	group.set_age_composition(count, age_weights)
	macro_cell_info_panel.refresh_fauna_tabs_if_active()
	print("[DEBUG] rabbit population #%d (%d,%d) impostata a %d" % [group.id, coords.x, coords.y, count])

func _on_debug_set_deer_pressed() -> void:
	var coords := _debug_target_coords()
	var count := int(debug_deer_spin_box.value)

	var deer_rules := AnimalCalculator.get_animal_rules("deer")
	var group := world.find_population_group("deer", coords)
	if group == null:
		group = PopulationGroup.new("deer", _build_initial_territory(coords, deer_rules, "deer"), world.allocate_population_group_id())
		world.population_groups.append(group)
	group.set_population(count)
	var age_weights: Dictionary = deer_rules.initial_age_ratio if deer_rules != null else {}
	group.set_age_composition(count, age_weights)
	macro_cell_info_panel.refresh_fauna_tabs_if_active()
	print("[DEBUG] deer population #%d (%d,%d) impostata a %d" % [group.id, coords.x, coords.y, count])


# Territorio iniziale di un gruppo appena creato: una sola cella per specie con
# min_territory_cells <= 1 (rabbit — comportamento identico a prima di Step 5), altrimenti una
# BFS di TerritoryBuilderService a partire da coords fino a min_territory_cells celle (deer),
# escludendo le celle già occupate da un territorio ESISTENTE della stessa specie (species_name —
# vedi TerritoryBuilderService._collect_species_occupied_cells). La dimensione è fissa da qui in
# poi: nessuna espansione/restringimento nel tempo (Step 8 futuro).
func _build_initial_territory(coords: Vector2i, rules: AnimalRules, species_name: String) -> Territory:
	if rules == null or rules.min_territory_cells <= 1:
		return Territory.from_single_cell(coords)
	return TerritoryBuilderService.new().build_territory(world, coords, rules.min_territory_cells, species_name)

func _update_calendar_display() -> void:
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)
