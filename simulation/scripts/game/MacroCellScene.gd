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
var rabbit_renderer: AnimalGroupRenderer
var deer_renderer: AnimalGroupRenderer
var boar_renderer: AnimalGroupRenderer
var tarpan_renderer: AnimalGroupRenderer
var aurochs_renderer: AnimalGroupRenderer
var wild_donkey_renderer: AnimalGroupRenderer
var mouflon_renderer: AnimalGroupRenderer
var bezoar_renderer: AnimalGroupRenderer
var partridge_renderer: AnimalGroupRenderer
var wolf_renderer: AnimalGroupRenderer
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
	animals_visible = GameSettings.macro_cell_animals_visible
	flora_daily_updates_enabled = GameSettings.macro_cell_flora_updates_enabled

	# year_title_label.text non più impostato qui (richiesta utente, 2026-09-04): ora mostra l'Era
	# corrente invece della label statica "calendar_label", aggiornata da _update_calendar_display
	# così resta viva anche quando un futuro trigger tech→era chiamerà GameData.set_current_era.
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = tr("advance_year_tooltip")
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	primary_actions_bar.configure_slot(
		0, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	primary_actions_bar.set_slot_toggled(0, animals_visible)
	primary_actions_bar.configure_slot(
		1, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates",
		tr("toggle_flora_updates_description")
	)
	primary_actions_bar.set_slot_toggled(1, flora_daily_updates_enabled)
	primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	# Slot 1 lasciato vuoto apposta: i bottoni di navigazione stanno accostati al bordo destro
	# della riga (slot 2 e 3), separati dal bottone opzioni a sinistra.
	secondary_actions_bar.configure_slot(2, "🌍", tr("back_to_world"), &"back_to_world", tr("back_to_world_description"))
	secondary_actions_bar.configure_slot(3, "🧍", tr("game_view"), &"game_view", tr("game_view_description"))
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

	# Punto di invocazione per LODOrchestrator (Parte A: classificazione + log diagnostico; Parte B
	# Punto 2: il risultato viene ora anche conservato su macro_world.lod_focus_state — vedi
	# World.gd). La "zona a fuoco" è per ora la sola macrocella appena aperta, la scelta più
	# semplice prima di un eventuale intorno più ampio. macro_world.lod_focus_live_cells viene
	# salvata insieme al risultato: WorldTimeService la userà per ricalcolare periodicamente
	# lod_focus_state ad ogni checkpoint stagionale (fix del bug "nuovi gruppi da split mai
	# classificati"), senza dover ripassarla da qui ogni volta.
	if macro_world != null and macro_cell != null:
		var focus_live_cells: Dictionary = {Vector2i(macro_cell.x, macro_cell.y): true}
		var lod_result := LODOrchestrator.new().set_focus_region(macro_world, focus_live_cells)
		LODOrchestrator.print_classification_log(lod_result)
		macro_world.lod_focus_live_cells = focus_live_cells
		macro_world.lod_focus_state = lod_result

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
		"move_speed": rabbit_rules.move_speed if rabbit_rules != null else 3.0,
		"turn_rate": rabbit_rules.turn_rate if rabbit_rules != null else 1.5,
		"max_individuals_per_cluster": rabbit_rules.max_individuals_per_cluster if rabbit_rules != null else 1,
		"cluster_comfort_radius": rabbit_rules.cluster_comfort_radius if rabbit_rules != null else 5.0,
		"cluster_attraction_strength": rabbit_rules.cluster_attraction_strength if rabbit_rules != null else 1.5,
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
		"mesh": AnimalGroupRenderer.build_rabbit_mesh(
			AnimalGroupRenderer.RABBIT_BODY_LENGTH, AnimalGroupRenderer.RABBIT_BODY_WIDTH,
			AnimalGroupRenderer.RABBIT_EAR_LENGTH, AnimalGroupRenderer.RABBIT_EAR_WIDTH,
			AnimalGroupRenderer.RABBIT_COLOR
		),
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
		"move_speed": deer_rules.move_speed if deer_rules != null else 3.5,
		"turn_rate": deer_rules.turn_rate if deer_rules != null else 1.2,
		"max_individuals_per_cluster": deer_rules.max_individuals_per_cluster if deer_rules != null else 1,
		"cluster_comfort_radius": deer_rules.cluster_comfort_radius if deer_rules != null else 6.0,
		"cluster_attraction_strength": deer_rules.cluster_attraction_strength if deer_rules != null else 1.5,
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
		"mesh": AnimalGroupRenderer.build_deer_mesh(
			AnimalGroupRenderer.DEER_BODY_LENGTH, AnimalGroupRenderer.DEER_BODY_WIDTH,
			AnimalGroupRenderer.DEER_EAR_LENGTH, AnimalGroupRenderer.DEER_EAR_WIDTH,
			AnimalGroupRenderer.DEER_COLOR
		),
	})

	# Cinghiale: stesso schema di rabbit/deer sopra, inclusi i 4 parametri di Cluster Movement
	# (data-driven da AnimalRules/boar.tres grazie al refactor che li ha resi generici — nessun
	# valore hardcoded qui, a differenza di come erano rabbit/deer prima di quel refactor).
	boar_renderer = AnimalGroupRenderer.new()
	add_child(boar_renderer)
	var boar_rules := AnimalCalculator.get_animal_rules("boar")
	boar_renderer.configure({
		"individuals_per_group": boar_rules.visual_group_size if boar_rules != null else 1,
		"move_speed": boar_rules.move_speed if boar_rules != null else 3.0,
		"turn_rate": boar_rules.turn_rate if boar_rules != null else 1.5,
		"max_individuals_per_cluster": boar_rules.max_individuals_per_cluster if boar_rules != null else 1,
		"cluster_comfort_radius": boar_rules.cluster_comfort_radius if boar_rules != null else 5.0,
		"cluster_attraction_strength": boar_rules.cluster_attraction_strength if boar_rules != null else 1.5,
		"hop_speed": boar_rules.hop_speed if boar_rules != null else 6.0,
		"movement_phase_duration_min": boar_rules.movement_phase_duration_min if boar_rules != null else 2.0,
		"movement_phase_duration_max": boar_rules.movement_phase_duration_max if boar_rules != null else 5.0,
		"rest_phase_duration_min": boar_rules.rest_phase_duration_min if boar_rules != null else 3.0,
		"rest_phase_duration_max": boar_rules.rest_phase_duration_max if boar_rules != null else 7.0,
		"hop_duration_min": boar_rules.hop_duration_min if boar_rules != null else 0.2,
		"hop_duration_max": boar_rules.hop_duration_max if boar_rules != null else 0.4,
		"hop_pause_min": boar_rules.hop_pause_min if boar_rules != null else 0.1,
		"hop_pause_max": boar_rules.hop_pause_max if boar_rules != null else 0.3,
		"size_multiplier_by_age": boar_rules.size_multiplier_by_age if boar_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_boar_mesh(
			AnimalGroupRenderer.BOAR_BODY_LENGTH, AnimalGroupRenderer.BOAR_BODY_WIDTH,
			AnimalGroupRenderer.BOAR_EAR_LENGTH, AnimalGroupRenderer.BOAR_EAR_WIDTH,
			AnimalGroupRenderer.BOAR_COLOR
		),
	})

	# Tarpan: stesso schema di rabbit/deer/boar sopra.
	tarpan_renderer = AnimalGroupRenderer.new()
	add_child(tarpan_renderer)
	var tarpan_rules := AnimalCalculator.get_animal_rules("tarpan")
	tarpan_renderer.configure({
		"individuals_per_group": tarpan_rules.visual_group_size if tarpan_rules != null else 1,
		"move_speed": tarpan_rules.move_speed if tarpan_rules != null else 3.0,
		"turn_rate": tarpan_rules.turn_rate if tarpan_rules != null else 1.5,
		"max_individuals_per_cluster": tarpan_rules.max_individuals_per_cluster if tarpan_rules != null else 1,
		"cluster_comfort_radius": tarpan_rules.cluster_comfort_radius if tarpan_rules != null else 5.0,
		"cluster_attraction_strength": tarpan_rules.cluster_attraction_strength if tarpan_rules != null else 1.5,
		"hop_speed": tarpan_rules.hop_speed if tarpan_rules != null else 6.0,
		"movement_phase_duration_min": tarpan_rules.movement_phase_duration_min if tarpan_rules != null else 2.0,
		"movement_phase_duration_max": tarpan_rules.movement_phase_duration_max if tarpan_rules != null else 5.0,
		"rest_phase_duration_min": tarpan_rules.rest_phase_duration_min if tarpan_rules != null else 3.0,
		"rest_phase_duration_max": tarpan_rules.rest_phase_duration_max if tarpan_rules != null else 7.0,
		"hop_duration_min": tarpan_rules.hop_duration_min if tarpan_rules != null else 0.2,
		"hop_duration_max": tarpan_rules.hop_duration_max if tarpan_rules != null else 0.4,
		"hop_pause_min": tarpan_rules.hop_pause_min if tarpan_rules != null else 0.1,
		"hop_pause_max": tarpan_rules.hop_pause_max if tarpan_rules != null else 0.3,
		"size_multiplier_by_age": tarpan_rules.size_multiplier_by_age if tarpan_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_tarpan_mesh(
			AnimalGroupRenderer.TARPAN_BODY_LENGTH, AnimalGroupRenderer.TARPAN_BODY_WIDTH,
			AnimalGroupRenderer.TARPAN_EAR_LENGTH, AnimalGroupRenderer.TARPAN_EAR_WIDTH,
			AnimalGroupRenderer.TARPAN_COLOR
		),
	})

	# Aurochs: stesso schema di rabbit/deer/boar/tarpan sopra.
	aurochs_renderer = AnimalGroupRenderer.new()
	add_child(aurochs_renderer)
	var aurochs_rules := AnimalCalculator.get_animal_rules("aurochs")
	aurochs_renderer.configure({
		"individuals_per_group": aurochs_rules.visual_group_size if aurochs_rules != null else 1,
		"move_speed": aurochs_rules.move_speed if aurochs_rules != null else 3.0,
		"turn_rate": aurochs_rules.turn_rate if aurochs_rules != null else 1.5,
		"max_individuals_per_cluster": aurochs_rules.max_individuals_per_cluster if aurochs_rules != null else 1,
		"cluster_comfort_radius": aurochs_rules.cluster_comfort_radius if aurochs_rules != null else 5.0,
		"cluster_attraction_strength": aurochs_rules.cluster_attraction_strength if aurochs_rules != null else 1.5,
		"hop_speed": aurochs_rules.hop_speed if aurochs_rules != null else 6.0,
		"movement_phase_duration_min": aurochs_rules.movement_phase_duration_min if aurochs_rules != null else 2.0,
		"movement_phase_duration_max": aurochs_rules.movement_phase_duration_max if aurochs_rules != null else 5.0,
		"rest_phase_duration_min": aurochs_rules.rest_phase_duration_min if aurochs_rules != null else 3.0,
		"rest_phase_duration_max": aurochs_rules.rest_phase_duration_max if aurochs_rules != null else 7.0,
		"hop_duration_min": aurochs_rules.hop_duration_min if aurochs_rules != null else 0.2,
		"hop_duration_max": aurochs_rules.hop_duration_max if aurochs_rules != null else 0.4,
		"hop_pause_min": aurochs_rules.hop_pause_min if aurochs_rules != null else 0.1,
		"hop_pause_max": aurochs_rules.hop_pause_max if aurochs_rules != null else 0.3,
		"size_multiplier_by_age": aurochs_rules.size_multiplier_by_age if aurochs_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_aurochs_mesh(
			AnimalGroupRenderer.AUROCHS_BODY_LENGTH, AnimalGroupRenderer.AUROCHS_BODY_WIDTH,
			AnimalGroupRenderer.AUROCHS_EAR_LENGTH, AnimalGroupRenderer.AUROCHS_EAR_WIDTH,
			AnimalGroupRenderer.AUROCHS_COLOR
		),
	})

	# Wild donkey: stesso schema di rabbit/deer/boar/tarpan/aurochs sopra.
	wild_donkey_renderer = AnimalGroupRenderer.new()
	add_child(wild_donkey_renderer)
	var wild_donkey_rules := AnimalCalculator.get_animal_rules("wild_donkey")
	wild_donkey_renderer.configure({
		"individuals_per_group": wild_donkey_rules.visual_group_size if wild_donkey_rules != null else 1,
		"move_speed": wild_donkey_rules.move_speed if wild_donkey_rules != null else 3.0,
		"turn_rate": wild_donkey_rules.turn_rate if wild_donkey_rules != null else 1.5,
		"max_individuals_per_cluster": wild_donkey_rules.max_individuals_per_cluster if wild_donkey_rules != null else 1,
		"cluster_comfort_radius": wild_donkey_rules.cluster_comfort_radius if wild_donkey_rules != null else 5.0,
		"cluster_attraction_strength": wild_donkey_rules.cluster_attraction_strength if wild_donkey_rules != null else 1.5,
		"hop_speed": wild_donkey_rules.hop_speed if wild_donkey_rules != null else 6.0,
		"movement_phase_duration_min": wild_donkey_rules.movement_phase_duration_min if wild_donkey_rules != null else 2.0,
		"movement_phase_duration_max": wild_donkey_rules.movement_phase_duration_max if wild_donkey_rules != null else 5.0,
		"rest_phase_duration_min": wild_donkey_rules.rest_phase_duration_min if wild_donkey_rules != null else 3.0,
		"rest_phase_duration_max": wild_donkey_rules.rest_phase_duration_max if wild_donkey_rules != null else 7.0,
		"hop_duration_min": wild_donkey_rules.hop_duration_min if wild_donkey_rules != null else 0.2,
		"hop_duration_max": wild_donkey_rules.hop_duration_max if wild_donkey_rules != null else 0.4,
		"hop_pause_min": wild_donkey_rules.hop_pause_min if wild_donkey_rules != null else 0.1,
		"hop_pause_max": wild_donkey_rules.hop_pause_max if wild_donkey_rules != null else 0.3,
		"size_multiplier_by_age": wild_donkey_rules.size_multiplier_by_age if wild_donkey_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_wild_donkey_mesh(
			AnimalGroupRenderer.WILD_DONKEY_BODY_LENGTH, AnimalGroupRenderer.WILD_DONKEY_BODY_WIDTH,
			AnimalGroupRenderer.WILD_DONKEY_EAR_LENGTH, AnimalGroupRenderer.WILD_DONKEY_EAR_WIDTH,
			AnimalGroupRenderer.WILD_DONKEY_COLOR
		),
	})

	# Mouflon: stesso schema di rabbit/deer/boar/tarpan/aurochs/wild_donkey sopra.
	mouflon_renderer = AnimalGroupRenderer.new()
	add_child(mouflon_renderer)
	var mouflon_rules := AnimalCalculator.get_animal_rules("mouflon")
	mouflon_renderer.configure({
		"individuals_per_group": mouflon_rules.visual_group_size if mouflon_rules != null else 1,
		"move_speed": mouflon_rules.move_speed if mouflon_rules != null else 3.0,
		"turn_rate": mouflon_rules.turn_rate if mouflon_rules != null else 1.5,
		"max_individuals_per_cluster": mouflon_rules.max_individuals_per_cluster if mouflon_rules != null else 1,
		"cluster_comfort_radius": mouflon_rules.cluster_comfort_radius if mouflon_rules != null else 5.0,
		"cluster_attraction_strength": mouflon_rules.cluster_attraction_strength if mouflon_rules != null else 1.5,
		"hop_speed": mouflon_rules.hop_speed if mouflon_rules != null else 6.0,
		"movement_phase_duration_min": mouflon_rules.movement_phase_duration_min if mouflon_rules != null else 2.0,
		"movement_phase_duration_max": mouflon_rules.movement_phase_duration_max if mouflon_rules != null else 5.0,
		"rest_phase_duration_min": mouflon_rules.rest_phase_duration_min if mouflon_rules != null else 3.0,
		"rest_phase_duration_max": mouflon_rules.rest_phase_duration_max if mouflon_rules != null else 7.0,
		"hop_duration_min": mouflon_rules.hop_duration_min if mouflon_rules != null else 0.2,
		"hop_duration_max": mouflon_rules.hop_duration_max if mouflon_rules != null else 0.4,
		"hop_pause_min": mouflon_rules.hop_pause_min if mouflon_rules != null else 0.1,
		"hop_pause_max": mouflon_rules.hop_pause_max if mouflon_rules != null else 0.3,
		"size_multiplier_by_age": mouflon_rules.size_multiplier_by_age if mouflon_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_mouflon_mesh(
			AnimalGroupRenderer.MOUFLON_BODY_LENGTH, AnimalGroupRenderer.MOUFLON_BODY_WIDTH,
			AnimalGroupRenderer.MOUFLON_EAR_LENGTH, AnimalGroupRenderer.MOUFLON_EAR_WIDTH,
			AnimalGroupRenderer.MOUFLON_COLOR
		),
	})

	# Bezoar: stesso schema di rabbit/deer/boar/tarpan/aurochs/wild_donkey/mouflon sopra.
	bezoar_renderer = AnimalGroupRenderer.new()
	add_child(bezoar_renderer)
	var bezoar_rules := AnimalCalculator.get_animal_rules("bezoar")
	bezoar_renderer.configure({
		"individuals_per_group": bezoar_rules.visual_group_size if bezoar_rules != null else 1,
		"move_speed": bezoar_rules.move_speed if bezoar_rules != null else 3.0,
		"turn_rate": bezoar_rules.turn_rate if bezoar_rules != null else 1.5,
		"max_individuals_per_cluster": bezoar_rules.max_individuals_per_cluster if bezoar_rules != null else 1,
		"cluster_comfort_radius": bezoar_rules.cluster_comfort_radius if bezoar_rules != null else 5.0,
		"cluster_attraction_strength": bezoar_rules.cluster_attraction_strength if bezoar_rules != null else 1.5,
		"hop_speed": bezoar_rules.hop_speed if bezoar_rules != null else 6.0,
		"movement_phase_duration_min": bezoar_rules.movement_phase_duration_min if bezoar_rules != null else 2.0,
		"movement_phase_duration_max": bezoar_rules.movement_phase_duration_max if bezoar_rules != null else 5.0,
		"rest_phase_duration_min": bezoar_rules.rest_phase_duration_min if bezoar_rules != null else 3.0,
		"rest_phase_duration_max": bezoar_rules.rest_phase_duration_max if bezoar_rules != null else 7.0,
		"hop_duration_min": bezoar_rules.hop_duration_min if bezoar_rules != null else 0.2,
		"hop_duration_max": bezoar_rules.hop_duration_max if bezoar_rules != null else 0.4,
		"hop_pause_min": bezoar_rules.hop_pause_min if bezoar_rules != null else 0.1,
		"hop_pause_max": bezoar_rules.hop_pause_max if bezoar_rules != null else 0.3,
		"size_multiplier_by_age": bezoar_rules.size_multiplier_by_age if bezoar_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_bezoar_mesh(
			AnimalGroupRenderer.BEZOAR_BODY_LENGTH, AnimalGroupRenderer.BEZOAR_BODY_WIDTH,
			AnimalGroupRenderer.BEZOAR_EAR_LENGTH, AnimalGroupRenderer.BEZOAR_EAR_WIDTH,
			AnimalGroupRenderer.BEZOAR_COLOR
		),
	})

	# Partridge: stesso schema di rabbit/deer/boar/tarpan/aurochs/wild_donkey/mouflon/bezoar sopra
	# — prima specie non-mammifero (sagoma con ali ripiegate invece di orecchie/corna, vedi
	# AnimalGroupRenderer.build_partridge_mesh), stessa pipeline di configurazione, nessuna
	# differenza di trattamento qui.
	partridge_renderer = AnimalGroupRenderer.new()
	add_child(partridge_renderer)
	var partridge_rules := AnimalCalculator.get_animal_rules("partridge")
	partridge_renderer.configure({
		"individuals_per_group": partridge_rules.visual_group_size if partridge_rules != null else 1,
		"move_speed": partridge_rules.move_speed if partridge_rules != null else 3.0,
		"turn_rate": partridge_rules.turn_rate if partridge_rules != null else 1.5,
		"max_individuals_per_cluster": partridge_rules.max_individuals_per_cluster if partridge_rules != null else 1,
		"cluster_comfort_radius": partridge_rules.cluster_comfort_radius if partridge_rules != null else 5.0,
		"cluster_attraction_strength": partridge_rules.cluster_attraction_strength if partridge_rules != null else 1.5,
		"hop_speed": partridge_rules.hop_speed if partridge_rules != null else 6.0,
		"movement_phase_duration_min": partridge_rules.movement_phase_duration_min if partridge_rules != null else 2.0,
		"movement_phase_duration_max": partridge_rules.movement_phase_duration_max if partridge_rules != null else 5.0,
		"rest_phase_duration_min": partridge_rules.rest_phase_duration_min if partridge_rules != null else 3.0,
		"rest_phase_duration_max": partridge_rules.rest_phase_duration_max if partridge_rules != null else 7.0,
		"hop_duration_min": partridge_rules.hop_duration_min if partridge_rules != null else 0.2,
		"hop_duration_max": partridge_rules.hop_duration_max if partridge_rules != null else 0.4,
		"hop_pause_min": partridge_rules.hop_pause_min if partridge_rules != null else 0.1,
		"hop_pause_max": partridge_rules.hop_pause_max if partridge_rules != null else 0.3,
		"size_multiplier_by_age": partridge_rules.size_multiplier_by_age if partridge_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_partridge_mesh(
			AnimalGroupRenderer.PARTRIDGE_BODY_LENGTH, AnimalGroupRenderer.PARTRIDGE_BODY_WIDTH,
			AnimalGroupRenderer.PARTRIDGE_EAR_LENGTH, AnimalGroupRenderer.PARTRIDGE_EAR_WIDTH,
			AnimalGroupRenderer.PARTRIDGE_COLOR
		),
	})

	wolf_renderer = AnimalGroupRenderer.new()
	add_child(wolf_renderer)
	var wolf_rules := AnimalCalculator.get_animal_rules("wolf")
	wolf_renderer.configure({
		"individuals_per_group": wolf_rules.visual_group_size if wolf_rules != null else 1,
		"move_speed": wolf_rules.move_speed if wolf_rules != null else 3.0,
		"turn_rate": wolf_rules.turn_rate if wolf_rules != null else 1.5,
		"max_individuals_per_cluster": wolf_rules.max_individuals_per_cluster if wolf_rules != null else 1,
		"cluster_comfort_radius": wolf_rules.cluster_comfort_radius if wolf_rules != null else 5.0,
		"cluster_attraction_strength": wolf_rules.cluster_attraction_strength if wolf_rules != null else 1.5,
		"hop_speed": wolf_rules.hop_speed if wolf_rules != null else 6.0,
		"movement_phase_duration_min": wolf_rules.movement_phase_duration_min if wolf_rules != null else 2.0,
		"movement_phase_duration_max": wolf_rules.movement_phase_duration_max if wolf_rules != null else 5.0,
		"rest_phase_duration_min": wolf_rules.rest_phase_duration_min if wolf_rules != null else 3.0,
		"rest_phase_duration_max": wolf_rules.rest_phase_duration_max if wolf_rules != null else 7.0,
		"hop_duration_min": wolf_rules.hop_duration_min if wolf_rules != null else 0.2,
		"hop_duration_max": wolf_rules.hop_duration_max if wolf_rules != null else 0.4,
		"hop_pause_min": wolf_rules.hop_pause_min if wolf_rules != null else 0.1,
		"hop_pause_max": wolf_rules.hop_pause_max if wolf_rules != null else 0.3,
		"size_multiplier_by_age": wolf_rules.size_multiplier_by_age if wolf_rules != null else [1.0, 1.0, 1.0],
		"mesh": AnimalGroupRenderer.build_wolf_mesh(
			AnimalGroupRenderer.WOLF_BODY_LENGTH, AnimalGroupRenderer.WOLF_BODY_WIDTH,
			AnimalGroupRenderer.WOLF_EAR_LENGTH, AnimalGroupRenderer.WOLF_EAR_WIDTH,
			AnimalGroupRenderer.WOLF_COLOR
		),
	})

	# Applica lo stato di visibilità ripristinato sopra (default true dei renderer altrimenti
	# resterebbe visibile anche se l'utente l'aveva disattivato prima di uscire).
	rabbit_renderer.set_animals_visible(animals_visible)
	deer_renderer.set_animals_visible(animals_visible)
	boar_renderer.set_animals_visible(animals_visible)
	tarpan_renderer.set_animals_visible(animals_visible)
	aurochs_renderer.set_animals_visible(animals_visible)
	wild_donkey_renderer.set_animals_visible(animals_visible)
	mouflon_renderer.set_animals_visible(animals_visible)
	bezoar_renderer.set_animals_visible(animals_visible)
	partridge_renderer.set_animals_visible(animals_visible)
	wolf_renderer.set_animals_visible(animals_visible)

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
	boar_renderer.clock = clock
	tarpan_renderer.clock = clock
	aurochs_renderer.clock = clock
	wild_donkey_renderer.clock = clock
	mouflon_renderer.clock = clock
	bezoar_renderer.clock = clock
	partridge_renderer.clock = clock
	wolf_renderer.clock = clock
	_update_calendar_display()


# Azzera lo stato di focus del LOD (Parte B, Punto 2) quando questa scena viene lasciata, per
# QUALUNQUE via — "Torna al Mondo" (_on_back_to_world_pressed), "Torna al menu principale"
# (_on_system_menu_action_selected), o una futura terza via non ancora scritta: _exit_tree() è il
# callback nativo di Godot invocato quando il nodo esce dall'albero (change_scene_to_file lo
# libera sempre), quindi copre ogni caso senza dover ricordare di richiamare l'azzeramento in ogni
# singolo gestore di bottone. Riporta lod_focus_state a {} = "nessun focus attivo" (vista mondo),
# lo stesso stato di partenza prima che questa scena venisse mai aperta — WorldScene, che riusa lo
# stesso macro_world per riferimento, torna quindi a vedere tutti i gruppi allo stesso modo, come
# oggi.
func _exit_tree() -> void:
	if macro_world != null:
		macro_world.lod_focus_state = {}
		macro_world.lod_focus_live_cells = {}


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

	# begin_vegetation_batch()/end_vegetation_batch() (vedi MicroCellRenderer.gd e il commento
	# gemello in GameScene._refresh_resource_visuals): senza batching i 6 setter chiamati qui sotto
	# ricostruivano TREE/SHRUB/GRASS più volte ciascuno sugli stessi individui.
	renderer.begin_vegetation_batch()

	var vegetation_service := VegetationPositionService.new()
	renderer.set_vegetation_positions(vegetation_service.generate_positions(macro_state, occupied, game_data.year, game_data.current_day))
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

	var this_cell := Vector2i(macro_cell.x, macro_cell.y)
	var rabbit_group := macro_world.find_population_group("rabbit", this_cell)
	_update_animal_renderer_population(rabbit_renderer, rabbit_group, AnimalCalculator.get_animal_rules("rabbit"), this_cell)
	var deer_group := macro_world.find_population_group("deer", this_cell)
	_update_animal_renderer_population(deer_renderer, deer_group, AnimalCalculator.get_animal_rules("deer"), this_cell)
	var boar_group := macro_world.find_population_group("boar", this_cell)
	_update_animal_renderer_population(boar_renderer, boar_group, AnimalCalculator.get_animal_rules("boar"), this_cell)
	var tarpan_group := macro_world.find_population_group("tarpan", this_cell)
	_update_animal_renderer_population(tarpan_renderer, tarpan_group, AnimalCalculator.get_animal_rules("tarpan"), this_cell)
	var aurochs_group := macro_world.find_population_group("aurochs", this_cell)
	_update_animal_renderer_population(aurochs_renderer, aurochs_group, AnimalCalculator.get_animal_rules("aurochs"), this_cell)
	var wild_donkey_group := macro_world.find_population_group("wild_donkey", this_cell)
	_update_animal_renderer_population(wild_donkey_renderer, wild_donkey_group, AnimalCalculator.get_animal_rules("wild_donkey"), this_cell)
	var mouflon_group := macro_world.find_population_group("mouflon", this_cell)
	_update_animal_renderer_population(mouflon_renderer, mouflon_group, AnimalCalculator.get_animal_rules("mouflon"), this_cell)
	var bezoar_group := macro_world.find_population_group("bezoar", this_cell)
	_update_animal_renderer_population(bezoar_renderer, bezoar_group, AnimalCalculator.get_animal_rules("bezoar"), this_cell)
	var partridge_group := macro_world.find_population_group("partridge", this_cell)
	_update_animal_renderer_population(partridge_renderer, partridge_group, AnimalCalculator.get_animal_rules("partridge"), this_cell)
	var wolf_group := macro_world.find_population_group("wolf", this_cell)
	_update_animal_renderer_population(wolf_renderer, wolf_group, AnimalCalculator.get_animal_rules("wolf"), this_cell)

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


# Popola un AnimalGroupRenderer con la quota di QUESTA cella (get_population_by_cell — con
# territori multi-cella, Step 5, group.population è il totale sull'INTERO territorio, non quanti
# individui sono realmente qui; stessa fonte di verità già usata da WorldInfoPanel/
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
	var save_service := GameSaveService.new()
	save_service.save_game_to_json(macro_world, game_data, path)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_animals_visibility":
			animals_visible = not animals_visible
			# Un solo toggle per tutta la fauna (rabbit + deer + boar + tarpan + aurochs +
			# wild_donkey + mouflon + bezoar + partridge + wolf, non uno per specie): nessun caso d'uso reale oggi
			# per nasconderle separatamente — se servirà un controllo più fine in futuro (es.
			# gameplay-specifico), lo si introduce allora.
			rabbit_renderer.set_animals_visible(animals_visible)
			deer_renderer.set_animals_visible(animals_visible)
			boar_renderer.set_animals_visible(animals_visible)
			tarpan_renderer.set_animals_visible(animals_visible)
			aurochs_renderer.set_animals_visible(animals_visible)
			wild_donkey_renderer.set_animals_visible(animals_visible)
			mouflon_renderer.set_animals_visible(animals_visible)
			bezoar_renderer.set_animals_visible(animals_visible)
			partridge_renderer.set_animals_visible(animals_visible)
			wolf_renderer.set_animals_visible(animals_visible)
			primary_actions_bar.set_slot_toggled(0, animals_visible)
			GameSettings.macro_cell_animals_visible = animals_visible
		&"toggle_flora_updates":
			flora_daily_updates_enabled = not flora_daily_updates_enabled
			primary_actions_bar.set_slot_toggled(1, flora_daily_updates_enabled)
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
