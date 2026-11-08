extends Node2D

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]

# Vista principale del player su una singola macrocella (res://gameplay/scenes/game/). Oggi
# raggiungibile solo tramite questo bottone debug e l'equivalente in WorldScene — il vero
# aggancio dal flusso principale è uno step successivo separato, non ancora fatto (vedi TODO in
# GameScene.gd._ready()).
const GAME_SCENE_PATH := "res://gameplay/scenes/game/GameScene.tscn"

var world: World
var macro_world: World
var macro_cell: MacroCellData
var macro_state: MacroCellState
var game_data: GameData
var renderer: MicroCellRenderer
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
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
	# Visibile solo a DebugLogging.ENABLED (vedi _setup_clock) — stesso meccanismo già in uso per
	# debug_animal_container in WorldScene.
	GameClockController.Speed.DEBUG: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/SpeedDebugButton,
}
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/AdvanceYearButton
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar
@onready var macro_cell_detail_panel: MacroCellDetailPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/MacroCellDetailPanel

func _ready() -> void:
	# Ripristina lo stato dei due toggle dalla sessione precedente (vedi GameSettings): senza
	# questo, uscendo e rientrando in questa scena i toggle tornerebbero sempre al default "attivo",
	# perdendo silenziosamente la scelta dell'utente.
	flora_daily_updates_enabled = GameSettings.macro_cell_flora_updates_enabled

	# year_title_label.text non più impostato qui (richiesta utente, 2026-09-04): ora mostra l'Era
	# corrente invece della label statica "calendar_label", aggiornata da _update_calendar_display
	# così resta viva anche quando un futuro trigger tech→era chiamerà GameData.set_current_era.
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = TooltipText.wrap(tr("advance_year_tooltip"))
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	primary_actions_bar.configure_slot(
		0, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates",
		tr("toggle_flora_updates_description")
	)
	primary_actions_bar.set_slot_toggled(0, flora_daily_updates_enabled)
	primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	# Slot 1 lasciato vuoto apposta: i bottoni di navigazione stanno accostati al bordo destro
	# della riga (slot 2 e 3), separati dal bottone opzioni a sinistra.
	secondary_actions_bar.configure_slot(2, "🌍", tr("back_to_world"), &"back_to_world", tr("back_to_world_description"))
	secondary_actions_bar.configure_slot(3, "🧍", tr("game_view"), &"game_view", tr("game_view_description"))
	secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit_to_desktop"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))
	# Bugfix, richiesta utente 2026-09-05 (stesso di GameScene.gd): senza questa riga il clock
	# ripartiva nell'istante tra la chiusura del menu di sistema e l'apertura di questo file dialog.
	save_game_file_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_game_file_dialog))

	macro_world = GameSettings.active_world
	game_data = GameSettings.active_game_data
	if game_data == null:
		push_warning("Nessun game_data condiviso: creo un anno locale di riserva.")
		game_data = GameData.new()

	if macro_world != null:
		macro_cell = macro_world.get_cell_at(GameSettings.selected_macro_cell_x, GameSettings.selected_macro_cell_y)

	# Punto di invocazione per LODOrchestrator. La "zona a fuoco" è per ora la sola macrocella appena
	# aperta, la scelta più semplice prima di un eventuale intorno più ampio.
	if macro_world != null and macro_cell != null:
		var focus_live_cells: Dictionary = {Vector2i(macro_cell.x, macro_cell.y): true}
		LODOrchestrator.set_focus_region(macro_world, focus_live_cells, SeasonCalculator.get_season_for_day(game_data.current_day))
		macro_world.lod_focus_active = true
		macro_world.live_cell_coords = focus_live_cells

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
				river_exterior_occupied = _compute_river_exterior_occupied(river_positions)
			renderer.set_streams(StreamMicrocellService.get_layout(macro_world, macro_cell))

			var stone_service := StonePositionService.new()
			stone_service.generate_if_needed(macro_state, macro_cell, StreamMicrocellService.get_positions(macro_world, macro_cell))
			# Rocce esaurite (2026-10-08, RockStoneService.is_depleted): non si disegnano.
			renderer.set_depleted_stone_positions(RockStoneService.get_depleted_positions(macro_state))
			renderer.set_stone_positions(macro_state.stone_positions)
			# Pebble (2026-09-08, richiesta utente) — stessa fonte/stesso momento delle posizioni
			# stone appena sopra. Registro unificato (2026-09-19, refactor lot_source): pebble vive
			# ora in MacroCellState.lot_registry["pebble"], letto tramite _build_lot_availability_map
			# sotto invece di un Dictionary dedicato.
			renderer.set_pebble_availability(_build_lot_availability_map("pebble", macro_state.stone_positions))

			_refresh_resource_visuals()

	_setup_clock()
	_update_calendar_display()


# Azzera lo stato di focus del LOD (Parte B, Punto 2) quando questa scena viene lasciata, per
# QUALUNQUE via — "Torna al Mondo" (_on_back_to_world_pressed), "Torna al menu principale"
# (_on_system_menu_action_selected), o una futura terza via non ancora scritta: _exit_tree() è il
# callback nativo di Godot invocato quando il nodo esce dall'albero (change_scene_to_file lo
# libera sempre), quindi copre ogni caso senza dover ricordare di richiamare l'azzeramento in ogni
# singolo gestore di bottone. Riporta lod_focus_active a false = "nessun focus attivo" (vista mondo),
# lo stesso stato di partenza prima che questa scena venisse mai aperta.
func _exit_tree() -> void:
	if macro_world != null:
		macro_world.lod_focus_active = false


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
# Disponibilità già risolta per un elenco di posizioni/lotti candidati di `resource_name` — STESSO
# helper/STESSO principio di GameScene._build_lot_availability_map (2026-09-19, refactor
# lot_source), duplicato qui deliberatamente (classi diverse, nessuna utility condivisa tra le
# due — stesso principio già seguito ovunque nel progetto per Node script distinti).
func _build_lot_availability_map(resource_name: String, positions: Array) -> Dictionary:
	var availability: Dictionary = {}
	for pos in positions:
		var lot := Vector2i(pos.x, pos.y)
		# get_available_ignoring_lock — stesso motivo di GameScene._build_lot_availability_map.
		var available: int = TerrainScatteredResourceService.get_available_ignoring_lock(macro_state, resource_name, lot)
		if available > 0:
			availability[lot] = available
	return availability


func _refresh_resource_visuals() -> void:
	if macro_state == null:
		return

	# Pool TREE_INDIVIDUAL/SHRUB_INDIVIDUAL (2026-09-08, richiesta utente) — stesso aggancio di
	# GameScene._refresh_resource_visuals, RISCRITTO 2026-09-19 (refactor lot_source): una sola
	# chiamata generica invece delle tre StickPoolService/PlantFiberPoolService/MushroomPoolService.
	# refresh_macrocell hardcoded.
	LotCapacityService.refresh_all_vegetation_lot_capacities(macro_state, game_data)
	renderer.set_stick_availability(_build_lot_availability_map("stick", macro_state.tree_claimed_lots.keys()))
	# plant_fiber/mushroom: nessun rendering agganciato qui (stesso principio di prima di questo
	# refactor — "i funghi non vanno disegnati per ora"), il refresh sopra li mantiene comunque
	# freschi per pickup/ispezione microcella.

	var occupied: Dictionary = {}
	# Rocce esaurite (2026-10-08): non più vietate alla vegetazione, come in GameScene._refresh_resource_visuals.
	var depleted_rocks := RockStoneService.get_depleted_positions(macro_state)
	for pos in macro_state.stone_positions:
		if not depleted_rocks.has(pos):
			occupied[pos] = true
	for pos in river_positions:
		occupied[pos] = true
	for pos in StreamMicrocellService.get_positions(macro_world, macro_cell):
		occupied[pos] = true

	# begin_vegetation_batch()/end_vegetation_batch() (vedi MicroCellRenderer.gd e il commento
	# gemello in GameScene._refresh_resource_visuals): senza batching i 6 setter chiamati qui sotto
	# ricostruivano TREE/SHRUB/GRASS più volte ciascuno sugli stessi individui.
	renderer.begin_vegetation_batch()

	# Edifici esclusi (2026-10-28, alberi nati nascosti sotto gli edifici a ogni apertura di questa vista): stessa regola di
	# GameScene._building_positions_for_cell, in `occupied` (GRASS, lotti nuovi) e in building_positions (lotti già noti).
	var building_positions: Dictionary = {}
	if macro_world != null and macro_cell != null:
		for building in macro_world.buildings:
			if building.macro_x != macro_cell.x or building.macro_y != macro_cell.y:
				continue
			var uncleared_site := not building.is_complete and not bool(building.construction_progress.get("ground_cleared", false))
			for site_cell in BuildingFootprint.cells_of(building):
				if uncleared_site and BuildingSiteClearingService.has_woody_vegetation(macro_state, site_cell):
					continue
				occupied[site_cell] = true
				building_positions[site_cell] = true

	var vegetation_service := VegetationPositionService.new()
	renderer.set_vegetation_positions(vegetation_service.generate_positions(macro_state, occupied, game_data.year, game_data.current_day, building_positions))
	# PRIMA di set_*_subtypes/set_*_age_params sotto — vedi commento gemello in
	# GameScene._refresh_resource_visuals sul perché l'ordine conta qui.
	renderer.set_cut_positions(_get_cut_positions())
	renderer.set_dead_positions(_get_dead_positions())

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

	renderer.set_shrub_subtypes(macro_state.shrub_individual_subtype)
	renderer.set_shrub_age_params(
		game_data.year, _get_age_params(GameTypes.WorldObjectType.SHRUB), macro_state.shrub_virtual_birth_year
	)
	renderer.set_tree_subtypes(macro_state.tree_individual_subtype)
	renderer.set_tree_age_params(
		game_data.year, _get_age_params(GameTypes.WorldObjectType.TREE), macro_state.tree_virtual_birth_year
	)
	# Dopo le posizioni: set_season ricostruisce anche il buffer erba (colore dipende dalla
	# stagione), così lo fa una volta sola con le posizioni già aggiornate invece di due volte.
	renderer.set_season(SeasonCalculator.get_season_for_day(game_data.current_day))

	renderer.end_vegetation_batch()

	_update_info_panel()


# I numeri del pannello info leggono macro_state/macro_cell direttamente (nessun rebuild di
# mesh coinvolto): vanno tenuti aggiornati ogni giorno in cui qualcosa è davvero cambiato,
# INDIPENDENTEMENTE da flora_daily_updates_enabled — quel toggle riguarda solo quando vale la
# pena ricostruire la resa grafica (costosa), non se i dati mostrati sono corretti. Per questo
# è una funzione a sé invece di restare solo in coda a _refresh_resource_visuals.
func _update_info_panel() -> void:
	if macro_state == null:
		return
	macro_cell_detail_panel.show_cell(macro_cell, macro_state, SeasonCalculator.get_season_for_day(game_data.current_day))


# Parametri fasce età per ciascun sottotipo di object_type con track_age_bands=true nella
# macrocella corrente (chiave = subtype_name), passati già risolti a MicroCellRenderer (vedi
# _refresh_resource_visuals, chiamata per SHRUB e TREE) — il renderer non conosce
# ResourceCalculator/MacroCellState, riceve solo dati già pronti. Il sottotipo/anno di nascita di
# ogni individuo non si decidono più qui (vedi IndividualVegetationService, chiamato dentro
# generate_positions prima di arrivare a questo punto) — restano solo i parametri di fascia età
# (youth/adult duration, size_multiplier_by_age), non più il campo "ratios" (usato solo dalla
# stima a percentile, ora eseguita direttamente da IndividualVegetationService sui dati di
# macro_state, non più passata attraverso questo dizionario).
func _get_age_params(object_type: GameTypes.WorldObjectType) -> Dictionary:
	var params: Dictionary = {}
	for rule in ResourceCalculator.get_subtype_rules(object_type):
		if not rule.track_age_bands:
			continue

		params[rule.subtype_name] = {
			"youth_duration_years": rule.youth_duration_years,
			"adult_duration_years": rule.adult_duration_years,
			"size_multiplier_by_age": rule.size_multiplier_by_age,
		}
	return params


# Posizioni con blocco di taglio/morte attualmente attivo, raggruppate per WorldObjectType — vedi
# MicroCellRenderer.set_cut_positions/set_dead_positions.
func _get_cut_positions() -> Dictionary:
	return {
		GameTypes.WorldObjectType.TREE: IndividualVegetationService.get_cut_positions(macro_state, GameTypes.WorldObjectType.TREE, game_data.year),
		GameTypes.WorldObjectType.SHRUB: IndividualVegetationService.get_cut_positions(macro_state, GameTypes.WorldObjectType.SHRUB, game_data.year),
	}


func _get_dead_positions() -> Dictionary:
	return {
		GameTypes.WorldObjectType.TREE: IndividualVegetationService.get_dead_positions(macro_state, GameTypes.WorldObjectType.TREE),
		GameTypes.WorldObjectType.SHRUB: IndividualVegetationService.get_dead_positions(macro_state, GameTypes.WorldObjectType.SHRUB),
	}

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
	await SaveIndicator.begin()
	var save_service := GameSaveService.new()
	save_service.save_game_to_json(macro_world, game_data, path)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_flora_updates":
			flora_daily_updates_enabled = not flora_daily_updates_enabled
			primary_actions_bar.set_slot_toggled(0, flora_daily_updates_enabled)
			GameSettings.macro_cell_flora_updates_enabled = flora_daily_updates_enabled

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"back_to_world":
			_on_back_to_world_pressed()
		&"game_view":
			_on_game_view_pressed()
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
			get_tree().change_scene_to_file("res://simulation/scenes/menus/MainMenu.tscn")
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
	# Retrocompatibilità (richiesta utente, 2026-09-04 — rimozione di Speed.X3): GameSettings.
	# active_clock_speed è un plain int di sessione (mai un vero enum, vedi il commento lì), quindi
	# un valore stantio che non corrisponde più a nessuna chiave di speed_buttons (es. il vecchio
	# X3, o un futuro membro rimosso) ripiegherebbe silenziosamente su una velocità sbagliata invece
	# di rompere il caricamento — qui viene invece ricondotto a X1.
	var restored_speed: int = GameSettings.active_clock_speed
	clock.speed = restored_speed if speed_buttons.has(restored_speed) else GameClockController.Speed.X1
	clock.day_advanced.connect(_on_day_advanced)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	for speed in speed_buttons.keys():
		speed_buttons[speed].pressed.connect(_on_speed_button_pressed.bind(speed))
	# Pulsante "velocità debug" (richiesta utente, 2026-09-04): stesso flag già usato in WorldScene
	# per debug_animal_container, nessun meccanismo di debug-mode nuovo introdotto.
	speed_buttons[GameClockController.Speed.DEBUG].visible = DebugLogging.ENABLED
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
		play_pause_button.tooltip_text = TooltipText.wrap(tr("pause"))
	else:
		play_pause_button.text = "▶"
		play_pause_button.tooltip_text = TooltipText.wrap(tr("play"))

func _on_day_advanced(checkpoint_ran: bool) -> void:
	_update_calendar_display()
	if not checkpoint_ran:
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
	year_title_label.text = game_data.current_era_name.capitalize()
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)

func _on_back_to_world_pressed() -> void:
	GameSettings.returning_to_world_scene = true
	if clock != null and macro_world != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://simulation/scenes/game/WorldScene.tscn")

# GameScene ora esiste (res://gameplay/scenes/game/GameScene.tscn) — questo bottone è uno dei
# due canali "debug" da cui è raggiungibile oggi (l'altro è WorldScene._on_game_view_pressed),
# in attesa che il vero ingresso post-seeding venga agganciato (vedi TODO in
# GameScene.gd._ready()). Stesso schema di _on_back_to_world_pressed sopra.
func _on_game_view_pressed() -> void:
	GameSettings.active_world = macro_world
	GameSettings.active_game_data = game_data
	GameSettings.returning_to_player_view = true
	if clock != null and macro_world != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
