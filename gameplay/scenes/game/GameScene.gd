extends Node2D

# DEBITO TECNICO DELIBERATO: la logica di rendering di questa scena (MicroCellRenderer + i 10
# AnimalGroupRenderer, il ricalcolo posizioni vegetazione/pesci/pietre, i parametri età/sottotipo
# passati al renderer) è una DUPLICAZIONE di simulation/scripts/game/MacroCellScene.gd, non una
# condivisione (nessuna composizione/ereditarietà tra le due scene). Scelta concordata
# esplicitamente: GameScene (vista player reale) e MacroCellScene (vista debug) potranno
# divergere nel tempo — GameScene guadagnerà interazione/gameplay che MacroCellScene non avrà
# mai bisogno di avere, e viceversa MacroCellScene resterà uno strumento di debug/ispezione.
# Unificare il rendering condiviso (es. un componente comune instanziato da entrambe) è
# rimandato a quando GameScene sarà stabile — per ora, se una delle due cambia, l'altra va
# aggiornata a mano se il cambiamento deve valere per entrambe.
#
# STREAMING MULTI-CELLA: MicroCellRenderer/AnimalGroupRenderer/FogOfWarRenderer NON sono mai
# stati resi "consapevoli" di più celle — sono la STESSA classe condivisa con MacroCellScene
# (verificato: un solo file ciascuna, MacroCellScene.gd fa `MicroCellRenderer.new()` esattamente
# come qui), quindi qualunque modifica interna le avrebbe impattate. La soluzione: GameScene
# istanzia un'istanza INTERA di ciascuna per ogni macrocella "viva" (vedi LiveMacroCell.gd),
# ciascuna dentro un container Node2D posizionato con `position = offset_macro * MACRO_CELL_
# PIXELS` — Godot compone la trasformazione gratis, quindi ogni renderer/set di animali/fog
# continua a operare nel proprio spazio locale [0,100) esattamente come se fosse l'unica cella
# della scena (zero modifiche a quelle tre classi). Scope di questo primo step: al più 2 celle
# vive — il centro (dove si trova il player, sempre live_cells[center_macro_coords]) + al più UN
# vicino cardinale nella direzione di avvicinamento (vedi _update_live_neighbor), mai le 8
# circostanti, niente diagonali.

# Margine di clamp quando un attraversamento bordo viene bloccato (vedi _block_border_crossing):
# tiene l'individuo appena dentro il bordo attuale invece che un'intera microcella indietro.
const BORDER_CLAMP_EPSILON: float = 0.01

# Pixel per macrocella nello spazio condiviso di GameScene (stesso CELL_SIZE=10 di
# MicroCellRenderer/IndividualView, World.WIDTH=100 microcelle per lato) — usato per posizionare
# il container di ogni cella viva rispetto al centro (vedi _reposition_live_cells).
const MACRO_CELL_PIXELS: int = World.WIDTH * MicroCellRenderer.CELL_SIZE

# Margini (in microcelle, dal bordo condiviso) per attivare/disattivare un vicino vivo — due
# soglie diverse (isteresi) per evitare di attivare/disattivare di continuo quando il player
# oscilla vicino alla soglia: si attiva solo entro il margine stretto, ma una volta attivo resta
# tale finché non si supera quello largo. Vedi _compute_relevant_neighbor_offsets.
const LIVE_NEIGHBOR_ACTIVATE_MARGIN: float = 25.0
const LIVE_NEIGHBOR_DEACTIVATE_MARGIN: float = 35.0

var macro_world: World
var game_data: GameData

# Vector2i (coordinate macro ASSOLUTE) -> LiveMacroCell — vedi LiveMacroCell.gd. Al più 2 chiavi
# in questo step: center_macro_coords sempre presente, più al più un vicino cardinale vivo.
var live_cells: Dictionary = {}
# Coordinate macro della cella "centro" — quella in cui si trova fisicamente l'individuo
# (Individual.position è sempre relativo a QUESTA cella). Aggiornata solo da un vero
# attraversamento bordo (_attempt_macro_cell_transition), mai dall'attivazione/disattivazione
# del vicino (quella non cambia mai il centro, solo cosa altro è vivo intorno).
var center_macro_coords: Vector2i = Vector2i(-1, -1)
# Coordinate macro ASSOLUTE (non offset relativi al centro — restano valide invariate attraverso
# un cambio di centro, a differenza di un offset che andrebbe ritradotto ogni volta) di ogni
# vicino attualmente vivo oltre al centro — vedi _compute_relevant_neighbor_offsets/
# _update_live_neighbor. Fino a 3 chiavi (i 2 cardinali di un angolo + la diagonale), mai più.
var _active_neighbor_coords_set: Dictionary = {}
# Vector2i (coord macro) -> FogOfWarMemory, UNA per macrocella mai attivata in questa sessione,
# non solo per quelle attualmente vive — a differenza di live_cells (che perde una cella quando
# esce dal set vivo), questo dizionario non viene mai ripulito qui: una macrocella già visitata
# ritrova esattamente il proprio last_seen_by_position quando ridiventa viva (centrale o vicina),
# invece di ripartire da una memoria vuota come accadeva quando FogOfWarMemory era ricreata ad
# ogni _activate_live_cell. Deliberatamente NON persistito su salvataggio in questo step (solo
# in-sessione, si azzera comunque a fine partita) e deliberatamente senza limite di dimensione/
# pulizia — entrambi rimandati a un prossimo step dedicato una volta validata questa forma dati.
var fog_of_war_memories: Dictionary = {}

# Stesso schema di MacroCellScene per animals_visible (default ATTIVO, il toggle nel
# PrimaryActionsBar di GameInfoPanel serve a DISATTIVARLO — vedi _on_primary_action_pressed).
# flora_daily_updates_enabled invece default SPENTO (vedi GameSettings.game_scene_flora_updates_
# enabled per il perché — costo del rebuild giornaliero su tutte le celle vive). Entrambi i
# valori qui sotto sono comunque sempre sovrascritti da _ready() con quanto salvato in
# GameSettings prima di essere davvero usati — sono solo i default per una sessione mai toccata.
var animals_visible: bool = true
var flora_daily_updates_enabled: bool = false
var clock: GameClockController
# Individuo controllabile — vedi Individual.gd/IndividualView.gd/IndividualController.gd
# (gameplay/scripts/entities/) e IndividualMovementService.gd (gameplay/services/). Il
# movimento gira ogni frame in _process qui sotto, indipendentemente dal clock giorno/anno
# (confermato con l'utente).
var individual: Individual
var individual_view: IndividualView
var individual_controller: IndividualController
var individual_movement_service := IndividualMovementService.new()
# La camera segue individual.position ogni frame SOLO mentre individual.is_moving è true (vedi
# _process sotto) — durante una camminata questo produce lo scorrimento continuo atteso (la
# scena "scorre sotto" il player, invece di lasciarlo sparire fuori vista con lo zoom stretto);
# non appena l'individuo si ferma il segui si disattiva da solo e la camera torna libera
# (WASD/edge-pan di CameraController tornano pienamente efficaci), permettendo di allontanarsi
# per guardare celle già note/congelate (vedi FogOfWarMemory) senza che nulla la ricorregga.
# Nessun bisogno di uno "sgancio" esplicito: lo sgancio è già implicito nel fermarsi. Il bottone
# "🎯"/tasto X restano comunque il modo per ri-centrarla manualmente da ferma.
var camera_follows_individual: bool = true
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""

@onready var game_info_panel: GameInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/GameInfoPanel
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var help_dialog: HelpDialog = $HelpDialog
@onready var save_game_file_dialog: FileDialog = $SaveGameFileDialog
@onready var camera: Camera2D = $Camera2D
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

func _ready() -> void:
	# Ripristina lo stato dei due toggle dalla sessione precedente (vedi GameSettings): senza
	# questo, uscendo e rientrando in questa scena tornerebbero sempre al default "attivo",
	# perdendo silenziosamente la scelta dell'utente — stesso principio già usato da
	# MacroCellScene per i suoi due toggle (campi GameSettings separati, vedi lì per il perché).
	animals_visible = GameSettings.game_scene_animals_visible
	flora_daily_updates_enabled = GameSettings.game_scene_flora_updates_enabled

	year_title_label.text = tr("calendar_label")
	advance_year_button.text = "+1"
	advance_year_button.tooltip_text = tr("advance_year_tooltip")
	advance_year_button.pressed.connect(_on_advance_year_pressed)
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	game_info_panel.primary_actions_bar.set_slot_toggled(0, animals_visible)
	game_info_panel.primary_actions_bar.set_slot_toggled(1, flora_daily_updates_enabled)
	game_info_panel.primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	game_info_panel.secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))
	help_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(help_dialog))

	# --- Logica di ingresso -------------------------------------------------------------------
	# 1) Ritorno da WorldScene/MacroCellScene via bottone debug "🧍": riusa lo stato condiviso
	#    esattamente com'era, mai RI-scegliere una cella già nota (GameData.player_macro_cell_x/y)
	#    — stesso schema del ramo returning_from_macro_cell di WorldScene._ready().
	var returning := GameSettings.returning_to_player_view
	if returning:
		GameSettings.returning_to_player_view = false
		macro_world = GameSettings.active_world
		game_data = GameSettings.active_game_data
	else:
		# 2) Ingresso "vero": WorldScene._redirect_to_game_scene reindirizza qui, invece che a se
		# stessa, subito dopo _populate_new_world per una partita nuova (player_macro_cell_x/y
		# ancora -1 a questo punto) O subito dopo un caricamento da disco riuscito — usa lo
		# stesso canale condiviso di handoff già in uso ovunque nel progetto
		# (GameSettings.active_world/active_game_data), valorizzato lì prima del
		# change_scene_to_file.
		macro_world = GameSettings.active_world
		game_data = GameSettings.active_game_data
	# fog_of_war_memories letto qui, IDENTICO nei due rami: WorldScene._redirect_to_game_scene
	# valorizza sempre GameSettings.active_fog_of_war_memories prima di reindirizzare qui, sia per
	# una partita nuova ({} — fog_of_war_memories mai toccato lì, nessuna eredità indebita da una
	# partita precedente ancora viva in GameSettings in questo stesso processo) sia per un
	# salvataggio appena caricato (il contenuto vero, vedi GameLoadService) — e i due bottoni
	# debug "🧍" fanno lo stesso prima di un ritorno (_on_world_debug_pressed/_on_macro_cell_
	# debug_pressed). Il dizionario resta lo stesso oggetto scritto altrove (Dictionary è per
	# riferimento in GDScript) — nessuna copia necessaria.
	fog_of_war_memories = GameSettings.active_fog_of_war_memories

	if game_data == null:
		push_warning("Nessun game_data condiviso: creo un anno locale di riserva.")
		game_data = GameData.new()

	# BUGFIX (trovato in sessione reale): i due bottoni debug "🧍" impostano SEMPRE
	# returning_to_player_view=true, anche al primissimo click in assoluto su una partita appena
	# creata — in quel caso player_macro_cell_x/y sono ancora -1 nonostante returning=true, e il
	# ramo 1 sopra non li valorizza mai. Senza questo controllo la scena cadeva nel fallback
	# "mondo vuoto di riserva" sotto — silenzioso ma sbagliato (vista player vuota alla primissima
	# apertura). La guardia sotto (invariata: scatta solo se le coordinate sono ANCORA -1) copre
	# quindi sia il vero "ingresso 2" sia questo caso limite del "ritorno 1" — non ricalcola mai
	# una cella già nota, in nessuno dei due rami.
	if macro_world != null:
		if game_data.player_macro_cell_x == -1 or game_data.player_macro_cell_y == -1:
			# I quattro filtri/preferenza vengono dalle scelte CONGELATE di questa partita
			# (GameData.starting_*, valorizzate una volta sola in WorldScene._populate_new_world
			# alla creazione), non da GameSettings.selected_* (dato di flusso runtime,
			# potenzialmente stale dopo un load in una sessione successiva) — confermato con
			# l'utente.
			var chosen := FirstStartMacroCellSelectionService.new().select_starting_cell(
				macro_world,
				game_data.starting_exclude_hostile_start,
				game_data.starting_exclude_predator_territories,
				game_data.starting_resource_richness_preference,
				game_data.starting_guarantee_animal_presence
			)
			game_data.player_macro_cell_x = chosen.x
			game_data.player_macro_cell_y = chosen.y

	individual = Individual.new()
	# Riprende la posizione salvata (GameData.player_micro_x/y, vedi GameSaveService/
	# GameLoadService) se presente — sentinel -1.0/-1.0 (partita nuova, o save precedente
	# l'introduzione di questo campo) vuol dire "mai valorizzata": in quel caso resta il default
	# di sempre, al centro della griglia.
	if game_data.player_micro_x >= 0.0 and game_data.player_micro_y >= 0.0:
		individual.position = Vector2(game_data.player_micro_x, game_data.player_micro_y)
	else:
		individual.position = Vector2(World.WIDTH / 2.0, World.HEIGHT / 2.0)
	# Riprende lo zoom salvato (GameData.camera_zoom) se presente — sentinel -1.0 (partita nuova,
	# o save precedente l'introduzione di questo campo) vuol dire "mai valorizzato": in quel caso
	# resta lo zoom di default impostato in GameScene.tscn.
	if game_data.camera_zoom > 0.0:
		camera.zoom = Vector2(game_data.camera_zoom, game_data.camera_zoom)
	individual_view = IndividualView.new()
	add_child(individual_view)
	individual_view.setup(individual)
	# z_index invece di affidarsi all'ordine dei figli (che con lo streaming multi-cella non è più
	# un unico elenco piatto sotto GameScene, ma un container Node2D per cella viva, creato/
	# distrutto dinamicamente da _activate_live_cell/_deactivate_live_cell): senza questo,
	# individual_view finiva sotto il terreno della cella centrale (aggiunta DOPO di lui in
	# _ready()) e il pallino spariva. z_index=1 lo tiene sempre sopra terreno/animali (z_index=0
	# di default in ogni container) qualunque sia l'ordine reale di creazione dei container — vedi
	# anche fog_of_war_renderer.z_index=2 in _activate_live_cell, che deve restare sopra ANCHE a
	# individual_view.
	individual_view.z_index = 1

	# Prima cella viva: il centro. center_macro_coords va fissato PRIMA di attivarla, perché
	# _activate_live_cell non decide da sé "sono il centro" — è solo orchestrazione qui.
	center_macro_coords = Vector2i(game_data.player_macro_cell_x, game_data.player_macro_cell_y)
	_activate_live_cell(center_macro_coords.x, center_macro_coords.y)
	_reposition_live_cells()
	_rebind_fog_bindings()
	if macro_world != null:
		_refresh_lod_focus_region()
	_update_center_info_panel()

	individual_controller = IndividualController.new()
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer)

	_setup_clock()
	_assign_clock_to_all_live_cells()
	_update_calendar_display()

	# Centra la camera sul player UNA SOLA VOLTA all'ingresso in scena — copre sia una partita
	# nuova (individual al centro griglia) sia un salvataggio ripristinato (individual alla
	# posizione salvata, vedi player_micro_x/y sopra). Da qui in poi la camera resta libera
	# (camera_follows_individual segue solo mentre l'individuo si muove, vedi sopra).
	_center_camera_on_individual()


# Movimento dell'individuo controllabile: gira ogni frame, indipendentemente da clock.is_playing
# (il player deve poter esplorare la macrocella anche a simulazione in pausa — confermato con
# l'utente). Non tocca in alcun modo il pipeline giorno/anno di WorldTimeService.
func _process(delta: float) -> void:
	if individual != null:
		individual_movement_service.advance_movement(individual, delta)
		_check_macro_cell_border_crossing()
		_update_live_neighbor()

	for cell in live_cells.values():
		if cell.fog_of_war_renderer == null:
			continue
		# FogOfWarRenderer legge sempre individual.position direttamente dall'oggetto a cui è
		# stato legato in setup() (vedi _rebind_fog_bindings, richiamata solo quando center_
		# macro_coords cambia, non ogni frame): per il centro è già legato all'Individual vero
		# (stesso spazio locale per definizione, non serve toccare nulla qui), per un vicino
		# vivo è legato al suo individuo "ombra" (fog_proxy_individual) — questo qui sotto tiene
		# SOLO quella posizione ombra sincronizzata ogni frame, traducendo la posizione reale
		# nello spazio locale di QUELLA cella (offset macro * WIDTH/HEIGHT).
		if cell.fog_proxy_individual != null and (cell.macro_x != center_macro_coords.x or cell.macro_y != center_macro_coords.y):
			var offset := Vector2i(cell.macro_x, cell.macro_y) - center_macro_coords
			cell.fog_proxy_individual.position = individual.position - Vector2(offset.x * World.WIDTH, offset.y * World.HEIGHT)
		cell.fog_of_war_renderer.update_visibility(game_data.get_absolute_day())

	if camera_follows_individual and individual != null and individual.is_moving:
		_center_camera_on_individual()


func _unhandled_input(event: InputEvent) -> void:
	if individual_controller != null:
		individual_controller.handle_input(event)

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		_center_camera_on_individual()


# Sposta la camera esattamente sulla posizione corrente dell'individuo — stesso spazio pixel di
# IndividualView (individual.position, in microcelle, moltiplicata per lo stesso CELL_SIZE=10 di
# MicroCellRenderer/IndividualView). Sempre lo spazio della cella CENTRALE, che è sempre
# posizionata a offset zero (vedi _reposition_live_cells) — nessuna traduzione necessaria.
# Richiamato sia dal tasto X (_unhandled_input sopra) sia dal bottone "🎯" della
# PrimaryActionsBar (vedi _on_primary_action_pressed).
func _center_camera_on_individual() -> void:
	if individual == null:
		return
	camera.position = individual.position * MicroCellRenderer.CELL_SIZE


# Azzera lo stato di focus del LOD quando questa scena viene lasciata — stessa motivazione di
# MacroCellScene._exit_tree().
func _exit_tree() -> void:
	if macro_world != null:
		macro_world.lod_focus_state = {}
		macro_world.lod_focus_region = Rect2i()


# ============================================================================================
# Celle vive: attivazione/disattivazione/posizionamento (streaming multi-cella)
# ============================================================================================

# Crea e popola per intero una LiveMacroCell per (mx, my) — stesso lavoro che prima faceva
# _load_macro_cell per L'UNICA cella, ora parametrizzato: risoluzione cella/stato, rigenerazione
# del micro-mondo uniforme, vicini per il renderer, fiume, pietre, vegetazione/pesci/fauna (via
# _refresh_resource_visuals). NON tocca la focus region LOD (vedi _refresh_lod_focus_region,
# chiamata separatamente dal chiamante) né game_info_panel (vedi _update_center_info_panel, solo
# per il centro). Non ritorna mai null: se macro_world è null o la cella non esiste (bordo del
# mondo/coordinate invalide), crea comunque container/renderer con un mondo vuoto di riserva —
# stesso fallback che aveva _load_macro_cell. È compito del CHIAMANTE decidere se vale la pena
# attivare una cella (es. _update_live_neighbor non chiama questo metodo affatto se il vicino è
# oltre il bordo del mondo — vedi lì).
func _activate_live_cell(mx: int, my: int) -> LiveMacroCell:
	var cell := LiveMacroCell.new()
	cell.macro_x = mx
	cell.macro_y = my
	cell.macro_cell = macro_world.get_cell_at(mx, my) if macro_world != null else null
	cell.world = World.new()

	if cell.macro_cell != null:
		cell.world.generate_uniform_terrain(cell.macro_cell.terrain_base, cell.macro_cell.water_type, cell.macro_cell.coast_type)
	else:
		if macro_world == null:
			push_warning("Nessun mondo condiviso: genero un mondo vuoto di riserva.")
		else:
			push_warning("Macrocella (%d,%d) non trovata: genero un mondo vuoto di riserva." % [mx, my])
		cell.world.generate_empty_world()

	cell.container = Node2D.new()
	add_child(cell.container)

	cell.renderer = MicroCellRenderer.new()
	cell.container.add_child(cell.renderer)
	cell.renderer.setup(cell.world)

	cell.animal_renderers = _build_animal_renderers(cell.container)
	for r in cell.animal_renderers.values():
		r.set_animals_visible(animals_visible)
		r.clock = clock # può essere null qui (centro attivato prima di _setup_clock in _ready()); vedi _assign_clock_to_all_live_cells

	# Riusa la FogOfWarMemory già accumulata per QUESTE coordinate se questa macrocella è già
	# stata viva in questa sessione (vedi fog_of_war_memories) — ne crea una nuova vuota solo la
	# prima volta che (mx, my) diventa viva. Mai una FogOfWarMemory.new() incondizionata: quella
	# perderebbe ogni volta il last_seen_by_position accumulato in una visita precedente.
	var coords := Vector2i(mx, my)
	if not fog_of_war_memories.has(coords):
		fog_of_war_memories[coords] = FogOfWarMemory.new()
	cell.fog_of_war_memory = fog_of_war_memories[coords]
	# Individuo "ombra" per il fog: usato ogni volta che questa cella NON è il centro (vedi
	# _process/_rebind_fog_bindings) — crearlo comunque qui, anche per il centro dove resta
	# inutilizzato finché non smette di esserlo, evita un ramo separato.
	cell.fog_proxy_individual = Individual.new()
	cell.fog_of_war_renderer = FogOfWarRenderer.new()
	# ULTIMO figlio del container aggiunto apposta (vedi FogOfWarRenderer.gd): l'ordine dei figli
	# è l'ordine di disegno in Godot 2D, deve stare sopra renderer/animali per coprire davvero
	# tutto quello che nasconde ALL'INTERNO di questa cella. z_index=2 in più (non basterebbe da
	# solo l'essere ultimo figlio DEL CONTAINER): deve restare sopra anche a individual_view, che
	# è un fratello del container stesso, non un suo discendente — vedi z_index=1 su
	# individual_view in _ready() per il motivo per cui qui serve un valore ESPLICITO più alto,
	# non ci si può affidare all'ordine dei figli tra sotto-alberi diversi.
	cell.container.add_child(cell.fog_of_war_renderer)
	cell.fog_of_war_renderer.z_index = 2
	# Legato di default all'individuo ombra (mai quello vero qui): se questa cella è proprio la
	# cella centrale che si sta attivando, spetta al chiamante richiamare _rebind_fog_bindings()
	# subito dopo per ri-legarla all'Individual vero — _activate_live_cell non sa da sé se sta
	# attivando il centro o un vicino (vedi commento in testa alla funzione).
	cell.fog_of_war_renderer.setup(cell.fog_proxy_individual, cell.fog_of_war_memory)

	if cell.macro_cell != null and macro_world != null:
		# NIENTE cell.renderer.set_neighbors qui (a differenza di MacroCellScene, che la chiama
		# ancora): quella fascia di anteprima piatta da 40px (_draw_neighbor_previews, preesistente
		# e condivisa con MacroCellScene — colore pieno, niente griglia/vegetazione) è pensata per
		# UNA cella isolata senza vicini davvero renderizzati. Qui, quando un vicino diventa vivo
		# (vedi _update_live_neighbor), il suo container occupa ESATTAMENTE lo stesso spazio dove
		# quella fascia verrebbe disegnata — le due celle finirebbero per disegnare ciascuna la
		# propria fascia piatta sopra il contenuto vero dell'altra, proprio al confine condiviso
		# (il sintomo osservato: una banda piatta senza griglia tra due celle vive). Con lo
		# streaming multi-cella il vicino vero prende il ruolo che prima aveva l'anteprima.

		cell.macro_state = macro_world.get_cell_state_at(cell.macro_cell.x, cell.macro_cell.y)
		if cell.macro_state != null:
			if cell.macro_cell.water_type == GameTypes.WaterType.RIVER:
				var thickness_ratio: float = float(cell.macro_state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
				cell.renderer.set_river(cell.macro_cell.river_shape, thickness_ratio)
				cell.river_positions = RiverMicrocellService.get_river_positions(cell.macro_cell.river_shape, thickness_ratio)
				cell.river_exterior_occupied = _compute_river_exterior_occupied(cell.river_positions)

			var stone_service := StonePositionService.new()
			stone_service.generate_if_needed(cell.macro_state)
			cell.renderer.set_stone_positions(cell.macro_state.stone_positions)

			_refresh_resource_visuals(cell)

	live_cells[Vector2i(mx, my)] = cell
	return cell


func _deactivate_live_cell(coords: Vector2i) -> void:
	var cell: LiveMacroCell = live_cells.get(coords)
	if cell == null:
		return
	cell.container.queue_free()
	live_cells.erase(coords)


# Riposiziona il container di ogni cella viva rispetto al centro corrente — la cella centrale
# finisce sempre a offset zero, un vicino a ±MACRO_CELL_PIXELS sull'asse giusto. Richiamata ad
# ogni cambio di center_macro_coords e ad ogni attivazione/disattivazione del vicino (il centro
# non si muove mai in quei casi, ma è un'operazione economica su al più 2 celle, non vale la
# pena distinguere i casi).
func _reposition_live_cells() -> void:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		cell.container.position = Vector2(coords.x - center_macro_coords.x, coords.y - center_macro_coords.y) * MACRO_CELL_PIXELS


# Ricalcola la focus region LOD (LODOrchestrator) coprendo TUTTE le celle vive attuali, non solo
# il centro — un vicino vivo è visivamente presente quanto il centro, quindi le sue popolazioni
# animali restano Livello 2 (simulazione piena) esattamente come oggi fa il centro da solo,
# nessuna nuova categoria di LOD necessaria: set_focus_region riclassifica sempre TUTTE le
# popolazioni del mondo da zero, quindi una cella che esce dal set vivo torna candidata a
# Livello 1 automaticamente. Identico schema di MacroCellScene per l'invocazione di
# LODOrchestrator, solo la region ora può coprire più di una cella.
func _refresh_lod_focus_region() -> void:
	if macro_world == null or live_cells.is_empty():
		return

	var min_coords := center_macro_coords
	var max_coords := center_macro_coords
	for coords in live_cells:
		min_coords = Vector2i(min(min_coords.x, coords.x), min(min_coords.y, coords.y))
		max_coords = Vector2i(max(max_coords.x, coords.x), max(max_coords.y, coords.y))

	var focus_region := Rect2i(min_coords, max_coords - min_coords + Vector2i.ONE)
	var lod_result := LODOrchestrator.new().set_focus_region(macro_world, focus_region)
	LODOrchestrator.print_classification_log(lod_result)
	macro_world.lod_focus_region = focus_region
	macro_world.lod_focus_state = lod_result


func _update_center_info_panel() -> void:
	var center: LiveMacroCell = live_cells.get(center_macro_coords)
	if center != null and center.macro_cell != null:
		game_info_panel.set_coords(center.macro_cell.x, center.macro_cell.y)


# Ri-lega ogni FogOfWarRenderer vivo all'individuo giusto in base a chi è ORA il centro:
# l'Individual vero per la cella centrale, il proprio individuo ombra per chiunque altro (vedi
# LiveMacroCell.fog_proxy_individual e il commento in _process). Richiamata SOLO quando center_
# macro_coords cambia (prima attivazione in _ready(), commit di attraversamento) — mai ogni
# frame: setup() forza un queue_redraw(), richiamarlo ogni frame vanificherebbe l'early-out di
# FogOfWarRenderer.update_visibility. L'attivazione/disattivazione del solo vicino (_update_live_
# neighbor) non cambia mai chi è il centro, quindi non ha mai bisogno di richiamare questo.
func _rebind_fog_bindings() -> void:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.fog_of_war_renderer == null:
			continue
		if coords == center_macro_coords:
			cell.fog_of_war_renderer.setup(individual, cell.fog_of_war_memory)
		else:
			cell.fog_of_war_renderer.setup(cell.fog_proxy_individual, cell.fog_of_war_memory)


# ============================================================================================
# Attivazione dei vicini per prossimità (streaming) — gira ogni frame. Fino a 3 vicini oltre al
# centro: i 2 cardinali di un angolo insieme più la diagonale che li completa (mai la diagonale
# da sola, mai un raggio oltre il primo anello) — così vicino a un angolo del mondo si vedono le
# 4 celle davvero adiacenti (centro + 2 cardinali + diagonale), non solo 2.
# ============================================================================================

const CORNER_DIAGONAL_OFFSETS := [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

# Quali offset (cardinali + eventuale diagonale) sono abbastanza vicini da meritare un vicino
# vivo — isteresi PER DIREZIONE: un candidato già attivo resta tale finché resta entro il margine
# largo di disattivazione (evita di disattivarlo e riattivarlo subito solo perché il player ha
# oscillato di poche microcelle vicino a un bordo), un candidato non ancora attivo serve il
# margine stretto di attivazione per entrare. La diagonale è rilevante SOLO se lo sono insieme
# entrambi i cardinali che la delimitano (vicino a un vero angolo) — non ha una propria soglia di
# distanza, eredita l'isteresi dei due cardinali. Non serve gestire posizioni fuori
# [0, WIDTH)/[0, HEIGHT): _check_macro_cell_border_crossing gira PRIMA nello stesso _process e
# risolve sempre (blocca o conferma) qualunque sconfinamento nello stesso frame.
func _compute_relevant_neighbor_offsets() -> Array:
	var distance_by_cardinal := {
		Vector2i(-1, 0): individual.position.x,
		Vector2i(1, 0): float(World.WIDTH) - individual.position.x,
		Vector2i(0, -1): individual.position.y,
		Vector2i(0, 1): float(World.HEIGHT) - individual.position.y,
	}

	var relevant: Array = []
	for offset in distance_by_cardinal:
		var distance: float = distance_by_cardinal[offset]
		var is_active := _active_neighbor_coords_set.has(center_macro_coords + offset)
		var margin := LIVE_NEIGHBOR_DEACTIVATE_MARGIN if is_active else LIVE_NEIGHBOR_ACTIVATE_MARGIN
		if distance <= margin:
			relevant.append(offset)

	for diagonal in CORNER_DIAGONAL_OFFSETS:
		if relevant.has(Vector2i(diagonal.x, 0)) and relevant.has(Vector2i(0, diagonal.y)):
			relevant.append(diagonal)

	return relevant


# Traccia le coordinate ASSOLUTE dei vicini attivi (non offset relativi al centro): restano
# valide invariate attraverso un cambio di centro (_attempt_macro_cell_transition), a differenza
# di offset che andrebbero ritradotti ad ogni attraversamento — questo è ciò che permette al
# vicino appena attraversato di restare vivo senza nessuna gestione speciale nel commit: dopo un
# attraversamento verso est, il vecchio centro è semplicemente il "vicino a ovest" del nuovo
# centro, e la prossima chiamata a questo metodo lo riconosce da sola.
#
# BUGFIX: prima chiamava _refresh_lod_focus_region() (che riclassifica TUTTE le popolazioni del
# mondo e stampa il log — costoso con migliaia di popolazioni) incondizionatamente ad ogni frame,
# anche quando non cambiava assolutamente nulla (il vecchio guard d'uscita copriva solo "stesso
# vicino di prima", non "nessun vicino, come prima" — il caso comune quando si è lontani da ogni
# bordo). Ora `changed` traccia se il set di vicini attivi è davvero cambiato in questa chiamata,
# e reposition/focus-region girano solo in quel caso.
func _update_live_neighbor() -> void:
	if individual == null or macro_world == null:
		return

	var relevant_coords_set: Dictionary = {}
	for offset in _compute_relevant_neighbor_offsets():
		relevant_coords_set[center_macro_coords + offset] = true

	var changed := false

	for coords in _active_neighbor_coords_set.keys():
		if coords == center_macro_coords:
			# Il vicino appena attraversato È il nuovo centro (vedi commento sopra) — si toglie
			# dal tracking "vicini" senza disattivare nulla, il centro resta vivo per definizione.
			_active_neighbor_coords_set.erase(coords)
			continue
		if not relevant_coords_set.has(coords):
			_deactivate_live_cell(coords)
			_active_neighbor_coords_set.erase(coords)
			changed = true

	for coords in relevant_coords_set:
		if _active_neighbor_coords_set.has(coords):
			continue
		if not live_cells.has(coords):
			if macro_world.get_cell_at(coords.x, coords.y) == null:
				continue # bordo del mondo: nessuna cella da attivare in questa direzione
			_activate_live_cell(coords.x, coords.y)
		_active_neighbor_coords_set[coords] = true
		changed = true

	if not changed:
		return

	_reposition_live_cells()
	_refresh_lod_focus_region()


# ============================================================================================
# Attraversamento bordo — forma semplice: blocco e commit avvengono ENTRAMBI esattamente al
# bordo vero (0/WIDTH), nessuna soglia estesa. Prima di questa sessione esisteva una fascia di
# anteprima statica con soglia di commit posticipata (rimossa): non serve più rallentare
# l'attraversamento, perché ora il vicino è già reso per intero PRIMA che il player lo raggiunga
# (vedi _update_live_neighbor sopra) — il salto al bordo vero è già invisibile.
# ============================================================================================

# Punto di intercettazione dell'uscita dal bordo della griglia micro — richiamato ogni frame da
# _process, subito dopo il movimento. Un controllo per asse, non un unico controllo combinato:
# in caso di uscita diagonale (entrambi gli assi fuori range nello stesso frame) i due controlli
# vengono comunque eseguiti in sequenza nella stessa chiamata, gestendo il caso come due
# attraversamenti 4-connessi consecutivi (es. prima verso est, poi verso nord) invece di
# richiedere un vicino diagonale non previsto (sempre e solo N/S/E/O).
func _check_macro_cell_border_crossing() -> void:
	if individual == null or macro_world == null:
		return

	if individual.position.x < 0.0:
		_attempt_macro_cell_transition(-1, 0)
	elif individual.position.x >= float(World.WIDTH):
		_attempt_macro_cell_transition(1, 0)

	if individual == null:
		return

	if individual.position.y < 0.0:
		_attempt_macro_cell_transition(0, -1)
	elif individual.position.y >= float(World.HEIGHT):
		_attempt_macro_cell_transition(0, 1)


# Gestisce un tentativo di uscita in direzione (dx, dy) — sempre un solo asse alla volta, l'altro
# è sempre 0 (vedi _check_macro_cell_border_crossing sopra). Se la macrocella adiacente non
# esiste (bordo del mondo) o la microcella di ingresso è acqua, l'individuo resta all'ultima
# posizione valida (_block_border_crossing, nessun attraversamento). Altrimenti conferma subito
# il cambio macrocella riusando lo stesso percorso di caricamento di _ready() (_activate_live_
# cell, di norma già eseguito in anticipo da _update_live_neighbor — vedi la rete di sicurezza
# sotto per il caso raro in cui non lo sia ancora).
func _attempt_macro_cell_transition(dx: int, dy: int) -> void:
	var target_x := center_macro_coords.x + dx
	var target_y := center_macro_coords.y + dy
	var target_cell := macro_world.get_cell_at(target_x, target_y)

	if target_cell == null:
		_block_border_crossing(dx, dy)
		return

	# Posizione di ingresso nella macrocella adiacente: la posizione "avvolge" dal lato opposto,
	# preservando la parte frazionaria per continuità visiva (uscire a x=100.3 verso est entra a
	# x=0.3 nella macrocella a est, non uno snap secco a 0.0). Solo l'asse attraversato cambia.
	var entry_position := individual.position
	if dx == 1:
		entry_position.x -= float(World.WIDTH)
	elif dx == -1:
		entry_position.x += float(World.WIDTH)
	if dy == 1:
		entry_position.y -= float(World.HEIGHT)
	elif dy == -1:
		entry_position.y += float(World.HEIGHT)

	if _is_entry_microcell_water(target_cell, entry_position):
		_block_border_crossing(dx, dy)
		return

	# Ferma il movimento in corso invece di lasciarlo proseguire nella nuova macrocella: il
	# target_position originale è in coordinate della VECCHIA macrocella, senza più significato
	# qui (e potrebbe ricadere di nuovo oltre il bordo, ritriggerando un altro attraversamento a
	# catena). Il giocatore imposta un nuovo target esplicitamente dopo l'arrivo.
	individual.stop()
	game_data.player_macro_cell_x = target_x
	game_data.player_macro_cell_y = target_y
	center_macro_coords = Vector2i(target_x, target_y)

	# Rete di sicurezza: non dovrebbe capitare quasi mai dato il pre-caricamento per prossimità
	# (_update_live_neighbor gira ogni frame, ben prima che l'individuo raggiunga davvero il
	# bordo vero, vedi LIVE_NEIGHBOR_ACTIVATE_MARGIN), ma un movimento molto rapido o un salvataggio
	# ripristinato già a ridosso del bordo potrebbe in teoria saltarlo.
	if not live_cells.has(center_macro_coords):
		_activate_live_cell(target_x, target_y)

	individual.position = entry_position
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer)
	_reposition_live_cells()
	_rebind_fog_bindings()
	_refresh_lod_focus_region()
	_update_center_info_panel()
	# individual.stop() sopra ha già disattivato is_moving, quindi il segui-camera in _process
	# (gated su is_moving, vedi camera_follows_individual) non ricentrerebbe più da solo in
	# questo stesso frame — senza questa chiamata esplicita la camera resterebbe ferma al bordo
	# vecchio mentre la posizione dell'individuo è appena saltata di un'intera macrocella
	# (avvolgimento), facendolo sparire dalla vista.
	_center_camera_on_individual()


# Ferma l'individuo esattamente al bordo della macrocella ATTUALE (mai un'intera microcella
# indietro) sull'asse (dx, dy) che ha tentato l'uscita — usato sia per il bordo del mondo
# (nessuna macrocella adiacente) sia per un'acqua di destinazione (_is_entry_microcell_water).
func _block_border_crossing(dx: int, dy: int) -> void:
	if dx == 1:
		individual.position.x = float(World.WIDTH) - BORDER_CLAMP_EPSILON
	elif dx == -1:
		individual.position.x = 0.0
	if dy == 1:
		individual.position.y = float(World.HEIGHT) - BORDER_CLAMP_EPSILON
	elif dy == -1:
		individual.position.y = 0.0
	individual.stop()


# Il micro-livello di ogni macrocella è terreno UNIFORME (vedi World.generate_uniform_terrain,
# usato anche da _activate_live_cell per ogni cella): "il tipo di terreno della microcella di
# destinazione" si riduce quasi sempre a un controllo sulla macrocella intera (terrain_base ==
# WATER copre SEA/LAKE, sempre completamente acqua), con l'unica eccezione di una macrocella-
# fiume (terra con una fascia fluviale locale) — lì la posizione di ingresso va confrontata con
# RiverMicrocellService.get_river_positions, lo stesso servizio già usato da _activate_live_cell,
# cosi il test di occupazione non può mai disallinearsi da cosa viene davvero disegnato.
func _is_entry_microcell_water(target_cell: MacroCellData, entry_position: Vector2) -> bool:
	if target_cell.terrain_base == GameTypes.TerrainBase.WATER:
		return true

	if target_cell.water_type == GameTypes.WaterType.RIVER:
		var target_state := macro_world.get_cell_state_at(target_cell.x, target_cell.y)
		if target_state != null:
			var thickness_ratio: float = float(target_state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
			var river_cells := RiverMicrocellService.get_river_positions(target_cell.river_shape, thickness_ratio)
			var entry_microcell := Vector2i(int(entry_position.x), int(entry_position.y))
			if river_cells.has(entry_microcell):
				return true

	return false


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


# Rigenera vegetazione/pesci/popolazioni animali/parametri età-frutta-stagione per UNA cella
# viva — stesso lavoro che prima faceva _refresh_resource_visuals sull'unica cella, ora
# parametrizzato. game_info_panel viene aggiornato solo se `cell` è il centro (vedi
# _update_center_info_panel): il pannello mostra dove si trova il player, non i vicini.
func _refresh_resource_visuals(cell: LiveMacroCell) -> void:
	if cell.macro_state == null:
		return

	var occupied: Dictionary = {}
	for pos in cell.macro_state.stone_positions:
		occupied[pos] = true
	for pos in cell.river_positions:
		occupied[pos] = true

	var vegetation_service := VegetationPositionService.new()
	cell.renderer.set_vegetation_positions(vegetation_service.generate_positions(cell.macro_state, occupied))

	var fish_positions: Array = []
	var fish_service := FishPositionService.new()
	if cell.macro_cell.water_type == GameTypes.WaterType.SEA or cell.macro_cell.water_type == GameTypes.WaterType.LAKE:
		fish_positions = fish_service.generate_positions(cell.macro_state)
	elif cell.macro_cell.water_type == GameTypes.WaterType.RIVER:
		var occupied_for_fish: Dictionary = cell.river_exterior_occupied.duplicate()
		for pos in cell.macro_state.stone_positions:
			occupied_for_fish[pos] = true
		fish_positions = fish_service.generate_positions(cell.macro_state, occupied_for_fish)
	cell.renderer.set_fish_positions(fish_positions)

	var this_cell := Vector2i(cell.macro_cell.x, cell.macro_cell.y)
	for species in cell.animal_renderers:
		var group := macro_world.find_population_group(species, this_cell)
		_update_animal_renderer_population(cell.animal_renderers[species], group, AnimalCalculator.get_animal_rules(species), this_cell)

	cell.renderer.set_shrub_fruit_ratio(_get_shrub_fruit_ratio(cell.macro_state))
	cell.renderer.set_shrub_age_params(game_data.year, _get_age_params(cell.macro_state, GameTypes.WorldObjectType.SHRUB))
	cell.renderer.set_tree_fruit_ratios(_get_tree_subtype_ratio(cell.macro_state, "wild_fruit"), _get_tree_subtype_ratio(cell.macro_state, "domesticable_fruit"))
	cell.renderer.set_tree_conifer_ratio(_get_tree_subtype_ratio(cell.macro_state, "conifer"))
	cell.renderer.set_tree_age_params(game_data.year, _get_age_params(cell.macro_state, GameTypes.WorldObjectType.TREE))
	cell.renderer.set_season(SeasonCalculator.get_season_for_day(game_data.current_day))

	if cell.macro_x == center_macro_coords.x and cell.macro_y == center_macro_coords.y:
		_update_info_panel()


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


# GameInfoPanel non ha ancora un corpo con dati da mostrare (body_container vuoto per ora — vedi
# GameInfoPanel.gd). Questo resta comunque il punto di aggancio invariato rispetto a
# MacroCellScene._update_info_panel (chiamato dagli stessi punti: fine di
# _refresh_resource_visuals per il centro e da _on_day_advanced nei giorni in cui quel rebuild
# viene saltato), cosi' quando GameInfoPanel guadagnera' un corpo reale il collegamento e' gia'
# pronto.
func _update_info_panel() -> void:
	pass


func _get_shrub_fruit_ratio(macro_state: MacroCellState) -> float:
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


func _get_age_params(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
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


func _get_tree_subtype_ratio(macro_state: MacroCellState, subtype_name: String) -> float:
	var composition := macro_state.get_subtype_composition(GameTypes.WorldObjectType.TREE)
	if composition.is_empty():
		return 0.0

	var total: int = 0
	for amount in composition.values():
		total += int(amount)
	if total <= 0:
		return 0.0

	return float(int(composition.get(subtype_name, 0))) / float(total)


# ============================================================================================
# Costruzione dei 10 AnimalGroupRenderer per una cella viva — stessa configurazione per ogni
# specie di sempre (fallback identici quando AnimalCalculator.get_animal_rules ritorna null),
# solo estratta in un helper riusabile una volta per cella invece che scritta una volta sola per
# tutta la scena.
# ============================================================================================

func _build_animal_renderer(container: Node2D, config: Dictionary) -> AnimalGroupRenderer:
	var r := AnimalGroupRenderer.new()
	container.add_child(r)
	r.configure(config)
	return r


func _build_animal_renderers(container: Node2D) -> Dictionary:
	var renderers: Dictionary = {}

	var rabbit_rules := AnimalCalculator.get_animal_rules("rabbit")
	renderers["rabbit"] = _build_animal_renderer(container, {
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

	var deer_rules := AnimalCalculator.get_animal_rules("deer")
	renderers["deer"] = _build_animal_renderer(container, {
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

	var boar_rules := AnimalCalculator.get_animal_rules("boar")
	renderers["boar"] = _build_animal_renderer(container, {
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

	var tarpan_rules := AnimalCalculator.get_animal_rules("tarpan")
	renderers["tarpan"] = _build_animal_renderer(container, {
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

	var aurochs_rules := AnimalCalculator.get_animal_rules("aurochs")
	renderers["aurochs"] = _build_animal_renderer(container, {
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

	var wild_donkey_rules := AnimalCalculator.get_animal_rules("wild_donkey")
	renderers["wild_donkey"] = _build_animal_renderer(container, {
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

	var mouflon_rules := AnimalCalculator.get_animal_rules("mouflon")
	renderers["mouflon"] = _build_animal_renderer(container, {
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

	var bezoar_rules := AnimalCalculator.get_animal_rules("bezoar")
	renderers["bezoar"] = _build_animal_renderer(container, {
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

	var partridge_rules := AnimalCalculator.get_animal_rules("partridge")
	renderers["partridge"] = _build_animal_renderer(container, {
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

	var wolf_rules := AnimalCalculator.get_animal_rules("wolf")
	renderers["wolf"] = _build_animal_renderer(container, {
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

	return renderers


func _assign_clock_to_all_live_cells() -> void:
	for cell in live_cells.values():
		for r in cell.animal_renderers.values():
			r.clock = clock


# Aggiorna GameData con la posizione ATTUALE dell'individuo/zoom camera (vedi Individual.position/
# Camera2D.zoom) — game_data è la stessa istanza scritta su disco da _on_save_game_file_selected
# E la stessa istanza riletta da _ready() al rientro in GameScene (returning_to_player_view),
# quindi basta valorizzarla qui perché sia il salvataggio vero sia un giro andata-ritorno per
# WorldScene/MacroCellScene (bottoni debug "🧍", che non passano MAI da un salvataggio) trovino
# la posizione aggiornata. BUGFIX: prima i due bottoni debug non richiamavano questo, quindi un
# giro verso WorldScene/MacroCellScene e ritorno faceva "dimenticare" ogni spostamento fatto
# dopo l'ultimo salvataggio vero, ripristinando invece la posizione salvata (o il centro griglia
# di default). game_data.player_macro_cell_x/y non serve toccarlo qui: è già tenuto aggiornato
# in tempo reale ad ogni attraversamento vero (vedi _attempt_macro_cell_transition), non solo al
# salvataggio.
func _sync_individual_state_to_game_data() -> void:
	if individual != null:
		game_data.player_micro_x = individual.position.x
		game_data.player_micro_y = individual.position.y
	# La posizione camera non ha stato proprio da salvare (segue sempre Individual mentre si
	# muove, vedi camera_follows_individual), solo lo zoom (zoom.x == zoom.y sempre).
	game_data.camera_zoom = camera.zoom.x


func _on_save_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo condiviso: impossibile salvare.")
		return
	_sync_individual_state_to_game_data()
	save_game_file_dialog.popup_centered()

func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()
	save_service.save_game_to_json(macro_world, game_data, path, fog_of_war_memories)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_animals_visibility":
			animals_visible = not animals_visible
			# Un solo toggle per tutta la fauna, di TUTTE le celle vive — stesso principio di
			# MacroCellScene, esteso a più di una cella.
			for cell in live_cells.values():
				for r in cell.animal_renderers.values():
					r.set_animals_visible(animals_visible)
			game_info_panel.primary_actions_bar.set_slot_toggled(0, animals_visible)
			GameSettings.game_scene_animals_visible = animals_visible
		&"toggle_flora_updates":
			flora_daily_updates_enabled = not flora_daily_updates_enabled
			game_info_panel.primary_actions_bar.set_slot_toggled(1, flora_daily_updates_enabled)
			GameSettings.game_scene_flora_updates_enabled = flora_daily_updates_enabled
		&"center_on_individual":
			_center_camera_on_individual()

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"help":
			help_dialog.open_dialog()
		&"menu":
			system_menu_dialog.open_menu()
		&"world_debug":
			_on_world_debug_pressed()
		&"macro_cell_debug":
			_on_macro_cell_debug_pressed()

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

	if checkpoint_ran or flora_daily_updates_enabled:
		for cell in live_cells.values():
			_refresh_resource_visuals(cell)
	else:
		_update_info_panel()

func _on_advance_year_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo condiviso: impossibile avanzare l'anno.")
		return
	clock.force_advance_to_year_end()

func _update_calendar_display() -> void:
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)


# STRUMENTO DI DEBUG (vedi GameInfoPanel.gd): da rimuovere o nascondere dietro un flag prima del
# player finale — il player non deve poter "teletrasportarsi" alla vista mondo a piacimento.
# Stesso schema di MacroCellScene._on_back_to_world_pressed: macro_world/game_data sono già gli
# stessi oggetti letti da GameSettings.active_world/active_game_data all'ingresso (mai
# riassegnati a qualcos'altro nel frattempo), quindi non serve riscriverli — solo lo stato
# dell'orologio, che invece cambia durante la sessione.
func _on_world_debug_pressed() -> void:
	_sync_individual_state_to_game_data()
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.returning_to_world_scene = true
	if clock != null and macro_world != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://simulation/scenes/game/WorldScene.tscn")


# STRUMENTO DI DEBUG (vedi GameInfoPanel.gd): da rimuovere o nascondere dietro un flag prima del
# player finale. Stesso schema del bottone "🧍" di WorldScene/MacroCellScene (_on_game_view_
# pressed) ma in direzione opposta: verso MacroCellScene, sulla STESSA cella in cui si trova il
# player (GameData.player_macro_cell_x/y) — nessun returning_to_* da impostare, MacroCellScene
# non ha un concetto di "ritorno", legge sempre selected_macro_cell_x/y + active_world fresco.
func _on_macro_cell_debug_pressed() -> void:
	_sync_individual_state_to_game_data()
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.selected_macro_cell_x = game_data.player_macro_cell_x
	GameSettings.selected_macro_cell_y = game_data.player_macro_cell_y
	GameSettings.active_world = macro_world
	GameSettings.active_game_data = game_data
	if clock != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://simulation/scenes/game/MacroCellScene.tscn")
