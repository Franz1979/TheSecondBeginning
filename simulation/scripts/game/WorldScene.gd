extends Node2D

# Durata dell'evidenziazione lampeggiante (WorldRenderer.flash_cells) delle celle del territorio
# di un PopulationGroup, quando l'utente clicca la sua riga nella tab Fauna del pannello — più
# lunga del feedback-pennello del map editor (WorldRenderer.PAINT_FLASH_DURATION), qui l'utente
# deve avere il tempo di individuare le celle sulla mappa, non solo confermare un click.
const POPULATION_HIGHLIGHT_DURATION: float = 2.0

# Vista principale del player su una singola macrocella (res://gameplay/scenes/game/). Ingresso
# "vero": _redirect_to_game_scene, chiamato da _ready() subito dopo il seeding di una partita
# nuova (_load_world -> _populate_new_world). Raggiungibile anche manualmente tramite il bottone
# debug "🧍" (_on_game_view_pressed) e l'equivalente in MacroCellScene.
const GAME_SCENE_PATH := "res://gameplay/scenes/game/GameScene.tscn"

var world: World
var game_data: GameData
# Vector2i (coord macro) -> FogOfWarMemory — WorldScene non genera mai fog propria (nessun
# concetto di visibilità qui), esiste solo per farla transitare intatta attraverso i punti in cui
# questa scena tocca world/game_data: da un salvataggio appena caricato (_load_world) fino a
# GameScene (_redirect_to_game_scene/_on_game_view_pressed) o di nuovo su disco se si salva da
# qui senza mai passare da GameScene (_on_save_game_file_selected) — stessa natura/motivazione di
# world/game_data sopra.
var fog_of_war_memories: Dictionary = {}
var renderer: WorldRenderer
var game_controller: CellSelectorController
var clock: GameClockController
# Gate sul redraw giornaliero costoso di WorldRenderer (griglia 100x100 immediate-mode) — vedi
# GameSettings.world_scene_redraw_enabled per il perché. Default true: comportamento
# invariato finché l'utente non lo disattiva esplicitamente.
var world_daily_redraw_enabled: bool = true
# true SOLO quando _load_world() ha appena caricato con successo un salvataggio ESISTENTE
# (GameSettings.selected_save_file) — false sia per una partita nuova (che ha già il proprio
# is_new_game) sia per un caricamento fallito (fallback su mondo vuoto, resta in WorldScene per
# poterlo diagnosticare, invariato). Vedi _ready(): un salvataggio caricato con successo deve
# riaprire GameScene con la posizione del player esattamente dov'era, non più mostrare WorldScene.
var _loaded_existing_save: bool = false
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""

@onready var primary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/PrimaryActionsBar
@onready var secondary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SecondaryActionsBar
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var world_info_panel: WorldInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/WorldInfoPanel
@onready var year_label: Label = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/YearLabel
@onready var play_pause_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/PlayPauseButton
@onready var speed_buttons: Dictionary = {
	GameClockController.Speed.X1: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed1xButton,
	GameClockController.Speed.X2: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed2xButton,
	GameClockController.Speed.X3: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed3xButton,
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
}
@onready var advance_year_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/CalendarHeaderContainer/AdvanceYearButton
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar
@onready var debug_animal_container: HBoxContainer = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugAnimalContainer
@onready var debug_animal_spin_box: SpinBox = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugAnimalContainer/DebugAnimalSpinBox
@onready var debug_animal_species_option: OptionButton = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugAnimalContainer/DebugAnimalSpeciesOption
@onready var debug_set_animal_button: Button = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/DebugAnimalContainer/DebugSetAnimalButton

func _ready() -> void:
	# Ripristina lo stato del toggle dalla sessione precedente (vedi GameSettings): senza questo,
	# uscendo e rientrando in questa scena (es. via MacroCellScene) tornerebbe sempre al default
	# "attivo", perdendo silenziosamente la scelta dell'utente — stesso principio già usato da
	# MacroCellScene per i suoi due toggle.
	world_daily_redraw_enabled = GameSettings.world_scene_redraw_enabled

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
	# Slot 1 e 2 lasciati vuoti apposta: i bottoni di navigazione stanno tutti accostati al bordo
	# destro della riga (slot 3), separati dal bottone opzioni a sinistra — vedi MacroCellScene
	# per lo stesso schema con anche back_to_world.
	secondary_actions_bar.configure_slot(3, "🧍", tr("game_view"), &"game_view", tr("game_view_description"))
	secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))

	debug_animal_container.visible = DebugLogging.ENABLED
	for species_name in AnimalCalculator.list_species_names():
		debug_animal_species_option.add_item(species_name)
	debug_set_animal_button.pressed.connect(_on_debug_set_animal_pressed)

	var returning_from_macro_cell := GameSettings.returning_to_world_scene
	var is_new_game := false
	if returning_from_macro_cell:
		GameSettings.returning_to_world_scene = false
		world = GameSettings.active_world
		game_data = GameSettings.active_game_data
		fog_of_war_memories = GameSettings.active_fog_of_war_memories
	else:
		is_new_game = _load_world()

	# Partita NUOVA appena seminata (vedi _load_world/_populate_new_world sotto) O un salvataggio
	# ESISTENTE appena caricato con successo (vedi _loaded_existing_save sopra): in entrambi i
	# casi il player deve aprire subito GameScene, non piu' WorldScene — per un salvataggio
	# esistente, GameData.player_macro_cell_x/y e player_micro_x/y sono gia' valorizzati da
	# GameLoadService, quindi GameScene riprende esattamente da dove il player aveva lasciato la
	# partita invece di sceglierne una nuova. Un caricamento FALLITO (fallback su mondo vuoto,
	# _loaded_existing_save resta false in quel ramo) continua invece a mostrare WorldScene come
	# prima, per poterlo diagnosticare.
	if is_new_game or _loaded_existing_save:
		_redirect_to_game_scene()
		return

	_create_renderer()
	_setup_clock()
	_update_calendar_display()

	game_controller = CellSelectorController.new()
	game_controller.setup(world, renderer)
	game_controller.cell_selected.connect(_on_cell_selected)
	world_info_panel.visible = true
	# Nessuna cella selezionata ancora a inizio scena: senza questo, le tab Fauna (dati
	# world-level, indipendenti dalla cella) resterebbero vuote finché l'utente non clicca una
	# cella almeno una volta — show_cell(null, ...) imposta comunque il riferimento world del
	# pannello prima del controllo "cell == null" interno, lasciando il resto del pannello vuoto
	# come atteso quando non c'è selezione.
	world_info_panel.show_cell(null, null, world)
	world_info_panel.population_group_highlight_requested.connect(_on_population_group_highlight_requested)
	world_info_panel.population_species_highlight_requested.connect(_on_population_species_highlight_requested)

	if returning_from_macro_cell:
		var cell := world.get_cell_at(GameSettings.selected_macro_cell_x, GameSettings.selected_macro_cell_y)
		if cell != null:
			_on_cell_selected(cell, world.get_cell_state_at(cell.x, cell.y))


# Ritorna true SOLO quando arriva davvero a seminare una partita nuova (_populate_new_world in
# fondo) — false in ogni uscita del ramo "carica salvataggio esistente"
# (GameSettings.selected_save_file), sia successo (vedi _loaded_existing_save, valorizzato li'
# sotto) sia fallback su mondo vuoto in caso di errore (un fallimento di caricamento non e' una
# partita nuova, e _loaded_existing_save resta false: _ready() lo tratta come "non
# reindirizzare", resta su WorldScene per poterlo diagnosticare). _ready() reindirizza a
# GameScene sia per is_new_game sia per _loaded_existing_save — vedi li'.
func _load_world() -> bool:
	if GameSettings.selected_save_file != "":
		var load_service := GameLoadService.new()
		var loaded_game := load_service.load_game_from_json(GameSettings.selected_save_file)
		if loaded_game == null:
			print("Caricamento partita fallito. Genero mondo vuoto.")
			game_data = GameData.new()
			world = World.new()
			world.generate_empty_world()
			return false
		world = loaded_game.world
		game_data = loaded_game.game_data
		fog_of_war_memories = loaded_game.fog_of_war_memories
		_loaded_existing_save = true
		return false

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

	_populate_new_world(world)
	return true

# Dispaccia verso il seminatore scelto in NewGameOptionsMenu (GameSettings.
# selected_world_age_mode, impostato li' subito prima di raggiungere questa scena — mai
# persistito nei save, solo un dato di flusso runtime come selected_map_type/selected_map_file).
# "CLASSIC" e' anche il default difensivo del campo stesso in GameSettings: se per qualunque
# motivo questa scena venisse raggiunta senza passare dalla schermata opzioni, il comportamento
# resta quello di sempre (InitialResourceSetupService invariato), non un livello a caso.
func _populate_new_world(target_world: World) -> void:
	# Statistica di difficolta' (vedi GameData) — valorizzata qui, l'unico punto in cui una
	# partita NUOVA viene davvero creata (mai per una partita caricata, vedi _load_world sopra),
	# prima di qualunque ramo CLASSIC/non-CLASSIC sotto cosi' viene registrata comunque, anche
	# per una partita CLASSIC (ratio -1.0 = non applicabile, ma le tre stringhe scelte restano
	# comunque utili per le statistiche).
	game_data.starting_world_age_mode = GameSettings.selected_world_age_mode
	game_data.starting_animal_density = GameSettings.selected_animal_density
	game_data.starting_population_size = GameSettings.selected_population_size
	game_data.starting_exclude_hostile_start = GameSettings.selected_exclude_hostile_start
	game_data.starting_exclude_predator_territories = GameSettings.selected_exclude_predator_territories
	game_data.starting_resource_richness_preference = GameSettings.selected_resource_richness_preference
	game_data.starting_group_size_preference = GameSettings.selected_group_size_preference
	game_data.starting_guarantee_animal_presence = GameSettings.selected_guarantee_animal_presence
	game_data.starting_difficulty_ratio = DifficultyCalculator.compute_difficulty_ratio(
		GameSettings.selected_world_age_mode,
		GameSettings.selected_animal_density,
		GameSettings.selected_population_size,
		GameSettings.selected_exclude_hostile_start,
		GameSettings.selected_exclude_predator_territories,
		GameSettings.selected_resource_richness_preference,
		GameSettings.selected_group_size_preference,
		GameSettings.selected_guarantee_animal_presence
	)

	if GameSettings.selected_world_age_mode == "CLASSIC":
		InitialResourceSetupService.new().populate_resources(target_world)
		return

	var age := GameTypes.WorldAge.OLD
	match GameSettings.selected_world_age_mode:
		"YOUNG":
			age = GameTypes.WorldAge.YOUNG
		"ADULT":
			age = GameTypes.WorldAge.ADULT
		"OLD":
			age = GameTypes.WorldAge.OLD
	ParametricResourceSetupService.new().populate_resources(target_world, age)

	# Semina automatica animali SOLO per un mondo non-CLASSIC (vedi guard sopra — un ritorno
	# anticipato per CLASSIC non arriva mai qui). GameSettings.selected_animal_density e'
	# ignorato del tutto quando CLASSIC e' scelto, esattamente come da richiesta: in quel caso il
	# mondo resta popolabile solo a mano via pannello debug, invariato.
	var density := GameTypes.AnimalDensity.MEDIUM
	match GameSettings.selected_animal_density:
		"FEW":
			density = GameTypes.AnimalDensity.FEW
		"MEDIUM":
			density = GameTypes.AnimalDensity.MEDIUM
		"MANY":
			density = GameTypes.AnimalDensity.MANY
	var population_size := GameTypes.PopulationSize.NORMAL
	match GameSettings.selected_population_size:
		"SPARSE":
			population_size = GameTypes.PopulationSize.SPARSE
		"NORMAL":
			population_size = GameTypes.PopulationSize.NORMAL
		"DENSE":
			population_size = GameTypes.PopulationSize.DENSE

	AnimalSeedingService.new().populate_animals(target_world, density, population_size)

# Ingresso "vero" per una partita NUOVA appena seminata O per un salvataggio ESISTENTE appena
# caricato con successo — chiamato da _ready() subito dopo _load_world() quando is_new_game o
# _loaded_existing_save e' true, PRIMA che WorldScene costruisca la propria vista
# (_create_renderer/_setup_clock). Stesso canale di handoff gia' in uso per i bottoni debug
# (GameSettings.active_world/active_game_data), ma NON returning_to_player_view = true: quel
# flag e' riservato al canale "torno dal debug" (vedi GameScene._ready() ramo 1, che riusa una
# cella gia' nota). Per una partita nuova, GameData.player_macro_cell_x/y sono ancora -1, quindi
# GameScene deve prendere il proprio ramo 2 e invocare da se' FirstStartMacroCellSelectionService
# — lasciare returning_to_player_view a false (il suo default) e' cio' che glielo permette. Per
# un salvataggio esistente, player_macro_cell_x/y e player_micro_x/y sono gia' valorizzati da
# GameLoadService: lo stesso ramo 2 di GameScene li trova gia' validi e non invoca la selezione,
# riprendendo semplicemente da dove il player aveva lasciato la partita.
#
# Stato clock azzerato esplicitamente ai default (pausa, velocita' 1x) invece di derivarlo da un
# GameClockController che qui non viene mai creato (vedi sotto): senza questo, un residuo di
# velocita'/play-state lasciato da una sessione precedente nella STESSA run dell'app (es.
# l'utente aveva premuto play a 3x, e' tornato al menu principale, ha avviato/caricato un'altra
# partita) trapelerebbe silenziosamente in questa, dato che GameSettings.active_clock_is_playing/
# active_clock_speed sono campi di sessione, non resettati automaticamente da un semplice cambio
# di scena. Stesso reset ragionevole sia per una partita nuova sia per un salvataggio appena
# aperto: nessuno dei due persiste play/pausa/velocita' del clock (solo GameData.year/current_day
# lo fanno), quindi ripartire in pausa a 1x e' il default piu' prevedibile in entrambi i casi.
#
# _create_renderer()/_setup_clock() (il resto della vista mondo, WorldRenderer immediate-mode
# sull'intera griglia 100x100 incluso) vengono deliberatamente SALTATI in questo ramo (vedi il
# "return" subito dopo la chiamata a questo metodo in _ready()): costruirli solo per lasciare
# la scena un istante dopo sarebbe lavoro sprecato.
func _redirect_to_game_scene() -> void:
	GameSettings.active_world = world
	GameSettings.active_game_data = game_data
	# {} per una partita nuova (fog_of_war_memories mai valorizzato in questo ramo), il contenuto
	# di un salvataggio appena caricato altrimenti (vedi _load_world) — stesso canale di handoff
	# di active_world/active_game_data sopra, letto da GameScene._ready() in entrambi i suoi rami.
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.active_clock_is_playing = false
	GameSettings.active_clock_speed = GameClockController.Speed.X1
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

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
	get_tree().change_scene_to_file("res://simulation/scenes/game/MacroCellScene.tscn")


func _on_population_group_highlight_requested(cells: Array) -> void:
	renderer.flash_cells(cells, POPULATION_HIGHLIGHT_DURATION)


func _on_population_species_highlight_requested(entries: Array) -> void:
	renderer.highlight_group_territories(entries, WorldInfoPanel.SPECIES_TERRITORY_HIGHLIGHT_DURATION)


func _on_cell_selected(cell: MacroCellData, state: MacroCellState) -> void:
	world_info_panel.show_cell(cell, state, world)
	renderer.set_selected_cell(cell)

func _on_save_game_pressed() -> void:
	save_game_file_dialog.popup_centered()

func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()

	save_service.save_game_to_json(
		world,
		game_data,
		path,
		fog_of_war_memories
	)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_world_redraw":
			world_daily_redraw_enabled = not world_daily_redraw_enabled
			primary_actions_bar.set_slot_toggled(0, world_daily_redraw_enabled)
			GameSettings.world_scene_redraw_enabled = world_daily_redraw_enabled

# Canale "debug": ritorno manuale alla vista player da WorldScene senza essere appena arrivati da
# una partita nuova (vedi _redirect_to_game_scene per l'ingresso "vero" post-seeding). Stesso
# schema dell'equivalente in MacroCellScene._on_game_view_pressed.
func _on_game_view_pressed() -> void:
	GameSettings.active_world = world
	GameSettings.active_game_data = game_data
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.returning_to_player_view = true
	if clock != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
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
			get_tree().change_scene_to_file("res://simulation/scenes/menus/MainMenu.tscn")
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
		world_info_panel.show_cell(renderer.selected_cell, state, world)
	else:
		# Le tab Fauna sono dati world-level (non legati alla cella selezionata): senza una cella
		# selezionata, show_cell sopra non viene mai chiamata — vanno comunque rinfrescate qui se
		# l'utente le ha aperte, altrimenti restano ferme finché non seleziona/deseleziona una
		# cella (il bug segnalato: "si aggiornano solo entrando e uscendo da una cella").
		world_info_panel.refresh_world_tabs_if_active()

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

func _on_debug_set_animal_pressed() -> void:
	if debug_animal_species_option.item_count == 0:
		return
	var species_name := debug_animal_species_option.get_item_text(debug_animal_species_option.selected)
	var coords := _debug_target_coords()
	var count := int(debug_animal_spin_box.value)

	var rules := AnimalCalculator.get_animal_rules(species_name)
	var group := world.find_population_group(species_name, coords)
	if group == null:
		group = PopulationGroup.new(species_name, _build_initial_territory(coords, rules, species_name), world.allocate_population_group_id())
		world.population_groups.append(group)
		# Branchi predatori (PredatorRules, es. wolf): patrol_route va calcolato SUBITO dopo la
		# creazione del territorio, non lasciato vuoto — PredationService._process_group non tenta
		# mai una caccia se group.patrol_route.is_empty() (guard esplicito lì). Solo alla creazione:
		# il territorio di un gruppo esistente non cambia più da qui (nessuna logica di espansione/
		# contrazione per predatori ancora, vedi PredatorRules.gd), quindi non serve ricalcolare se
		# il bottone viene premuto di nuovo sulla stessa specie/cella (branch group == null sopra
		# non rientra in quel caso).
		if rules is PredatorRules:
			PredatorPatrolService.new().recompute_route(group, rules as PredatorRules)
	group.set_population(count)
	# Riallinea age_composition al nuovo totale (vedi PopulationGroup.set_age_composition) —
	# senza questo, la maturazione delle age band non avrebbe mai dati su cui operare finché la
	# natalità (prompt futuro) non esiste ancora.
	var age_weights: Dictionary = rules.initial_age_ratio if rules != null else {}
	group.set_age_composition(count, age_weights)
	world_info_panel.refresh_world_tabs_if_active()
	print("[DEBUG] %s population #%d (%d,%d) impostata a %d" % [species_name, group.id, coords.x, coords.y, count])


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
