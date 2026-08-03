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
var rabbit_renderer: AnimalGroupRenderer
var deer_renderer: AnimalGroupRenderer
var animals_visible: bool = true
var flora_daily_updates_enabled: bool = true
var clock: GameClockController
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""
# Posizioni microcella coperte dal fiume (Array[Vector2i], vuoto se la macrocella non ha
# river). Calcolate una sola volta in _ready(): river_shape/river_space non cambiano mai
# durante la sessione (nessun service della pipeline annuale li tocca), quindi non serve
# ricalcolarle a ogni _refresh_resource_visuals(). Escludono grass/shrub/tree (vegetazione
# terrestre) via `occupied`, ma NON stone — le rocce nel letto/sulle rive del fiume restano
# plausibili e StonePositionService non riceve questo dizionario.
var river_positions: Array = []
# Inverso di river_positions (Dictionary per lookup O(1)): tutte le posizioni microcella NON
# fiume, calcolate una sola volta in _ready() insieme a river_positions per lo stesso motivo
# (river_shape/river_space non cambiano mai durante la sessione). Usato come `occupied` di
# partenza per FishPositionService su celle RIVER: passandolo (duplicato) al generatore, le
# uniche posizioni candidate restano quelle dentro river_positions — vedi _refresh_resource_visuals.
var river_exterior_occupied: Dictionary = {}

@onready var primary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var secondary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SecondaryActionsBar
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
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
@onready var macro_cell_detail_panel: MacroCellDetailPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellDetailPanel

func _ready() -> void:
	# Ripristina lo stato dei due toggle dalla sessione precedente (vedi GameSettings): senza
	# questo, uscendo e rientrando in questa scena i toggle tornerebbero sempre al default "attivo",
	# perdendo silenziosamente la scelta dell'utente.
	animals_visible = GameSettings.macro_cell_animals_visible
	flora_daily_updates_enabled = GameSettings.macro_cell_flora_updates_enabled

	year_title_label.text = tr("calendar_label")
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = tr("advance_year_tooltip")
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	primary_actions_bar.configure_slot(0, "🌍", tr("back_to_world"), &"back_to_world", tr("back_to_world_description"))
	primary_actions_bar.configure_slot(
		1, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	primary_actions_bar.set_slot_toggled(1, animals_visible)
	primary_actions_bar.configure_slot(
		2, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates",
		tr("toggle_flora_updates_description")
	)
	primary_actions_bar.set_slot_toggled(2, flora_daily_updates_enabled)
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

	rabbit_renderer = AnimalGroupRenderer.new()
	add_child(rabbit_renderer)
	var rabbit_rules := AnimalCalculator.get_animal_rules("rabbit")
	rabbit_renderer.configure({
		"individuals_per_group": rabbit_rules.visual_group_size if rabbit_rules != null else 1,
		"move_speed": 3.0,
		"turn_rate": 1.5,
		"max_individuals_per_cluster": rabbit_rules.max_individuals_per_cluster if rabbit_rules != null else 1,
		"cluster_comfort_radius": 5.0,
		"cluster_attraction_strength": 1.5,
		"hop_speed": rabbit_rules.hop_speed if rabbit_rules != null else 6.0,
		"movement_phase_duration_min": rabbit_rules.movement_phase_duration_min if rabbit_rules != null else 2.0,
		"movement_phase_duration_max": rabbit_rules.movement_phase_duration_max if rabbit_rules != null else 5.0,
		"rest_phase_duration_min": rabbit_rules.rest_phase_duration_min if rabbit_rules != null else 3.0,
		"rest_phase_duration_max": rabbit_rules.rest_phase_duration_max if rabbit_rules != null else 7.0,
		"hop_duration_min": rabbit_rules.hop_duration_min if rabbit_rules != null else 0.2,
		"hop_duration_max": rabbit_rules.hop_duration_max if rabbit_rules != null else 0.4,
		"hop_pause_min": rabbit_rules.hop_pause_min if rabbit_rules != null else 0.1,
		"hop_pause_max": rabbit_rules.hop_pause_max if rabbit_rules != null else 0.3,
		"size_multiplier_by_age": rabbit_rules.size_multiplier_by_age if rabbit_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_rabbit_mesh(3.0, 1.3, 2.7, 0.9, Color(0.93, 0.91, 0.87, 0.95)),
	})

	# Cervo: stesso schema del coniglio sopra (parametri comportamentali da AnimalRules/deer.tres,
	# sagoma dedicata via build_deer_mesh — vedi AnimalGroupRenderer per la motivazione della
	# separazione). Corpo più grande del coniglio (coerente con la specie: ~1.7-1.8x in lunghezza
	# e larghezza), colore bruno invece del grigio-chiaro del coniglio.
	deer_renderer = AnimalGroupRenderer.new()
	add_child(deer_renderer)
	var deer_rules := AnimalCalculator.get_animal_rules("deer")
	deer_renderer.configure({
		"individuals_per_group": deer_rules.visual_group_size if deer_rules != null else 1,
		"move_speed": 3.5,
		"turn_rate": 1.2,
		"max_individuals_per_cluster": deer_rules.max_individuals_per_cluster if deer_rules != null else 1,
		"cluster_comfort_radius": 6.0,
		"cluster_attraction_strength": 1.5,
		"hop_speed": deer_rules.hop_speed if deer_rules != null else 6.0,
		"movement_phase_duration_min": deer_rules.movement_phase_duration_min if deer_rules != null else 2.0,
		"movement_phase_duration_max": deer_rules.movement_phase_duration_max if deer_rules != null else 5.0,
		"rest_phase_duration_min": deer_rules.rest_phase_duration_min if deer_rules != null else 3.0,
		"rest_phase_duration_max": deer_rules.rest_phase_duration_max if deer_rules != null else 7.0,
		"hop_duration_min": deer_rules.hop_duration_min if deer_rules != null else 0.2,
		"hop_duration_max": deer_rules.hop_duration_max if deer_rules != null else 0.4,
		"hop_pause_min": deer_rules.hop_pause_min if deer_rules != null else 0.1,
		"hop_pause_max": deer_rules.hop_pause_max if deer_rules != null else 0.3,
		"size_multiplier_by_age": deer_rules.size_multiplier_by_age if deer_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_deer_mesh(5.5, 2.2, 1.4, 0.6, Color(0.55, 0.4, 0.25, 0.95)),
	})

	# Applica lo stato di visibilità ripristinato sopra (default true dei renderer altrimenti
	# resterebbe visibile anche se l'utente l'aveva disattivato prima di uscire).
	rabbit_renderer.set_animals_visible(animals_visible)
	deer_renderer.set_animals_visible(animals_visible)

	if macro_cell != null and macro_world != null:
		renderer.set_neighbors(_get_neighbor_cells(macro_cell), _get_neighbor_states(macro_cell))

		macro_state = macro_world.get_cell_state_at(macro_cell.x, macro_cell.y)
		if macro_state != null:
			if macro_cell.water_type == GameTypes.WaterType.RIVER:
				var thickness_ratio: float = float(macro_state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
				renderer.set_river(macro_cell.river_shape, thickness_ratio)
				river_positions = RiverMicrocellService.get_river_positions(macro_cell.river_shape, thickness_ratio)
				river_exterior_occupied = _compute_river_exterior_occupied(river_positions)

			var stone_service := StonePositionService.new()
			stone_service.generate_if_needed(macro_state)
			renderer.set_stone_positions(macro_state.stone_positions)

			_refresh_resource_visuals()

	_setup_clock()
	rabbit_renderer.clock = clock
	deer_renderer.clock = clock
	_update_calendar_display()

# "occupied" invertito rispetto al solito uso (qui marca ciò che NON è disponibile per FISH,
# cioè tutto tranne il fiume): passato a ResourcePositionService, le uniche candidate a
# superare il filtro restano le posizioni dentro river_positions.
func _compute_river_exterior_occupied(positions: Array) -> Dictionary:
	var river_position_set: Dictionary = {}
	for pos in positions:
		river_position_set[pos] = true

	var exterior: Dictionary = {}
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			if not river_position_set.has(pos):
				exterior[pos] = true
	return exterior


# Grass/shrub/tree non sono persistite (a differenza di stone): vanno ricalcolate ogni
# volta che la loro quantità può essere cambiata, cioè all'apertura della scena e ai
# checkpoint stagionali (o ogni giorno, se flora_daily_updates_enabled — vedi _on_day_advanced),
# così la vegetazione "cresce"/cambia a vista. Aggiorna anche il pannello info in coda (vedi
# _update_info_panel) — quest'ultimo però va tenuto sincronizzato ogni giorno a prescindere,
# per questo _on_day_advanced lo richiama anche da solo nei giorni in cui questo rebuild
# completo viene saltato.
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

	var fish_positions: Array = []
	var fish_service := FishPositionService.new()
	if macro_cell.water_type == GameTypes.WaterType.SEA or macro_cell.water_type == GameTypes.WaterType.LAKE:
		# L'intera macrocella è acqua: nessuna posizione da escludere.
		fish_positions = fish_service.generate_positions(macro_state)
	elif macro_cell.water_type == GameTypes.WaterType.RIVER:
		# Duplicato: generate_positions muta il dizionario passato aggiungendo le posizioni
		# scelte, e river_exterior_occupied va riusato identico a ogni refresh, non accumulare
		# i pesci di un anno come "occupati" per quello successivo. Le rocce (stabili per tutta
		# la sessione, come river_positions) possono già stare dentro il fiume — vanno escluse
		# così un pesce non finisce disegnato esattamente sopra una roccia.
		var occupied_for_fish: Dictionary = river_exterior_occupied.duplicate()
		for pos in macro_state.stone_positions:
			occupied_for_fish[pos] = true
		fish_positions = fish_service.generate_positions(macro_state, occupied_for_fish)
	renderer.set_fish_positions(fish_positions)

	var this_cell := Vector2i(macro_cell.x, macro_cell.y)
	var rabbit_group := macro_world.find_population_group("rabbit", this_cell)
	_update_animal_renderer_population(rabbit_renderer, rabbit_group, AnimalCalculator.get_animal_rules("rabbit"), this_cell)
	var deer_group := macro_world.find_population_group("deer", this_cell)
	_update_animal_renderer_population(deer_renderer, deer_group, AnimalCalculator.get_animal_rules("deer"), this_cell)

	renderer.set_shrub_fruit_ratio(_get_shrub_fruit_ratio())
	renderer.set_shrub_age_params(game_data.year, _get_age_params(GameTypes.WorldObjectType.SHRUB))
	renderer.set_tree_fruit_ratios(_get_tree_subtype_ratio("wild_fruit"), _get_tree_subtype_ratio("domesticable_fruit"))
	renderer.set_tree_conifer_ratio(_get_tree_subtype_ratio("conifer"))
	renderer.set_tree_age_params(game_data.year, _get_age_params(GameTypes.WorldObjectType.TREE))
	# Dopo le posizioni: set_season ricostruisce anche il buffer erba (colore dipende dalla
	# stagione), così lo fa una volta sola con le posizioni già aggiornate invece di due volte.
	renderer.set_season(SeasonCalculator.get_season_for_day(game_data.current_day))

	_update_info_panel()


# Popola un AnimalGroupRenderer con la quota di QUESTA cella (get_population_by_cell — con
# territori multi-cella, Step 5, group.population è il totale sull'INTERO territorio, non quanti
# individui sono realmente qui; stessa fonte di verità già usata da MacroCellInfoPanel/
# MacroCellDetailPanel, per rabbit a 1 sola cella degenera nello stesso valore). Se la specie
# traccia le age band (track_age_bands), la quota viene ulteriormente ripartita per fascia
# (get_age_composition_in_cell) così il renderer può disegnare Y/A/O a dimensioni diverse
# (size_multiplier_by_age) — altrimenti passa la quota totale a set_population, scala fissa 1.0.
func _update_animal_renderer_population(
	renderer_node: AnimalGroupRenderer, group: PopulationGroup, rules: AnimalRules, coords: Vector2i
) -> void:
	var age_aware := rules != null and rules.track_age_bands

	if group == null:
		if age_aware:
			renderer_node.set_population_by_age(0, 0, 0)
		else:
			renderer_node.set_population(0)
		return

	if age_aware:
		var age_composition := group.get_age_composition_in_cell(coords)
		renderer_node.set_population_by_age(
			int(age_composition.get(GameTypes.AgeBand.YOUNG, 0)),
			int(age_composition.get(GameTypes.AgeBand.ADULT, 0)),
			int(age_composition.get(GameTypes.AgeBand.OLD, 0))
		)
	else:
		renderer_node.set_population(int(group.get_population_by_cell().get(coords, 0)))


# I numeri del pannello info leggono macro_state/macro_cell direttamente (nessun rebuild di
# mesh coinvolto): vanno tenuti aggiornati ogni giorno in cui qualcosa è davvero cambiato,
# INDIPENDENTEMENTE da flora_daily_updates_enabled — quel toggle riguarda solo quando vale la
# pena ricostruire la resa grafica (costosa), non se i dati mostrati sono corretti. Per questo
# è una funzione a sé invece di restare solo in coda a _refresh_resource_visuals.
func _update_info_panel() -> void:
	if macro_state == null:
		return
	macro_cell_detail_panel.show_cell(macro_cell, macro_state, SeasonCalculator.get_season_for_day(game_data.current_day), macro_world)


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

# Parametri fasce età per ciascun sottotipo di object_type con track_age_bands=true nella
# macrocella corrente (chiave = subtype_name), passati già risolti a MicroCellRenderer (vedi
# _refresh_resource_visuals, chiamata per SHRUB e TREE) — stessa separazione di responsabilità di
# _get_shrub_fruit_ratio: il renderer non conosce ResourceCalculator/MacroCellState, riceve solo
# dati già pronti. I ratio arrivano da MacroCellState.get_age_composition, non normalizzati qui
# (AgeBandVisualService normalizza già internamente).
func _get_age_params(object_type: GameTypes.WorldObjectType) -> Dictionary:
	var params: Dictionary = {}
	for rule in ResourceCalculator.get_subtype_rules(object_type):
		if not rule.track_age_bands:
			continue

		var composition := macro_state.get_age_composition(object_type, rule.subtype_name)
		var young: int = int(composition.get(GameTypes.AgeBand.YOUNG, 0))
		var adult: int = int(composition.get(GameTypes.AgeBand.ADULT, 0))
		var old: int = int(composition.get(GameTypes.AgeBand.OLD, 0))

		params[rule.subtype_name] = {
			"youth_duration_years": rule.youth_duration_years,
			"adult_duration_years": rule.adult_duration_years,
			"size_multiplier_by_age": rule.size_multiplier_by_age,
			"ratios": [float(young), float(adult), float(old)],
		}
	return params

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

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"back_to_world":
			_on_back_to_world_pressed()
		&"toggle_animals_visibility":
			animals_visible = not animals_visible
			# Un solo toggle per tutta la fauna (rabbit + deer, non uno per specie): nessun caso
			# d'uso reale oggi per nasconderle separatamente — se servirà un controllo più fine
			# in futuro (es. gameplay-specifico), lo si introduce allora.
			rabbit_renderer.set_animals_visible(animals_visible)
			deer_renderer.set_animals_visible(animals_visible)
			primary_actions_bar.set_slot_toggled(1, animals_visible)
			GameSettings.macro_cell_animals_visible = animals_visible
		&"toggle_flora_updates":
			flora_daily_updates_enabled = not flora_daily_updates_enabled
			primary_actions_bar.set_slot_toggled(2, flora_daily_updates_enabled)
			GameSettings.macro_cell_flora_updates_enabled = flora_daily_updates_enabled

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
			_on_save_pressed()
		&"back_to_main_menu":
			_pending_leave_action = &"back_to_main_menu"
			save_confirmation_dialog.open_dialog()
		&"exit_game":
			_pending_leave_action = &"exit_game"
			save_confirmation_dialog.open_dialog()

func _on_save_confirmation_option_selected(option: StringName) -> void:
	match option:
		&"save_and_leave":
			_on_save_pressed()
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

	# _refresh_resource_visuals già chiama _update_info_panel al suo interno: qui va invocata
	# a parte solo quando quel rebuild completo (costoso) viene saltato, così i dati del
	# pannello restano sempre aggiornati giorno per giorno anche a rendering "stagionale".
	if checkpoint_ran or flora_daily_updates_enabled:
		_refresh_resource_visuals()
	else:
		_update_info_panel()

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
