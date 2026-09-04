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
# MicroCellRenderer/HumanIndividualView, World.WIDTH=100 microcelle per lato) — usato per posizionare
# il container di ogni cella viva rispetto al centro (vedi _reposition_live_cells).
const MACRO_CELL_PIXELS: int = World.WIDTH * MicroCellRenderer.CELL_SIZE

# Proposta 2 (mitigazione "pop-in"): distanza minima (microcelle) percorsa dal player dall'ultimo
# refresh vegetazione della cella centrale prima di richiederne un altro — vedi _process sotto e
# _refresh_resource_visuals (che aggiorna _last_vegetation_refresh_position ad ogni chiamata,
# qualunque sia la causa: checkpoint, taglio, edificio, o questo trigger da movimento). Metà del
# visibility_radius di default di FogOfWarRenderer (6.0): abbastanza piccolo da tenere il ritardo
# di reveal contenuto mentre cammini, abbastanza grande da non rifare il rebuild ad ogni singolo
# frame di movimento (costerebbe carissimo, vedi [VEG REFRESH TIMING]).
const VEGETATION_REFRESH_MOVE_THRESHOLD: float = 3.0

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
# (HumanIndividual.position è sempre relativo a QUESTA cella). Aggiornata solo da un vero
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

# DEBUG TEMPORANEO — misura quanti individui TREE/SHRUB stiamo trattando come tali, per macrocella
# mai per costruzione più delle celle vive/appena uscite dal set vivo (max 4) con questo sistema —
# serve da baseline prima del redesign "individui solo dove il fog è fresco" (vedi discussione con
# l'utente sul rischio di 200 macrocelle sempre calcolate per individuo con edifici che alimentano
# il fog permanentemente). Da rimuovere una volta completata la misurazione.
var _debug_individual_counts_by_macro: Dictionary = {}

# Posizione (spazio locale della cella centrale, stesse unità di individual.position) all'ultimo
# refresh vegetazione della cella centrale — vedi VEGETATION_REFRESH_MOVE_THRESHOLD/_process.
# Sentinel Vector2(INF, INF): forza il primo controllo in _process a considerare "spostato
# abbastanza" vero, anche se di fatto il primo refresh vero lo fa già _ready() esplicitamente
# (vedi lì) — qui serve solo a non lasciare un valore arbitrario prima del primo aggiornamento
# reale (fatto da _refresh_resource_visuals stessa, per QUALUNQUE causa di refresh, non solo
# questo trigger da movimento).
var _last_vegetation_refresh_position: Vector2 = Vector2(INF, INF)

# Stesso schema di MacroCellScene per animals_visible (default ATTIVO, il toggle nel
# PrimaryActionsBar di GameInfoPanel serve a DISATTIVARLO — vedi _on_primary_action_pressed).
# flora_daily_updates_enabled invece default SPENTO (vedi GameSettings.game_scene_flora_updates_
# enabled per il perché — costo del rebuild giornaliero su tutte le celle vive). Entrambi i
# valori qui sotto sono comunque sempre sovrascritti da _ready() con quanto salvato in
# GameSettings prima di essere davvero usati — sono solo i default per una sessione mai toccata.
var animals_visible: bool = true
var flora_daily_updates_enabled: bool = false
var clock: GameClockController
# Primo consumatore gameplay-side dei checkpoint temporali classificati (richiesta utente,
# 2026-09-05) — vedi GameTimeService per il perché va tenuto in un campo (RefCounted, ma non
# usa-e-getta come gli altri *Service: deve restare vivo quanto clock perché le sue connessioni ai
# segnali di clock sopravvivano).
var game_time_service: GameTimeService
# "individual" è ora il BERSAGLIO CORRENTE di movimento/streaming (Step 2 del piano movimento
# indipendente, 2026-09-02 — non più un "leader" fisso: coincide con human_individuals[0] solo come
# valore INIZIALE assegnato in _ready(), vedi lì). Cambia ogni volta che la selezione cambia su un
# individuo diverso (vedi _set_movement_target, richiamato da _unhandled_input dopo un hit di
# human_individual_selector_controller) — mai su una deselezione (click a vuoto): senza un bersaglio
# nuovo esplicito, movimento/streaming restano ancorati all'ultimo individuo che li deteneva
# (richiesta utente, 2026-09-02, punto 3). individual_controller/individual_movement_service sotto
# sono entrambi stateless rispetto all'identità (vedi HumanIndividualController/
# HumanIndividualMovementService) — un solo controller/service condiviso, ri-agganciato via
# individual_controller.setup() ad ogni cambio di bersaglio, mai un'istanza per individuo. Il
# movimento gira ogni frame in _process qui sotto, indipendentemente dal clock giorno/anno
# (confermato con l'utente). Nessun supporto a movimento simultaneo multiplo in questo step: un solo
# bersaglio alla volta, mai più di un individuo in movimento nello stesso momento.
var individual: HumanIndividual
var individual_controller: HumanIndividualController
var individual_movement_service := HumanIndividualMovementService.new()
# Hit-test di selezione per QUALSIASI individuo umano visibile — vedi HumanIndividualSelectorController.gd.
# Sostituisce, per il click sinistro, quello che prima faceva HumanIndividualController._try_select
# (ora rimossa da lì, richiesta utente 2026-09-02: "click su un individuo qualsiasi tra quelli
# visibili", non solo human_individuals[0]). individual_controller sopra resta per il SOLO movimento
# (click destro) — ma non più fisso su un singolo individuo, vedi _set_movement_target.
var human_individual_selector_controller := HumanIndividualSelectorController.new()
# Popolo/insediamento/gruppo del player, seminati da HumanSeedingService in _ready() (vedi li').
# human_individuals contiene TUTTI gli individui generati (coppie fondatrici + figli), tutti
# ugualmente selezionabili/muovibili: nessuno ha più uno status speciale (Step 2, 2026-09-02 —
# completa lo smontaggio del concetto di "leader" iniziato allo Step 1 rimuovendo la formazione
# rigida). "individual" sopra è solo il bersaglio CORRENTE, non un ruolo fisso su un membro
# specifico — vedi il commento su quel campo. human_individual_views è parallelo per indice a
# human_individuals (UNA sola collezione, non più individual_view+extra_individual_views separati
# — unificati nel bugfix del 2026-09-02, vedi Bug 2: la riparentazione sotto il container giusto,
# vedi sotto, richiede di trovare la view di UN individuo qualsiasi per indice, la vecchia
# distinzione "indice 0 a parte" era solo un residuo del vecchio concetto di leader e rendeva quel
# lookup inutilmente speciale).
const PLAYER_HUMAN_RULES_PATH := "res://human/data/human_rules/player_human_rules.tres"
var human_folk: Folk
var human_population_group: HumanPopulationGroup
var human_individuals: Array[HumanIndividual] = []
var human_individual_views: Array[HumanIndividualView] = []
# Autorità di selezione unica — Step 1 (richiesta utente, 2026-09-04) del piano "centra
# generalizzato + selezione edifici" discusso con l'utente: PRIMA esistevano due meccanismi
# paralleli e indipendenti (HumanIndividual.is_selected sull'entità + selected_vegetation sotto),
# ciascuno ripulito manualmente dal chiamante ogni volta che l'altro tipo vinceva la selezione
# (vedi es. _select_vegetation, che chiamava _deselect_all_human_individuals() a mano) — esattamente
# il punto anticipato dal vecchio commento "un'autorità di selezione unica è rimandata a quando
# arriverà davvero un terzo tipo selezionabile" (edifici, Step 4/5 del piano). _selection_kind è
# QUEL punto unico da interrogare per sapere "cosa è selezionato ORA", indipendentemente dal tipo —
# consumato dagli step successivi (centra generico, dispatch pannello). Deliberatamente NON
# sostituisce ancora le variabili esistenti (individual/selected_vegetation/is_selected) né
# ristruttura la coreografia mostra/nascondi tab (che ha sottigliezze delicate sul flicker, vedi
# _select_vegetation/_clear_individual_selection) — Step 1 è un'aggiunta di bookkeeping a
# comportamento INVARIATO, mantenuta manualmente in sync agli stessi identici punti di prima.
# NOTA: quando kind==INDIVIDUAL, l'individuo selezionato è semplicemente `individual` (il bersaglio
# di movimento/camera, sempre aggiornato in coppia con la selezione, vedi _set_movement_target) —
# nessun campo duplicato serve per questo caso. BUILDING aggiunto allo Step 4 (richiesta utente,
# 2026-09-04) — il terzo tipo selezionabile già anticipato sopra, vedi selected_building sotto.
enum SelectionKind { NONE, INDIVIDUAL, VEGETATION, BUILDING }
var _selection_kind: SelectionKind = SelectionKind.NONE

# Click-detection su un singolo individuo di vegetazione (TREE/SHRUB) — vedi
# VegetationSelectorController. selected_vegetation vive qui (non su un oggetto persistente come
# HumanIndividual.is_selected per il player: un individuo vegetale non ha una Resource propria, solo
# l'identità posizionale Vector3i) — {} = nessuna selezione, altrimenti {"macro_coords": Vector2i,
# "object_type": GameTypes.WorldObjectType, "individual_key": Vector3i}. Significativo solo quando
# _selection_kind == VEGETATION (vedi sopra). Vedi
# _select_vegetation/_clear_vegetation_selection/_invalidate_selected_vegetation_if_missing.
const VEGETATION_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/VegetationInfoPanel.tscn")
var vegetation_selector_controller := VegetationSelectorController.new()
var selected_vegetation: Dictionary = {}

# Click-detection su un edificio esistente — Step 4 (richiesta utente, 2026-09-04), stesso
# principio di selected_vegetation sopra ma più semplice: un edificio ha un id stabile (Building.
# id), quindi {} = nessuna selezione, altrimenti {"macro_coords": Vector2i, "building_id": int}.
# Significativo solo quando _selection_kind == BUILDING. BuildingInfoPanel (Step 5, stessa
# richiesta utente) vive nella STESSA SelectionTab di vegetation_info_panel/human_individual_info_
# panel, stesso principio "componente muto" — vedi _select_building/_clear_building_selection.
const BUILDING_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/BuildingInfoPanel.tscn")
var building_selector_controller := BuildingSelectorController.new()
var selected_building: Dictionary = {}
var building_info_panel: BuildingInfoPanel
var vegetation_info_panel: VegetationInfoPanel

const MINIMAP_PANEL_SCENE := preload("res://gameplay/scenes/game/MiniMapPanel.tscn")
var minimap_panel: MiniMapPanel
# Controllo a schede dentro body_container (richiesta utente, 2026-09-01) — vedi GameInfoTabs.gd
# per il perché sostituisce lo spacer elastico + minimap_panel diretto di prima. Campo vero (non
# solo locale a _ready()): _select_vegetation/_clear_vegetation_selection lo richiamano per
# mostrare/nascondere la scheda "selezione corrente" (vedi lì).
const GAME_INFO_TABS_SCENE := preload("res://gameplay/scenes/game/GameInfoTabs.tscn")
var game_info_tabs: GameInfoTabs
# Dettaglio dell'individuo umano selezionato nella scheda selezione (richiesta utente,
# 2026-09-01, Passo 1 — esteso 2026-09-02 a un individuo QUALSIASI del gruppo, non più solo
# human_individuals[0], via HumanIndividualSelectorController). Stesso principio di
# vegetation_info_panel: componente proprio, GameScene decide quando mostrarlo/nasconderlo (vedi
# _select_individual/_clear_individual_selection), mai l'individuo stesso o un controller.
const HUMAN_INDIVIDUAL_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/HumanIndividualInfoPanel.tscn")
var human_individual_info_panel: HumanIndividualInfoPanel
# Riepilogo + elenco del gruppo umano nella scheda 🧍 (richiesta utente, 2026-09-01) — popolato
# UNA VOLTA in _ready() subito dopo il seeding (vedi HumanPopulationInfoPanel.show_population),
# nessun refresh dinamico ancora: nessuna simulazione umana cambia population/individui nel tempo
# oggi. Elemento UI distinto da human_individual_info_panel/SelectionTab — nessuna sovrapposizione,
# vive nella propria tab (PopulationTab) sempre visibile, non legata a nessuna selezione.
const HUMAN_POPULATION_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/HumanPopulationInfoPanel.tscn")
var human_population_info_panel: HumanPopulationInfoPanel

# Anteprima "fantasma" della capanna (vedi BuildBar/BuildingGhost) — attivata dal tasto 🛖 nel
# sottomenu costruzione, segue il mouse ogni frame finché attiva. Click sinistro piazza DAVVERO
# una Building su macro_world.buildings (vedi _place_building_at) — istantanea e completa, ma
# solo se BuildingVerificationService.is_position_buildable lo consente (ricollegato 2026-08-30,
# criteri ricostruiti da zero passo per passo — mancano ancora materiali/tech/spazio libero).
# Click destro esce dal modo piazzamento (vedi _clear_building_ghost). null = nessuna anteprima attiva, creata/distrutta
# on/off dal toggle invece di restare sempre presente e solo nascosta — un solo Node2D usa e
# getta, costo trascurabile ricrearlo alla prossima attivazione. Il fantasma resta attivo DOPO un
# piazzamento riuscito, apposta: permette di piazzarne molte in fila senza riaprire il sottomenu
# ogni volta.
var _building_ghost: BuildingGhost = null
# Tipo di edificio selezionato nel sottomenu (vedi _building_type_name_for_action) — "" quando
# nessun fantasma è attivo. Solo "hut" esiste oggi, ma tenerlo come dato invece di un valore
# hardcoded in _place_building_at evita di dover toccare quel metodo quando arriverà un secondo
# tipo di edificio.
var _selected_building_type_name: String = ""
# Camera LIBERA (Step 3 del piano movimento indipendente, 2026-09-02 — RIMUOVE il follow
# automatico che prima seguiva individual.position ogni frame mentre individual.is_moving era
# vero): nessun individuo viene più inseguito, mai — WASD/edge-pan/drag-to-pan (vedi
# CameraController) restano sempre pienamente liberi, indipendentemente da chi si muove. Il
# bottone "🎯"/tasto X restano l'UNICO modo per centrare la camera sulla selezione corrente, ora
# animato (vedi _center_camera_on_individual/_center_camera_tween sotto) invece che a scatto —
# stesso motivo per cui _attempt_macro_cell_transition non forza più un ricentraggio dopo un
# attraversamento bordo: quel forcing esisteva solo per compensare il follow automatico appena
# rimosso, tenerlo da solo avrebbe reintrodotto un caso isolato di "la camera insegue comunque",
# in contraddizione con l'obiettivo di questo step (nessuna eccezione).
var _center_camera_tween: Tween
const CENTER_CAMERA_TWEEN_DURATION: float = 0.45 # secondi — spostamento "centra" animato, non a scatto
var _clock_was_playing_before_dialogs: bool = false
var _open_dialog_count: int = 0
var _pending_leave_action: StringName = &""

@onready var game_info_panel: GameInfoPanel = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/GameInfoPanel
@onready var build_bar: BuildBar = $CanvasLayer/BuildBar
@onready var debug_bar: DebugBar = $CanvasLayer/DebugBar
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
	GameClockController.Speed.X4: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/Speed4xButton,
	# Visibile solo a DebugLogging.ENABLED (vedi _setup_clock) — stesso meccanismo già in uso per
	# debug_bar/debug_animal_container.
	GameClockController.Speed.DEBUG: $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/ClockControlsContainer/SpeedDebugButton,
}
@onready var season_progress_bar: SeasonProgressBar = $CanvasLayer/Sidebar/MarginContainer/VBoxContainer/SeasonProgressBar

func _ready() -> void:
	# Ripristina lo stato dei due toggle dalla sessione precedente (vedi GameSettings): senza
	# questo, uscendo e rientrando in questa scena tornerebbero sempre al default "attivo",
	# perdendo silenziosamente la scelta dell'utente — stesso principio già usato da
	# MacroCellScene per i suoi due toggle (campi GameSettings separati, vedi lì per il perché).
	animals_visible = GameSettings.game_scene_animals_visible
	flora_daily_updates_enabled = GameSettings.game_scene_flora_updates_enabled

	# year_title_label.text non più impostato qui (richiesta utente, 2026-09-04): ora mostra l'Era
	# corrente invece della label statica "calendar_label", aggiornata da _update_calendar_display
	# così resta viva anche quando un futuro trigger tech→era chiamerà GameData.set_current_era.
	# +1 spostato dentro DebugBar (richiesta utente, 2026-09-01) — vedi _on_debug_action_pressed
	# per il case &"advance_year", niente più bottone/wiring qui.
	save_game_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_game_file_dialog.current_dir = GameSettings.SAVES_DIR
	save_game_file_dialog.file_selected.connect(_on_save_game_file_selected)

	# Slot 0=flora, 1=animali su DebugBar (vedi DebugBar.gd) — stesso stato iniziale di sempre,
	# solo il pannello che lo mostra e' cambiato.
	debug_bar.set_slot_toggled(0, flora_daily_updates_enabled)
	debug_bar.set_slot_toggled(1, animals_visible)
	debug_bar.action_pressed.connect(_on_debug_action_pressed)
	game_info_panel.primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	game_info_panel.secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	build_bar.submenu_row.action_pressed.connect(_on_build_submenu_action_pressed)
	# Controllo a schede (richiesta utente, 2026-09-01, sostituisce lo spacer elastico +
	# minimap_panel/vegetation_info_panel diretti usati prima — vedi GameInfoTabs.gd) — unico
	# figlio diretto di body_container: size_flags_vertical=3 (impostato nel suo stesso .tscn) gli
	# fa occupare tutto lo spazio verticale che BodyScrollContainer riceve. body_container arriva
	# altrimenti vuoto per design (vedi GameInfoPanel.gd): GameScene, non GameInfoPanel stesso,
	# istanzia qui il proprio contenuto — GameInfoPanel resta "muto" su
	# vegetazione/minimappa/selezione.
	game_info_tabs = GAME_INFO_TABS_SCENE.instantiate()
	game_info_panel.body_container.add_child(game_info_tabs)
	# minimap_panel (richiesta utente, 2026-09-02: schermo ingrandito, la minimappa deve restare
	# SEMPRE visibile in basso, ANCORATA — non deve più salire/scendere a seconda di quale scheda
	# è aperta, come succedeva quando viveva dentro body_container insieme a game_info_tabs, la
	# cui altezza varia da scheda a scheda). Vive in game_info_panel.minimap_slot, un sibling FISSO
	# di BodyScrollContainer nella VBoxContainer esterna di GameInfoPanel — vedi GameInfoPanel.gd
	# per il perché quella posizione resta sempre stabile. Dimensionamento/comportamento di
	# minimap_panel stesso INVARIATI (si autodimensiona ancora quadrata sulla larghezza
	# disponibile, vedi MiniMapPanel._on_panel_resized) — cambia solo DOVE vive nell'albero, non
	# come si calcola la propria taglia.
	minimap_panel = MINIMAP_PANEL_SCENE.instantiate()
	game_info_panel.minimap_slot.add_child(minimap_panel)
	# vegetation_info_panel vive dentro SelectionTab, sempre presente in barra (la tab stessa non
	# si nasconde più — solo il suo contenuto, gestito da GameInfoTabs.empty_selection_label, vedi
	# _select_vegetation/_clear_vegetation_selection più sotto) invece che sempre visibile sopra
	# le tab come prima — componente stesso INVARIATO (nessuna logica di tab al suo interno),
	# così resta facilmente spostabile in futuro (es. un popup sulla mappa) senza toccarlo:
	# basterebbe cambiare QUI dove viene parcheggiato e come viene mostrato/nascosto, non lui.
	vegetation_info_panel = VEGETATION_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(vegetation_info_panel)
	vegetation_info_panel.cut_requested.connect(_on_cut_requested)
	# human_individual_info_panel vive nella STESSA SelectionTab, sibling di vegetation_info_panel
	# ed empty_selection_label — mai visibile insieme a vegetation_info_panel per costruzione
	# (selezione reciprocamente esclusiva, vedi _select_vegetation/individual.is_selected=false),
	# stesso principio "componente muto, GameScene decide" di vegetation_info_panel.
	human_individual_info_panel = HUMAN_INDIVIDUAL_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(human_individual_info_panel)
	# building_info_panel (Step 5, richiesta utente 2026-09-04) — terzo sibling nella STESSA
	# SelectionTab, stesso identico principio "componente muto" di vegetation_info_panel/
	# human_individual_info_panel; zero modifiche a GameInfoTabs per aggiungerlo (già agnostica).
	building_info_panel = BUILDING_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(building_info_panel)
	# "🎯 centra" (Step 3, richiesta utente 2026-09-04): non più un bottone per-pannello (era dentro
	# human_individual_info_panel, funzionava solo per individui) — un solo bottone condiviso
	# nell'header di GameInfoTabs.SelectionTab, sopra a qualunque pannello selection_content stia
	# mostrando ora. _center_camera_on_selection risolve la posizione in base a _selection_kind.
	game_info_tabs.center_requested.connect(_center_camera_on_selection)
	# human_population_info_panel vive in PopulationTab — instanziato qui insieme al resto (stesso
	# principio "componente muto"), ma popolato (show_population) solo più sotto, DOPO il seeding
	# umano: human_individuals/human_folk non esistono ancora a questo punto di _ready().
	human_population_info_panel = HUMAN_POPULATION_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.population_tab.add_child(human_population_info_panel)
	# Bottone "🎯" per riga (richiesta utente, 2026-09-04) — stesso schema di minimap_panel.
	# cell_clicked subito sotto: il pannello segnala solo "questo individuo", GameScene decide.
	human_population_info_panel.individual_center_requested.connect(_on_population_individual_center_requested)
	minimap_panel.cell_clicked.connect(_on_minimap_cell_clicked)
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

	if macro_world != null:
		minimap_panel.setup(macro_world)

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

	# Semina Folk + HumanPopulationGroup + HumanIndividual (coppie fondatrici + figli) — vedi
	# HumanSeedingService per l'algoritmo di composizione/eta'/nomi — OPPURE ricostruisce un popolo
	# già persistito (richiesta utente, 2026-09-02): GameSettings.active_human_individuals non
	# vuoto significa che esiste già un popolo, sia perché si ritorna da un giro debug verso
	# WorldScene/MacroCellScene sia perché questo è un salvataggio appena caricato (in entrambi i
	# casi WorldScene/GameScene stesso lo hanno già propagato lì — vedi GameSettings.active_human_*)
	# — in quel caso NON si semina nulla, si riusano gli STESSI oggetti (stessi id, stesse
	# posizioni, stessa storia), mai una copia. human_rules caricato qui via load() diretto in
	# ENTRAMBI i rami (nessun HumanCalculator-per-convenzione ancora, un solo Folk esiste per ora):
	# un domani con piu' Folk questo path fisso andra' sostituito da una vera risoluzione per Folk.
	var human_rules := load(PLAYER_HUMAN_RULES_PATH) as HumanRules
	var start_macro_coords := Vector2i(game_data.player_macro_cell_x, game_data.player_macro_cell_y)
	if not GameSettings.active_human_individuals.is_empty():
		human_folk = GameSettings.active_human_folk
		human_population_group = GameSettings.active_human_population_group
		human_individuals = GameSettings.active_human_individuals
		# human_rules_ref (Resource) non è mai serializzato/propagato dentro il popolo stesso —
		# path fisso di competenza di GameScene, vedi sopra — va ri-assegnato qui ad ogni
		# ricostruzione, stesso motivo per cui HumanSeedingService non lo tocca da sé nel ramo
		# seeding sotto.
		human_folk.human_rules_ref = human_rules
		# Bersaglio corrente ripristinato sullo STESSO individuo che lo era all'uscita/salvataggio
		# (game_data.player_individual_id, vedi GameData) — mai più sempre human_individuals[0].
		# Scansione lineare accettabile (pochi individui, stesso principio già discusso per
		# _macro_cell_has_individuals). null trovato (non dovrebbe succedere per dati coerenti, rete
		# di sicurezza) ripiega sul primo membro invece di lasciare `individual` null.
		individual = null
		for member in human_individuals:
			if member.id == game_data.player_individual_id:
				individual = member
				break
		if individual == null:
			individual = human_individuals[0]
	else:
		# set_current_era (richiesta utente, 2026-09-04 — bugfix): PRIMO punto reale in cui viene
		# chiamato — prima esisteva solo come infrastruttura mai collegata (nessun trigger tech→era
		# ancora implementato, vedi GameData), quindi game_data.era_effective_age_band_durations_
		# male/female restava sempre vuoto e la semina leggeva le durate BASE di HumanRules, mai
		# scalate per l'Era (game_data.current_era_name di default = "paleolithic"). Questo non è
		# un trigger di avanzamento — è il bootstrap iniziale, chiamato una sola volta qui, per
		# l'Era di partenza della partita.
		game_data.set_current_era(game_data.current_era_name, human_rules)
		var seeding_result := HumanSeedingService.new().seed_player_start(
			start_macro_coords, game_data.starting_group_size_preference, human_rules, "Player Folk", game_data.year,
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female
		)
		human_folk = seeding_result.folk
		human_population_group = seeding_result.group
		human_individuals = seeding_result.individuals
		# Tutto il gruppo nasce nella stessa macrocella (vedi HumanIndividual.home_macro_coords) —
		# valorizzato qui, prima di qualunque view (vedi sotto, dopo l'attivazione della cella
		# centrale): è il dato che dice a GameScene sotto quale LiveMacroCell.container parentare
		# la view di ciascuno. Posizioni già assolute (HumanSeedingService._grid_spawn_position è
		# già centrata su World.WIDTH/HEIGHT/2.0) — nessun ricentraggio da fare qui, a differenza di
		# prima: quella danza esisteva solo per ripristinare GameData.player_micro_x/y (RIMOSSO,
		# vedi GameData — ogni salvataggio/ritorno passa ora dal ramo sopra, mai più da qui).
		for member in human_individuals:
			member.home_macro_coords = start_macro_coords
		# Solo valore INIZIALE del bersaglio di movimento/streaming (Step 2, 2026-09-02) —
		# human_individuals[0] non ha altro status speciale da qui in poi, vedi il commento sul
		# campo "individual" sopra: il giocatore può spostare il bersaglio su un membro qualsiasi
		# selezionandolo (_set_movement_target).
		individual = human_individuals[0]

	# Popola la scheda 🧍 (richiesta utente, 2026-09-01) — human_individuals/human_folk sono
	# finalizzati solo qui (posizioni di spawn comprese), stesso motivo per cui l'istanza del
	# pannello (sopra) e la sua popolazione dati sono separate in due punti diversi di _ready().
	# Estratta in _refresh_population_panel (richiesta utente, 2026-09-05 — bugfix "pannello mai
	# aggiornato dopo il primo popolamento"): stessa identica chiamata di prima, ora riusabile anche
	# dal rollover d'anno.
	_refresh_population_panel()

	# Prima cella viva: il centro. center_macro_coords va fissato PRIMA di attivarla, perché
	# _activate_live_cell non decide da sé "sono il centro" — è solo orchestrazione qui.
	center_macro_coords = Vector2i(game_data.player_macro_cell_x, game_data.player_macro_cell_y)
	_activate_live_cell(center_macro_coords.x, center_macro_coords.y)

	# Una HumanIndividualView a testa, TUTTE parentate sotto il container della LiveMacroCell in
	# cui l'individuo si trova fisicamente (member.home_macro_coords, valorizzato sopra) — bugfix
	# Bug 2, 2026-09-02: PRIMA ogni view era figlia diretta di GameScene, con la propria position
	# scritta come coordinate locali "nude" (individual.position * CELL_SIZE, vedi
	# HumanIndividualView._process) senza sommare alcun offset di macrocella — funzionava solo
	# perché ogni HumanIndividual coincideva SEMPRE con la cella centrale (il leader la definiva, gli
	# extra la seguivano in formazione rigida ogni frame). Rotto da Step 1 (formazione rimossa) +
	# Step 2 (il centro può spostarsi lasciando indietro chi non è il bersaglio): un individuo
	# fermo in una macrocella che smette di essere il centro veniva comunque disegnato come se
	# fosse ancora lì. Fix: STESSO pattern già usato da MicroCellRenderer/AnimalGroupRenderer/
	# FogOfWarRenderer (vedi _activate_live_cell) — figlio del container giusto, cosi' Godot compone
	# la trasformazione (offset di macrocella) gratis, HumanIndividualView.gd stesso resta identico,
	# nessun calcolo di offset esplicito da aggiungere lì. Va dopo _activate_live_cell sopra: il
	# container della cella centrale deve esistere prima di potervi parentare qualcosa (prima
	# viveva PRIMA dell'attivazione, quindi doveva per forza essere figlia di GameScene).
	# _activate_all_building_cells()/_activate_all_individual_cells() PRIMA del loop view sotto
	# (bugfix, 2026-09-02): un individuo ricostruito da un salvataggio può avere home_macro_coords
	# diversa dal centro (lasciato indietro prima di salvare) — la sua cella deve essere già viva
	# prima che il loop sotto tenti live_cells[member.home_macro_coords], altrimenti quella chiave
	# non esiste ancora in live_cells. Per una partita nuova (tutti nascono nel centro, già attivo
	# sopra) questo riordino è un no-op.
	_activate_all_building_cells()
	_activate_all_individual_cells()

	human_individual_views.clear()
	for member in human_individuals:
		var view := HumanIndividualView.new()
		live_cells[member.home_macro_coords].container.add_child(view)
		# game_data/human_folk.human_rules_ref passati per il ridimensionamento per età/sesso
		# (richiesta utente, 2026-09-04 — vedi HumanIndividualView.gd per il dettaglio): entrambi
		# già valorizzati a questo punto di _ready() (vedi sopra), stesso principio di
		# fog_of_war_renderer.setup(cell.fog_of_war_memory) — le dipendenze arrivano dal chiamante.
		view.setup(member, game_data, human_folk.human_rules_ref if human_folk != null else null)
		# z_index invariato (era già necessario prima, per lo stesso motivo — vedi
		# fog_of_war_renderer.z_index=2 in _activate_live_cell, che deve restare sopra ANCHE alle
		# view individuo): tiene la view sopra terreno/animali (z_index=0 di default) del container
		# di cui ora è figlia, sotto la fog of war di quello stesso container.
		view.z_index = 1
		human_individual_views.append(view)

	_reposition_live_cells()
	# Niente _rebind_fog_bindings()/secondo refresh qui (RIMOSSI, Step 4 FoW multi-sorgente,
	# 2026-09-02): quel meccanismo esisteva solo per correggere un binding fog inizialmente legato
	# a un placeholder (fog_proxy_individual) — con source_positions (vedi FogOfWarRenderer.gd),
	# _activate_live_cell chiama update_visibility() con le posizioni VERE prima del proprio primo
	# refresh interno, quindi quel refresh è già corretto al primo giro, nessuna correzione
	# successiva necessaria (bug "tutto verde alla partita nuova" strutturalmente non più possibile,
	# non solo corretto).
	if macro_world != null:
		_refresh_lod_focus_region()
	_update_center_info_panel()

	individual_controller = HumanIndividualController.new()
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer, game_data)

	_setup_clock()
	_assign_clock_to_all_live_cells()
	_update_calendar_display()

	# Posiziona la camera UNA SOLA VOLTA all'ingresso in scena, poi resta libera per tutta la
	# sessione (Step 3, 2026-09-02 — vedi il commento su _center_camera_tween sopra). Se un
	# salvataggio porta con sé una posizione camera propria (game_data.camera_position_saved, vedi
	# GameData — sentinella booleana, non -1.0: a differenza di player_macro_cell_x/y, camera_x/y
	# non hanno un intervallo valido limitato, CameraController non ha alcun limite di pan), la
	# ripristina ESATTAMENTE lì com'era stata lasciata, istantanea (nessuno spostamento visibile
	# da animare in questo frame, la scena non è ancora mai stata mostrata). Altrimenti (partita
	# nuova, o save precedente l'introduzione di questo campo) resta il comportamento di sempre:
	# centrata sull'individuo iniziale, anch'essa istantanea per lo stesso motivo (animated=false).
	if game_data.camera_position_saved:
		camera.position = Vector2(game_data.camera_x, game_data.camera_y)
	else:
		_center_camera_on_individual(false)
	# camera_zoom (vedi GameData) era già salvato ma MAI riapplicato al caricamento — bug dormiente
	# trovato durante la ricognizione di questo piano, corretto qui insieme al resto dello stato
	# camera persistito (stesso punto naturale, nessun altro posto lo applicava prima).
	if game_data.camera_zoom > 0.0:
		camera.zoom = Vector2(game_data.camera_zoom, game_data.camera_zoom)


# Movimento dell'individuo controllabile: gira ogni frame, indipendentemente da clock.is_playing
# (il player deve poter esplorare la macrocella anche a simulazione in pausa — confermato con
# l'utente). Non tocca in alcun modo il pipeline giorno/anno di WorldTimeService.
func _process(delta: float) -> void:
	if individual != null:
		individual_movement_service.advance_movement(individual, delta)
		_check_macro_cell_border_crossing()
		_update_live_neighbor()

	# Step 4 FoW multi-sorgente, 2026-09-02 — SOSTITUISCE il vecchio meccanismo a proxy (un solo
	# "individuo ombra" per cella vicina, sincronizzato sul bersaglio corrente): ogni cella viva
	# riceve ora, ogni frame, la lista di posizioni di TUTTI gli human_individuals rilevanti per lei
	# (vedi _relevant_source_positions_for_cell — home_macro_coords entro 1 cella di distanza,
	# tradotta nello spazio locale di QUELLA cella), non solo del bersaglio corrente. Nessun binding
	# persistente da mantenere/correggere: ogni chiamata è autosufficiente, quindi indipendente da
	# chi sia il bersaglio o da quando è cambiato l'ultima volta.
	for cell in live_cells.values():
		if cell.fog_of_war_renderer == null:
			continue
		cell.fog_of_war_renderer.update_visibility(game_data.get_absolute_day(), _relevant_source_positions_for_cell(cell))

	# Proposta 2 (mitigazione "pop-in", diagnostica lentezza) — rinfresca la vegetazione della cella
	# centrale quando il player si è spostato abbastanza da poter aver scoperto area non coperta
	# dall'ultimo rebuild (VEGETATION_REFRESH_MOVE_THRESHOLD), invece di aspettare il prossimo
	# checkpoint stagionale. Solo la cella CENTRALE: è l'unica dove individual.position cambia
	# davvero frame per frame (le celle vicine, se vive per via di edifici lontani, dipendono dal
	# proprio raggio edificio — vedi _building_visible_positions — non dalla posizione del player).
	if individual != null and live_cells.has(center_macro_coords):
		if individual.position.distance_to(_last_vegetation_refresh_position) >= VEGETATION_REFRESH_MOVE_THRESHOLD:
			if DebugLogging.SHOW_VEGETATION_REFRESH_TIMING_LOGS:
				print("[VEG REFRESH TRIGGER] movimento: cella (%d,%d), spostamento=%.1f microcelle da ultimo refresh" % [
					center_macro_coords.x, center_macro_coords.y, individual.position.distance_to(_last_vegetation_refresh_position)
				])
			_refresh_resource_visuals(live_cells[center_macro_coords])

	if _building_ghost != null:
		_building_ghost.global_position = _building_ghost.get_global_mouse_position()
		# Ricollegato (2026-08-30, vedi BuildingVerificationService per la cronologia): aggiorna
		# l'aspetto del fantasma ogni frame in base ai criteri di edificabilità via
		# set_buildable_appearance (verde/rosso, invariato) — ricostruiti da zero passo per passo,
		# vedi il service per lo stato attuale dei criteri. `rules` risolte qui (non passate da
		# _on_build_submenu_action_pressed) perché il tipo selezionato non cambia mai mentre il
		# fantasma è attivo — coerente con come _place_building_at le risolve al momento del click.
		var ghost_rules := BuildingCalculator.get_building_rules(_selected_building_type_name)
		BuildingVerificationService.set_buildable_appearance(
			_building_ghost,
			ghost_rules != null and BuildingVerificationService.is_position_buildable(
				live_cells, MACRO_CELL_PIXELS, MicroCellRenderer.CELL_SIZE, _building_ghost.global_position,
				game_data.get_absolute_day(), macro_world, _building_ghost.rotation_dir, ghost_rules
			)
		)


func _unhandled_input(event: InputEvent) -> void:
	# Mentre l'anteprima capanna è attiva, il click e il tasto R prendono priorità assoluta su
	# tutto il resto (vegetazione/player) — altrimenti click sinistro finirebbe per selezionare/
	# deselezionare vegetazione invece di piazzare, e l'unico modo per uscire dal "modo
	# piazzamento" sarebbe ricliccare esattamente 🛖. Destro = annulla, sinistro = piazza (il
	# fantasma RESTA attivo dopo, vedi _building_ghost/_place_building_at, per piazzarne molte in
	# fila), R = ruota la porta di 90° (BuildingGhost.rotate_clockwise) senza uscire dal modo
	# piazzamento.
	if _building_ghost != null:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_clear_building_ghost()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_place_building_at(_building_ghost.global_position)
				return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			_building_ghost.rotate_clockwise()
			return

	# Priorità concordata con l'utente: vegetazione/edifici vincono entro il proprio raggio di
	# hit-test (più piccolo/preciso del raggio di selezione del player, vedi VegetationSelectorController/
	# BuildingSelectorController) — Step 4 (richiesta utente, 2026-09-04): generalizzato da "solo
	# vegetazione" al MIGLIOR candidato tra i tipi selezionabili sulla mappa (chi ha la distanza più
	# piccola vince tra loro, vedi map_hit sotto), non più un solo tipo con priorità fissa. Se
	# nessuno dei due trova nulla, il flusso prosegue esattamente come prima di questi controller.
	# Un click sinistro "a vuoto" (nessun tipo mappa trovato) deseleziona comunque vegetazione ED
	# edificio — stesso principio di _deselect_all_human_individuals, che già deseleziona ogni
	# individuo umano su un click lontano da tutti loro. ECCEZIONE: se il bersaglio corrente
	# (individual, vedi il commento sul campo) è oggettivamente più vicino al click del miglior
	# candidato mappa (es. è fermo proprio accanto a una pianta/edificio), vince lui anche se il
	# candidato ricade comunque nel proprio raggio di click — vedi _is_player_closer_to_click
	# (confronta sempre e solo il bersaglio corrente, non l'intero human_individuals: la priorità
	# non è stata estesa a tutti i membri del gruppo in questo step).
	var vegetation_hit := vegetation_selector_controller.try_select(event, live_cells)
	var building_hit := building_selector_controller.try_select(
		event, live_cells, macro_world.buildings if macro_world != null else []
	)
	var map_hit: Dictionary = {}
	var map_hit_kind := SelectionKind.NONE
	if not vegetation_hit.is_empty() and (building_hit.is_empty() or vegetation_hit["distance"] <= building_hit["distance"]):
		map_hit = vegetation_hit
		map_hit_kind = SelectionKind.VEGETATION
	elif not building_hit.is_empty():
		map_hit = building_hit
		map_hit_kind = SelectionKind.BUILDING

	if not map_hit.is_empty() and not _is_player_closer_to_click(map_hit["distance"]):
		if map_hit_kind == SelectionKind.VEGETATION:
			_select_vegetation(map_hit)
		else:
			_select_building(map_hit)
	else:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_clear_vegetation_selection()
			_clear_building_selection()
			# Selezione di un individuo umano QUALSIASI (richiesta utente, 2026-09-02) — hit-test
			# puro via HumanIndividualSelectorController (non tocca mai is_selected da sé), mutua
			# esclusione applicata qui: al più un individuo selezionato alla volta in tutto
			# human_individuals. Un hit sposta ANCHE il bersaglio di movimento/streaming su di lui
			# (_set_movement_target, Step 2 del piano movimento indipendente) — un click a vuoto
			# invece deseleziona senza toccare il bersaglio, che resta ancorato all'ultimo individuo
			# selezionato (richiesta utente, 2026-09-02, punto 3).
			var hit_individual: HumanIndividual = human_individual_selector_controller.try_select(
				event, live_cells[center_macro_coords].renderer, human_individuals, center_macro_coords
			)
			_deselect_all_human_individuals()
			if hit_individual != null:
				hit_individual.is_selected = true
				_selection_kind = SelectionKind.INDIVIDUAL
				_select_individual(hit_individual)
				_set_movement_target(hit_individual)
			else:
				_clear_individual_selection()
		# Solo movimento ora (click destro, gated su individual.is_selected) — vedi
		# HumanIndividualController per il perché la selezione è stata rimossa da lì. Opera sempre
		# sul bersaglio CORRENTE (vedi _set_movement_target sopra), non più su un individuo fisso.
		if individual_controller != null:
			individual_controller.handle_input(event)

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		_center_camera_on_individual()


# Vero se un individuo umano QUALSIASI è più vicino al click corrente del miglior candidato mappa
# (vegetazione O edificio, Step 4 — stesso spazio pixel locale della cella CENTRALE, usato sia da
# VegetationSelectorController/BuildingSelectorController che qui, così le distanze sono
# direttamente confrontabili). Non richiede che il click ricada nel raggio di selezione vero del
# player (SELECT_RADIUS_MICROCELLS in HumanIndividualSelectorController): decide solo chi tenta per primo,
# human_individual_selector_controller applica comunque la propria soglia subito dopo.
#
# BUGFIX (2026-09-03, trovato testando una New Game vera per la prima volta da tempo — non
# correlato al lavoro sul FoW di questa sessione). Prima c'erano DUE difetti in cascata qui:
#   1. `individual == null` ritornava sempre false (vero SOLO prima della primissima selezione di
#      una partita nuova — `individual` arriva già valorizzato da un salvataggio caricato), che
#      rendeva impossibile selezionare chiunque se il punto di spawn aveva vegetazione vicina.
#   2. Anche con un bersaglio corrente già impostato, il confronto guardava SOLO la posizione di
#      `individual` (il bersaglio corrente), non quella dell'individuo che si sta effettivamente
#      cercando di cliccare — quindi selezionare un individuo DIVERSO dal bersaglio corrente, se
#      sopra vegetazione, falliva comunque (bug segnalato dopo il fix del punto 1).
# Fix per entrambi: confronta sempre contro il candidato più vicino tra TUTTI gli
# human_individuals (mai solo il bersaglio corrente) — stessa formula di offset di
# HumanIndividualSelectorController.try_select, replicata qui perché quella classe ritorna
# l'individuo selezionato (filtrato dalla propria soglia SELECT_RADIUS_MICROCELLS), non una
# distanza grezza confrontabile con map_object_distance_px. Quando il bersaglio corrente è anche
# il candidato più vicino il risultato coincide con la vecchia logica (home_macro_coords ==
# center_macro_coords per costruzione mentre è bersaglio, vedi _set_movement_target — offset
# sempre Vector2i.ZERO in quel caso).
func _is_player_closer_to_click(map_object_distance_px: float) -> bool:
	var center_cell: LiveMacroCell = live_cells.get(center_macro_coords)
	if center_cell == null or center_cell.renderer == null:
		return false
	var mouse_px: Vector2 = center_cell.renderer.get_local_mouse_position()

	var best_distance_px := INF
	for candidate in human_individuals:
		var offset := Vector2(candidate.home_macro_coords - center_macro_coords) * World.WIDTH
		var candidate_px: Vector2 = (candidate.position + offset) * MicroCellRenderer.CELL_SIZE
		best_distance_px = minf(best_distance_px, mouse_px.distance_to(candidate_px))
	return best_distance_px < map_object_distance_px


# Sposta la camera esattamente sulla posizione corrente dell'individuo — stesso spazio pixel di
# HumanIndividualView (individual.position, in microcelle, moltiplicata per lo stesso CELL_SIZE=10 di
# MicroCellRenderer/HumanIndividualView). Sempre lo spazio della cella CENTRALE, che è sempre
# posizionata a offset zero (vedi _reposition_live_cells) — nessuna traduzione necessaria.
# Richiamata dal tasto X (_unhandled_input sopra): "torna sul player", un comando dedicato che
# riporta la vista sul bersaglio di movimento/camera INDIPENDENTEMENTE da cosa sia selezionato ora
# (funziona anche con vegetazione selezionata o nessuna selezione) — deliberatamente NON unificata
# con _center_camera_on_selection sotto (Step 2, richiesta utente 2026-09-04): sono due intenti
# diversi che solo prima di quello step coincidevano sempre (esisteva un solo tipo di bersaglio).
# Riusata comunque DA _center_camera_on_selection per il ramo INDIVIDUAL, invece di duplicare la
# logica — vedi sotto.
#
# animated=true di default (requisito utente, 2026-09-02: uno spostamento a scatto non è più
# accettabile ora che è l'UNICO modo di muovere la camera sulla selezione, vedi il commento su
# _center_camera_tween) — un breve tween invece di un assegnamento diretto. animated=false resta
# per l'UNICO caso in cui uno scatto è corretto: il posizionamento iniziale in _ready(), prima che
# la scena sia mai stata mostrata (nessuno spostamento visibile da animare).
func _center_camera_on_individual(animated: bool = true) -> void:
	if individual == null:
		return
	_animate_camera_to(individual.position * MicroCellRenderer.CELL_SIZE, animated)


# Step 2 del piano "centra generalizzato" (richiesta utente, 2026-09-04) — a differenza di
# _center_camera_on_individual sopra (dedicata al tasto X, sempre e solo sul bersaglio di
# movimento/camera), questa centra su QUALUNQUE cosa sia OGGI selezionata, secondo _selection_kind
# (l'autorità di selezione unica introdotta allo Step 1) — è la funzione dietro ai trigger "🎯"
# espliciti dell'utente (bottone nella lista popolazione, e il futuro bottone unico nella
# SelectionTab, Step 3). Un piccolo branch per tipo qui, non altrove — CameraFocusService separato
# rimandato finché non servirà davvero (oggi tre rami, tutti piccoli):
#   - INDIVIDUAL: delega a _center_camera_on_individual sopra (stesso risultato per costruzione,
#     dato che quando kind==INDIVIDUAL il selezionato È sempre `individual`, vedi il commento su
#     _selection_kind).
#   - VEGETATION: a differenza dell'individuo, una pianta selezionata NON ri-centra il mondo (può
#     restare in QUALSIASI cella viva, non solo quella centrale) — serve quindi la stessa
#     traduzione cross-macrocella già usata da _reposition_live_cells/_on_minimap_cell_clicked:
#     posizione locale al renderer proprietario (MicroCellRenderer.get_individual_screen_position,
#     già nello stesso spazio pixel di CELL_SIZE) PIÙ l'offset della sua macrocella rispetto al
#     centro. Se la cella non è più viva o l'individuo non c'è più (selezione stantia), no-op
#     silenzioso — stesso principio difensivo già in uso altrove per selected_vegetation.
#   - BUILDING (Step 4, richiesta utente 2026-09-04): stessa identica traduzione cross-macrocella
#     di VEGETATION sopra (un edificio può anch'esso stare in qualsiasi cella viva) — vedi
#     MicroCellRenderer.get_building_screen_position, l'equivalente per gli edifici.
func _center_camera_on_selection(animated: bool = true) -> void:
	match _selection_kind:
		SelectionKind.INDIVIDUAL:
			_center_camera_on_individual(animated)
		SelectionKind.VEGETATION:
			var macro_coords: Vector2i = selected_vegetation["macro_coords"]
			var cell: LiveMacroCell = live_cells.get(macro_coords)
			if cell == null or cell.renderer == null:
				return
			var local_position: Vector2 = cell.renderer.get_individual_screen_position(
				selected_vegetation["object_type"], selected_vegetation["individual_key"]
			)
			var macro_offset := Vector2(macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
			_animate_camera_to(local_position + macro_offset, animated)
		SelectionKind.BUILDING:
			# Stessa identica traduzione cross-macrocella del ramo VEGETATION sopra — un edificio,
			# come una pianta, può stare in qualsiasi cella viva, non solo quella centrale (Step 4,
			# richiesta utente 2026-09-04). get_building_screen_position è l'equivalente di
			# get_individual_screen_position per gli edifici (vedi MicroCellRenderer).
			var building_macro_coords: Vector2i = selected_building["macro_coords"]
			var building_cell: LiveMacroCell = live_cells.get(building_macro_coords)
			if building_cell == null or building_cell.renderer == null:
				return
			var building_local_position: Vector2 = building_cell.renderer.get_building_screen_position(
				selected_building["building_id"]
			)
			var building_macro_offset := Vector2(building_macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
			_animate_camera_to(building_local_position + building_macro_offset, animated)
		_:
			pass


# Estratta da _center_camera_on_individual (Step 2, richiesta utente 2026-09-04) — solo il
# meccanismo di animazione/scatto, condiviso ora da entrambe le funzioni "centra" sopra invece di
# essere duplicato. _center_camera_tween viene killata prima di ripartire, in entrambi i rami:
# premere "centra" due volte di fila (o mentre un tween precedente sta ancora animando) non deve
# far litigare due tween sulla stessa proprietà.
func _animate_camera_to(target_position: Vector2, animated: bool) -> void:
	if _center_camera_tween != null:
		_center_camera_tween.kill()
	if not animated:
		camera.position = target_position
		return
	_center_camera_tween = create_tween()
	_center_camera_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_center_camera_tween.tween_property(camera, "position", target_position, CENTER_CAMERA_TWEEN_DURATION)


# Click sulla minimappa (MiniMapPanel.cell_clicked) — sposta SOLO la camera, mai il player né
# attiva la cella cliccata (scelta esplicita confermata con l'utente, 2026-08-30): se la
# macrocella non è tra le live_cells non c'è alcun container lì, quindi la vista mostra il vuoto
# del canvas, non un errore. Stessa formula di _reposition_live_cells (posizione del container di
# una cella viva rispetto al centro), più mezzo MACRO_CELL_PIXELS per puntare al CENTRO della
# macrocella invece che al suo angolo in alto a sinistra.
func _on_minimap_cell_clicked(macro_coords: Vector2i) -> void:
	camera.position = (
		Vector2(macro_coords.x - center_macro_coords.x, macro_coords.y - center_macro_coords.y) * MACRO_CELL_PIXELS
		+ Vector2(MACRO_CELL_PIXELS, MACRO_CELL_PIXELS) / 2.0
	)


# Bottone "🎯" per riga nel pannello popolazione (richiesta utente, 2026-09-04: "un piccolo button
# a fianco di ognuno... al clic mi centri su di loro e mi selezioni il cliccato") — stessa
# sequenza select+movimento di un click diretto sull'individuo in _unhandled_input (deselect-tutti
# → seleziona → _select_individual per il popup → _set_movement_target, che ri-ancora anche lo
# streaming/center_macro_coords se target non è co-locato col centro — vedi lì), PIÙ
# _center_camera_on_selection() esplicito alla fine (Step 2, richiesta utente 2026-09-04 — era
# _center_camera_on_individual, stesso risultato per costruzione dato che kind è appena stato
# impostato a INDIVIDUAL qui sopra): un click su un bottone UI non è un click nel mondo, non sposta
# la camera da sé come farebbe un click diretto sul personaggio già visibile.
func _on_population_individual_center_requested(target: HumanIndividual) -> void:
	# _clear_vegetation_selection/_clear_building_selection (bugfix, richiesta utente 2026-09-04,
	# scoperto mentre si aggiungeva la selezione edifici): PRIMA mancavano qui — selezionare un
	# individuo da questa lista mentre vegetazione/edificio erano già selezionati lasciava ENTRAMBI
	# selezionati (evidenziazione a schermo compresa), esattamente il difetto che la mutua
	# esclusione a 3 vie altrove (_unhandled_input, _select_vegetation, _select_building) evita già.
	_clear_vegetation_selection()
	_clear_building_selection()
	_deselect_all_human_individuals()
	target.is_selected = true
	_selection_kind = SelectionKind.INDIVIDUAL
	_select_individual(target)
	_set_movement_target(target)
	_center_camera_on_selection()


# ============================================================================================
# Selezione di un individuo di vegetazione — vedi VegetationSelectorController/selected_vegetation.
# ============================================================================================

# Applica una selezione risolta da vegetation_selector_controller: aggiorna lo stato locale,
# l'highlight sul SOLO renderer che possiede l'individuo (ogni cella viva ha la propria istanza di
# MicroCellRenderer, vedi LiveMacroCell — le altre vanno esplicitamente ripulite, altrimenti un
# highlight precedente su un'altra cella viva resterebbe visibile) e il pannello.
#
# _deselect_all_human_individuals() qui sotto (bugfix, 2026-09-01 — CORREGGE la decisione
# precedente "un hit sulla vegetazione ha priorità e non influenza la selezione del player",
# rivelatasi un'asimmetria indesiderata: selezionare una pianta mentre il player era già
# selezionato lasciava ENTRAMBI selezionati, col tasto destro che continuava a muovere il player
# mentre il pannello mostrava la pianta — mai possibile il contrario, dato che
# individual_controller.handle_input, l'unico altro punto che scrive is_selected per il leader,
# gira solo nel ramo "vince il player" di _unhandled_input, mai in questo. Esteso 2026-09-02 a
# TUTTI gli individui umani, non solo il leader — vedi _deselect_all_human_individuals): Selezione
# ORA reciprocamente esclusiva, come nella maggior parte dei giochi — un'eventuale autorità di
# selezione unica (invece di due stati separati, questo campo sull'entità + selected_vegetation
# qui) è rimandata a quando arriverà davvero un terzo tipo selezionabile o la selezione multipla,
# non prima.
#
# human_individual_info_panel.clear() qui sotto (bugfix, 2026-09-01, Passo 1 individuo): il
# fix sopra azzera SOLO il flag is_selected, non nasconde il pannello che lo mostrava — senza
# questa riga il pannello individuo restava visibile, sovrapposto a vegetation_info_panel appena
# mostrato da _refresh_vegetation_panel (testo scritto uno sopra l'altro, bug osservato).
func _select_vegetation(hit: Dictionary) -> void:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		if coords == hit["macro_coords"]:
			cell.renderer.set_selected_individual(hit["object_type"], hit["individual_key"])
		else:
			cell.renderer.clear_selected_individual()

	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_building_selection() # mutua esclusione a 3 vie (Step 4, richiesta utente 2026-09-04)
	selected_vegetation = hit
	_selection_kind = SelectionKind.VEGETATION
	_refresh_vegetation_panel()
	game_info_tabs.show_selection_tab()


func _clear_vegetation_selection() -> void:
	if selected_vegetation.is_empty():
		return
	selected_vegetation = {}
	_selection_kind = SelectionKind.NONE
	for cell in live_cells.values():
		if cell.renderer != null:
			cell.renderer.clear_selected_individual()
	vegetation_info_panel.clear()
	game_info_tabs.hide_selection_tab()


# ============================================================================================
# Selezione di un edificio — Step 4/5 (richiesta utente, 2026-09-04). Struttura gemella di
# _select_vegetation/_clear_vegetation_selection sopra: BuildingInfoPanel (Step 5) mostra
# type/status/durability/anno di costruzione/risorse immagazzinate/id, risolti dal vero oggetto
# Building via _find_building_by_id — questo pannello, come gli altri due, riceve solo dati già
# risolti (l'intero Building, stesso schema di HumanIndividualInfoPanel.show_individual).
# ============================================================================================

func _select_building(hit: Dictionary) -> void:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		if coords == hit["macro_coords"]:
			cell.renderer.set_selected_building(hit["building_id"])
		else:
			cell.renderer.clear_selected_building()

	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_vegetation_selection()
	selected_building = hit
	_selection_kind = SelectionKind.BUILDING
	_refresh_building_panel()
	game_info_tabs.show_selection_tab()


func _clear_building_selection() -> void:
	if selected_building.is_empty():
		return
	selected_building = {}
	_selection_kind = SelectionKind.NONE
	for cell in live_cells.values():
		if cell.renderer != null:
			cell.renderer.clear_selected_building()
	building_info_panel.clear()
	game_info_tabs.hide_selection_tab()


# Risolve selected_building["building_id"] sul vero oggetto Building (scansione lineare di
# macro_world.buildings — stesso costo già accettato altrove nel progetto per lo stesso array, vedi
# _macro_cell_has_buildings) e popola building_info_panel. A differenza di _refresh_vegetation_
# panel, nessuna gestione "marker bloccato": un edificio non ha ancora un modo di sparire una volta
# piazzato (nessuna demolizione implementata) — l'unica via di invalidazione oggi resta lo
# scaricamento della sua macrocella, già gestita da _deactivate_live_cell. Guardia comunque
# presente (building non trovato -> deseleziona) per onestà difensiva, stesso principio già seguito
# ovunque nel progetto per selezioni potenzialmente stantie.
func _refresh_building_panel() -> void:
	var building := _find_building_by_id(selected_building.get("building_id", -1))
	if building == null:
		_clear_building_selection()
		return
	building_info_panel.show_building(building)
	# Titolo (Step 6, richiesta utente 2026-09-04) — stessa formula già in BuildingInfoPanel.
	var type_name: String = tr(building.rules.building_name) if building.rules != null else building.building_type_name
	game_info_tabs.set_selection_title("Type: " + type_name)


func _find_building_by_id(building_id: int) -> Building:
	if macro_world == null:
		return null
	for building in macro_world.buildings:
		if building.id == building_id:
			return building
	return null


# Deseleziona TUTTI gli individui umani — mutua esclusione esplicita: al più un individuo umano
# selezionato alla volta nell'intero human_individuals, indipendentemente da chi fosse selezionato
# prima (richiesta utente, 2026-09-02). Usato sia quando un altro tipo di selezione vince
# (vegetazione, sopra) sia su un click che non colpisce nessun individuo (vedi _unhandled_input).
# Non tocca pannello/tab (il chiamante decide se e come nasconderli) né il bersaglio di movimento/
# streaming (vedi _set_movement_target: quello cambia SOLO su un nuovo hit, mai su una
# deselezione).
func _deselect_all_human_individuals() -> void:
	for other in human_individuals:
		other.is_selected = false


# Mostra i dati dell'individuo umano cliccato nella scheda selezione — QUALSIASI individuo del
# gruppo, non più solo il leader (richiesta utente, 2026-09-02, esteso da human_individuals[0] a
# tutti; popup INVARIATO, stessa show_individual/HumanCalculator.get_age_band di prima, solo
# parametrizzato sull'individuo cliccato invece del campo fisso `individual`). Chiamata da
# _unhandled_input subito dopo che human_individual_selector_controller ha trovato un hit e
# _deselect_all_human_individuals + target.is_selected=true hanno aggiornato la mutua esclusione.
# Età ricalcolata al volo da HumanCalculator (mai salvata su HumanIndividual, stesso principio già
# usato da HumanSeedingService in fase di generazione) — human_folk.human_rules_ref è lo stesso
# HumanRules usato lì. strength resta fuori, non ancora richiesto.
# max_workforce/residual_workforce (2026-09-04): nessun consumo reale ancora esistente (nessuna
# classe Action), quindi residual coincide sempre col max — l'UNICA riga da sostituire quando
# arriverà HumanIndividual.residual_workforce è quella subito sotto (residual_workforce =
# max_workforce), il pannello non va toccato.
func _select_individual(target: HumanIndividual) -> void:
	var age: int = game_data.year - target.birth_year_virtual
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female, target.sex, float(age)
	)
	var max_workforce := HumanCalculator.get_base_workforce(human_folk.human_rules_ref, age_band, target.sex)
	var residual_workforce := max_workforce # TODO: sostituire con target.residual_workforce quando esisterà
	human_individual_info_panel.show_individual(target, age, age_band, max_workforce, residual_workforce)
	game_info_tabs.set_selection_title("Name: " + target.name)
	game_info_tabs.show_selection_tab()


# Ripopola la scheda 👨‍👩‍👧 con i dati correnti — stessa identica chiamata di _ready() (vedi lì),
# estratta per essere riusabile anche da _on_year_rolled_over sotto.
func _refresh_population_panel() -> void:
	human_population_info_panel.show_population(
		human_population_group.total_count, human_individuals, game_data.year,
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		human_folk.id, human_population_group.id
	)


# Ripopola la scheda selezione SOLO se un individuo è davvero selezionato ora (_selection_kind ==
# INDIVIDUAL) — scansione lineare su human_individuals per trovare chi ha is_selected=true, stesso
# costo già accettato altrove nel progetto per array analoghi (es. _find_building_by_id). No-op se
# non è un individuo ad essere selezionato (vegetazione/edificio/nessuna selezione: non è compito
# di questo handler, quei pannelli non mostrano età).
func _refresh_selected_individual_panel() -> void:
	if _selection_kind != SelectionKind.INDIVIDUAL:
		return
	for member in human_individuals:
		if member.is_selected:
			_select_individual(member)
			return


# Bugfix (richiesta utente, 2026-09-05 — vedi commento alla connessione in _setup_clock): tiene
# sincronizzati i due pannelli umani col passare degli anni, non solo su un nuovo popolamento/una
# nuova selezione manuale.
func _on_year_rolled_over() -> void:
	_refresh_population_panel()
	_refresh_selected_individual_panel()


# Sposta il bersaglio di movimento/streaming (il campo "individual", vedi il commento lì) su
# `target` — Step 2 del piano movimento indipendente, 2026-09-02. individual_controller/
# individual_movement_service restano gli stessi, stateless rispetto all'identità (vedi
# HumanIndividualController): basta ri-agganciare il controller esistente al nuovo bersaglio,
# esattamente come fa già _attempt_macro_cell_transition quando cambia il renderer di riferimento.
# Chiamata SOLO su un hit di selezione riuscito, mai su una deselezione (vedi _unhandled_input): il
# bersaglio resta quello precedente finché non ne viene scelto uno nuovo.
#
# Bugfix 2026-09-02 (due sintomi distinti trovati testando un bersaglio non co-locato col centro —
# entrambi dovuti a questa funzione, che faceva un handoff PARZIALE al nuovo bersaglio):
#
# Sintomo 2 (movimento residuo) — target.stop() sotto scarta is_moving/path lasciati da un
# PRECEDENTE turno di `target` come bersaglio: nessun altro punto del codice pulisce questo stato
# per un individuo che STA PER diventare bersaglio (solo per quello che lo è già, vedi
# HumanIndividualMovementService.advance_movement/_attempt_macro_cell_transition/
# _block_border_crossing, i soli tre punti che chiamano .stop()) — senza questo, un individuo
# selezionato, spostato, poi abbandonato per un altro bersaglio PRIMA di arrivare, riprendeva a
# camminare da solo verso il vecchio target_position stantio non appena ri-selezionato. Gated su
# `target != individual`: se target è GIA' il bersaglio corrente, un suo eventuale is_moving è
# stato ATTUALE (avanzato ogni frame proprio ora), non residuo — fermarlo qui interromperebbe una
# camminata in corso voluta dal giocatore solo perché ha ri-cliccato la stessa selezione (es. per
# rivedere il popup), un effetto collaterale non voluto e diverso dal caso che questo fix corregge.
#
# Sintomo 1 (streaming non ri-ancorato) — PRIMA questa funzione agganciava incondizionatamente
# individual_controller al nuovo bersaglio assumendo fosse già nella cella centrale — falso per un
# individuo lasciato indietro in una cella diventata neighbor (vedi HumanIndividual.
# home_macro_coords): il risultato era la vecchia cella disattivata a torto dal frame successivo
# (_update_live_neighbor interpreta individual.position come "distanza dal bordo del centro",
# sempre grande se quella posizione non è davvero locale al centro). NOTA (Step 4 FoW
# multi-sorgente, 2026-09-02): la parte del bug che riguardava un cerchio FoW disegnato nel posto
# sbagliato non esiste più per costruzione — FogOfWarRenderer non è più "legato" a nessun bersaglio,
# riceve ogni frame le posizioni vere di tutti gli individui rilevanti (vedi
# _relevant_source_positions_for_cell), indipendentemente da chi sia il bersaglio corrente — quindi
# non serve più correggere nulla lì (_rebind_fog_bindings è stata rimossa insieme al meccanismo che
# la richiedeva). Resta valida la parte su _update_live_neighbor: se target non è co-locato col
# centro corrente, RI-ANCORARE l'intero streaming su di lui prima di agganciare
# individual_controller — stesso schema già validato per Bug 1 (attraversamento bordo): il delta di
# ri-basamento va applicato alla camera PRIMA di riassegnare center_macro_coords (serve ancora il
# valore vecchio per calcolarlo), un eventuale tween "centra" in corso va killato per lo stesso
# motivo di Bug 1. Delta VETTORIALE pieno (non un solo asse come in un attraversamento bordo): una
# selezione può "saltare" più di una cella su entrambi gli assi in un colpo solo. Nessuna
# riattivazione di celle necessaria: un individuo cliccabile è per costruzione già visibile, quindi
# la sua home_macro_coords è già in live_cells. _update_live_neighbor si auto-corregge da sé al
# frame successivo (stesso principio già usato da _attempt_macro_cell_transition, che non lo
# richiama esplicitamente): con center_macro_coords ora aggiornato, individual.position torna a
# essere letto nel riferimento giusto.
func _set_movement_target(target: HumanIndividual) -> void:
	if target != individual:
		target.stop()
		# BUGFIX (2026-09-04, richiesta utente, non correlato al lavoro sul FoW): il VECCHIO
		# bersaglio (quello abbandonato dal cambio di selezione) deve fermarsi per intero, non solo
		# smettere di essere avanzato. GameScene._process chiama individual_movement_service.
		# advance_movement SOLO sul bersaglio CORRENTE, quindi il vecchio smette correttamente di
		# muoversi in posizione — ma senza questa chiamata il suo is_moving restava true per
		# sempre (nessuno lo azzerava più), e HumanIndividualView anima gambe/braccia in base a
		# QUEL flag, non alla posizione reale: risultato, un personaggio fermo con gambe/braccia
		# che continuavano a camminare all'infinito. individual (il vecchio bersaglio) può essere
		# null alla primissima selezione di una partita nuova — guardia esplicita.
		if individual != null:
			individual.stop()

	if target.home_macro_coords != center_macro_coords:
		if _center_camera_tween != null:
			_center_camera_tween.kill()
		camera.position -= Vector2(target.home_macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
		center_macro_coords = target.home_macro_coords
		_reposition_live_cells()
		_refresh_lod_focus_region()
		_update_center_info_panel()

	individual = target
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer, game_data)


# Simmetrico a _clear_vegetation_selection: no-op se il pannello non era già mostrato, per non
# forzare un ritorno indesiderato alla scheda precedente su ogni click "vuoto" (richiamare
# GameInfoTabs.hide_selection_tab quando non c'era nulla da nascondere strapperebbe l'utente da
# una scheda su cui si fosse nel frattempo spostato manualmente).
func _clear_individual_selection() -> void:
	if not human_individual_info_panel.visible:
		return
	human_individual_info_panel.clear()
	game_info_tabs.hide_selection_tab()
	_selection_kind = SelectionKind.NONE


# Richiede al renderer proprietario i dati aggiornati e li passa al pannello — RIDERIVA lo stato
# (vivo vs bloccato) da zero ogni volta tramite has_individual, mai fidandosi di un flag salvato
# al momento della selezione: un individuo vivo può diventare un ceppo tra una selezione e il
# refresh successivo (es. tagliato da questa stessa sessione), e il pannello deve sempre riflettere
# la verità corrente, non quella di quando è stato selezionato. Se la cella non è più viva o
# l'individuo non c'è più in nessuna delle due forme, la selezione viene invalidata.
func _refresh_vegetation_panel() -> void:
	var cell: LiveMacroCell = live_cells.get(selected_vegetation["macro_coords"])
	if cell == null or cell.renderer == null:
		_clear_vegetation_selection()
		return
	var object_type: GameTypes.WorldObjectType = selected_vegetation["object_type"]
	var individual_key: Vector3i = selected_vegetation["individual_key"]
	# Titolo (Step 6, richiesta utente 2026-09-04): identico nei due rami sotto (vivo/bloccato,
	# dipende solo da object_type) — impostato qui una volta sola invece che duplicato in entrambi.
	game_info_tabs.set_selection_title("Type: " + GameTypes.WorldObjectType.keys()[object_type].capitalize())

	if cell.renderer.has_individual(object_type, individual_key):
		var info := cell.renderer.get_individual_info(object_type, individual_key)
		vegetation_info_panel.show_vegetation(object_type, info["subtype_name"], info["age_band"], info["years_lived"])
		return

	var blocked_info := cell.renderer.get_blocked_marker_info(object_type, individual_key)
	if blocked_info.is_empty():
		_clear_vegetation_selection()
		return
	vegetation_info_panel.show_cut_marker(object_type, blocked_info["state"], blocked_info["years_ago"])


# Da richiamare a fine _refresh_resource_visuals(cell) per QUALUNQUE cella viva (non solo il
# centro): se l'individuo selezionato è sparito dal nuovo rebuild in ENTRAMBE le forme (né vivo né
# bloccato — migrato, o finestra di rientro scaduta), la selezione va invalidata esplicitamente —
# deciso esplicitamente con l'utente: meglio "nessuna selezione" onesto che un pannello con dati
# stantii. Altrimenti il pannello viene comunque aggiornato (_refresh_vegetation_panel rideriva da
# sé se è ancora vivo o ormai bloccato).
func _invalidate_selected_vegetation_if_missing(cell: LiveMacroCell) -> void:
	if selected_vegetation.is_empty() or selected_vegetation["macro_coords"] != cell.coords():
		return
	var object_type: GameTypes.WorldObjectType = selected_vegetation["object_type"]
	var individual_key: Vector3i = selected_vegetation["individual_key"]
	if cell.renderer.has_individual(object_type, individual_key) or cell.renderer.has_blocked_marker(object_type, individual_key):
		_refresh_vegetation_panel()
	else:
		_clear_vegetation_selection()


# Prima chiamata reale a PlayerHarvestService (vedi lì per gli effetti esatti): l'individuo
# selezionato smette di essere vivo, un rebuild immediato della SOLA cella coinvolta lo fa
# sparire dai blob vivi e comparire come ceppo/rovi (cut_positions, vedi _refresh_resource_visuals)
# — nessuna attesa del prossimo giorno/anno simulato. Guardia esplicita su has_individual: il
# bottone "Cut" di VegetationInfoPanel è nascosto quando la selezione è già un marker bloccato
# (vedi show_cut_marker), ma questo controllo resta comunque come rete di sicurezza.
#
# La selezione (selected_vegetation) NON viene più azzerata dopo il taglio (bugfix, richiesta
# utente 2026-09-04 — prima lo era: "il ceppo appena creato non è ri-selezionabile in questa
# stessa azione", una scelta deliberata ma percepita come un difetto ora che _center_camera_on_
# selection/il salto di tab la rendono più visibile — tagliare buttava l'utente fuori dalla
# SelectionTab, su PopulationTab). object_type/individual_key restano IDENTICI prima e dopo il
# taglio (vedi PlayerHarvestService: vegetation_cut_exceptions è chiavato sulla stessa Vector3i
# lotto+indice, mai riassegnata) — la chiamata sotto a _refresh_resource_visuals(cell) invoca già
# _invalidate_selected_vegetation_if_missing(cell) al proprio interno, che rileva has_blocked_
# marker()==true per questa stessa chiave e richiama _refresh_vegetation_panel() da sé: il
# passaggio pianta-viva → ceppo/rovi avviene quindi automaticamente, stesso identico meccanismo già
# usato per invalidare una selezione stantia altrove, qui riusato per farla invece SOPRAVVIVERE al
# cambio di stato. Nessuna chiamata esplicita in più necessaria qui.
func _on_cut_requested() -> void:
	if selected_vegetation.is_empty():
		return
	var cell: LiveMacroCell = live_cells.get(selected_vegetation["macro_coords"])
	if cell == null or cell.renderer == null:
		_clear_vegetation_selection()
		return
	var object_type: GameTypes.WorldObjectType = selected_vegetation["object_type"]
	var individual_key: Vector3i = selected_vegetation["individual_key"]
	if not cell.renderer.has_individual(object_type, individual_key):
		_clear_vegetation_selection()
		return
	var info := cell.renderer.get_individual_info(object_type, individual_key)
	if info.is_empty():
		_clear_vegetation_selection()
		return

	PlayerHarvestService.cut_individual(cell.macro_state, object_type, individual_key, info["subtype_name"], info["size_multiplier"], game_data.year)
	# Il taglio cambia dedicated_space/vegetation_cut_exceptions per QUESTA cella — invalida la
	# cache posizioni (vedi LiveMacroCell.needs_full_vegetation_recompute), altrimenti il refresh
	# sotto riuserebbe la lista di ieri e il ceppo appena creato non comparirebbe.
	cell.needs_full_vegetation_recompute = true
	_refresh_resource_visuals(cell)


# Prima chiamata reale a NaturalMortalityVisualService (vedi lì per il criterio di scelta) —
# chiamata da _on_day_advanced PRIMA del rebuild della cella, per ciascuna cella viva, per TREE e
# SHRUB. select_dying_individuals consuma già last_mortality_loss (lo cancella), quindi è sicuro
# chiamarla ogni giorno: nei giorni senza mortalità appena applicata è un no-op silenzioso. Per
# ogni individuo scelto, il size_multiplier va letto dal renderer PRIMA di marcarlo morto (una
# volta marcato, sottotipo/età sono dimenticati e quel dato non sarebbe più recuperabile) — stesso
# identico schema di _on_cut_requested sopra.
func _apply_natural_mortality_visuals(cell: LiveMacroCell) -> void:
	if cell.macro_state == null or cell.renderer == null or cell.fog_of_war_memory == null:
		return
	# is_resource_fresh (non più has_ever_been_seen, vedi NaturalMortalityVisualService — NON
	# is_terrain_fresh: quel tier copre solo il tipo di terreno/bioma, troppo grezzo per "quali
	# piante c'erano") ha bisogno del giorno corrente e della soglia — letti una sola volta qui,
	# non per ogni object_type sotto.
	var fog_rules := FogOfWarCalculator.get_fog_of_war_rules()
	var resource_memory_days: int = fog_rules.resource_memory_days if fog_rules != null else 30
	var current_absolute_day := game_data.get_absolute_day()
	for object_type in NaturalMortalityVisualService.MORTAL_INDIVIDUAL_TYPES:
		var dying: Array = NaturalMortalityVisualService.select_dying_individuals(
			cell.macro_state, cell.fog_of_war_memory, object_type, current_absolute_day, resource_memory_days
		)
		for individual_key in dying:
			var info := cell.renderer.get_individual_info(object_type, individual_key)
			if info.is_empty():
				continue
			NaturalMortalityVisualService.kill_individual(cell.macro_state, object_type, individual_key, info["size_multiplier"], game_data.year)


# Azzera lo stato di focus del LOD quando questa scena viene lasciata — stessa motivazione di
# MacroCellScene._exit_tree().
func _exit_tree() -> void:
	if macro_world != null:
		macro_world.lod_focus_state = {}
		macro_world.lod_focus_live_cells = {}


# ============================================================================================
# Celle vive: attivazione/disattivazione/posizionamento (streaming multi-cella)
# ============================================================================================

# Crea e popola per intero una LiveMacroCell per (mx, my) — stesso lavoro che prima faceva
# _load_macro_cell per L'UNICA cella, ora parametrizzato: risoluzione cella/stato, rigenerazione
# del micro-mondo uniforme, vicini per il renderer, fiume, pietre, vegetazione/pesci/fauna (via
# _refresh_resource_visuals). NON tocca la focus region LOD (vedi _refresh_lod_focus_region,
# chiamata separatamente dal chiamante) né le coordinate mostrate in DebugBar (vedi
# _update_center_info_panel, solo per il centro). Non ritorna mai null: se macro_world è null o la cella non esiste (bordo del
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
	cell.fog_of_war_renderer = FogOfWarRenderer.new()
	# ULTIMO figlio del container aggiunto apposta (vedi FogOfWarRenderer.gd): l'ordine dei figli
	# è l'ordine di disegno in Godot 2D, deve stare sopra renderer/animali per coprire davvero
	# tutto quello che nasconde ALL'INTERNO di questa cella. z_index=2 in più (non basterebbe da
	# solo l'essere ultimo figlio del container): deve restare sopra anche alle HumanIndividualView
	# di questa cella (vedi _ready(), aggiunte a QUESTO STESSO container DOPO — z_index=1 lì — un
	# tempo erano fratelli del container invece che suoi figli, non più dal bugfix Bug 2,
	# 2026-09-02, ma lo z_index esplicito resta comunque necessario: essendo aggiunte dopo questo
	# fog_of_war_renderer, il solo ordine dei figli le metterebbe sopra di lui, sbagliato).
	cell.container.add_child(cell.fog_of_war_renderer)
	cell.fog_of_war_renderer.z_index = 2
	cell.fog_of_war_renderer.setup(cell.fog_of_war_memory)
	# Popola subito source_positions con le posizioni VERE (Step 4 FoW multi-sorgente, 2026-09-02
	# — RIMPIAZZA il vecchio binding a un placeholder + correzione successiva via
	# _rebind_fog_bindings): questa cella, centro o vicino che sia, non ha mai bisogno di essere
	# "corretta" più tardi — update_visibility() riceve già le posizioni giuste al primo giro,
	# quindi il _refresh_resource_visuals sotto (se questa cella ne fa uno) parte già corretto.
	cell.fog_of_war_renderer.update_visibility(game_data.get_absolute_day(), _relevant_source_positions_for_cell(cell))

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

			# _refresh_building_visuals PRIMA di _refresh_resource_visuals (ordine invertito rispetto
			# a prima, 2026-08-30/Proposta 2): quest'ultima ora filtra cosa costruire nel renderer in
			# base a FogOfWarRenderer.compute_visible_positions, che legge anche _building_visible_
			# positions — se girasse prima di _refresh_building_visuals, alla primissima attivazione di
			# una cella-edificio quell'insieme sarebbe ancora vuoto e le posizioni vicino all'edificio
			# verrebbero scartate dal primo rebuild (si autocorregge al refresh successivo, ma
			# nessun motivo di lasciare quella finestra scorretta quando basta invertire due righe).
			_refresh_building_visuals(cell)
			_refresh_resource_visuals(cell)

	live_cells[Vector2i(mx, my)] = cell
	return cell


# ESPERIMENTO (2026-08-30, deciso con l'utente): ogni macrocella con almeno un edificio resta
# viva a prescindere dalla prossimità del player — vegetazione a individui, FoW, animali, tutto
# il pacchetto di LiveMacroCell, indefinitamente, finché quell'edificio esiste. Deliberatamente
# SENZA tetto sul numero di macrocelle così attivate: è esattamente la misura che questo sistema
# di debug doveva produrre (vedi Building.gd — "misurare il rischio di esplosione di individui da
# visibilità permanente da edifici" prima di ridisegnare l'architettura). Il rischio collaterale
# scoperto inizialmente (LODOrchestrator.set_focus_region riceveva un Rect2i bounding-box di
# TUTTE le celle vive, quindi un edificio lontano ingrossava il rettangolo inglobando ogni
# popolazione animale sul percorso player<->edificio, non solo quelle vicine a una cella VERA) è
# stato risolto lo stesso giorno: ora si passa l'insieme delle singole coordinate vive, vedi
# _refresh_lod_focus_region/World.lod_focus_live_cells. Il costo che resta da osservare con questo
# esperimento è quindi di nuovo solo quello reale: vegetazione a individui per ogni macrocella-
# edificio, e popolazioni animali davvero adiacenti a una di esse.
func _activate_all_building_cells() -> void:
	if macro_world == null:
		return
	var building_macro_coords: Dictionary = {}
	for building in macro_world.buildings:
		building_macro_coords[Vector2i(building.macro_x, building.macro_y)] = true
	for coords in building_macro_coords:
		if not live_cells.has(coords):
			_activate_live_cell(coords.x, coords.y)


# Scansione lineare di macro_world.buildings — accettabile con pochi edifici (tool di debug),
# vedi discussione con l'utente su un eventuale indice Dictionary[Vector2i, Array[Building]] se
# il numero crescesse abbastanza da farlo pesare.
func _macro_cell_has_buildings(coords: Vector2i) -> bool:
	if macro_world == null:
		return false
	for building in macro_world.buildings:
		if building.macro_x == coords.x and building.macro_y == coords.y:
			return true
	return false


# Mirror di _activate_all_building_cells sopra, per human_individuals invece che macro_world.
# buildings (richiesta utente, 2026-09-02 — "ogni cella con un individuo della popolazione del
# player deve essere considerata viva come per gli edifici"). OGGI è un no-op garantito: ogni
# individuo nasce co-locato con center_macro_coords (mai persistito per identità tra sessioni,
# vedi HumanIndividual/HumanSeedingService — si riseminano sempre dal centro), quindi la sua
# home_macro_coords è già viva quando questa gira in _ready(). Aggiunta comunque ORA (non
# rimandata) perché il prossimo passo pianificato è la persistenza degli individui — a quel punto
# smetterà di essere un no-op (un individuo ricaricato potrebbe trovarsi in una cella mai vissuta
# in questa sessione, esattamente il motivo per cui esiste il pass equivalente per gli edifici) e
# non vogliamo doverci ricordare di aggiungerla in un secondo momento.
func _activate_all_individual_cells() -> void:
	if macro_world == null:
		return
	var individual_macro_coords: Dictionary = {}
	for member in human_individuals:
		individual_macro_coords[member.home_macro_coords] = true
	for coords in individual_macro_coords:
		if not live_cells.has(coords):
			_activate_live_cell(coords.x, coords.y)


# Mirror di _macro_cell_has_buildings sopra, stessa scansione lineare accettabile con pochi
# individui (5-20 oggi) — stessa nota sull'eventuale indice Dictionary[Vector2i, Array[
# HumanIndividual]] se il numero crescesse (es. con la persistenza/nascite future) abbastanza da
# farlo pesare.
func _macro_cell_has_individuals(coords: Vector2i) -> bool:
	for member in human_individuals:
		if member.home_macro_coords == coords:
			return true
	return false


# Step 4 FoW multi-sorgente, 2026-09-02 — per la cella `cell`, la lista delle posizioni (Vector2)
# di ogni human_individuals GIÀ TRADOTTA nello spazio locale di QUELLA cella, pronta per
# FogOfWarRenderer.update_visibility(). Stessa formula di offset già stabilita per Bug 2/
# HumanIndividualSelectorController (individual.position + (home_macro_coords - target_coords) *
# World.WIDTH) — qui generalizzata da "sempre verso il centro" a "verso QUALUNQUE cella vivente".
# Filtro economico (richiesta utente, 2026-09-02): un individuo la cui home_macro_coords è a 2+
# celle di distanza (Chebyshev — qualunque asse) da `cell` non può MAI rientrare nel raggio di
# visibilità (visibility_radius, poche microcelle, contro celle larghe World.WIDTH=100 microcelle),
# quindi viene scartato prima ancora di calcolare la traduzione — evita di costruire posizioni
# inutili per individui lontani, specialmente quando la popolazione crescerà.
func _relevant_source_positions_for_cell(cell: LiveMacroCell) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var cell_coords := Vector2i(cell.macro_x, cell.macro_y)
	for member in human_individuals:
		var delta := member.home_macro_coords - cell_coords
		if abs(delta.x) >= 2 or abs(delta.y) >= 2:
			continue
		positions.append(member.position + Vector2(delta) * World.WIDTH)
	return positions


# Celle vive che il player sta EFFETTIVAMENTE esplorando in questo momento — il centro più gli
# eventuali vicini attivi di prossimità (_active_neighbor_coords_set, max ~4 per come è
# progettato lo streaming multi-cella, vedi _compute_relevant_neighbor_offsets). Deliberatamente
# esclude le celle vive SOLO per un edificio lontano (_activate_all_building_cells) o per un
# individuo del player rimasto indietro (_activate_all_individual_cells, stesso principio) —
# usata da _on_day_advanced per limitare il ridisegno vegetazione costoso al checkpoint stagionale
# a ciò che qualcuno sta davvero guardando, vedi lì per il perché è sicuro farlo.
func _player_proximity_live_cells() -> Array:
	var cells: Array = []
	if live_cells.has(center_macro_coords):
		cells.append(live_cells[center_macro_coords])
	for coords in _active_neighbor_coords_set:
		if coords == center_macro_coords:
			continue
		if live_cells.has(coords):
			cells.append(live_cells[coords])
	return cells


func _deactivate_live_cell(coords: Vector2i) -> void:
	var cell: LiveMacroCell = live_cells.get(coords)
	if cell == null:
		return
	# L'individuo/edificio selezionato (se presente) vive nel renderer che sta per essere distrutto
	# — vedi _select_vegetation/selected_vegetation e _select_building/selected_building (Step 4).
	if not selected_vegetation.is_empty() and selected_vegetation["macro_coords"] == coords:
		_clear_vegetation_selection()
	if not selected_building.is_empty() and selected_building["macro_coords"] == coords:
		_clear_building_selection()
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


# Ricalcola il focus LOD (LODOrchestrator) coprendo TUTTE le celle vive attuali, non solo il
# centro — un vicino vivo è visivamente presente quanto il centro, quindi le sue popolazioni
# animali restano Livello 2 (simulazione piena) esattamente come oggi fa il centro da solo,
# nessuna nuova categoria di LOD necessaria: set_focus_region riclassifica sempre TUTTE le
# popolazioni del mondo da zero, quindi una cella che esce dal set vivo torna candidata a
# Livello 1 automaticamente. Passa l'insieme delle SINGOLE coordinate vive (mai un Rect2i che ne
# faccia il bounding box, vedi World.lod_focus_live_cells) — fix 2026-08-30: con
# _activate_all_building_cells le celle vive possono essere anche molto distanti tra loro, e un
# bounding box avrebbe trattato come "a fuoco" pure tutto lo spazio vuoto in mezzo.
func _refresh_lod_focus_region() -> void:
	if macro_world == null or live_cells.is_empty():
		return

	var focus_live_cells: Dictionary = {}
	for coords in live_cells:
		focus_live_cells[coords] = true

	var lod_result := LODOrchestrator.new().set_focus_region(macro_world, focus_live_cells)
	LODOrchestrator.print_classification_log(lod_result)
	macro_world.lod_focus_live_cells = focus_live_cells
	macro_world.lod_focus_state = lod_result
	minimap_panel.update_visibility(focus_live_cells, center_macro_coords)


func _update_center_info_panel() -> void:
	var center: LiveMacroCell = live_cells.get(center_macro_coords)
	if center != null and center.macro_cell != null:
		debug_bar.set_coords(center.macro_cell.x, center.macro_cell.y)


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
			# Un vicino che ospita un edificio O un individuo del player non va MAI disattivato
			# per allontanamento del bersaglio (richiesta utente, 2026-09-02, estende alla stessa
			# regola già in uso per gli edifici — vedi _activate_all_building_cells/
			# _activate_all_individual_cells): resta vivo indefinitamente finché l'edificio esiste
			# o finché ci sono individui del player fisicamente lì (home_macro_coords), smette
			# solo di essere tracciato come "vicino di prossimità" (nessun cambiamento reale a
			# live_cells, quindi changed resta false qui).
			if _macro_cell_has_buildings(coords) or _macro_cell_has_individuals(coords):
				_active_neighbor_coords_set.erase(coords)
				continue
			_deactivate_live_cell(coords)
			_active_neighbor_coords_set.erase(coords)
			changed = true

	for coords in relevant_coords_set:
		if _active_neighbor_coords_set.has(coords):
			continue
		# changed scatta SOLO se questa cella non era già viva (es. resa viva da un edificio, vedi
		# _activate_all_building_cells): iniziare a tracciarla anche come "vicino di prossimità"
		# non cambia live_cells né le posizioni dei container, quindi non giustifica da solo un
		# nuovo _reposition_live_cells()/_refresh_lod_focus_region() — senza questa distinzione il
		# log di classificazione LOD veniva stampato due volte identico ogni volta che un vicino di
		# prossimità coincideva con una cella già viva per un edificio.
		if not live_cells.has(coords):
			if macro_world.get_cell_at(coords.x, coords.y) == null:
				continue # bordo del mondo: nessuna cella da attivare in questa direzione
			_activate_live_cell(coords.x, coords.y)
			changed = true
		_active_neighbor_coords_set[coords] = true

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
	# Bugfix Bug 2 (2026-09-02): il bersaglio è l'UNICO individuo la cui macrocella fisica cambia
	# davvero (chiunque altro resta dov'era, mai mosso da nulla) — aggiorna home_macro_coords e
	# riparenta la sua HumanIndividualView sotto il nuovo container, esattamente come farebbe
	# _activate_live_cell per un renderer qualsiasi. reparent() invece di remove_child+add_child
	# manuali: nessuna differenza pratica qui (HumanIndividualView._process sovrascrive comunque
	# position da zero subito dopo, ad ogni frame), ma è l'API dedicata di Godot per lo scopo.
	individual.home_macro_coords = center_macro_coords
	var target_view_index := human_individuals.find(individual)
	if target_view_index != -1:
		human_individual_views[target_view_index].reparent(live_cells[center_macro_coords].container)
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer, game_data)
	_reposition_live_cells()
	# Bugfix (Passo 1 del piano bug camera/extra, 2026-09-02 — CORREGGE una rimozione sbagliata
	# nello Step 3: qui NON viveva solo una compensazione per il follow automatico, ma anche una
	# correzione di una discontinuità strutturale del sistema di coordinate ri-basate per
	# macrocella, indipendente dal follow — rimuovendo tutto insieme avevo tolto anche questa
	# seconda cosa). _reposition_live_cells() appena sopra ha spostato OGNI container di
	# -Vector2(dx,dy)*MACRO_CELL_PIXELS (ri-basamento su center_macro_coords, vedi quella funzione):
	# camera.position vive nello stesso spazio canvas ma non è dentro nessun container, quindi senza
	# questa riga resterebbe fermo al vecchio valore assoluto mentre l'intero mondo si è appena
	# ri-basato sotto di lui — visivamente indistinguibile da "la camera è saltata". Traslare
	# camera.position dello STESSO delta (mai ricentrare sul bersaglio, che reintrodurrebbe un
	# follow mascherato) mantiene la camera puntata sullo stesso punto fisico del mondo: se era già
	# centrata sul bersaglio, resta centrata su di lui (anche lui trasla della stessa quantità, per
	# definizione sempre al centro); se era altrove, resta su quell'altrove esatto. Un eventuale
	# tween "centra" ancora in corso (vedi _center_camera_tween) va killato PRIMA di toccare
	# camera.position qui — altrimenti al frame successivo il tween continuerebbe a interpolare
	# verso il proprio target salvato nel vecchio spazio di coordinate, vanificando/confliggendo
	# con questa correzione.
	if _center_camera_tween != null:
		_center_camera_tween.kill()
	camera.position -= Vector2(dx, dy) * MACRO_CELL_PIXELS
	_refresh_lod_focus_region()
	_update_center_info_panel()


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
# parametrizzato. Le coordinate in DebugBar vengono aggiornate solo se `cell` è il centro (vedi
# _update_center_info_panel): mostrano dove si trova il player, non i vicini.
func _refresh_resource_visuals(cell: LiveMacroCell) -> void:
	if cell.macro_state == null:
		return

	# TEMPORANEO (diagnostica Proposta 2, vedi DebugLogging.SHOW_VEGETATION_REFRESH_TIMING_LOGS) —
	# cronometri separati per capire se il costo dell'8.9s/8 celle osservato al checkpoint
	# stagionale è nella GENERAZIONE posizioni (VegetationPositionService, indipendente dal FoW,
	# non beneficerebbe di un filtro per visibilità) o nel REBUILD MultiMesh
	# (MicroCellRenderer.set_vegetation_positions/set_*_subtypes/set_*_age_params, che invece
	# potrebbe saltare le posizioni coperte da nero pieno). Include anche il costo di
	# _update_animal_renderer_population (find_population_group è O(popolazioni totali) per
	# specie per cella — non c'entra col FoW, ma vale la pena isolarlo comunque visto che vive
	# nella stessa funzione).
	var _veg_timings_ms: Dictionary = {}
	var _veg_refresh_start_usec := Time.get_ticks_usec()

	var occupied: Dictionary = {}
	for pos in cell.macro_state.stone_positions:
		occupied[pos] = true
	for pos in cell.river_positions:
		occupied[pos] = true
	# Le microcelle edificate vanno escluse esattamente come stone/river — GRASS si affida solo a
	# `occupied` (nessuna memoria persistita, vedi VegetationPositionService), mentre per TREE/SHRUB
	# questo copre solo i lotti MAI ancora rivendicati (un lotto già noto va bloccato a parte, vedi
	# building_positions sotto — `occupied` da solo non lo fermerebbe, vedi commento in
	# VegetationPositionService.generate_positions).
	var building_positions: Dictionary = {}
	for pos in _building_positions_for_cell(cell):
		occupied[pos] = true
		building_positions[pos] = true

	# Cache (vedi LiveMacroCell.needs_full_vegetation_recompute/cached_vegetation_positions):
	# generate_positions è deterministica, il suo output cambia SOLO se dedicated_space/anno/
	# eccezioni taglio-morte/edifici sono davvero cambiati — mai per il solo spostamento del
	# player. Un refresh da movimento (nessuno di questi eventi) trova il flag già a false (chi
	# ha causato l'ultimo VERO cambiamento lo rimette a true esplicitamente) e riusa la lista già
	# calcolata, saltando del tutto il ricalcolo (~90-190ms/cella misurati).
	var _step_start_usec := Time.get_ticks_usec()
	if cell.needs_full_vegetation_recompute:
		var vegetation_service := VegetationPositionService.new()
		cell.cached_vegetation_positions = vegetation_service.generate_positions(cell.macro_state, occupied, game_data.year, game_data.current_day, building_positions)
		cell.needs_full_vegetation_recompute = false
	var vegetation_positions: Dictionary = cell.cached_vegetation_positions
	_veg_timings_ms["1_position_generation"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	# Proposta 2 (filtro FoW): il renderer riceve solo le posizioni che il FoW mostrerebbe comunque
	# in dettaglio (vedi FogOfWarRenderer.compute_visible_positions) — una posizione coperta da
	# FROZEN_OVERLAY_COLOR+hint o da nero pieno non mostra MAI il vero blob, quindi costruirgli
	# comunque un'istanza MultiMesh è lavoro sprecato. `vegetation_positions` (NON filtrato) resta
	# la fonte di verità passata a set_vegetation_presence sotto (serve l'insieme completo per
	# l'hint sintetico) e a _debug_print_individual_counts (conteggio reale di quanti individui
	# esistono, non solo quanti ne disegniamo). Il "pop-in" (zone appena esplorate che restano vuote
	# fino al prossimo refresh) resta un limite noto e accettato — mitigato da VEGETATION_REFRESH_
	# MOVE_THRESHOLD in _process, non risolto del tutto.
	_step_start_usec = Time.get_ticks_usec()
	var render_vegetation_positions := _filter_vegetation_positions_by_visibility(cell, vegetation_positions)
	_veg_timings_ms["1b_fog_visibility_filter"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	# begin_vegetation_batch()/end_vegetation_batch() (vedi MicroCellRenderer.gd): senza batching, i
	# 6 setter chiamati in questa funzione (qui + set_shrub_subtypes/set_shrub_age_params/
	# set_tree_subtypes/set_tree_age_params/set_season sotto) ricostruivano TREE fino a 4 volte,
	# SHRUB fino a 3, GRASS fino a 2 — stesso lavoro ripetuto sugli stessi individui, misurato come
	# il grosso del costo di un checkpoint stagionale con più celle vive. Dentro la finestra di
	# batch i setter si limitano a segnare "sporco"; end_vegetation_batch() (sotto, cronometrato a
	# parte in "6_batched_rebuild") fa il rebuild vero una sola volta per tipo.
	cell.renderer.begin_vegetation_batch()

	_step_start_usec = Time.get_ticks_usec()
	cell.renderer.set_vegetation_positions(render_vegetation_positions)
	_veg_timings_ms["2_multimesh_positions_set"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	# Ripristinato (richiesta utente, 2026-08-30): serve di nuovo per misurare l'esperimento
	# "ogni macrocella con edifici resta viva" (vedi _activate_all_building_cells) — quanto
	# esplode il conteggio individui al crescere delle celle-edificio sempre vive. Gated dietro
	# SHOW_VEGETATION_REFRESH_TIMING_LOGS (richiesta utente, 2026-09-02 — prima incondizionati,
	# quindi la voce più rumorosa del log: stampavano ad OGNI refresh innescato dal movimento,
	# ~ogni 3 microcelle mentre si cammina): stesso flag già usato dai log gemelli [VEG REFRESH
	# TRIGGER]/[VEG REFRESH TIMING] per lo stesso evento, così un solo interruttore silenzia o
	# riattiva l'intero gruppo insieme.
	if DebugLogging.SHOW_VEGETATION_REFRESH_TIMING_LOGS:
		_debug_print_individual_counts(cell, vegetation_positions, render_vegetation_positions)
		_debug_print_dedicated_space(cell)
	# FogOfWarRenderer disegna la vegetazione "sfocata" (Opzione B, vedi lì) sopra questa stessa
	# vegetazione VERA — MicroCellRenderer non sa nulla del fog of war, mai più da quando abbiamo
	# spostato l'Opzione B lì: il ritardo di aggiornamento a checkpoint qui non è un problema (solo
	# "c'è vegetazione più o meno qui", non l'identità precisa, e le posizioni sono comunque stabili
	# da un checkpoint all'altro), mentre FogOfWarRenderer resta reattivo giorno per giorno.
	cell.fog_of_war_renderer.set_vegetation_presence(vegetation_positions)
	# PRIMA di qualunque altro setter che ricalcola i lotti vivi (set_*_subtypes/set_*_age_params
	# sotto): quei rebuild leggono cut_positions/dead_positions per calcolare local_count
	# (vivi+bloccati, vedi MicroCellRenderer._lot_extent_counts) — se arrivassero DOPO, userebbero
	# ancora i valori dell'anno scorso per quei rebuild intermedi.
	cell.renderer.set_cut_positions(_get_cut_positions(cell.macro_state))
	cell.renderer.set_dead_positions(_get_dead_positions(cell.macro_state))

	_step_start_usec = Time.get_ticks_usec()
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
	_veg_timings_ms["3_fish_positions"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	_step_start_usec = Time.get_ticks_usec()
	var this_cell := Vector2i(cell.macro_cell.x, cell.macro_cell.y)
	for species in cell.animal_renderers:
		var group := macro_world.find_population_group(species, this_cell)
		_update_animal_renderer_population(cell.animal_renderers[species], group, AnimalCalculator.get_animal_rules(species), this_cell)
	_veg_timings_ms["4_animal_renderer_population"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	_step_start_usec = Time.get_ticks_usec()
	cell.renderer.set_shrub_subtypes(cell.macro_state.shrub_individual_subtype)
	cell.renderer.set_shrub_age_params(
		game_data.year, _get_age_params(cell.macro_state, GameTypes.WorldObjectType.SHRUB), cell.macro_state.shrub_virtual_birth_year
	)
	cell.renderer.set_tree_subtypes(cell.macro_state.tree_individual_subtype)
	cell.renderer.set_tree_age_params(
		game_data.year, _get_age_params(cell.macro_state, GameTypes.WorldObjectType.TREE), cell.macro_state.tree_virtual_birth_year
	)
	cell.renderer.set_season(SeasonCalculator.get_season_for_day(game_data.current_day))
	_veg_timings_ms["5_subtype_age_params_set"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	_step_start_usec = Time.get_ticks_usec()
	cell.renderer.end_vegetation_batch()
	_veg_timings_ms["6_batched_rebuild"] = (Time.get_ticks_usec() - _step_start_usec) / 1000.0

	_invalidate_selected_vegetation_if_missing(cell)

	if cell.macro_x == center_macro_coords.x and cell.macro_y == center_macro_coords.y:
		_update_info_panel()
		# Qualunque sia la causa di QUESTO refresh (checkpoint, taglio, edificio, o il trigger da
		# movimento in _process) — vedi VEGETATION_REFRESH_MOVE_THRESHOLD sopra: azzera la distanza
		# percorsa da qui, altrimenti un refresh arrivato da un'altra causa non "conterebbe" ai fini
		# del trigger da movimento, che ritriggererebbe subito dopo inutilmente.
		_last_vegetation_refresh_position = individual.position if individual != null else _last_vegetation_refresh_position

	if DebugLogging.SHOW_VEGETATION_REFRESH_TIMING_LOGS:
		var total_ms: float = (Time.get_ticks_usec() - _veg_refresh_start_usec) / 1000.0
		var labels: Array = _veg_timings_ms.keys()
		labels.sort()
		var parts: Array = []
		for label in labels:
			# Prefisso di ordinamento variabile in lunghezza ("1_"/"1b_"/"2_"...) — trova il primo
			# "_" invece di un substr a indice fisso, così l'etichetta stampata resta pulita
			# qualunque sia la lunghezza del prefisso.
			parts.append("%s=%.1fms" % [label.substr(label.find("_") + 1), _veg_timings_ms[label]])
		print("[VEG REFRESH TIMING] macrocella (%d,%d) totale=%.1fms | %s" % [
			cell.macro_x, cell.macro_y, total_ms, ", ".join(parts)
		])


# Proposta 2 — filtra `positions` (stesso formato di VegetationPositionService.generate_positions:
# WorldObjectType -> Array[Vector3i] per TREE/SHRUB lotto x,y+indice, Array[Vector2i] per GRASS)
# tenendo solo le voci la cui (x,y) è nell'insieme "visibile in dettaglio" di FogOfWarRenderer.
# compute_visible_positions — Vector3i e Vector2i condividono i campi x/y, letti genericamente
# senza bisogno di conoscere il tipo esatto per voce. Ritorna `positions` invariato (nessun filtro)
# se la cella non ha un FogOfWarRenderer valido — difensivo, non dovrebbe succedere in pratica per
# una cella viva reale.
func _filter_vegetation_positions_by_visibility(cell: LiveMacroCell, positions: Dictionary) -> Dictionary:
	if cell.fog_of_war_renderer == null:
		return positions
	var visible := cell.fog_of_war_renderer.compute_visible_positions(game_data.get_absolute_day())
	var filtered: Dictionary = {}
	for object_type in positions:
		var kept: Array = []
		for entry in positions[object_type]:
			if visible.has(Vector2i(entry.x, entry.y)):
				kept.append(entry)
		filtered[object_type] = kept
	return filtered


# DEBUG TEMPORANEO — vedi _debug_individual_counts_by_macro. GRASS escluso apposta (nessuna
# identità individuale, vedi VegetationPositionService). "totale sessione" resta la somma su TUTTE
# le macrocelle mai rinfrescate in questa sessione (anche quelle non più vive ora, se mai
# esistesse un modo per disattivarle) — "celle vive ora" (live_cells.size(), aggiunto 2026-08-30
# per l'esperimento _activate_all_building_cells) è invece il numero da guardare per capire quante
# macrocelle stanno pagando il costo pieno DI QUESTO momento, dato che con gli edifici sempre vivi
# il numero non è più limitato a ≤2 (centro + un vicino) come prima.
func _debug_print_individual_counts(cell: LiveMacroCell, vegetation_positions: Dictionary, render_vegetation_positions: Dictionary) -> void:
	var count: int = (
		vegetation_positions.get(GameTypes.WorldObjectType.TREE, []).size()
		+ vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []).size()
	)
	# "disegnati" (richiesta utente, 2026-08-30): conteggio SEPARATO su render_vegetation_positions
	# (il sottoinsieme filtrato da _filter_vegetation_positions_by_visibility, quello che finisce
	# davvero nel MultiMesh) — mai sommato in _debug_individual_counts_by_macro/"totale sessione",
	# che restano legati a `count` (individui REALI, indipendenti dal FoW): due metriche diverse,
	# una misura la simulazione, l'altra il costo di rendering di QUESTO refresh.
	var drawn_count: int = (
		render_vegetation_positions.get(GameTypes.WorldObjectType.TREE, []).size()
		+ render_vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []).size()
	)
	_debug_individual_counts_by_macro[Vector2i(cell.macro_x, cell.macro_y)] = count

	var total: int = 0
	for c in _debug_individual_counts_by_macro.values():
		total += c
	# +1 se questa stessa cella non è ancora in live_cells: _activate_live_cell chiama
	# _refresh_resource_visuals (quindi questo log) PRIMA di inserire la cella in live_cells alla
	# fine della propria esecuzione — senza questa correzione, il primissimo refresh di ogni cella
	# appena attivata la conterebbe come mancante per un istante.
	var current_coords := Vector2i(cell.macro_x, cell.macro_y)
	var live_count: int = live_cells.size()
	if not live_cells.has(current_coords):
		live_count += 1
	# "totale celle vive" (richiesta utente, 2026-08-30): a differenza di "totale sessione" (somma
	# su TUTTE le macrocelle tracciate, incluse quelle uscite dal focus ma non ancora dimenticate
	# dal fog of war, quindi con un conteggio congelato al loro ultimo refresh) questo somma solo
	# le celle ATTUALMENTE vive — lo stesso +1 di live_count sopra, per lo stesso motivo di ordine
	# chiamata/inserimento in live_cells.
	var live_total: int = 0
	for coords in _debug_individual_counts_by_macro:
		if live_cells.has(coords) or coords == current_coords:
			live_total += _debug_individual_counts_by_macro[coords]
	print("[DEBUG INDIVIDUI] macrocella (%d,%d): %d individui (disegnati: %d) | celle vive ora: %d | macrocelle tracciate: %d | totale sessione: %d | totale celle vive: %d" % [
		cell.macro_x, cell.macro_y, count, drawn_count, live_count, _debug_individual_counts_by_macro.size(), total, live_total
	])
	# DEBUG TEMPORANEO (richiesta utente, 2026-09-02): elenco ESPLICITO delle coordinate vive in
	# questo momento — "celle vive ora" sopra è solo un conteggio, non dice QUALI. Stessa
	# correzione di live_count sopra (current_coords potrebbe non essere ancora in live_cells alla
	# primissima chiamata per una cella appena attivata), per restare coerente con quel numero.
	var live_coords: Array = live_cells.keys()
	if not live_cells.has(current_coords):
		live_coords.append(current_coords)
	live_coords.sort()
	print("[DEBUG CELLE VIVE] %s" % [live_coords])


# DEBUG TEMPORANEO — segue il lavoro su edifici/spazio (BuildingSiteClearingService/
# SpaceReconciliationService): dedicated_space per tipo (river_space incluso separatamente,
# stesso trattamento di MacroCellState.get_total_dedicated_space) più il totale, per verificare a
# vista che uno scambio libera-poi-occupa non faccia salire la somma oltre MacroCellState.
# TOTAL_SPACE (o quanto ci si avvicina/supera nel raro caso di overshoot discusso).
const _DEBUG_SPACE_TYPES := [
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.ROCK,
	GameTypes.WorldObjectType.BUILDING,
]

func _debug_print_dedicated_space(cell: LiveMacroCell) -> void:
	if cell.macro_state == null:
		return
	var parts: Array = []
	for object_type in _DEBUG_SPACE_TYPES:
		parts.append("%s=%d" % [GameTypes.WorldObjectType.keys()[object_type], cell.macro_state.get_dedicated_space(object_type)])
	parts.append("river=%d" % cell.macro_state.get_river_space())
	print("[DEBUG SPAZIO] macrocella (%d,%d): %s | totale=%d/%d | vuoto=%d" % [
		cell.macro_x, cell.macro_y, ", ".join(parts),
		cell.macro_state.get_total_dedicated_space(), MacroCellState.TOTAL_SPACE, cell.macro_state.get_empty_space()
	])


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


# Sottotipo/anno di nascita non si decidono più qui (vedi IndividualVegetationService, chiamato
# dentro generate_positions PRIMA di arrivare a questo punto di _refresh_resource_visuals): questa
# funzione resta solo per i parametri fascia età (youth/adult duration, size_multiplier_by_age)
# che _resolve_age_band_and_size del renderer legge per-sottotipo — non più il campo "ratios" (usato
# solo dalla stima a percentile, ora eseguita direttamente da IndividualVegetationService sui dati
# di macro_state, non più passata attraverso questo dizionario).
func _get_age_params(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
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
# MicroCellRenderer.set_cut_positions/set_dead_positions (il marker visivo da disegnare sopra lo
# slot bloccato al posto del blob vivo, che per quello slot non esiste).
func _get_cut_positions(macro_state: MacroCellState) -> Dictionary:
	return {
		GameTypes.WorldObjectType.TREE: IndividualVegetationService.get_cut_positions(macro_state, GameTypes.WorldObjectType.TREE, game_data.year),
		GameTypes.WorldObjectType.SHRUB: IndividualVegetationService.get_cut_positions(macro_state, GameTypes.WorldObjectType.SHRUB, game_data.year),
	}


func _get_dead_positions(macro_state: MacroCellState) -> Dictionary:
	return {
		GameTypes.WorldObjectType.TREE: IndividualVegetationService.get_dead_positions(macro_state, GameTypes.WorldObjectType.TREE),
		GameTypes.WorldObjectType.SHRUB: IndividualVegetationService.get_dead_positions(macro_state, GameTypes.WorldObjectType.SHRUB),
	}




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


# Aggiorna GameData con la posizione ATTUALE dell'individuo/zoom camera (vedi HumanIndividual.position/
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
		# player_individual_id (richiesta utente, 2026-09-02 — persistenza umana): quale membro
		# del gruppo era il bersaglio corrente, per ripristinare `individual` sullo STESSO
		# individuo invece che sempre human_individuals[0] (vedi _ready()). player_macro_cell_x/y
		# DERIVATO da individual.home_macro_coords (mai più mantenuto incrementalmente sparso tra
		# _attempt_macro_cell_transition e altri punti — quel campo serve anche a chi non è
		# individual/GameScene, es. FirstStartMacroCellSelectionService/il salto debug verso
		# MacroCellScene, quindi va tenuto comunque aggiornato, ma derivarlo qui una volta sola al
		# momento del sync è più robusto che fidarsi di ogni singolo punto che sposta il bersaglio
		# per ricordarsi di aggiornarlo a mano).
		game_data.player_individual_id = individual.id
		game_data.player_macro_cell_x = individual.home_macro_coords.x
		game_data.player_macro_cell_y = individual.home_macro_coords.y
	# Posizione camera (Step 3, 2026-09-02 — PRIMA non aveva stato proprio da salvare: seguiva
	# sempre l'individuo, la cui posizione era già persistita sopra. Ora che la camera è libera,
	# non è più derivabile da nient'altro, va salvata per conto suo). camera_position_saved=true
	# marca il campo come valorizzato — vedi GameData per il perché un booleano esplicito invece
	# del sentinel -1.0 usato altrove in questo stesso metodo.
	game_data.camera_x = camera.position.x
	game_data.camera_y = camera.position.y
	game_data.camera_position_saved = true
	game_data.camera_zoom = camera.zoom.x


func _on_save_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo condiviso: impossibile salvare.")
		return
	_sync_individual_state_to_game_data()
	save_game_file_dialog.popup_centered()

func _on_save_game_file_selected(path: String) -> void:
	var save_service := GameSaveService.new()
	save_service.save_game_to_json(
		macro_world, game_data, path, fog_of_war_memories, human_folk, human_population_group, human_individuals
	)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()

# &"center_on_individual" (era l'unico case qui) rimosso insieme allo spostamento del bottone "🎯"
# fuori da PrimaryActionsBar — vive ora nell'header di GameInfoTabs.SelectionTab (Step 3, richiesta
# utente 2026-09-04 — vedi game_info_tabs.center_requested in _ready). Slot 0 di primary_actions_bar
# è oggi il placeholder "statistiche" (&"statistics", disabled — vedi GameInfoPanel._ready): nessun
# case qui finché resta disabilitato, un futuro passo che lo implementa ne aggiungerà uno.
func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		_:
			pass


# toggle_animals_visibility/toggle_flora_updates/world_debug/macro_cell_debug — vissuti prima
# dentro _on_primary_action_pressed/_on_secondary_action_pressed, spostati qui insieme allo
# spostamento dei relativi bottoni da GameInfoPanel a DebugBar (vedi DebugBar.gd): stesso
# comportamento di sempre, solo il pannello sorgente del segnale action_pressed e' cambiato.
func _on_debug_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"toggle_animals_visibility":
			animals_visible = not animals_visible
			# Un solo toggle per tutta la fauna, di TUTTE le celle vive — stesso principio di
			# MacroCellScene, esteso a più di una cella.
			for cell in live_cells.values():
				for r in cell.animal_renderers.values():
					r.set_animals_visible(animals_visible)
			debug_bar.set_slot_toggled(1, animals_visible)
			GameSettings.game_scene_animals_visible = animals_visible
		&"toggle_flora_updates":
			flora_daily_updates_enabled = not flora_daily_updates_enabled
			debug_bar.set_slot_toggled(0, flora_daily_updates_enabled)
			GameSettings.game_scene_flora_updates_enabled = flora_daily_updates_enabled
		&"world_debug":
			_on_world_debug_pressed()
		&"macro_cell_debug":
			_on_macro_cell_debug_pressed()
		&"advance_year":
			_on_advance_year_pressed()


# Tasto 🛖 nel sottomenu costruzione di BuildBar — per ora SOLO l'anteprima visiva (vedi
# BuildingGhost/_building_ghost), toggle on/off allo stesso click: nessun piazzamento reale,
# nessuna verifica materiali/tech/spazio (quei sistemi non esistono ancora). Creata/distrutta ad
# ogni toggle invece di restare sempre presente e solo nascosta — un Node2D usa e getta, costo
# trascurabile.
func _on_build_submenu_action_pressed(action_id: StringName) -> void:
	var building_type_name := _building_type_name_for_action(action_id)
	if building_type_name == "":
		return
	if _building_ghost != null:
		_clear_building_ghost()
		return
	_selected_building_type_name = building_type_name
	_building_ghost = BuildingGhost.new()
	add_child(_building_ghost)


# Unica mappatura action_id -> nome tipo edificio (per BuildingCalculator.get_building_rules) —
# solo "hut" esiste oggi, ma tenerla come funzione dedicata invece di un valore hardcoded dentro
# _place_building_at evita di dover toccare quel metodo quando arriverà un secondo tipo.
func _building_type_name_for_action(action_id: StringName) -> String:
	match action_id:
		&"build_hut":
			return "hut"
		_:
			return ""


func _clear_building_ghost() -> void:
	if _building_ghost == null:
		return
	_building_ghost.queue_free()
	_building_ghost = null
	_selected_building_type_name = ""


# Piazzamento REALE (debug, vedi discussione con l'utente sul perché è così semplice): completo
# immediatamente — is_complete=true da subito, current_durability già a rules.max_durability,
# niente min_construction_days/required_labor/materiali/tech (quei sistemi non esistono ancora —
# in futuro il taglio e la costruzione diventeranno processi distribuiti su più giorni, non più
# istantanei come oggi). Verifica di edificabilità (BuildingVerificationService) ricollegata
# 2026-08-30, ricostruita da zero passo per passo — vedi il service per lo stato attuale dei
# criteri.
# Il fantasma NON viene rimosso da qui: resta al chiamante (_unhandled_input) l'aver deciso di
# continuare il modo piazzamento dopo un piazzamento riuscito.
#
# Sequenza "libera-poi-occupa": PRIMA si libera dal budget vegetazione esattamente quello che
# occupa già la microcella (BuildingSiteClearingService — TREE/SHRUB realmente presenti, se
# entrambi coesistono per via di MIX_TREE_AND_SHRUB vengono rimossi entrambi indipendentemente;
# GRASS se il renderer la mostra lì in questo momento), POI si aggiunge lo spazio dell'edificio.
# In questo ordine il totale dedicated_space+river_space non supera mai TOTAL_SPACE (era già
# ≤ TOTAL_SPACE prima, resta tale dopo — uno scambio, mai un'aggiunta a bilancio aperto), quindi
# MacroCellState.get_empty_space() non può mai andare sotto zero per colpa di un edificio.
func _place_building_at(world_position: Vector2) -> void:
	if macro_world == null:
		return
	var rules := BuildingCalculator.get_building_rules(_selected_building_type_name)
	if rules == null:
		return
	if not BuildingVerificationService.is_position_buildable(
		live_cells, MACRO_CELL_PIXELS, MicroCellRenderer.CELL_SIZE, world_position,
		game_data.get_absolute_day(), macro_world, _building_ghost.rotation_dir, rules
	):
		return
	var placement := _live_cell_and_micro_position_at(world_position)
	if placement.is_empty():
		return
	var target_cell: LiveMacroCell = placement["cell"]
	var micro_pos: Vector2i = placement["micro_pos"]
	var state := macro_world.get_cell_state_at(target_cell.macro_x, target_cell.macro_y)
	if state == null:
		return

	var current_grass_positions: Array = target_cell.renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	BuildingSiteClearingService.clear_microcell(state, micro_pos, current_grass_positions.has(micro_pos))

	var building := Building.new(rules, target_cell.macro_x, target_cell.macro_y, _selected_building_type_name)
	building.id = macro_world.allocate_building_id()
	building.micro_x = micro_pos.x
	building.micro_y = micro_pos.y
	building.is_complete = true
	building.current_durability = rules.max_durability
	building.built_year = game_data.year
	building.rotation = _building_ghost.rotation_dir
	macro_world.buildings.append(building)

	# Sottrae lo spazio dell'edificio dal budget vegetazione della macrocella — stesso meccanismo
	# generico già usato per ROCK (MacroCellState.dedicated_space), mai un campo dedicato a parte
	# come river_space: get_empty_space()/get_land_growth_surplus() lo vedono automaticamente al
	# prossimo controllo, nessun ricalcolo stagionale da aggiungere qui. Sommato (non sovrascritto)
	# al valore già presente, per supportare più edifici nella stessa macrocella.
	var current_building_space := state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
	state.set_dedicated_space(GameTypes.WorldObjectType.BUILDING, current_building_space + rules.required_space)

	_refresh_building_visuals(target_cell)
	# Ricalcola SUBITO la vegetazione (non solo al prossimo avanzamento giorno/anno): senza questa
	# chiamata, il taglio/decremento appena applicato ai dati resterebbe corretto ma invisibile a
	# schermo fino al prossimo trigger naturale — vedi _building_positions_for_cell, ora incluso
	# nell'occupied/building_positions passati a VegetationPositionService, che blocca in modo
	# permanente la rigenerazione su questa stessa microcella. dedicated_space[BUILDING] e i lotti
	# liberati da BuildingSiteClearingService sono cambiati per QUESTA cella — invalida la cache
	# posizioni (vedi LiveMacroCell.needs_full_vegetation_recompute).
	target_cell.needs_full_vegetation_recompute = true
	_refresh_resource_visuals(target_cell)

	print("[BUILDING] %s #%d piazzata in (%d,%d) — totale edifici: %d" % [
		_selected_building_type_name, building.id, target_cell.macro_x, target_cell.macro_y, macro_world.buildings.size()
	])


# LiveMacroCell + posizione MICRO (coordinate di griglia, non pixel) sotto world_position, o {} se
# nessuna cella viva la copre (fuori dall'area caricata) — stessa logica di traduzione (to_local +
# range check) già usata da BuildingVerificationService.is_position_buildable, qui estesa a
# restituire anche la posizione micro esatta (serve per l'ancoraggio del disegno, vedi
# MicroCellRenderer._draw_buildings), non solo "quale cella".
func _live_cell_and_micro_position_at(world_position: Vector2) -> Dictionary:
	for cell in live_cells.values():
		var local_pos: Vector2 = cell.container.to_local(world_position)
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= MACRO_CELL_PIXELS or local_pos.y >= MACRO_CELL_PIXELS:
			continue
		var micro_pos := Vector2i(int(local_pos.x / MicroCellRenderer.CELL_SIZE), int(local_pos.y / MicroCellRenderer.CELL_SIZE))
		return {"cell": cell, "micro_pos": micro_pos}
	return {}


# Posizioni MICRO (Array[Vector2i]) degli edifici già piazzati in QUESTA macrocella — filtra
# World.buildings per macro_x/macro_y, unica fonte di verità (nessuna copia mantenuta altrove).
# Usata sia per il disegno (_refresh_building_visuals) sia per escludere quelle stesse microcelle
# dalla rigenerazione di vegetazione (_refresh_resource_visuals) — un solo punto che le calcola,
# mai due elenchi che potrebbero disallinearsi.
func _building_positions_for_cell(cell: LiveMacroCell) -> Array:
	var positions: Array = []
	if macro_world == null:
		return positions
	for building in macro_world.buildings:
		if building.macro_x == cell.macro_x and building.macro_y == cell.macro_y:
			positions.append(Vector2i(building.micro_x, building.micro_y))
	return positions


# Stessa fonte/filtro di _building_positions_for_cell sopra, ma con l'orientamento (e, da Step 4,
# l'id) inclusi — vedi MicroCellRenderer.set_buildings/buildings (Array[Dictionary], {"position",
# "rotation","id"}). Funzione separata invece di arricchire quella sopra: _building_positions_for_
# cell resta usata anche per l'esclusione vegetazione, dove rotazione/id non servono a nessuno.
# "id" (Step 4, richiesta utente 2026-09-04): permette al renderer di ritrovare l'edificio
# selezionato tra i propri (set_selected_building/get_building_screen_position) senza dover
# conoscere Building stesso — stesso principio "il renderer conosce solo le forme, mai gli oggetti
# di gioco" già seguito per la vegetazione (individual_key, mai un riferimento a MacroCellState).
func _buildings_for_cell(cell: LiveMacroCell) -> Array:
	var result: Array = []
	if macro_world == null:
		return result
	for building in macro_world.buildings:
		if building.macro_x == cell.macro_x and building.macro_y == cell.macro_y:
			result.append({
				"position": Vector2i(building.micro_x, building.micro_y),
				"rotation": building.rotation,
				"id": building.id,
			})
	return result


# Microcelle entro rules.visibility_radius di ciascun edificio di QUESTA macrocella (distanza di
# Chebyshev/quadrata, coerente col design originale "0 = solo la propria, 1 = le 8 intorno, 2 =
# un altro anello") — passate a FogOfWarRenderer, che le tratta come il raggio del player
# (nessun overlay, mark_seen sempre aggiornato). Dictionary (non Array) perché il consumatore fa
# solo test di appartenenza per singola posizione, mai un'iterazione ordinata.
func _building_visible_positions_for_cell(cell: LiveMacroCell) -> Dictionary:
	var positions: Dictionary = {}
	if macro_world == null:
		return positions
	for building in macro_world.buildings:
		if building.macro_x != cell.macro_x or building.macro_y != cell.macro_y:
			continue
		var radius: int = building.rules.visibility_radius if building.rules != null else 0
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var pos := Vector2i(building.micro_x + dx, building.micro_y + dy)
				if pos.x < 0 or pos.x >= World.WIDTH or pos.y < 0 or pos.y >= World.HEIGHT:
					continue
				positions[pos] = true
	return positions


# Ricostruisce l'elenco di posizioni edificio da disegnare per QUESTA cella viva, e le posizioni
# rese permanentemente visibili in FoW dal loro raggio — chiamata sia dopo un piazzamento riuscito
# sia all'attivazione di una cella viva (_activate_live_cell), così gli edifici già presenti in un
# save caricato o in una cella rivisitata vengono ridisegnati e la loro FoW resta corretta subito,
# senza dover aspettare che il player vi transiti fisicamente.
func _refresh_building_visuals(cell: LiveMacroCell) -> void:
	if macro_world == null:
		return
	cell.renderer.set_buildings(_buildings_for_cell(cell))
	if cell.fog_of_war_renderer != null:
		cell.fog_of_war_renderer.set_building_visible_positions(_building_visible_positions_for_cell(cell))

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"help":
			help_dialog.open_dialog()
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
	# Bugfix (richiesta utente, 2026-09-05): human_population_info_panel/human_individual_info_panel
	# mostravano età/age_band ricalcolate al volo (mai salvate, vedi HumanCalculator.get_age_band)
	# ma solo al MOMENTO in cui venivano popolati (rispettivamente: una volta sola in _ready, o ad
	# ogni nuova selezione) — mai più aggiornati col passare degli anni, disallineando la vista
	# individuale (si aggiornava solo cambiando selezione) da quella aggregata (mai aggiornata
	# affatto). L'età cambia SOLO al rollover d'anno (mai infragiornaliero), quindi basta
	# agganciarsi al nuovo clock.year_rolled_over (vedi GameClockController) invece che a
	# day_advanced (che scatterebbe inutilmente ogni giorno).
	clock.year_rolled_over.connect(_on_year_rolled_over)
	# Primo aggancio gameplay-side ai checkpoint classificati (richiesta utente, 2026-09-05) — vedi
	# GameTimeService per il perché l'istanza va tenuta in un campo, non usa-e-getta.
	game_time_service = GameTimeService.new()
	game_time_service.connect_to_clock(clock, game_data)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	for speed in speed_buttons.keys():
		speed_buttons[speed].pressed.connect(_on_speed_button_pressed.bind(speed))
	# Pulsante "velocità debug" (richiesta utente, 2026-09-04): stesso flag già usato altrove
	# (debug_bar/debug_animal_container), nessun meccanismo di debug-mode nuovo introdotto.
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
	# TEMPORANEO (diagnostica lentezza, vedi GameClockController._process/[DAY TOTAL]) — questo
	# intero handler gira SINCRONO dentro day_advanced.emit(), quindi dentro il cronometro di
	# [DAY TOTAL]: il ramo sotto (rebuild vegetazione per cella viva, "come individui" — posizioni/
	# MultiMesh, non "come aggregati" — quello è dedicated_space/quantity, già misurato da
	# [LOD TIMING] growth_checkpoint dentro WorldTimeService) è il costo GameScene-side mai visto
	# da WorldTimeService, sospettato responsabile della differenza tra [DAY TOTAL] e la somma di
	# [DAY TIMING].
	var _debug_day_advanced_start_usec := Time.get_ticks_usec()

	_update_calendar_display()
	# Cadenza propria, scollegata da checkpoint_ran/animals_changed sopra e dal checkpoint
	# stagionale di WorldTimeService (vedi _maybe_prune_fog_of_war_memories per il perché) — gira
	# quindi anche nei giorni "vuoti" in cui il resto di questa funzione farebbe early-return sotto.
	_maybe_prune_fog_of_war_memories()
	if not (checkpoint_ran or animals_changed):
		if DebugLogging.SHOW_DAILY_TIMING_LOGS:
			var elapsed_ms: float = (Time.get_ticks_usec() - _debug_day_advanced_start_usec) / 1000.0
			print("[GAMESCENE DAY] _on_day_advanced (nessun rebuild vegetazione: checkpoint_ran=no, animals_changed=no) = %.1fms" % elapsed_ms)
		return

	if checkpoint_ran or flora_daily_updates_enabled:
		if checkpoint_ran:
			# Crescita/mortalità/encroachment (WorldTimeService) hanno appena potuto cambiare
			# dedicated_space per QUALUNQUE macrocella del mondo, comprese le celle vive SOLO per
			# via di un edificio lontano (mai realmente rinfrescate qui sotto, vedi _player_
			# proximity_live_cells) — la loro cache posizioni va comunque invalidata ORA, anche se
			# il ricalcolo vero verrà rimandato a quando il player ci arriverà davvero (trigger da
			# movimento in _process, o riattivazione al cambio di centro). Senza questo, quelle
			# celle mostrerebbero per sempre lo stato di dedicated_space del momento in cui sono
			# diventate vive, anche dopo anni di crescita/mortalità mai riflessi.
			for cell in live_cells.values():
				cell.needs_full_vegetation_recompute = true

		# Proposta "prossimità" (2026-08-30, idea utente): il ridisegno vero (posizioni+MultiMesh,
		# costoso) si limita alle celle che il player sta EFFETTIVAMENTE esplorando — il centro più
		# gli eventuali vicini attivi di prossimità (max ~4, vedi _active_neighbor_coords_set) — mai
		# le celle vive SOLO per un edificio lontano: nessuno le sta guardando, quindi un ridisegno
		# lì sarebbe invisibile e sprecato. I dati restano comunque corretti (vedi sopra): quando il
		# player ci arriverà davvero, needs_full_vegetation_recompute è ancora true e quella cella
		# verrà rinfrescata con lo stato vero e aggiornato, non quello del momento dell'attivazione.
		var proximity_cells := _player_proximity_live_cells()
		var vegetation_refresh_start_usec := Time.get_ticks_usec()
		for cell in proximity_cells:
			# PRIMA del rebuild: se ResourceMortalityService ha appena registrato una perdita
			# aggregata quest'anno (last_mortality_loss, scritto solo al rollover d'anno — vedi
			# WorldTimeService._run_seasonal_checkpoints), la traduce in marker "morto" specifici
			# così il rebuild qui sotto li disegna subito, nella stessa chiamata. No-op silenzioso
			# nei giorni ordinari (il campo è vuoto).
			_apply_natural_mortality_visuals(cell)
			_refresh_resource_visuals(cell)
		if DebugLogging.SHOW_DAILY_TIMING_LOGS:
			var vegetation_refresh_ms: float = (Time.get_ticks_usec() - vegetation_refresh_start_usec) / 1000.0
			print("[GAMESCENE DAY] rebuild vegetazione (%d/%d celle vive rinfrescate — solo prossimità, checkpoint_ran=%s flora_daily_updates_enabled=%s) = %.1fms" % [
				proximity_cells.size(), live_cells.size(), "si" if checkpoint_ran else "no", "si" if flora_daily_updates_enabled else "no", vegetation_refresh_ms
			])
	else:
		_update_info_panel()

	if DebugLogging.SHOW_DAILY_TIMING_LOGS:
		var elapsed_ms: float = (Time.get_ticks_usec() - _debug_day_advanced_start_usec) / 1000.0
		print("[GAMESCENE DAY] _on_day_advanced totale = %.1fms" % elapsed_ms)

# Pulizia periodica di TUTTE le FogOfWarMemory mai create in questa partita (fog_of_war_memories
# — non solo quelle attualmente vive: l'obiettivo è limitare la crescita nel tempo anche per
# macrocelle uscite dal set vivo da tempo, vedi la discussione con l'utente sul dizionario
# last_seen_by_position altrimenti non limitato). Cadenza indipendente da WorldTimeService di
# proposito: quel servizio itera l'intero mondo ad ogni checkpoint stagionale (costoso per
# design), mentre qui il dominio è già naturalmente piccolo (solo le macrocelle mai visitate dal
# player) — non c'è motivo di accoppiare le due cose, né di prendere in prestito la cadenza
# stagionale. game_data.fog_of_war_last_prune_absolute_day persiste su salvataggio (vedi
# GameData/GameSaveService/GameLoadService) apposta: senza, ogni ricaricamento farebbe ripartire
# il conteggio da zero, sfasando la cadenza reale rispetto al tempo di gioco davvero trascorso.
func _maybe_prune_fog_of_war_memories() -> void:
	var rules := FogOfWarCalculator.get_fog_of_war_rules()
	var interval_days: int = rules.prune_interval_days if rules != null else 21
	var current_absolute_day := game_data.get_absolute_day()
	if current_absolute_day - game_data.fog_of_war_last_prune_absolute_day < interval_days:
		return

	# Soglia = il massimo ATTUALMENTE conosciuto, mai un tetto teorico futuro (vedi
	# FogOfWarCalculator.get_max_known_memory_days per il perché) — letto una sola volta per
	# l'intera passata, non per ogni FogOfWarMemory, dato che è lo stesso per tutta la partita oggi.
	var max_known_memory_days := FogOfWarCalculator.get_max_known_memory_days()
	for coords in fog_of_war_memories:
		var memory: FogOfWarMemory = fog_of_war_memories[coords]
		# "aveva ancora qualcosa PRIMA di potare, non ha più nulla DOPO" — il segnale preciso che
		# questa macrocella, nel suo insieme, è appena diventata del tutto dimenticata (non solo
		# "questa specifica entry era già vuota da prima", che non è un evento, solo uno stato).
		var had_positions_before: bool = not memory.last_seen_by_position.is_empty()
		# Step 3.3 (2026-09-03, quarto trigger del dirty-tracking, discrepanza 1 discussa con
		# l'utente): prune_stale ora RESTITUISCE le posizioni potate invece di scartarle — sono
		# l'UNICO altro punto (oltre ai tre già noti in FogOfWarRenderer: mark_seen, cambio
		# giorno, refresh vegetazione) che tocca last_seen_by_position, quindi la texture
		# persistente di FogOfWarRenderer deve saperlo esplicitamente, non affidarsi
		# all'invariante "terrain_memory_days è sempre il tier più lungo" (vera oggi, non
		# imposta dal codice). Solo per macrocelle ATTUALMENTE vive: quelle senza renderer non
		# hanno né cache né texture da invalidare, verranno ricostruite da zero quando
		# ridiventeranno vive.
		var pruned_positions := memory.prune_stale(current_absolute_day, max_known_memory_days)
		if not pruned_positions.is_empty() and live_cells.has(coords):
			live_cells[coords].fog_of_war_renderer.mark_positions_dirty(pruned_positions)
		if had_positions_before and memory.last_seen_by_position.is_empty():
			_forget_vegetation_identity(coords)

	game_data.fog_of_war_last_prune_absolute_day = current_absolute_day


# Svuota SOLO l'identità "ordinaria" di TREE/SHRUB per (mx,my) — mai le eccezioni di taglio/morte,
# vedi IndividualVegetationService.forget_known_individuals per il dettaglio completo. Chiamata
# SOLO quando il FogOfWarMemory di questa macrocella è appena diventato completamente vuoto (vedi
# sopra): per costruzione questo non può mai capitare per una macrocella attualmente viva — una
# cella viva ha sempre almeno le posizioni nel raggio di visibilità marcate "viste" in questo
# stesso giorno (mark_seen scatta ogni frame lì), quindi la sua età è sempre 0, mai oltre
# max_known_memory_days — nessun controllo esplicito "è viva?" necessario qui.
func _forget_vegetation_identity(coords: Vector2i) -> void:
	if macro_world == null:
		return
	var state := macro_world.get_cell_state_at(coords.x, coords.y)
	if state == null:
		return
	IndividualVegetationService.forget_known_individuals(state, GameTypes.WorldObjectType.TREE)
	IndividualVegetationService.forget_known_individuals(state, GameTypes.WorldObjectType.SHRUB)

	# DEBUG TEMPORANEO — vedi _debug_individual_counts_by_macro: senza questo il contatore di
	# debug non saprebbe mai che questa macrocella è stata svuotata (si aggiorna solo quando la
	# cella torna viva e viene rinfrescata, mai su un evento di pulizia) — resterebbe fermo al
	# vecchio conteggio per sempre, facendo sembrare che la pulizia non stia facendo nulla.
	if _debug_individual_counts_by_macro.has(coords):
		_debug_individual_counts_by_macro.erase(coords)
		var total: int = 0
		for c in _debug_individual_counts_by_macro.values():
			total += c
		print("[DEBUG INDIVIDUI] macrocella (%d,%d) dimenticata dal fog -> rimossa dal conteggio | totale sessione: %d" % [
			coords.x, coords.y, total
		])


func _on_advance_year_pressed() -> void:
	if macro_world == null:
		push_warning("Nessun mondo condiviso: impossibile avanzare l'anno.")
		return
	clock.force_advance_to_year_end()

func _update_calendar_display() -> void:
	year_title_label.text = game_data.current_era_name.capitalize()
	year_label.text = "Day %d of %d, Year %d" % [game_data.current_day + 1, GameData.DAYS_PER_YEAR, game_data.year]
	season_progress_bar.set_current_day(game_data.current_day)


# STRUMENTO DI DEBUG (vedi DebugBar.gd): da rimuovere prima del player finale — il player non
# deve poter "teletrasportarsi" alla vista mondo a piacimento.
# Stesso schema di MacroCellScene._on_back_to_world_pressed: macro_world/game_data sono già gli
# stessi oggetti letti da GameSettings.active_world/active_game_data all'ingresso (mai
# riassegnati a qualcos'altro nel frattempo), quindi non serve riscriverli — solo lo stato
# dell'orologio, che invece cambia durante la sessione.
func _on_world_debug_pressed() -> void:
	_sync_individual_state_to_game_data()
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.active_human_folk = human_folk
	GameSettings.active_human_population_group = human_population_group
	GameSettings.active_human_individuals = human_individuals
	GameSettings.returning_to_world_scene = true
	if clock != null and macro_world != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://simulation/scenes/game/WorldScene.tscn")


# STRUMENTO DI DEBUG (vedi DebugBar.gd): da rimuovere prima del player finale. Stesso schema del
# bottone "🧍" di WorldScene/MacroCellScene (_on_game_view_
# pressed) ma in direzione opposta: verso MacroCellScene, sulla STESSA cella in cui si trova il
# player (GameData.player_macro_cell_x/y) — nessun returning_to_* da impostare, MacroCellScene
# non ha un concetto di "ritorno", legge sempre selected_macro_cell_x/y + active_world fresco.
func _on_macro_cell_debug_pressed() -> void:
	_sync_individual_state_to_game_data()
	GameSettings.active_fog_of_war_memories = fog_of_war_memories
	GameSettings.active_human_folk = human_folk
	GameSettings.active_human_population_group = human_population_group
	GameSettings.active_human_individuals = human_individuals
	GameSettings.selected_macro_cell_x = game_data.player_macro_cell_x
	GameSettings.selected_macro_cell_y = game_data.player_macro_cell_y
	GameSettings.active_world = macro_world
	GameSettings.active_game_data = game_data
	if clock != null:
		GameSettings.active_clock_is_playing = clock.is_playing
		GameSettings.active_clock_speed = clock.speed
	get_tree().change_scene_to_file("res://simulation/scenes/game/MacroCellScene.tscn")
