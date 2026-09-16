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
# Sistema minimo di popup di notifica (richiesta utente, 2026-09-05) — istanziato via codice in
# _setup_clock (nessun .tscn, stesso pattern di HumanIndividualView), aggiunto sotto CanvasLayer
# così resta in overlay sopra il resto della UI di gioco.
var notification_popup: NotificationPopup
# Banner "selezione Transport a metà" (2026-09-14, richiesta utente — sostituisce l'idea di un
# timeout automatico: "prova una indicazione visibile") — STESSO principio/STESSA posizione di
# notification_popup sopra (istanziato via codice in _setup_clock, aggiunto sotto CanvasLayer),
# ma PERSISTENTE (mai in coda/auto-dissolvenza come NotificationPopup): resta visibile per l'intera
# durata in cui _debug_transport_source_building non è null, un singolo nodo mostrato/nascosto
# (mai ricreato) ai tre punti che cambiano quello stato — vedi _on_transport_source_resource_chosen
# (mostra)/_debug_try_assign_transport_command_on_right_click (nasconde, destinazione confermata)/
# _stop_selected_individual_task (nasconde, annullato con H).
var transport_selection_banner: PanelContainer
var transport_selection_banner_label: Label
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
# Cablaggio Walk/Action/Task (2026-09-06/07, richiesta utente) — stesso identico pattern di
# individual_movement_service sopra: stateless rispetto all'identità, un solo service condiviso,
# mai un'istanza per individuo (l'unico stato per-azione vive su HumanIndividual.current_task,
# non qui). Girato ogni frame in _process, DOPO individual_movement_service.advance_movement.
var individual_action_service := HumanIndividualActionService.new()

# TEMPORANEO (debug, richiesta utente — indagine "pipottini che ondeggiano fermi"): il pannello
# individuo normalmente si aggiorna solo al cambio giorno di gioco (_on_day_advanced) o al click di
# (ri)selezione, vedi _refresh_selected_individual_panel — troppo raro per osservare in tempo reale
# cosa succede a current_task/task_queue mentre si indaga il bug. Questo timer forza lo stesso
# refresh ogni DEBUG_PANEL_REFRESH_INTERVAL_SEC secondi REALI (Engine.get_process_delta_time, non
# game_delta: deve continuare anche a clock in pausa/a qualunque velocità di simulazione, stesso
# principio del movimento player in _process). Da RIMUOVERE (insieme al blocco in _process che lo
# consuma) una volta conclusa l'indagine — non è pensato per restare nella build finale.
const DEBUG_PANEL_REFRESH_INTERVAL_SEC: float = 0.5
var _debug_panel_refresh_timer: float = 0.0
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
# TaskDefinition "haul_resource" (2026-09-10, richiesta utente — estensione TaskFactory per PICKUP)
# — stesso pattern/stesso trattamento di PLAYER_HUMAN_RULES_PATH sopra: un path const, caricato via
# load() al punto d'uso (vedi _assign_pickup_task), non preload() (riservato alle .tscn in questo
# file, vedi le costanti *_SCENE sotto). Copre solo i primi due step [Walk, PickUp] — il resto della
# catena (ricerca magazzino/Unload/cammina-via) resta costruito a runtime da
# HumanIndividualActionService, invariato.
const HAUL_RESOURCE_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/haul_resource.tres"
# TaskDefinition "daydreaming" (2026-09-10, richiesta utente — refactor Daydream via TaskFactory,
# secondo/ultimo prompt) — stesso identico trattamento di HAUL_RESOURCE_TASK_DEFINITION_PATH sopra:
# copre solo i primi due step [Walk, Think] (vedi daydreaming.tres) — il resto della catena
# (ricerca edificio-pensieri/Unload/cammina-via) resta costruito a runtime da
# HumanIndividualActionService._handle_pending_thought_target_search/_handle_pending_walk_away,
# guidato da context["pending_thought_target_search"]/["pending_walk_away_position"] scritti da
# ThinkAction.on_complete/UnloadAction.on_complete (ramo THOUGHT) — vedi _debug_test_daydream_task.
const DAYDREAM_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/daydreaming.tres"
# TaskDefinition "rest" — Path/risoluzione target/costruzione+assegnazione SPOSTATI su
# NeedTaskAssignmentService (2026-09-13, richiesta utente — sistema di interrupt/coda da stamina
# critica: HumanIndividualActionService, il nuovo chiamante automatico, non può dipendere da un
# metodo privato di questo Node) — vedi NeedTaskAssignmentService.assign_rest_task/
# resolve_rest_target. _assign_rest_task sotto (trigger manuale tasto R) ora delega lì.
# TaskDefinition "wander" (2026-09-12, richiesta utente — Wander Task esplicita: Walk→LookAround→
# Walk→LookAround→Walk) — stesso trattamento di REST_TASK_DEFINITION_PATH sopra, SEMPRE 5 step
# fissi (vedi wander.tres): nessuna logica condizionale sul numero di step qui, i tre target Walk
# sono risolti PRIMA della costruzione da IdleTaskAssignmentService.resolve_wander_targets (2026-09-13,
# spostata lì — vedi quel file), stesso schema già in uso per Rest.
const WANDER_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/wander.tres"
# TaskDefinition "play" (2026-09-13, richiesta utente — Play Task esplicita, CHILD-only:
# Run→Jump→Run→Jump) — stesso trattamento di REST_TASK_DEFINITION_PATH/WANDER_TASK_DEFINITION_PATH
# sopra, SEMPRE 4 step fissi (vedi play.tres): nessuna logica condizionale sul numero di step qui, i
# due target Run sono risolti PRIMA della costruzione da IdleTaskAssignmentService.
# resolve_play_targets (2026-09-13, spostata lì — vedi quel file), stesso schema già in uso per
# Wander. Il vincolo CHILD-only vive su play.tres.allowed_age_bands (Task,
# vedi Task.allowed_age_bands), non su RunAction/JumpAction (restano generiche per età, vedi
# RunAction.gd/JumpAction.gd) — verificato da HumanIndividual.assign_task().
const PLAY_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/play.tres"
# TaskDefinition "transport" (2026-09-12, richiesta utente — Transport Task: Walk->source→Retrieve→
# Walk->destination→Unload) — SEMPRE 4 step fissi (vedi transport.tres): nessuna logica
# condizionale sul numero di step qui, source/destination/resource_name/quantity sono risolti PRIMA
# della costruzione da _resolve_transport_context (vedi sotto), stesso schema già in uso per Rest/
# Wander. source_building/destination_building arrivano dal trigger a due click destri
# (_debug_try_assign_transport_command_on_right_click, vedi sotto); resource_name/quantity dalla
# scelta del player nel TransportSourceDialog aperto dallo stesso trigger.
const TRANSPORT_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/transport.tres"
# TaskDefinition "emergency_rest" — stesso trattamento di "rest" sopra: path/risoluzione target/
# costruzione+assegnazione SPOSTATI su NeedTaskAssignmentService (2026-09-13, richiesta utente,
# sistema di interrupt/coda da stamina critica — ORA collegato: soglia 5%/20% dentro
# HumanIndividualActionService.apply_action, vedi lì) — vedi NeedTaskAssignmentService.
# assign_emergency_rest_task/resolve_emergency_rest_target. _assign_emergency_rest_task sotto
# (trigger manuale tasto E) ora delega lì.
# _pending_build_tasks (Dictionary building.id -> Task orfana in attesa di assegnazione manuale) È
# STATO RIMOSSO (2026-09-12, richiesta utente — sostituzione con un percorso generico di
# riassegnazione Task): il path del TaskDefinition "build" ora vive su Building.
# get_resumable_task_definition_path (vedi simulation/scripts/game/Building.gd) — dato di TIPO del
# target riassegnabile, non più un dettaglio di questa scena — e nessuna Task viene più
# pre-costruita al piazzamento del cantiere: _start_building_task_at crea SOLO il Building
# (is_complete=false), _try_assign_build_command_on_right_click costruisce la Task da zero via
# TaskReassignmentService al momento del click destro, identico sia alla primissima assegnazione
# sia a una riassegnazione dopo interruzione (vedi quella funzione sotto).
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
# MICROCELL aggiunto (2026-09-16, richiesta utente — ispezione con doppio click sinistro): settimo
# tipo, stessa mutua esclusione a N vie degli altri sei (vedi _select_microcell/
# _clear_microcell_selection).
enum SelectionKind { NONE, INDIVIDUAL, VEGETATION, BUILDING, DEAD_BODY, STONE, STICK_LOT, MICROCELL }
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

# Click-detection su un corpo morto esistente — Step 6 del sistema oggetti-scaduti (2026-09-05),
# struttura gemella di selected_building sopra: un corpo ha un id stabile (individual_id, mai
# riderivato — un individuo muore una volta sola), quindi -1 = nessuna selezione invece di un
# Dictionary vuoto (stesso sentinel già usato ovunque nel progetto per "non applicabile", es.
# HumanIndividual.mother_id). Significativo solo quando _selection_kind == DEAD_BODY.
const DEAD_BODY_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/DeadBodyInfoPanel.tscn")
var dead_body_selector_controller := DeadBodySelectorController.new()
var selected_dead_body_individual_id: int = -1
var dead_body_info_panel: DeadBodyInfoPanel
# individual_id -> DeadBodyView (bugfix, 2026-09-05: serve per accendere/spegnere il cerchiolino
# di selezione sulla view giusta — vedi _select_dead_body/_clear_dead_body_selection). Popolato in
# _on_human_individual_died quando la view viene creata. Voci possono restare stantie se la view
# si autodistrugge per scadenza (Step 5) — mai ripulite esplicitamente, ogni lettore controlla
# is_instance_valid() prima di usarle, stesso principio difensivo già in uso altrove nel progetto
# per riferimenti a nodi potenzialmente liberati (es. human_individual_views).
var dead_body_views: Dictionary = {}

# Click-detection su una singola posizione STONE (microcella, 2026-09-08, richiesta utente) —
# stesso principio di selected_vegetation, ma ancora più semplice: una posizione STONE non ha
# nemmeno un individual_key composito (lotto+indice), solo la posizione stessa (Vector2i, una
# pietra = una posizione, vedi StoneSelectorController). {} = nessuna selezione, altrimenti
# {"macro_coords": Vector2i, "position": Vector2i}. Significativo solo quando _selection_kind ==
# STONE. Nessun highlight visivo sulla mappa (a differenza di vegetazione/edifici, che accendono un
# cerchiolino via set_selected_individual/set_selected_building) — fuori scope per questo passo,
# solo il pannello informativo.
const STONE_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/StoneInfoPanel.tscn")
var stone_selector_controller := StoneSelectorController.new()
var selected_stone: Dictionary = {}
var stone_info_panel: StoneInfoPanel

# Click-detection sul "terreno" di una microcella TREE (2026-09-08, richiesta utente) — a
# differenza di selected_vegetation (un individuo preciso) qui l'intero LOTTO è il bersaglio, vedi
# StickLotSelectorController. {} = nessuna selezione, altrimenti {"macro_coords": Vector2i, "lot":
# Vector2i}. Significativo solo quando _selection_kind == STICK_LOT. Deliberatamente l'ULTIMA
# risorsa provata in _unhandled_input (dopo vegetazione/edificio/corpo morto/stone/individuo umano):
# l'utente ha chiesto questo click come alternativa al click preciso sulla pianta già esistente, non
# come sostituto — non compete quindi nella lista a priorità per distanza degli altri tipi mappa.
const TERRAIN_SCATTERED_RESOURCE_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/TerrainScatteredResourceInfoPanel.tscn")

# Pannello ispezione microcella (2026-09-16, richiesta utente — doppio click sinistro) — RIVISTO
# nello stesso giorno: PRIMA un Window/popup indipendente da _selection_kind, scartato subito dopo
# ("niente popup, va nella sidebar come ogni altra selezione, mutua esclusione a 7 vie") — ora
# istanziato dinamicamente come sibling nella STESSA game_info_tabs.selection_content degli altri
# pannelli sidebar (vedi sotto), stesso identico principio "componente muto".
const MICRO_CELL_INSPECTION_PANEL_SCENE := preload("res://gameplay/scenes/game/MicroCellInspectionPanel.tscn")
var micro_cell_inspection_panel: MicroCellInspectionPanel
var selected_microcell: Dictionary = {}
var stick_lot_selector_controller := StickLotSelectorController.new()
var selected_stick_lot: Dictionary = {}
# plant_fiber (2026-09-16, richiesta utente — Step 4) — STESSO principio di stick_lot_selector_
# controller sopra, ma per lotti SHRUB, usato SOLO dal comando destro-click "vai e raccogli"
# (_resolve_pickup_candidates sotto): nessuna selezione SINISTRO/pannello info dedicati ancora,
# a differenza di stick (fuori scope di questo passo).
var plant_fiber_lot_selector_controller := PlantFiberLotSelectorController.new()
# Nome campo/costante RINOMINATI (2026-09-15, richiesta utente — vedi TerrainScatteredResourceInfoPanel.gd
# per il perché) insieme alla classe/al file — stick_lot_selector_controller/selected_stick_lot/
# StickLotSelectorController sopra restano INVARIATI: quel meccanismo di SELEZIONE resta specifico
# allo stick lot per ora (non ancora esteso a fruits/funghi/uova), solo il PANNELLO che ne mostra il
# risultato ha cambiato identità.
var terrain_scattered_resource_info_panel: TerrainScatteredResourceInfoPanel
# _overlap_cycle_macro_coords/_overlap_cycle_lot/_overlap_cycle_index RIMOSSI (2026-09-16, richiesta
# utente — "va tolto il click singolo sulla cella"): erano lo stato del ciclo click-ripetuto
# vegetazione/stick-lot (2026-09-15) che permetteva a click singoli ripetuti di raggiungere il lotto
# stick "coperto" da una pianta — reso obsoleto dall'ispezione con doppio click (mostra risorse E
# vegetazione insieme, un solo gesto). Il click singolo seleziona ora SOLO oggetti precisi (stone,
# edificio, individuo, vegetazione) — mai più il lotto/la cella, vedi _unhandled_input sotto.

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

# Elenco di TUTTI gli edifici nella scheda 🏠 (2026-09-12, richiesta utente — "un info panel
# edifici, concettualmente simile a quella population") — A DIFFERENZA di human_population_info_
# panel sopra (popolato una volta sola, mai aggiornato), questo VA rinfrescato ogni volta che lo
# stato di un edificio cambia (piazzato/completato) o al tick giornaliero — vedi _refresh_
# buildings_panel/i suoi call site per dove.
const BUILDINGS_INFO_PANEL_SCENE := preload("res://gameplay/scenes/game/BuildingsInfoPanel.tscn")
var buildings_info_panel: BuildingsInfoPanel

# Elenco di TUTTE le Task assegnate in questa sessione nella scheda 🐞 (2026-09-12, richiesta utente
# — "una tab di debug... elencami tutte le task con id, nome task, l'assegnatario, lo stato") —
# legge direttamente TaskDebugRegistry (stateless/statico, non uno stato di simulazione), non un
# Dictionary passato da GameScene come per gli altri pannelli: vedi TaskDebugPanel.gd per il
# perché questo pannello è l'eccezione "non muta" della famiglia.
const TASK_DEBUG_PANEL_SCENE := preload("res://gameplay/scenes/game/TaskDebugPanel.tscn")
var task_debug_panel: TaskDebugPanel

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
# Modalità "seleziona bersaglio da demolire" (2026-09-12, richiesta utente — bottone 🧨 Demolisci
# della BuildBar) — true tra il click sul bottone e il click successivo (sinistro = tenta la
# demolizione sull'edificio colpito, destro = annulla), stesso identico pattern del modo piazzamento
# edificio (_building_ghost sopra: destro annulla, sinistro consuma) ma senza fantasma da disegnare
# — solo un flag, il cursore/feedback resta il toggle acceso sul bottone stesso (vedi
# _set_demolish_mode/BuildBar.DEMOLISH_MAIN_ROW_SLOT_INDEX). Nessuna demolizione avviene finché
# l'utente non conferma nel DemolishConfirmationDialog che si apre al click su un edificio valido —
# questo flag riguarda SOLO la fase di targeting, non l'esecuzione.
var _demolish_mode_active: bool = false
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
@onready var options_menu: OptionsMenu = $OptionsMenu
@onready var statistics_panel: StatisticsPanel = $StatisticsPanel
@onready var tech_tree_panel: TechTreePanel = $TechTreePanel
@onready var demolish_confirmation_dialog: DemolishConfirmationDialog = $DemolishConfirmationDialog
@onready var transport_source_dialog: TransportSourceDialog = $TransportSourceDialog
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
	# Toggle "Perditempo" (2026-09-16, richiesta utente) — stato SOLO di sessione (IdleTaskAssignmentService.
	# fallback_enabled, mai letto da GameSettings/un salvataggio): riparte sempre acceso ad ogni
	# avvio, questa riga si limita a riflettere nel testo del bottone il default con cui la classe è
	# già stata caricata, stesso principio delle due righe sopra per flora/animali.
	debug_bar.set_idle_fallback_label(IdleTaskAssignmentService.fallback_enabled)
	debug_bar.action_pressed.connect(_on_debug_action_pressed)
	game_info_panel.primary_actions_bar.action_pressed.connect(_on_primary_action_pressed)
	game_info_panel.secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	build_bar.submenu_row.action_pressed.connect(_on_build_submenu_action_pressed)
	# Controllo a schede (richiesta utente, 2026-09-01, sostituisce lo spacer elastico +
	# minimap_panel/vegetation_info_panel diretti usati prima — vedi GameInfoTabs.gd) — unico
	# figlio diretto di body_container: size_flags_vertical=3 (impostato nel suo stesso .tscn) gli
	# fa occupare tutto lo spazio verticale che body_container riceve (BodyScrollContainer, che un
	# tempo avvolgeva body_container dall'esterno, è stato RIMOSSO il 2026-09-13 — bugfix "la
	# scrollbar fa scorrere in alto anche le tab", vedi GameInfoPanel.gd/GameInfoTabs.gd: lo scroll
	# vive ora DENTRO ciascuna tab di GameInfoTabs, non più attorno all'intero TabContainer).
	# body_container arriva altrimenti vuoto per design (vedi GameInfoPanel.gd): GameScene, non
	# GameInfoPanel stesso,
	# istanzia qui il proprio contenuto — GameInfoPanel resta "muto" su
	# vegetazione/minimappa/selezione.
	game_info_tabs = GAME_INFO_TABS_SCENE.instantiate()
	game_info_panel.body_container.add_child(game_info_tabs)
	# minimap_panel (richiesta utente, 2026-09-02: schermo ingrandito, la minimappa deve restare
	# SEMPRE visibile in basso, ANCORATA — non deve più salire/scendere a seconda di quale scheda
	# è aperta, come succedeva quando viveva dentro body_container insieme a game_info_tabs, la
	# cui altezza varia da scheda a scheda). Vive in game_info_panel.minimap_slot, un sibling FISSO
	# di body_container nella VBoxContainer esterna di GameInfoPanel — vedi GameInfoPanel.gd
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
	# Step 9d piano mortalità (2026-09-05) — vedi _on_kill_requested.
	human_individual_info_panel.kill_requested.connect(_on_kill_requested)
	# building_info_panel (Step 5, richiesta utente 2026-09-04) — terzo sibling nella STESSA
	# SelectionTab, stesso identico principio "componente muto" di vegetation_info_panel/
	# human_individual_info_panel; zero modifiche a GameInfoTabs per aggiungerlo (già agnostica).
	building_info_panel = BUILDING_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(building_info_panel)
	building_info_panel.empty_all_requested.connect(_on_empty_all_requested)
	# resident_center_requested (2026-09-12, richiesta utente) — vedi _on_building_resident_center_
	# requested sotto.
	building_info_panel.resident_center_requested.connect(_on_building_resident_center_requested)
	# dead_body_info_panel (Step 6 del sistema oggetti-scaduti, 2026-09-05) — quarto sibling nella
	# STESSA SelectionTab, stesso identico principio "componente muto" degli altri tre.
	dead_body_info_panel = DEAD_BODY_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(dead_body_info_panel)
	# stone_info_panel (2026-09-08, richiesta utente) — quinto sibling nella STESSA SelectionTab,
	# stesso identico principio "componente muto" degli altri quattro.
	stone_info_panel = STONE_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(stone_info_panel)
	# terrain_scattered_resource_info_panel (2026-09-08, richiesta utente; rinominato 2026-09-15 da
	# stick_lot_info_panel, vedi TerrainScatteredResourceInfoPanel.gd) — sesto sibling nella STESSA
	# SelectionTab, stesso identico principio "componente muto" degli altri cinque.
	terrain_scattered_resource_info_panel = TERRAIN_SCATTERED_RESOURCE_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(terrain_scattered_resource_info_panel)
	# micro_cell_inspection_panel (2026-09-16, richiesta utente) — settimo sibling nella STESSA
	# SelectionTab, stesso identico principio "componente muto" degli altri sei.
	micro_cell_inspection_panel = MICRO_CELL_INSPECTION_PANEL_SCENE.instantiate()
	game_info_tabs.selection_content.add_child(micro_cell_inspection_panel)
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
	human_population_info_panel.individual_center_requested.connect(
		_on_population_individual_center_requested.bind("population_panel")
	)
	# buildings_info_panel vive in BuildingsTab (2026-09-12, richiesta utente) — instanziato qui
	# insieme al resto, popolato (show_buildings) subito sotto e poi ri-rinfrescato ogni volta che
	# lo stato di un edificio cambia (vedi _refresh_buildings_panel/i suoi call site).
	buildings_info_panel = BUILDINGS_INFO_PANEL_SCENE.instantiate()
	game_info_tabs.buildings_tab.add_child(buildings_info_panel)
	buildings_info_panel.building_center_requested.connect(_on_buildings_panel_center_requested)
	# task_debug_panel vive in DebugTab (2026-09-12, richiesta utente) — instanziato SEMPRE (stesso
	# principio già seguito per SpeedDebugButton: il nodo esiste comunque, solo la TAB che lo ospita
	# resta nascosta via set_tab_hidden quando DebugLogging.ENABLED è false, vedi GameInfoTabs._ready).
	# refresh() richiamato in due punti (vedi TaskDebugPanel.gd): quando questa tab diventa quella
	# attiva (tab_changed sotto) e al tick giornaliero (_on_day_advanced).
	task_debug_panel = TASK_DEBUG_PANEL_SCENE.instantiate()
	game_info_tabs.debug_tab.add_child(task_debug_panel)
	game_info_tabs.tab_changed.connect(_on_game_info_tab_changed)
	minimap_panel.cell_clicked.connect(_on_minimap_cell_clicked)
	system_menu_dialog.add_action(tr("save_game"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("options"), &"options")
	system_menu_dialog.add_action(tr("exit_to_desktop"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	system_menu_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(system_menu_dialog))
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)
	save_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_confirmation_dialog))
	help_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(help_dialog))
	options_menu.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(options_menu))
	statistics_panel.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(statistics_panel))
	tech_tree_panel.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(tech_tree_panel))
	demolish_confirmation_dialog.demolish_confirmed.connect(_on_demolish_confirmed)
	demolish_confirmation_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(demolish_confirmation_dialog))
	transport_source_dialog.resource_chosen.connect(_on_transport_source_resource_chosen)
	transport_source_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(transport_source_dialog))
	# Demolisci (2026-09-12, richiesta utente) — main_row.action_pressed, NON submenu_row (quello
	# resta per i tipi edificio, ascoltato sopra da _on_build_submenu_action_pressed): BuildBar._on_
	# main_row_action_pressed ignora già qualunque action_id diverso da OPEN_BUILD_MENU_ACTION (vedi
	# BuildBar.gd), quindi questo secondo ascoltatore sullo stesso segnale non compete con quello.
	build_bar.main_row.action_pressed.connect(_on_build_main_row_action_pressed)
	# idea_completed(idea_id) (2026-09-07, richiesta utente) — DUE ascoltatori separati, non uno
	# solo con più responsabilità: _refresh_building_slots_buildable per lo sblocco edifici (stesso
	# punto di aggancio già predisposto per un futuro Think/DepositThoughtAction), e
	# _on_idea_completed per il popup di notifica (stesso NotificationPopup/UserOptions.
	# show_notification_popups di morte/nascita, vedi lì). TechTreePanel non conosce nessuno dei
	# due, si limita a segnalare "l'Idea con questo id è stata completata".
	# BUGFIX 2026-09-07 (diagnosticato con l'utente, log alla mano): _refresh_building_slots_
	# buildable NON riceveva mai la chiamata — connect() diretto di un metodo a ZERO parametri su
	# un segnale che ne emette UNO (idea_id: String) non scarta l'argomento in eccesso come
	# presunto, fallisce silenziosamente. _on_idea_completed(idea_id: String) non ne soffriva
	# perché la sua firma combacia esattamente (un parametro String) — ecco perché il popup
	# funzionava sempre ma la BuildBar mai. Wrapper esplicito a un argomento per l'altro caso.
	tech_tree_panel.idea_completed.connect(func(_idea_id: String) -> void: _refresh_building_slots_buildable())
	tech_tree_panel.idea_completed.connect(_on_idea_completed)
	# Mancava (bugfix, richiesta utente 2026-09-05): system_menu_dialog si nasconde PRIMA che
	# save_game_file_dialog si apra (_on_save_pressed gira dopo l'hide() del bottone "Salva" nel
	# menu di sistema — vedi SystemMenuDialog.add_action), quindi senza questa riga _open_dialog_count
	# scendeva a 0 e il clock ripartiva nell'istante tra i due popup invece di restare in pausa
	# finché anche save_game_file_dialog non si chiude.
	save_game_file_dialog.visibility_changed.connect(_on_blocking_dialog_visibility_changed.bind(save_game_file_dialog))

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
			# I cinque filtri/preferenza vengono dalle scelte CONGELATE di questa partita
			# (GameData.starting_*, valorizzate una volta sola in WorldScene._populate_new_world
			# alla creazione), non da GameSettings.selected_* (dato di flusso runtime,
			# potenzialmente stale dopo un load in una sessione successiva) — confermato con
			# l'utente.
			var chosen := FirstStartMacroCellSelectionService.new().select_starting_cell(
				macro_world,
				game_data.starting_exclude_hostile_start,
				game_data.starting_exclude_predator_territories,
				game_data.starting_resource_richness_preference,
				game_data.starting_guarantee_animal_presence,
				game_data.starting_guarantee_stone_presence
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
		# FIX CRITICO DI PERSISTENZA (2026-09-12, richiesta utente, contestuale all'introduzione di
		# HumanTypes.AgeBand.INFANT) — set_current_era() PRIMA di qualunque lettura di game_data.
		# era_effective_age_band_durations_male/female in questo ramo (ricostruzione popolo esistente:
		# sia "salvataggio appena caricato" sia "ritorno da WorldScene/MacroCellScene"), non solo nel
		# ramo di semina qui sotto. Motivo: quei due array SONO persistiti in JSON (GameSaveService/
		# GameLoadService) ma erano ricalcolati via set_current_era SOLO al bootstrap di una partita
		# nuova (vedi sotto) — un salvataggio scritto PRIMA di un cambio nel numero/ordine delle fasce
		# di HumanTypes.AgeBand (es. questa stessa introduzione di INFANT) verrebbe altrimenti riletto
		# con l'array VECCHIO (lunghezza/ordine pre-cambio) fidandosi ciecamente del JSON, classificando
		# silenziosamente ogni individuo in una fascia d'età sbagliata finché non fosse scattato un
		# cambio Era vero. Ricalcolo SEMPRE fresco da HumanRules/EraRules invece di fidarsi del dato
		# persistito — idempotente (set_current_era non ha guardie su "già impostata", ricalcola e
		# basta), quindi innocuo anche nel ramo "ritorno" dove il valore era già corretto in questa
		# stessa sessione. L'array persistito in JSON resta scritto (nessuna modifica a GameSaveService/
		# GameLoadService: restano lì per compatibilità/debug) ma non viene più letto come fonte di
		# verità in nessun punto di ingresso.
		game_data.set_current_era(game_data.current_era_name, human_rules)
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
		# Ricollegamento signal dopo un caricamento da salvataggio (2026-09-11, richiesta utente —
		# chiude il gap segnalato in una sessione precedente: "dopo un reload i signal site_setup_
		# completed/site_cleared non vengono ricollegati") — SOLO `not returning`: questo stesso
		# ramo `if` è condiviso da DUE casi (vedi commento sopra) — un salvataggio appena caricato
		# (human_individuals qui sono istanze FRESCHE, appena ricostruite da TaskPersistenceService.
		# deserialize_task via GameLoadService, i cui segnali non sono MAI stati collegati) e un
		# ritorno da WorldScene/MacroCellScene via 🧍 (returning=true, GLI STESSI oggetti vivi di
		# questa sessione, già connessi quando le loro Task furono create — ricollegare qui li
		# duplicherebbe, ogni listener scatterebbe due volte). `returning` catturato PRIMA di questo
		# punto (vedi inizio funzione) distingue esattamente i due casi.
		if not returning:
			_reconnect_loaded_task_signals()
	else:
		# set_current_era (richiesta utente, 2026-09-04 — bugfix): PRIMO punto reale in cui viene
		# chiamato — prima esisteva solo come infrastruttura mai collegata (nessun trigger tech→era
		# ancora implementato, vedi GameData), quindi game_data.era_effective_age_band_durations_
		# male/female restava sempre vuoto e la semina leggeva le durate BASE di HumanRules, mai
		# scalate per l'Era (game_data.current_era_name di default = "paleolithic"). Questo non è
		# un trigger di avanzamento — è il bootstrap iniziale per una partita NUOVA, chiamato una
		# sola volta qui (2026-09-12: NON più l'unico punto di chiamata — vedi la stessa chiamata
		# nel ramo `if` sopra, per popolo già esistente/caricato/di ritorno), per
		# l'Era di partenza della partita.
		game_data.set_current_era(game_data.current_era_name, human_rules)
		var seeding_result := HumanSeedingService.new().seed_player_start(
			start_macro_coords, game_data.starting_group_size_preference, human_rules, "Player Folk", game_data.year,
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female, game_data
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
		# Snapshot popolazione all'anno 0 (Step 3 piano statistiche, richiesta utente 2026-09-06) —
		# GameTimeService._on_year_rolled_over registra uno snapshot ad ogni cambio anno, ma l'anno
		# 0 non "rotola" mai (è l'anno di partenza, non un rollover) — senza questa riga il grafico
		# popolazione/anno partirebbe dall'anno 1, saltando il conteggio dei fondatori (2/5/10 a
		# seconda di COUPLE/FAMILY/GROUP). Qui, non in GameTimeService: questo ramo è IL bootstrap
		# di una partita nuova (mai eseguito per una partita caricata/ripristinata, vedi il ramo
		# `if` sopra), stesso principio già seguito per set_current_era poco più in alto.
		game_data.population_snapshots[0] = human_individuals.size()
		# Snapshot edifici all'anno 0 (2026-09-12, richiesta utente — tab Statistiche/Edifici) —
		# stesso identico principio della riga sopra: una partita nuova parte sempre con 0 edifici
		# (nessuno piazzato prima che il player possa farlo), scritto qui esplicitamente per lo
		# stesso motivo (_on_year_rolled_over non gira mai per l'anno 0, che non "rotola").
		game_data.building_snapshots[0] = 0

	# Bugfix (richiesta utente, 2026-09-07): current_stamina/max_stamina di OGNI individuo restavano
	# al fallback HumanIndividual.FALLBACK_MAX_STAMINA (5000.0 — coincide col default di HumanRules.
	# base_max_stamina, quindi per un FERTILE_ADULT maschio il numero sembra "giusto per caso": il
	# sintomo reale, riportato dall'utente, era current_stamina bloccata a 5000 mentre il pannello
	# mostrava il max_stamina corretto — vedi _update_individual_panel_content, che lo ricalcola
	# sempre al volo, MAI dal campo) fino al primo ricalcolo giornaliero (HumanStaminaIndividualService,
	# agganciato a GameTimeService._on_day_advanced). Causa: HumanIndividual._init() (che chiama
	# _resolve_initial_max_stamina) gira SEMPRE prima che source_group_ref sia assegnato — sia in
	# HumanSeedingService (nuova partita) sia in GameLoadService (caricamento salvataggio), per
	# costruzione (l'oggetto va creato prima di poter puntare al gruppo che lo contiene) — quindi la
	# catena source_group_ref->folk_ref->human_rules_ref non è mai risolvibile a quel punto, e
	# individual.max_stamina/current_stamina restano al fallback fino a quando non passa un giorno
	# di gioco intero. Corretto qui in UN SOLO passaggio, sulla STESSA funzione già usata dal
	# ricalcolo giornaliero (nessuna logica duplicata): a questo punto human_individuals è già
	# finalizzato ED ha già source_group_ref valorizzato in ENTRAMBI i rami sopra (seeding nuovo o
	# ripristino/caricamento), quindi copre entrambi i casi in un colpo solo, subito all'ingresso in
	# scena invece che al primo avanzamento giorno.
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name)
	for member in human_individuals:
		HumanStaminaIndividualService.recalculate_max_stamina(member, game_data, era_rules)
		# Stesso identico bug/fix di max_stamina sopra, stessa causa (source_group_ref non ancora
		# assegnato quando HumanIndividual._init() chiama _resolve_initial_max_carry_capacity) —
		# richiesta utente 2026-09-08, riscontrato dopo l'introduzione della capacità di trasporto:
		# la barra "Capacità di trasporto" restava al fallback (30.0, HumanIndividual.
		# FALLBACK_MAX_CARRY_CAPACITY) fino al primo avanzamento giorno. Mancava questa stessa riga.
		HumanCarryCapacityIndividualService.recalculate_max_carry_capacity(member, game_data)
		# Stesso identico bug/fix di max_stamina/max_carry_capacity sopra, stessa causa — 2026-09-13,
		# richiesta utente, 5 nuovi parametri vitali (hunger/thirst/health/happiness/loyalty): senza
		# questa riga resterebbero tutti al fallback HumanIndividual.FALLBACK_MAX_VITAL fino al primo
		# avanzamento giorno, esattamente come stamina/carry capacity prima di questo fix.
		HumanVitalsIndividualService.recalculate_vitals(member, game_data)
		# Bugfix (2026-09-13, richiesta utente) — STESSO principio/STESSA causa dei tre fix sopra:
		# un individuo con current_task == null a questo punto (fondatore appena seminato, MAI
		# passato da apply_action — oppure un individuo caricato da salvataggio che era già libero
		# al momento del salvataggio) non riceveva MAI il controllo bisogno/coda/fallback
		# perditempo, perché quella logica viveva SOLO dentro HumanIndividualActionService.
		# _handle_task_completion_need_and_queue, raggiungibile solo al completamento naturale di
		# una Task PREESISTENTE — mai per chi una Task non l'ha mai avuta. Risolta qui, non dentro
		# HumanSeedingService (position/home_macro_coords NON sono ancora finalizzati quando gli
		# individui vengono creati lì — la griglia di spawn e il ricentraggio sul fondatore reale
		# girano DOPO, vedi seed_player_start/il codice sopra in questo stesso _ready — un Wander/
		# Rest calcolato in quel momento userebbe una posizione sbagliata, subito superata):
		# esattamente come i tre ricalcoli sopra, questo punto copre in un colpo solo SIA il
		# seeding di una partita nuova SIA il caricamento di un salvataggio (stesso commento di
		# testa al blocco: "a questo punto human_individuals è già finalizzato... posizioni di
		# spawn comprese"), senza dover duplicare la chiamata in due punti diversi. Un individuo
		# caricato con una current_task già in corso non viene toccato (guardia esplicita sotto) —
		# resolve_idle_individual presume un individuo LIBERO, mai chiamata altrimenti.
		#
		# ZOMBIE GUARD — recupero da salvataggio (2026-09-16, richiesta utente, fix "task zombie") —
		# un salvataggio fatto PRIMA di questo fix può contenere una current_task già conclusa
		# (current_step_index >= steps.size(), il bug ora corretto alla radice in
		# HumanIndividualActionService._handle_task_completion_need_and_queue) o task_queue con
		# voci concluse: PRIMA di decidere "è libero?" tramite il solo confronto con null sotto,
		# ripulisce entrambe — TaskQueueService.purge_finished_tasks/HumanIndividualActionService.
		# recover_zombie_current_task, le stesse due funzioni usate come difesa in profondità
		# altrove. Un individuo il cui current_task era già finito (mai un caso reale per un
		# salvataggio fatto DOPO questo fix, solo per uno precedente) si ritrova quindi trattato
		# come libero dal controllo esistente subito sotto, invece di restare bloccato per sempre
		# (prima "Solo H lo sbloccava").
		TaskQueueService.purge_finished_tasks(member)
		HumanIndividualActionService.recover_zombie_current_task(member)
		if member.current_task == null:
			HumanIndividualActionService.resolve_idle_individual(member, _resolve_age_band(member), macro_world)

	# Popola la scheda 🧍 (richiesta utente, 2026-09-01) — human_individuals/human_folk sono
	# finalizzati solo qui (posizioni di spawn comprese), stesso motivo per cui l'istanza del
	# pannello (sopra) e la sua popolazione dati sono separate in due punti diversi di _ready().
	# Estratta in _refresh_population_panel (richiesta utente, 2026-09-05 — bugfix "pannello mai
	# aggiornato dopo il primo popolamento"): stessa identica chiamata di prima, ora riusabile anche
	# dal rollover d'anno.
	_refresh_population_panel()
	# Popola la scheda 🏠 (2026-09-12, richiesta utente) — nessun edificio esiste ancora a inizio
	# partita in pratica (mostra semplicemente "0"), ma stesso principio "popolata da subito" di
	# _refresh_population_panel sopra, non lasciata vuota finché non arriva il primo refresh reale.
	_refresh_buildings_panel()

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
		view.clock = clock # può essere null qui (view creata prima di _setup_clock in _ready()); vedi _assign_clock_to_all_live_cells
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
	# Stato iniziale slot BuildBar (2026-09-07, richiesta utente) — copre sia un salvataggio con un
	# village center già esistente sia (da questo passo) idee già completate/mancanti: senza questa
	# chiamata i bottoni risulterebbero tutti abilitati finché il player non piazza qualcosa.
	_refresh_building_slots_buildable()

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
	# Aggancio al tempo di gioco (2026-09-07, richiesta utente) — movimento e azioni ora scalano
	# con la velocità 1x/2x/4x/X8/DEBUG e si fermano in pausa, invece di girare a tempo reale
	# grezzo: game_delta è una FRAZIONE DI GIORNO (stesso calcolo di GameClockController._process,
	# vedi get_game_day_delta lì), non più un delta in secondi. move_speed, STAMINA_DRAIN_PER_
	# MICROCELL e RestAction.STAMINA_REGEN_PER_DAY sono già stati ritarati (2026-09-07) per questa
	# nuova unità. 0.0 quando clock.is_playing è false, propagato di conseguenza a valle.
	#
	# CALCOLATO FUORI da `if individual != null` (2026-09-12, richiesta utente — piano
	# multi-individuo, Step 2/3): prima viveva dentro quel gate, quindi se il player deselezionava
	# tutti (nessun individuo selezionato) l'intero blocco sotto — quindi la Task di OGNI individuo,
	# non solo del selezionato — smetteva di avanzare. game_delta serve ora al ciclo su
	# active_individuals sotto, che deve girare indipendentemente da chi (se qualcuno) è selezionato.
	var game_delta := clock.get_game_day_delta(delta)

	# TEMPORANEO (debug — vedi _debug_panel_refresh_timer sopra per il perché): refresh forzato del
	# pannello individuo selezionato ogni DEBUG_PANEL_REFRESH_INTERVAL_SEC secondi REALI, con `delta`
	# (secondi reali di questo frame, MAI game_delta sopra) — indipendente da giorno di gioco/pausa/
	# velocità di simulazione. _refresh_selected_individual_panel() è già no-op se non è un individuo
	# ad essere selezionato (vedi quel commento), quindi questo blocco è innocuo quando nulla è
	# selezionato.
	_debug_panel_refresh_timer += delta
	if _debug_panel_refresh_timer >= DEBUG_PANEL_REFRESH_INTERVAL_SEC:
		_debug_panel_refresh_timer = 0.0
		_refresh_selected_individual_panel()

	# Ciclo su TUTTI gli individui con una Task attiva (2026-09-12, richiesta utente — piano
	# multi-individuo, Step 2: GENERALIZZA il refactor "loop-readiness" del 2026-09-10 — quello
	# costruiva già questa stessa Array[HumanIndividual] tipizzata con l'idiom append-esplicito
	# invece di un ternario (che a runtime produceva un Array generico, non Array[HumanIndividual] —
	# vedi commit 2026-09-10), ma la popolava sempre e solo con l'unico `individual` selezionato/
	# controllato dal player, mai con altri membri di human_individuals: stesso identico
	# comportamento visibile di prima, in attesa di questo passo). "Task attiva" = current_task non
	# nullo e non concluso — STESSO filtro che HumanIndividualActionService.apply_action applica già
	# da sé in testa (current_task == null or is_finished() -> no-op immediato, CONFERMATO leggendo
	# quel file: già sicuro se chiamato per un individuo senza Task valida), quindi filtrare qui è
	# solo un'ottimizzazione (evita N chiamate a vuoto ogni frame), mai un requisito di correttezza.
	# Un individuo entra/esce da questa lista da solo, frame per frame, in base al proprio
	# current_task — nessuna gestione esplicita di aggiunta/rimozione necessaria qui.
	#
	# ATTENZIONE (invariata dal 2026-09-10, ora concreta) — questo ciclo resta agganciato a
	# _process (framerate di rendering, ~60 chiamate/s indipendentemente da quanto serva davvero),
	# non a un tick di simulazione indipendente: con la popolazione odierna (poche decine) il costo
	# resta trascurabile, ma se la popolazione crescerà molto oltre andrà rivalutato (scala come
	# FPS × N, non più O(1) come quando un solo individuo poteva mai essere in questa lista).
	var active_individuals: Array[HumanIndividual] = []
	for member in human_individuals:
		if member.current_task != null and not member.current_task.is_finished():
			active_individuals.append(member)

	for active_individual in active_individuals:
		# advance_movement PRIMA di apply_action, per QUESTO individuo (2026-09-12, Step 3 — prima
		# advance_movement viveva FUORI da questo ciclo, chiamata una sola volta sul solo
		# `individual` selezionato) — stesso ordine/stesso motivo di sempre (invariato dal
		# 2026-09-06): WalkAction.get_stamina_delta calcola la distanza confrontando position con
		# l'ultima nota, quindi deve leggere la position GIÀ aggiornata da advance_movement in
		# questo stesso frame, per QUESTO individuo specifico.
		individual_movement_service.advance_movement(active_individual, game_delta)
		# macro_world (2026-09-09, richiesta utente — re-routing UnloadAction su magazzino pieno) —
		# apply_action ne ha bisogno per WarehouseSelectionService.find_best (world.buildings), vedi
		# HumanIndividualActionService.apply_action. game_data (2026-09-13, richiesta utente —
		# sistema di interrupt/coda da stamina critica) — apply_action ne ha bisogno per risolvere
		# l'age_band dell'individuo quando assegna da sé una Task-bisogno (stesso identico bisogno
		# di _resolve_age_band qui sotto, duplicato lì perché quel service non ha accesso a questo
		# Node — vedi HumanIndividualActionService._resolve_age_band).
		individual_action_service.apply_action(active_individual, game_delta, macro_world, game_data)
		# Attraversamento bordo/figlio a carico generalizzati (2026-09-12, Step 4/6 — prima
		# operavano solo su `individual`) — vedi _check_macro_cell_border_crossing/
		# _sync_dependent_child_position per il dettaglio: senza questo, un individuo non
		# selezionato che cammina oltre il bordo della propria macrocella (es. Task haul_resource/
		# Build con un target in una macrocella adiacente) non verrebbe mai rilevato, lasciando
		# home_macro_coords/posizione disallineate. DOPO apply_action/prima di
		# _sync_dependent_child_position, stesso ordine di sempre: se QUESTO individuo ha appena
		# attraversato un bordo, la sua home_macro_coords/position sono già quelle nuove quando si
		# sincronizza un suo eventuale figlio a carico, nello stesso frame.
		_check_macro_cell_border_crossing(active_individual)
		_sync_dependent_child_position(active_individual)

	if individual != null:
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
	# fantasma RESTA attivo dopo, vedi _building_ghost/_start_building_task_at, per piazzarne molte
	# in fila), R = ruota la porta di 90° (BuildingGhost.rotate_clockwise) senza uscire dal modo
	# piazzamento.
	#
	# Sx (2026-09-10, richiesta utente — prima porzione Build Task) — NON costruisce più
	# istantaneamente: avvia il cantiere (Building con is_complete=false + Build Task in attesa di
	# assegnazione manuale, vedi _start_building_task_at). Sx+B (tasto B TENUTO PREMUTO mentre si
	# clicca) resta il vecchio comportamento invariato — piazzamento istantaneo, is_complete=true da
	# subito, vedi _place_building_at — DECISIONE non specificata letteralmente nella richiesta
	# (che diceva solo "Sx+B resta invariato: costruisce istantaneamente"): ho interpretato "Sx+B"
	# come "tasto B tenuto premuto durante il click sinistro", stesso principio già in uso per R
	# (tasto premuto mentre il fantasma è attivo, nessun modo/toggle separato) — comodo per test
	# rapidi senza dover assegnare/aspettare una Task, nessun gate DebugLogging.ENABLED (stesso
	# comportamento ungato di oggi per il click semplice).
	if _building_ghost != null:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_clear_building_ghost()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				if Input.is_key_pressed(KEY_B):
					_place_building_at(_building_ghost.global_position)
				else:
					_start_building_task_at(_building_ghost.global_position)
				return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			_building_ghost.rotate_clockwise()
			return

	# Modalità "seleziona bersaglio da demolire" (2026-09-12, richiesta utente) — STESSO identico
	# principio di priorità assoluta del blocco _building_ghost sopra (mutuamente esclusivi in
	# pratica: il bottone Demolisci non è premibile mentre un'anteprima di piazzamento è attiva,
	# nessuna verifica incrociata scritta qui perché non può succedere per costruzione dell'unico
	# punto che entra in questa modalità, _on_build_main_row_action_pressed). Destro = annulla
	# (_set_demolish_mode(false), nessuna azione), sinistro = tenta la demolizione sull'edificio
	# colpito (_try_pick_demolish_target apre la conferma se il click ha colpito qualcosa, altrimenti
	# è un no-op silenzioso) — in ENTRAMBI i casi la modalità termina con questo singolo click, mai
	# persistente per piazzamenti multipli come invece il fantasma edificio.
	if _demolish_mode_active:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_set_demolish_mode(false)
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_try_pick_demolish_target(event)
				return

	# Ispezione microcella con DOPPIO click sinistro (2026-09-16, richiesta utente) — SEMPRE
	# intercettato qui, PRIMA della cascata di selezione normale sotto (STESSO principio/STESSA
	# posizione già in uso in WorldScene._unhandled_input per l'apertura di MacroCellScene): un
	# doppio click arriva come DUE eventi separati — il primo (senza double_click) attraversa
	# normalmente tutta la cascata sotto e seleziona/deseleziona come un click singolo qualunque
	# (richiesta esplicita utente: "il click singolo non deve mai aprire l'ispezione, nemmeno se non
	# colpisce nulla"); il SECONDO (con double_click=true) viene intercettato QUI, PRIMA di
	# raggiungere la cascata, e MAI lasciato proseguire (return incondizionato, indipendentemente da
	# cosa trova _handle_microcell_inspection_double_click) — altrimenti quel secondo evento
	# verrebbe ANCHE trattato come un secondo click singolo dalla cascata sotto (doppia selezione/
	# deselezione). In QUALUNQUE cella, fitta o vuota (richiesta esplicita utente) — nessun gate su
	# vegetation_hit/building_hit/altri esiti della cascata, che qui sotto non è ancora calcolata.
	#
	# DOPO i blocchi fantasma-edificio/demolizione sopra (mai prima): quei due restano a priorità
	# assoluta invariata (richiesta implicita — un doppio click rapido durante un piazzamento "in
	# fila" di più edifici non deve trasformarsi in un'ispezione, deve continuare a piazzare).
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_microcell_inspection_double_click(event)
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
	# STONE (2026-09-08, richiesta utente) — stessa unità/stesso schema di vegetation_hit/
	# building_hit (distanza in PIXEL, spazio locale della cella del match), compete alla pari nel
	# confronto map_hit sotto, nessun trattamento speciale.
	var stone_hit := stone_selector_controller.try_select(event, live_cells)
	# stick_lot_hit (click SINISTRO) RIMOSSO (2026-09-16, richiesta utente — "va tolto il click
	# singolo sulla cella"): calcolava il lotto sotto il click SOLO per il ciclo click-ripetuto e il
	# fallback "nessun oggetto preciso -> seleziona il lotto" più sotto, entrambi rimossi in questo
	# stesso passo. Il lotto stick resta comunque raggiungibile — via il DESTRO (raccolta,
	# _resolve_pickup_candidates più sotto, invariato) e via il DOPPIO click sinistro (ispezione,
	# _handle_microcell_inspection_double_click sopra, invariato) — solo il SINGOLO sinistro non lo
	# tocca più.
	# Corpo morto (bugfix, 2026-09-06, richiesta utente: un corpo morto in una cella densa di
	# vegetazione — es. morto in una foresta — non era mai raggiungibile dal click, perché prima
	# veniva provato SOLO come ultima risorsa, dopo che vegetazione/edifici avevano già "vinto" a
	# prescindere dalla reale distanza dal click). Ora compete alla PARI con vegetazione/edificio
	# nello stesso confronto "chi e' oggettivamente piu' vicino al click" sotto (map_hit) invece di
	# un gradino di priorità fisso e più basso. Unica differenza: la sua "distance" è in
	# MICROCELLE (DeadBodySelectorController, stessa unità di HumanIndividualSelectorController),
	# non in PIXEL come vegetation_hit/building_hit (VegetationSelectorController/
	# BuildingSelectorController) — convertita qui una volta sola per un confronto diretto.
	# .has() guard (bugfix, 2026-09-06): questa chiamata è ora valutata ad OGNI evento (spostata
	# fuori dal ramo "click sinistro premuto" per competere alla pari con vegetation_hit/
	# building_hit sopra, che sono anch'essi valutati ad ogni evento ma non indicizzano live_cells
	# direttamente) — un accesso diretto `live_cells[center_macro_coords]` qui rischierebbe un
	# errore su QUALUNQUE evento (non solo i click) se center_macro_coords non fosse ancora una
	# chiave valida (es. durante il primissimo frame prima che la cella focus sia attiva).
	var dead_body_hit: Dictionary = {}
	if live_cells.has(center_macro_coords):
		dead_body_hit = dead_body_selector_controller.try_select(
			event, live_cells[center_macro_coords].renderer, _get_dead_body_records(), center_macro_coords
		)
	var dead_body_distance_px: float = (
		dead_body_hit["distance"] * MicroCellRenderer.CELL_SIZE if not dead_body_hit.is_empty() else INF
	)

	var map_hit: Dictionary = {}
	var map_hit_kind := SelectionKind.NONE
	var best_map_distance_px := INF
	if not vegetation_hit.is_empty():
		map_hit = vegetation_hit
		map_hit_kind = SelectionKind.VEGETATION
		best_map_distance_px = vegetation_hit["distance"]
	if not building_hit.is_empty() and building_hit["distance"] < best_map_distance_px:
		map_hit = building_hit
		map_hit_kind = SelectionKind.BUILDING
		best_map_distance_px = building_hit["distance"]
	if not dead_body_hit.is_empty() and dead_body_distance_px < best_map_distance_px:
		map_hit = dead_body_hit
		map_hit_kind = SelectionKind.DEAD_BODY
		best_map_distance_px = dead_body_distance_px
	if not stone_hit.is_empty() and stone_hit["distance"] < best_map_distance_px:
		map_hit = stone_hit
		map_hit_kind = SelectionKind.STONE
		best_map_distance_px = stone_hit["distance"]

	# Ciclo click-ripetuto vegetazione/stick-lot RIMOSSO (2026-09-16, richiesta utente — "va tolto
	# il click singolo sulla cella. il click singolo vale solo su un oggetto... per vedere quello
	# che c'è nella cella click doppio"): esisteva (2026-09-15) per permettere a click singoli
	# ripetuti sulla stessa microcella di raggiungere il lotto stick "coperto" da una pianta —
	# superato dall'ispezione con doppio click (mostra risorse E vegetazione insieme, un solo
	# gesto, in qualunque cella). Il click singolo ora seleziona SOLO il vincitore normale tra
	# vegetazione/edificio/corpo morto/sasso (map_hit_kind, calcolato sopra, invariato).
	if not map_hit.is_empty() and not _is_player_closer_to_click(best_map_distance_px):
		match map_hit_kind:
			SelectionKind.VEGETATION:
				_select_vegetation(map_hit)
			SelectionKind.BUILDING:
				_select_building(map_hit)
			SelectionKind.DEAD_BODY:
				_select_dead_body(map_hit)
			SelectionKind.STONE:
				_select_stone(map_hit)
	else:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_clear_vegetation_selection()
			_clear_building_selection()
			_clear_dead_body_selection()
			_clear_stone_selection()
			_clear_stick_lot_selection()
			_clear_microcell_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
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
				# Fallback "seleziona il lotto/la cella" RIMOSSO (2026-09-16, richiesta utente — vedi
				# il commento esteso sopra su map_hit_kind): un click sinistro che non colpisce nessun
				# oggetto preciso ora si limita a deselezionare (righe sopra), mai più una selezione
				# di ripiego sulla cella intera — quella è ora esclusivamente doppio click.
		# Comando "vai e raccogli" (2026-09-09, richiesta utente — sostituisce l'attivazione via
		# click SINISTRO di Step 5/6, che risultava spesso "rubata" dalla vegetazione: un lotto stick
		# COINCIDE con la microcella dell'albero stesso, quindi quasi ogni click nel suo raggio
		# ricadeva nel raggio di hit-test dell'albero — vedi VegetationSelectorController, che vince
		# la priorità sopra — rendendo il lotto quasi impossibile da colpire quando "attivo". Il
		# DESTRO invece è già il tasto di comando dedicato in questo gioco (movimento) e NON compete
		# mai con la vegetazione (nessun *SelectorController diverso da Stone/StickLot hit-testa
		# eventi non-sinistri) — stesso identico problema risolto per costruzione, non serve più
		# nessuna disambiguazione spaziale. _try_assign_pickup_command_on_right_click sotto prova
		# STONE poi STICK_LOT (stesso ordine di priorità già in uso per il sinistro) PRIMA del
		# movimento normale: se trova un bersaglio raccoglibile assegna la Task Walk->PickUp e
		# consuma l'evento (il movimento normale sotto va saltato, altrimenti sovrascriverebbe subito
		# la Task appena assegnata — assign_task/set_target condividono lo stesso current_task, vedi
		# HumanIndividual.set_target); altrimenti (click destro altrove, o nessun individuo
		# selezionato) il comportamento resta l'invariato movimento puro verso il punto cliccato.
		#
		# _try_assign_unload_command_on_right_click (2026-09-09, richiesta utente) — stesso principio,
		# provato SUBITO DOPO pickup (nessuna sovrapposizione possibile: un edificio e una posizione
		# stone/lotto stick non condividono mai la stessa microcella, vedi BuildingVerificationService
		# Criterio 6): se il destro colpisce un edificio di stoccaggio con zaino non vuoto e categoria
		# compatibile, assegna Walk->Unload e consuma l'evento, altrimenti il movimento normale
		# prosegue invariato.
		if individual_controller != null:
			# Selezione Transport a metà (2026-09-14, richiesta utente — "il click destro successivo
			# vale SOLO per la destinazione Transport", niente competizione con altri comandi) —
			# CONTROLLATO PER PRIMO: se _debug_transport_source_building è già impostata (sorgente
			# scelta, in attesa del click di destinazione), pickup/unload/build vengono SALTATI DEL
			# TUTTO per questo evento — mai anche solo provati, non solo ignorato il loro esito. Prima
			# di questo fix _try_assign_build_command_on_right_click (provato PRIMA nella catena
			# sotto) intercettava sempre un click destro su un cantiere incompleto, il caso D'USO PIÙ
			# COMUNE come destinazione Transport (portare materiale a un cantiere), "rubando" il click
			# prima che _debug_try_assign_transport_command_on_right_click venisse mai raggiunta —
			# BUG CONFERMATO con l'utente. Nessun problema simmetrico con pickup/unload (mai
			# verificato un caso reale), ma bypassati comunque per coerenza: mentre una selezione
			# Transport è aperta, il destro è un canale "riservato" a quella sola interazione.
			if _debug_transport_source_building != null:
				if not _debug_try_assign_transport_command_on_right_click(event):
					individual_controller.handle_input(event)
			# _debug_try_assign_transport_command_on_right_click (2026-09-12, richiesta utente — test
			# Transport Task) — provato per ULTIMO, dopo pickup/unload/build: gated da
			# DebugLogging.ENABLED al proprio interno, vedi lì per il perché di questa posizione.
			elif not _try_assign_pickup_command_on_right_click(event) and not _try_assign_unload_command_on_right_click(event) and not _try_assign_build_command_on_right_click(event) and not _debug_try_assign_transport_command_on_right_click(event):
				individual_controller.handle_input(event)

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		_center_camera_on_individual()

	# Stop (2026-09-09, richiesta utente) — vedi _stop_selected_individual_task sotto per cosa fa.
	# Tasto H (mnemonico "Halt"), NON S ("Stop" — richiesta originale dell'utente): S è già
	# assegnato al pan camera (CameraController, WASD/frecce, Input.is_key_pressed continuo — vedi
	# help_pan_camera nell'help). Usare S qui avrebbe fermato la Task dell'individuo selezionato
	# OGNI VOLTA che il player preme S per spostare la visuale verso il basso, un'interruzione
	# accidentale e silenziosa della propria stessa Task ad ogni pan — sostituito con H. Comando
	# VERO (non debug, nessun gate DebugLogging.ENABLED), stesso trattamento del tasto X sopra.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_stop_selected_individual_task()

	# Rest Task esplicita (2026-09-12, richiesta utente) — tasto R su individuo selezionato,
	# mnemonico "Rest", stesso trattamento di H sopra: comando VERO (non debug, nessun gate
	# DebugLogging.ENABLED), nessun guard su una Task già in corso — _assign_rest_task sostituisce
	# sempre, decisione esplicita dell'utente ("nessuna protezione da progresso perso"). NESSUN
	# conflitto con l'ALTRO uso di KEY_R già esistente sopra (_building_ghost.rotate_clockwise,
	# riga ~879): quel ramo vive dentro `if _building_ghost != null: ... return`, quindi consuma
	# l'evento PRIMA che l'esecuzione raggiunga questo punto quando un fantasma edificio è attivo —
	# i due usi restano mutuamente esclusivi per costruzione (fantasma attivo vs nessun fantasma).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_assign_rest_task()

	# Wander Task esplicita (2026-09-12, richiesta utente) — CONFLITTO REALE TROVATO verificando
	# KEY_W come richiesto ("stesso controllo di conflitto già fatto per R"): a differenza di R
	# (conflitto risolvibile per mutua esclusione con lo stato del fantasma edificio, vedi sopra),
	# W è già legato in CameraController.gd al pan CONTINUO della camera verso l'alto
	# (Input.is_key_pressed(KEY_W), polling ad ogni frame — stesso identico motivo per cui S non fu
	# usato per Stop/H sopra, vedi quel commento: "un'interruzione accidentale e silenziosa della
	# propria stessa Task ad ogni pan"). Nessuna mutua esclusione possibile qui (il pan con W è
	# sempre attivo, non gated da uno stato come il fantasma edificio) — usare comunque W avrebbe
	# assegnato una nuova Wander Task (sostituendo qualunque cosa l'individuo stesse facendo) ogni
	# volta che il player sposta la visuale verso l'alto. Sostituito con G (mnemonico "Giro",
	# "farsi un Giro" — stesso principio di H per Halt sopra), tasto verificato libero. Stesso
	# trattamento di H/R: comando VERO, nessun gate DebugLogging.ENABLED, nessun guard su una Task
	# già in corso.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_assign_wander_task()

	# Play Task esplicita (2026-09-13, richiesta utente) — tasto P, mnemonico "Play", verificato
	# libero (nessun conflitto: W/A/S/D + frecce sono il pan camera continuo, +/- lo zoom, B/R
	# vivono dentro il ramo `if _building_ghost != null: ... return` quindi mai raggiunti quando
	# nessun fantasma è attivo, X/H/G sono gli altri comandi diretti già assegnati, T/Y/Z/U i debug
	# hook sotto — stesso identico controllo di conflitto già fatto per R/G). Stesso trattamento di
	# H/R/G: comando VERO, nessun gate DebugLogging.ENABLED, nessun guard su una Task già in corso
	# (assign_task sostituisce sempre). CHILD-only applicato DENTRO _assign_play_task tramite il
	# guard generico di HumanIndividual.assign_task (Task.allowed_age_bands, vedi play.tres) — un
	# individuo selezionato non-CHILD viene rifiutato silenziosamente con lo stesso log [TASK GUARD]
	# già visto per INFANT, nessun controllo duplicato qui.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_assign_play_task()

	# Emergency Rest Task — trigger di TEST MANUALE (2026-09-13, richiesta utente, in preparazione
	# al sistema di interrupt da stamina critica) — tasto E, mnemonico "Emergency", verificato
	# libero (nessuna occorrenza di KEY_E in tutto il progetto, stesso controllo di conflitto già
	# fatto per R/G/P: W/A/S/D+frecce pan, +/- zoom, B/R dentro il ramo fantasma edificio, X/H/G/P
	# gli altri comandi diretti, T/Y/Z/U i debug hook sotto). Stesso trattamento di H/R/G/P: comando
	# VERO, nessun gate DebugLogging.ENABLED, nessun guard su una Task già in corso — DA RIMUOVERE
	# (o spostare sotto un vero pannello/bottone debug) quando arriverà il vero trigger automatico
	# (soglia 5% stamina + coda), un prompt successivo.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_assign_emergency_rest_task()

	# TEST TEMPORANEO Task (2026-09-07, richiesta utente) — vedi _debug_test_two_walk_task sotto per
	# cosa fa e perché è qui. Tasto T, gated da DebugLogging.ENABLED (stesso flag che nasconde
	# SpeedDebugButton — mai visibile/attivo in una build "pulita"). DA RIMUOVERE (o spostare sotto
	# un vero pannello/bottone debug) quando si passa oltre questo step del refactor Stamina/Task.
	if DebugLogging.ENABLED and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		_debug_test_two_walk_task()

	# TEST TEMPORANEO end-to-end "Daydream" (2026-09-07, richiesta utente) — vedi
	# _debug_test_daydream_task sotto per cosa fa e perché è qui. Tasto Y, stesso gate/stesso
	# principio "usa e getta" del tasto T sopra: DA RIMUOVERE (o spostare sotto un vero pannello/
	# bottone debug) quando esisterà una vera TaskDefinition "Daydream".
	if DebugLogging.ENABLED and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y:
		_debug_test_daydream_task()

	# Svuota zaino (debug, 2026-09-09, richiesta utente) — vedi _debug_clear_selected_individual_
	# backpack sotto per cosa fa e perché è qui. Tasto Z (mnemonico "Zaino"), stesso gate/stesso
	# principio "usa e getta" di T/Y sopra: DA RIMUOVERE (o spostare sotto un vero pannello/bottone
	# debug) quando non servirà più a velocizzare i test manuali di PickUp su risorse diverse.
	if DebugLogging.ENABLED and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		_debug_clear_selected_individual_backpack()

	# Tasto U LIBERATO (2026-09-16, richiesta utente) — prima lanciava il TEST TEMPORANEO end-to-end
	# "haul_resource" (_debug_test_haul_resource_task sotto), che il proprio commento originale
	# segnava già "DA RIMUOVERE... quando esisterà una vera TaskDefinition 'haul_resource'" — quella
	# TaskDefinition esiste da tempo (Raccolta vera, click destro su stone/stick lot, vedi
	# _assign_pickup_task), quindi questo collegamento era ormai morto. U ora è il modificatore per
	# "Scaricare risorsa" (U + click destro su un deposito, vedi _try_assign_unload_command_on_right_
	# click) — _debug_test_haul_resource_task resta nel file, non più raggiungibile da nessun tasto
	# (rimozione della funzione stessa fuori scope di questo fix).


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


# Comando "Stop" (2026-09-09, richiesta utente, tasto H — vedi il commento in _unhandled_input per
# perché non S) — annulla la Task corrente dell'individuo SELEZIONATO (individual.is_selected,
# stesso gate già in uso per il comando destro-click di raccolta e per il debug hook Z: nessun
# individuo selezionato -> no-op silenzioso, mai un crash).
#
# individual.stop() (HumanIndividual.gd) è già il punto unico di pulizia Task/movimento riusato da
# ogni interruzione (vedi il suo commento: "la task associata va ripulita ogni volta che il
# movimento finisce... o per qualunque futura interruzione che passi da qui, stesso punto unico, mai
# duplicato altrove") — non serve nuova logica qui, solo richiamarlo: azzera current_task (il
# prossimo _process legge current_task == null e ricade nel Rest di default, già gestito da
# HumanIndividualActionService.apply_action) e is_moving/path, fermando un WalkAction a metà
# IMMEDIATAMENTE (nessun completamento del tragitto). Se lo step corrente era invece un
# PickUpAction, nessuna pulizia aggiuntiva necessaria (richiesta esplicita, verificata): consume()
# scatta solo dentro on_complete(), mai chiamato qui, quindi non c'è alcun effetto già applicato da
# annullare — la sola quantità "prenotata" (_quantity_to_collect) resta nell'istanza scartata,
# innocua.
func _stop_selected_individual_task() -> void:
	if individual == null or not individual.is_selected:
		return
	# Annulla selezione Transport a metà (2026-09-14, richiesta utente — "H cancella una task se in
	# corso completa, oppure se è in selezione a metà [tipo il transport], cancella quella") — DA
	# CONTROLLARE PER PRIMO, PRIMA di individual.stop() sotto: _debug_transport_source_building/
	# _debug_transport_pending_source_building sono stato del comando debug a due click (vedi
	# _debug_try_assign_transport_command_on_right_click), COMPLETAMENTE INDIPENDENTE da
	# individual.current_task — nessuna Transport Task esiste ancora finché la destinazione non
	# viene confermata, quindi non c'è nulla da "fermare" su individual, solo questo stato interno
	# di GameScene da azzerare. PRIMA di questo fix non esisteva NESSUN modo di uscire da questo
	# stato se non completando la selezione (anche per sbaglio, cliccando destro su un edificio
	# qualunque) — vedi l'indagine con l'utente. Ritorna qui SENZA toccare individual.stop()/
	# resolve_idle_individual: l'individuo può avere una Task in corso indipendente da questa
	# selezione (i due stati sono ortogonali, possono coesistere), quella Task NON viene toccata da
	# un annullo della sola selezione — un H successivo, a selezione ormai annullata, la fermerà
	# normalmente se il player lo preme di nuovo.
	if _debug_transport_source_building != null or _debug_transport_pending_source_building != null:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[TRANSPORT] Selezione sorgente/destinazione annullata (tasto H).")
		_debug_transport_source_building = null
		_debug_transport_pending_source_building = null
		_debug_transport_resource_name = ""
		_debug_transport_quantity = 0
		# Banner nascosto (2026-09-14, richiesta utente) — selezione annullata.
		if transport_selection_banner != null:
			transport_selection_banner.visible = false
		return
	individual.stop()
	# Bugfix (2026-09-14, richiesta utente) — individual.stop() da solo azzera SOLO current_task,
	# senza mai toccare task_queue né richiamare resolve_idle_individual: un individuo con una o più
	# Task sospese in coda (es. interrotto prima da un bisogno stamina) restava bloccato per sempre
	# con current_task null e la coda intatta, perché resolve_idle_individual (bisogno -> riprendi
	# dalla coda -> fallback perditempo -> stop, vedi HumanIndividualActionService.gd) non era mai
	# raggiunta da questo comando — solo da completamento naturale/seeding/nascita/load. STESSA
	# chiamata già usata per quei tre casi (es. riga ~781 sopra).
	HumanIndividualActionService.resolve_idle_individual(individual, _resolve_age_band(individual), macro_world)


# TEST TEMPORANEO (2026-09-07, richiesta utente) — verifica che una Task a PIÙ step avanzi da sola
# da uno step al successivo, senza un nuovo comando del player. Agisce sul bersaglio attualmente
# controllabile (individual, vedi il commento sul campo) — nessuna selezione richiesta.
#
# RIPROPOSTA (2026-09-08, richiesta utente, Step 2 piano raccolta/trasporto) — costruiva
# originariamente due WalkAction verso coordinate fisse; ora costruisce [WalkAction, PickUpAction]
# verso la posizione pebble più vicina all'individuo nella SUA macrocella corrente (individual.
# home_macro_coords), per verificare in-game decremento MacroCellState.pebble_quantities e
# assegnazione carico (carried_resource_name/carried_quantity) prima di passare a click/
# persistenza/UI nei prossimi step. Nessuna integrazione con TaskFactory/TaskPersistenceService qui
# (esplicitamente fuori scope di questo passo) — Task costruita a mano, stesso principio già seguito
# da questa stessa funzione e da _debug_test_daydream_task sotto.
#
# DA RIMUOVERE (o spostare sotto un vero pannello/bottone debug, es. DebugBar) quando si passa
# oltre questo step del refactor Stamina/Task — non è pensato per sopravvivere nella build finale.

func _debug_test_two_walk_task() -> void:
	if individual == null:
		return
	var cell: LiveMacroCell = live_cells.get(individual.home_macro_coords)
	if cell == null or cell.macro_state == null:
		push_error("[PICKUP TEST] Nessuna cella viva per la macrocella dell'individuo — impossibile trovare una posizione pebble.")
		return

	# Posizione stone con pebble disponibili più vicina all'individuo — stesso spazio locale di
	# individual.position (Vector2 continuo) e cell.macro_state.stone_positions (Vector2i, vedi
	# StonePositionService), nessuna conversione necessaria.
	var target_position := Vector2i(-1, -1)
	var best_distance := INF
	for pos in cell.macro_state.stone_positions:
		if int(cell.macro_state.pebble_quantities.get(pos, 0)) <= 0:
			continue
		var distance: float = individual.position.distance_to(Vector2(pos))
		if distance < best_distance:
			best_distance = distance
			target_position = pos
	if target_position == Vector2i(-1, -1):
		push_error("[PICKUP TEST] Nessuna posizione con pebble disponibili nella macrocella corrente.")
		return

	var walk := WalkAction.new(Vector2(target_position))
	var pickup := PickUpAction.new(target_position, cell.macro_state)
	var test_task := Task.new([walk, pickup])
	# individual.stop() SOLO DOPO can_assign_task() (2026-09-13, richiesta utente, bugfix — stesso
	# principio di _assign_play_task/_debug_test_daydream_task: nessun effetto collaterale se il
	# guard rifiuta, es. individuo INFANT/CHILD selezionato con Task precedente in corso).
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(test_task, age_band):
		return
	individual.stop()
	# Stesso refresh pebble/stick di _assign_pickup_task (2026-09-09) — vedi quel commento gemello.
	pickup.resource_collected.connect(func(_res: String, _pos: Vector2i, _qty: int) -> void:
		_refresh_resource_visuals(cell)
	)
	# assign_task (2026-09-09, richiesta utente, Step 4) — sostituisce l'assegnazione manuale
	# (current_task = Task.new([...]); walk.activate(individual)) diretta di prima: questo hook ora
	# valida lo stesso percorso generico che un futuro click/UI userà, non uno scavalcato a parte.
	# Il guard è già stato verificato sopra, quindi questa chiamata è garantita riuscire.
	individual.assign_task(test_task, age_band)
	print("[PICKUP TEST] Task Walk+PickUp assegnata a #%d %s verso %s (pebble disponibili: %d)" % [
		individual.id, individual.name, target_position, int(cell.macro_state.pebble_quantities.get(target_position, 0))
	])


# TEST TEMPORANEO end-to-end "Daydream" (2026-09-07, richiesta utente; RISCRITTA 2026-09-10 —
# secondo/ultimo prompt del refactor Daydream via TaskFactory, stesso principio già applicato a
# haul_resource/_assign_pickup_task) — costruisce solo i primi DUE step [Walk, Think] via
# TaskFactory.build_task (vedi DAYDREAM_TASK_DEFINITION_PATH/daydreaming.tres): il resto della
# sequenza (ricerca edificio-pensieri, Unload, "cammina via") si costruisce DA SÉ a runtime tramite
# Task.append_steps, guidato da context["pending_thought_target_search"]/["pending_walk_away_
# position"] scritti da ThinkAction.on_complete/UnloadAction.on_complete (ramo THOUGHT) — vedi
# HumanIndividualActionService._handle_pending_thought_target_search/_handle_pending_walk_away.
# Nessuna Task pre-costruita più lunga di due step necessaria qui, esattamente come
# _debug_test_haul_resource_task sopra.
#
# DA RIMUOVERE (o spostare sotto un vero pannello/bottone debug) quando esisterà un vero trigger
# non-debug per Daydream — stesso principio "usa e getta" di _debug_test_two_walk_task/
# _debug_test_haul_resource_task.
# Distanza del primo Walk ("around") — DIREZIONE casuale ad ogni chiamata (2026-09-07, richiesta
# utente: "non tutti i movimenti vadano nella stessa direzione", prima un offset FISSO Vector2(10,
# 10), sempre diagonale basso/destra) calcolata sotto con Vector2.from_angle(randf() * TAU), questa
# costante resta solo la DISTANZA (invariata, ~14.1 = lunghezza del vecchio Vector2(10,10)).
const _DEBUG_DAYDREAM_AROUND_DISTANCE: float = 14.1
# Durata BASE (giorni di gioco) prima del moltiplicatore Era — valore di partenza ARBITRARIO
# (2.0, richiesta utente), stesso trattamento "facilmente ritarabile" di ogni altra costante di
# questo sistema (STAMINA_DRAIN_PER_MICROCELL, STAMINA_REGEN_PER_DAY, ecc.).
const _DEBUG_DAYDREAM_THINK_BASE_DURATION: float = 2.0
# _DEBUG_DAYDREAM_LEAVE_DISTANCE RIMOSSA (2026-09-10) — la posizione di allontanamento dopo il
# deposito è ora calcolata da UnloadAction.on_complete stesso (ramo THOUGHT, usando la propria
# WALK_AWAY_DISTANCE, STESSO valore 5.0 di prima — vedi unload_action.gd), non più da questa
# funzione: nessun consumatore rimasto qui per questa costante.

func _debug_test_daydream_task() -> void:
	if individual == null:
		return

	# Gate upfront (2026-09-10, STEP 5a) — SOSTITUISCE la vecchia query diretta is_village_center
	# con ThoughtTargetSelectionService.has_thought_accepting_building: stesso comportamento visibile
	# (blocco upfront, PRIMA che qualunque step venga costruito/attivato — vedi ricognizione dedicata,
	# che aveva confermato questo timing per il codice precedente), ma criterio corretto
	# (accepts_thoughts, il flag che il meccanismo dinamico sotto userà davvero per risolvere
	# l'edificio, non più is_village_center — due flag concettualmente distinti su BuildingRules,
	# coincidenti sulla stessa unica istanza oggi solo per come sono popolati i dati, non per
	# garanzia strutturale). Funzione autonoma e riusabile (vive su ThoughtTargetSelectionService, non
	# qui): pronta per essere richiamata anche da una futura generazione automatica della Task
	# Daydream, non solo da questo tasto debug.
	#
	# BUGFIX (2026-09-12, richiesta utente) — has_thought_accepting_building ora richiede ANCHE
	# building.is_complete (vedi quel file): un Pebble Circle ancora in costruzione non fa più
	# superare questo gate. Messaggio d'errore aggiornato di conseguenza ("completo", non solo
	# "piazzato").
	if not ThoughtTargetSelectionService.has_thought_accepting_building(macro_world):
		push_error("[DAYDREAM TEST] Nessun edificio COMPLETO che accetta pensieri in questa partita — costruisci (e completa) uno Pebble Circle (BuildBar) prima di premere Y.")
		return

	var around_position: Vector2 = individual.position + Vector2.from_angle(randf() * TAU) * _DEBUG_DAYDREAM_AROUND_DISTANCE

	# Durata risolta = base × EraRules.think_duration_multiplier (invariato — stessa risoluzione
	# era_rules già in uso altrove nel file, es. _update_individual_panel_content, null-safe: un'Era
	# senza .tres risolvibile lascia la durata BASE invariata, moltiplicatore neutro 1.0, mai un
	# crash). Risolta QUI, nel chiamante, non da TaskFactory (che non risolve mai nulla, riceve solo
	# valori già decisi in context — stesso principio già seguito da _assign_pickup_task per il
	# proprio target).
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name)
	var think_duration: float = _DEBUG_DAYDREAM_THINK_BASE_DURATION * (era_rules.think_duration_multiplier if era_rules != null else 1.0)

	# TaskFactory.build_task (2026-09-10, STEP 5b) — SOSTITUISCE la costruzione manuale a 5 step di
	# prima: "target_position" (Vector2, letto da WALK — stesso step_walk_to_position.tres già usato
	# da haul_resource, RIUSATO qui as-is, context_keys=["target_position"] combacia) e
	# "think_duration" (float, letto da THINK — nuovo step_think.tres, context_keys=
	# ["think_duration"]), entrambi consumati e ripuliti da build_task stesso (consumed_context_keys,
	# vedi task_factory.gd), nessun erase() manuale necessario qui.
	var daydream_definition := load(DAYDREAM_TASK_DEFINITION_PATH) as TaskDefinition
	var context: Dictionary = {
		"target_position": around_position,
		"think_duration": think_duration,
	}
	var task := TaskFactory.build_task(daydream_definition, context)

	# Collegamento dei 4 signal-listener (2026-09-10, STEP 5c) — STESSI IDENTICI listener/callback di
	# prima (idea_completed x3, thought_deposited x1), ma non più collegabili subito dopo la
	# costruzione: l'UnloadAction non esiste ancora a questo punto (nasce dinamicamente più tardi,
	# quando ThinkAction completa e HumanIndividualActionService._handle_pending_thought_target_search
	# lo accoda alla Task — vedi ricognizione dedicata). Iscritto invece a task.step_appended (signal
	# generico introdotto nel prompt precedente, vedi Task.gd/append_steps), filtrando per tipo:
	# quando/se un UnloadAction viene accodato a QUESTA Task (mai per il WalkAction accodato insieme
	# a lui, né per il WalkAction di "cammina via" accodato più tardi da _handle_pending_walk_away),
	# collega i 4 listener. Resta connesso per tutta la vita di questa Task, indipendentemente da
	# quanti frame passano tra l'assegnazione e l'evento (dipende da quando l'individuo finisce di
	# pensare/cammina fino all'edificio trovato).
	#
	# _reconnect_unload_action_signals riusata TALE E QUALE (2026-09-11, estratta da qui — vedi lì
	# per i 4 listener veri, ora condivisi con _reconnect_loaded_task_signals/il gap sul reload) —
	# invariato ogni comportamento: STESSI 4 listener, STESSO momento (quando l'UnloadAction nasce).
	task.step_appended.connect(func(action: Action) -> void:
		if action is UnloadAction:
			_reconnect_unload_action_signals(action as UnloadAction, individual)
	)

	# Guard di età PRIMA di stop() (2026-09-13, richiesta utente, bugfix — bug osservato: un
	# FERTILE_ADULT con haul_resource in corso e zaino pieno, a cui viene assegnata Daydream via
	# questo tasto di test, è bloccato da ThinkAction.disallowed_age_bands — PRIMA di questo fix
	# stop() scattava comunque, scaricando l'inventario/azzerando l'haul_resource in corso anche se
	# Daydream non veniva mai davvero assegnata) — individual.can_assign_task verifica il guard
	# SENZA alcun side-effect; solo se passa si procede con stop()+assign_task, altrimenti return
	# immediato, nessun effetto collaterale, l'haul_resource in corso prosegue indisturbata.
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(task, age_band):
		return

	# stop() SOLO ORA, dopo il guard: il test parte sempre da uno stato pulito, ma solo quando sa
	# già che la nuova Task verrà davvero assegnata.
	individual.stop()

	# individual.assign_task (2026-09-10) — SOSTITUISCE l'assegnazione manuale `individual.
	# current_task = Task.new([...])` di prima: task_name/step_descriptions arrivano già valorizzati
	# da TaskFactory.build_task (da daydreaming.tres/step_think.tres), nessuna riga separata
	# necessaria qui per impostarli. assign_task attiva da sé il primo step (WalkAction verso
	# around_position) — sostituisce la chiamata manuale walk_to_around.activate(...) di prima. Il
	# guard è già stato verificato sopra, quindi questa chiamata è garantita riuscire.
	individual.assign_task(task, age_band)
	print("[DAYDREAM TEST] Task Walk+Think assegnata a #%d %s: around=%s, think=%.2fgg — il resto (ricerca edificio-pensieri/deposito/allontanamento) si costruisce da sé durante l'esecuzione." % [
		individual.id, individual.name, around_position, think_duration
	])


# _resolve_rest_target SPOSTATA su NeedTaskAssignmentService.resolve_rest_target (2026-09-13,
# richiesta utente, sistema di interrupt/coda da stamina critica) — stessa identica logica, vedi
# quel file. REST_TASK_NO_HOUSE_WANDER_RADIUS l'ha seguita lì.


# Trigger tasto R (2026-09-12, richiesta utente) — costruisce ed assegna SEMPRE la Rest Task
# completa [Walk, Rest, Walk away] all'individuo selezionato, sostituendo qualunque Task in corso
# (nessun guard "una Task in corso protegge dal cambio" — decisione esplicita: "nessuna protezione
# da progresso perso"; c'è invece il guard di ETÀ, vedi sotto). Thin wrapper (2026-09-13,
# richiesta utente) — risoluzione target/costruzione/assegnazione/stop() ORA TUTTE dentro
# NeedTaskAssignmentService.assign_rest_task, condivisa con il nuovo interrupt automatico dentro
# HumanIndividualActionService.apply_action: STESSO comportamento esterno di prima di questo
# spostamento per il player che preme R.
#
# individual.stop() NON più chiamato QUI (2026-09-13, richiesta utente, bugfix) — spostato dentro
# NeedTaskAssignmentService.assign_rest_task, DOPO il guard di età (individual.can_assign_task):
# prima di questo fix, stop() scattava incondizionatamente PRIMA di sapere se il guard avrebbe
# rifiutato la nuova Task, scaricando l'inventario/azzerando la Task PRECEDENTE anche quando
# l'assegnazione non sarebbe mai avvenuta (bug osservato con un individuo INFANT selezionato).
func _assign_rest_task() -> void:
	if individual == null or not individual.is_selected:
		return
	NeedTaskAssignmentService.assign_rest_task(individual, macro_world, _resolve_age_band(individual))


# _resolve_emergency_rest_target SPOSTATA su NeedTaskAssignmentService.resolve_emergency_rest_target
# (2026-09-13, richiesta utente, sistema di interrupt/coda da stamina critica) — stessa identica
# logica, vedi quel file. EMERGENCY_REST_STEP_LENGTH l'ha seguita lì.


# Trigger tasto E (2026-09-13, richiesta utente, mnemonico "Emergency" — tasto verificato libero,
# stesso controllo di conflitto già fatto per R/G/P: nessuna occorrenza di KEY_E in tutto il
# progetto) — TRIGGER DI TEST MANUALE, ORA AFFIANCATO dal vero trigger automatico (soglia 5%/20%
# stamina dentro HumanIndividualActionService.apply_action) — resta comunque disponibile come
# comando diretto indipendente, richiesta esplicita. Thin wrapper (2026-09-13) — risoluzione
# target/costruzione/assegnazione/stop() ORA TUTTE in NeedTaskAssignmentService.
# assign_emergency_rest_task, condivisa con l'interrupt automatico: STESSO comportamento esterno
# di prima di questo spostamento.
#
# individual.stop() NON più chiamato QUI (2026-09-13, richiesta utente, bugfix) — stesso motivo
# identico di _assign_rest_task sopra: ora dentro il service, DOPO il guard di età.
func _assign_emergency_rest_task() -> void:
	if individual == null or not individual.is_selected:
		return
	NeedTaskAssignmentService.assign_emergency_rest_task(individual, _resolve_age_band(individual))


# _resolve_wander_targets SPOSTATA su IdleTaskAssignmentService.resolve_wander_targets (2026-09-13,
# richiesta utente, fallback "perditempo" per individui liberi) — stessa identica logica, vedi
# quel file. WANDER_LEG_MIN_LENGTH/MAX_LENGTH l'hanno seguita lì (riusate anche da Play sotto).


# Trigger tasto G (2026-09-12, richiesta utente — vedi il commento esteso su KEY_G in
# _unhandled_input per il perché non W) — costruisce ed assegna SEMPRE la Wander Task completa
# [Walk, LookAround, Walk, LookAround, Walk] all'individuo selezionato, sostituendo qualunque Task
# in corso (nessun guard "una Task in corso protegge dal cambio" — stessa decisione esplicita già
# presa per Rest: "nessuna protezione da progresso perso"; c'è invece il guard di ETÀ, vedi sotto).
# One-shot per costruzione (richiesta esplicita, punto 5): nessun loop/riassegnazione automatica
# qui né altrove — quando i 5 step finiscono, Task.is_finished() diventa vero tramite il
# meccanismo generico già esistente (nessuna logica speciale da scrivere), e l'individuo resta
# senza Task finché non gliene si assegna un'altra manualmente, coerente con la rimozione del
# fallback implicito di Rest fatta in un giro precedente.
#
# individual.stop() RIMOSSO (2026-09-14, richiesta utente — bugfix "una Task sospendibile in corso
# — es. Build — spariva invece di sospendersi in coda quando il player premeva G/P/il comando
# Transport su un individuo occupato"): stop() azzerava SEMPRE current_task incondizionatamente,
# MAI passando dalla logica is_suspendable di assign_task() sotto (quella che decide se sospendere
# in coda o scartare) — bypassandola del tutto. RIMOSSO qui (non sostituito con nulla): assign_task
# già fa tutto da sé quando lo si lascia fare — sospende la Task precedente se is_suspendable,
# altrimenti la scarta, E chiama comunque .activate() sul primo step della nuova Task (che azzera
# is_moving da sé, via Action.activate() di base) — nessun "reset di stato pulito" perso. STESSO
# pattern già corretto di _assign_pickup_task (mai chiamato stop()), STESSO principio già applicato
# altrove per un bug simile (vedi _block_border_crossing: "individual.stop() (pieno) SOSTITUITO con
# is_moving/path").
func _assign_wander_task() -> void:
	if individual == null or not individual.is_selected:
		return
	var target_data: Dictionary = IdleTaskAssignmentService.resolve_wander_targets(individual)
	var wander_definition := load(WANDER_TASK_DEFINITION_PATH) as TaskDefinition
	var context: Dictionary = {
		"wander_target_1": target_data["target_1"],
		"wander_target_2": target_data["target_2"],
		"wander_target_3": target_data["target_3"],
	}
	var task := TaskFactory.build_task(wander_definition, context)
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(task, age_band):
		return
	individual.assign_task(task, age_band)
	if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[WANDER] Task assegnata a #%d %s: %s -> %s -> %s" % [
			individual.id, individual.name, target_data["target_1"], target_data["target_2"], target_data["target_3"]
		])


# _resolve_play_targets SPOSTATA su IdleTaskAssignmentService.resolve_play_targets (2026-09-13,
# richiesta utente, fallback "perditempo" per individui liberi) — stessa identica logica, vedi
# quel file.


# Trigger tasto P (2026-09-13, richiesta utente, mnemonico "Play" — tasto verificato libero: non in
# conflitto con WASD/frecce di pan camera, +/- di zoom, B/R del fantasma edificio, X/H/G dei comandi
# diretti Camera/Stop/Wander, T/Y/Z/U dei debug hook, vedi _unhandled_input) — costruisce ed
# assegna SEMPRE la Play Task completa [Run, Jump, Run, Jump] all'individuo selezionato, sostituendo
# qualunque Task in corso (nessun guard "una Task in corso protegge dal cambio" — stessa decisione
# esplicita già presa per Rest/Wander: "nessuna protezione da progresso perso"; c'è invece il
# guard di ETÀ, vedi sotto).
#
# CHILD-only (richiesta esplicita utente) — vincolo di TASK (play.tres.allowed_age_bands), non delle
# Action (RunAction/JumpAction restano generiche per età): se l'individuo selezionato NON è CHILD,
# il guard rifiuta silenziosamente (log [TASK GUARD] se DebugLogging.ENABLED, stesso comportamento
# già visto per INFANT).
#
# individual.stop() RIMOSSO (2026-09-14, richiesta utente — STESSO bugfix di _assign_wander_task,
# vedi quel commento esteso: stop() azzerava SEMPRE current_task incondizionatamente, bypassando la
# logica is_suspendable di assign_task() — una Build/haul_resource/Transport in corso spariva
# invece di sospendersi in coda quando il player premeva P su un individuo occupato). RIMOSSO qui,
# non sostituito con nulla: assign_task sotto già sospende/scarta/attiva da sé, guard CHILD-only già
# verificato sopra (can_assign_task) — se rifiuta, nessun effetto collaterale di alcun tipo, la Task
# precedente prosegue indisturbata (invariato rispetto a prima di questo fix).
func _assign_play_task() -> void:
	if individual == null or not individual.is_selected:
		return
	var target_data: Dictionary = IdleTaskAssignmentService.resolve_play_targets(individual)
	var play_definition := load(PLAY_TASK_DEFINITION_PATH) as TaskDefinition
	var context: Dictionary = {
		"play_target_1": target_data["target_1"],
		"play_target_2": target_data["target_2"],
	}
	var task := TaskFactory.build_task(play_definition, context)
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(task, age_band):
		return
	# Collegamento signal JumpAction.jumped (2026-09-13, richiesta utente, feedback visivo minimo) —
	# STESSO principio/STESSA posizione di _try_pick_demolish_target/TaskReassignmentService (vedi
	# _reconnect_build_task_signals: "un solo punto, i due chiamanti — creazione in-sessione e reload
	# — non possono disallinearsi", qui il gemello per Play è _reconnect_loaded_task_signals sotto).
	# Il guard CHILD-only è già stato verificato sopra (can_assign_task), quindi assign_task sotto
	# è garantita riuscire — questo collegamento non rischia più di restare "orfano" su una Task mai
	# attivata.
	for step in task.steps:
		if step is JumpAction:
			_reconnect_jump_action_signals(step as JumpAction, individual)
	individual.assign_task(task, age_band)
	if DebugLogging.ENABLED and DebugLogging.SHOW_IDLE_LOGS:
		print("[PLAY] Task assegnata a #%d %s: %s -> %s" % [
			individual.id, individual.name, target_data["target_1"], target_data["target_2"]
		])


# Risoluzione del context della Transport Task, PRIMA della costruzione (2026-09-12, richiesta
# utente — "stesso pattern già usato per _resolve_rest_target/_resolve_wander_targets") — ritorna
# SEMPRE un Dictionary con le sei chiavi lette da TaskFactory.build_task per i 4 step fissi
# [Walk->source, Retrieve, Walk->destination, Unload] (vedi transport.tres), mai null.
# source_building/destination_building/resource_name/quantity arrivano GIÀ RISOLTI dal chiamante
# (source/destination dal trigger a due click destri, resource_name/quantity dalla scelta del
# player nel TransportSourceDialog — vedi _debug_try_assign_transport_command_on_right_click/
# _on_transport_source_resource_chosen sotto): questa funzione si limita a tradurre le posizioni dei
# due edifici nello spazio locale di `target_individual` e a impacchettare tutto nelle chiavi che
# transport.tres si aspetta.
#
# Posizioni tradotte con la STESSA formula cross-macrocella già in uso ovunque nel progetto per
# questo scopo (es. _resolve_rest_target/_try_assign_unload_command_on_right_click/
# _debug_test_daydream_task): building.macro_x/y sono locali alla macrocella OSPITANTE l'edificio,
# non necessariamente quella HOME dell'individuo (offset zero, no-op, se coincidono).
func _resolve_transport_context(
	target_individual: HumanIndividual, source_building: Building, destination_building: Building,
	resource_name: String, quantity: int
) -> Dictionary:
	var source_macro_offset: Vector2 = Vector2(
		Vector2i(source_building.macro_x, source_building.macro_y) - target_individual.home_macro_coords
	) * World.WIDTH
	var source_position: Vector2 = Vector2(source_building.micro_x, source_building.micro_y) + source_macro_offset

	var destination_macro_offset: Vector2 = Vector2(
		Vector2i(destination_building.macro_x, destination_building.macro_y) - target_individual.home_macro_coords
	) * World.WIDTH
	var destination_position: Vector2 = Vector2(destination_building.micro_x, destination_building.micro_y) + destination_macro_offset

	return {
		"transport_source_position": source_position,
		"transport_source_building": source_building,
		"transport_resource_name": resource_name,
		"transport_quantity": quantity,
		"transport_destination_position": destination_position,
		"transport_destination_building": destination_building,
	}


# Costruisce ed assegna la Transport Task completa [Walk, Retrieve, Walk, Unload] all'individuo
# selezionato (2026-09-12, richiesta utente) — chiamata SOLO dal trigger a due click destri sotto,
# mai da _unhandled_input direttamente (stesso principio di _assign_rest_task/_assign_wander_task,
# separazione risoluzione/assegnazione). resource_name/quantity arrivano GIÀ SCELTI dal player nel
# TransportSourceDialog (vedi _on_transport_source_resource_chosen sotto), non più fissati nel
# codice.
#
# individual.stop() RIMOSSO (2026-09-14, richiesta utente — bugfix confermato con log: una Build
# Task sospendibile in corso spariva invece di sospendersi in coda quando il player assegnava
# Transport a quello stesso individuo — nessun [TASK SUSPEND] in log, a differenza dell'identica
# sequenza per Pickup/haul_resource, che invece sospende correttamente). STESSO fix di
# _assign_wander_task/_assign_play_task, vedi quei commenti estesi: RIMOSSO, non sostituito con
# nulla — assign_task() sotto già sospende/scarta/attiva da sé la Task precedente, nessun "reset di
# stato pulito" perso (Action.activate() sul primo step della Transport azzera già is_moving).
#
# Segnali ricollegati SUBITO dopo la costruzione (2026-09-12) — STESSO principio già seguito da
# _try_assign_unload_command_on_right_click per il proprio UnloadAction costruito a mano: senza
# questo, il deposito/prelievo fisico muterebbe comunque stored_resources correttamente (la
# mutazione vera vive in BuildingStorageService, non nel segnale), ma la UI (griglia di stoccaggio
# del pannello edificio, se aperto) non si aggiornerebbe da sola. resource_retrieved (nuovo segnale
# di RetrieveAction) riusa lo stesso identico handler di resource_deposited (_on_resource_deposited
# si limita a rinfrescare la macrocella dell'edificio passato, generico per qualunque building) —
# nessun nuovo handler dedicato necessario.
#
# Lampeggio SULLA DESTINAZIONE (2026-09-12, richiesta utente — "sul magazzino destinazione, fai un
# lampeggio come accade per la build, e per la pick up task") — STESSO trigger/STESSO principio di
# _try_assign_pickup_command_on_right_click/_try_assign_build_command_on_right_click: subito
# all'assegnazione, non all'arrivo. Icona "transport" (IconRegistry.COMMAND_ICONS), diversa da
# "pickup"/"build" — vedi IconRegistry.gd per la scelta dell'emoji (nessuna carriola in Unicode
# standard).
func _debug_assign_transport_task(
	source_building: Building, destination_building: Building, resource_name: String, quantity: int
) -> void:
	if individual == null or not individual.is_selected:
		return
	var context: Dictionary = _resolve_transport_context(
		individual, source_building, destination_building, resource_name, quantity
	)
	var transport_definition := load(TRANSPORT_TASK_DEFINITION_PATH) as TaskDefinition
	var task := TaskFactory.build_task(transport_definition, context)
	# Guard PRIMA di costruire i collegamenti signal sotto (2026-09-13, richiesta utente — un guard
	# rifiutato, oggi solo INFANT/CHILD selezionati, non deve lasciare segnali orfani collegati a una
	# Task mai attivata). individual.stop() NON PIÙ chiamato qui (2026-09-14 — vedi il commento esteso
	# in testa alla funzione): assign_task() sotto gestisce da sé sospensione/scarto della Task
	# precedente.
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(task, age_band):
		return
	for step in task.steps:
		if step is UnloadAction:
			_reconnect_unload_action_signals(step as UnloadAction, individual)
		elif step is RetrieveAction:
			(step as RetrieveAction).resource_retrieved.connect(
				func(_res_name: String, building: Building, _qty: int) -> void: _on_resource_deposited(building)
			)
	# Il guard è già stato verificato sopra (can_assign_task), quindi questa chiamata è garantita
	# riuscire — "❌" non scatta più da qui (nessun rifiuto possibile a questo punto), resta solo
	# come icona di comando "transport" riuscito.
	var assigned := individual.assign_task(task, age_band)
	var command_icon_key := "transport" if assigned else "task_rejected"

	var destination_macro_coords := Vector2i(destination_building.macro_x, destination_building.macro_y)
	if live_cells.has(destination_macro_coords):
		_spawn_command_blink_effect(
			live_cells[destination_macro_coords],
			Vector2i(destination_building.micro_x, destination_building.micro_y),
			IconRegistry.get_command_icon(command_icon_key)
		)

	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[TRANSPORT] Task assegnata a #%d %s: %s #%d -> %s #%d, risorsa='%s' quantità=%d" % [
			individual.id, individual.name,
			source_building.building_type_name, source_building.id,
			destination_building.building_type_name, destination_building.id,
			resource_name, quantity,
		])


# Stato del trigger a due click (2026-09-12, richiesta utente) — `_debug_transport_source_building`
# è null finché il player non conferma il TransportSourceDialog: il PRIMO click destro su un
# edificio con risorse NON lo imposta subito come sorgente, apre invece il dialog e tiene
# l'edificio "in sospeso" in `_debug_transport_pending_source_building` finché il player non
# conferma (sorgente impostata + resource_name/quantity salvati) o annulla (niente viene impostato,
# come se non avesse cliccato nulla — richiesta esplicita utente). Campi vivi per l'intera sessione
# di gioco (mai resettati altrove), stesso principio "usa e getta" degli altri campi di stato dei
# debug hook di questo file.
var _debug_transport_source_building: Building = null
var _debug_transport_pending_source_building: Building = null
var _debug_transport_resource_name: String = ""
var _debug_transport_quantity: int = 0


# Trigger "Transport" a due click DESTRI consecutivi su edifici DIVERSI (2026-09-12, richiesta
# utente — sostituisce il precedente trigger di test a valori fissi): il primo apre il
# TransportSourceDialog sulle risorse REALMENTE presenti in quell'edificio (building.
# stored_resources, "pannello muto" — nessuna query fatta dal dialog stesso, vedi TransportSource
# Dialog.gd), il secondo (dopo conferma del dialog, su un edificio diverso) costruisce ed assegna
# la Transport Task con risorsa/quantità scelte dal player.
#
# STESSO schema/STESSA posizione nella catena di _try_assign_pickup_command_on_right_click/
# _try_assign_unload_command_on_right_click/_try_assign_build_command_on_right_click sopra (provato
# per ULTIMO, dopo tutti e tre: un edificio già intercettato da uno di quelli — es. uno storage con
# zaino pieno per Unload, o un cantiere incompleto per Build — non arriva mai qui, nessuna
# competizione reale). Gated da DebugLogging.ENABLED, stesso principio "usa e getta" di T/Y/Z/U — DA
# RIMUOVERE (o spostare sotto un vero pannello/bottone debug) quando questo comando avrà una vera
# UI permanente (es. un bottone dedicato nella BuildBar).
func _debug_try_assign_transport_command_on_right_click(event: InputEvent) -> bool:
	if not DebugLogging.ENABLED:
		return false
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if individual == null or not individual.is_selected:
		return false

	var building_hit := building_selector_controller.try_select(
		event, live_cells, macro_world.buildings if macro_world != null else [], MOUSE_BUTTON_RIGHT
	)
	if building_hit.is_empty():
		return false
	var hit_building := _find_building_by_id(building_hit["building_id"])
	if hit_building == null:
		return false

	if _debug_transport_source_building == null:
		# Guard età PRIMA di aprire il dialog (2026-09-16, richiesta utente — bugfix UX: senza
		# questo controllo il popup si apriva comunque per un individuo INFANT/CHILD selezionato,
		# che poi veniva rifiutato solo alla fine del giro a due click da can_assign_task dentro
		# _debug_assign_transport_task, dopo aver già scelto risorsa/quantità/destinazione a vuoto).
		# STESSA lista di RetrieveAction/UnloadAction.disallowed_age_bands (i due step che la
		# Transport Task condivide con questo rifiuto) — duplicata qui apposta per poter bloccare
		# PRIMA di costruire la Task stessa: se quella lista cambia in futuro, va aggiornata anche
		# qui.
		var age_band := _resolve_age_band(individual)
		if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD:
			return true
		# available_quantities: Dictionary[String, int] — appiattito da stored_resources (Dictionary
		# [String, Dictionary{"quantity":int,"decay_fraction":float}]), stesso "spacchettamento" già
		# fatto da RetrieveAction.activate()/BuildingStorageService.withdraw per la stessa struttura.
		var available_quantities: Dictionary = {}
		for resource_name: String in hit_building.stored_resources.keys():
			var entry: Dictionary = hit_building.stored_resources[resource_name]
			var quantity: int = int(entry.get("quantity", 0))
			if quantity > 0:
				available_quantities[resource_name] = quantity

		if available_quantities.is_empty():
			if DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[TRANSPORT] %s #%d non ha risorse da prelevare." % [hit_building.building_type_name, hit_building.id])
			return true

		_debug_transport_pending_source_building = hit_building
		var display_name: String = tr(hit_building.rules.building_name) if hit_building.rules != null else hit_building.building_type_name
		transport_source_dialog.open_dialog(display_name, available_quantities)
		return true

	if hit_building == _debug_transport_source_building:
		if DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[TRANSPORT] destinazione uguale alla sorgente (#%d) — ignorato, clicca un edificio diverso." % hit_building.id)
		return true

	var source_building := _debug_transport_source_building
	_debug_transport_source_building = null
	# Banner nascosto (2026-09-14, richiesta utente) — destinazione confermata, la selezione non è
	# più "a metà".
	if transport_selection_banner != null:
		transport_selection_banner.visible = false
	_debug_assign_transport_task(source_building, hit_building, _debug_transport_resource_name, _debug_transport_quantity)
	return true


# Handler di conferma del TransportSourceDialog (2026-09-12, richiesta utente) — finalizza la
# sorgente "in sospeso" SOLO ora (mai al primo click, vedi commento sopra): da qui in poi il gioco
# resta in attesa del click destro sulla destinazione, stesso comportamento "sorgente impostata,
# aspetto destinazione" già esistente prima del dialog.
func _on_transport_source_resource_chosen(resource_name: String, quantity: int) -> void:
	if _debug_transport_pending_source_building == null:
		return
	_debug_transport_source_building = _debug_transport_pending_source_building
	_debug_transport_pending_source_building = null
	_debug_transport_resource_name = resource_name
	_debug_transport_quantity = quantity
	# Banner mostrato (2026-09-14, richiesta utente) — sorgente confermata, la selezione è ora "a
	# metà" finché non scegli la destinazione (o premi H per annullare).
	if transport_selection_banner != null:
		transport_selection_banner.visible = true
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[TRANSPORT] sorgente impostata: %s #%d, risorsa='%s' quantità=%d. Ora click destro sull'edificio destinazione." % [
		_debug_transport_source_building.building_type_name, _debug_transport_source_building.id, resource_name, quantity
	])


# DEBUG "usa e getta" (2026-09-09, richiesta utente) — svuota lo zaino dell'individuo SELEZIONATO
# (individual.is_selected, non solo il bersaglio `individual` — a differenza di _debug_test_
# two_walk_task/_debug_test_daydream_task sopra, che agiscono sempre sul bersaglio corrente a
# prescindere dalla selezione, qui la richiesta esplicita è "individuo selezionato": nessuna
# selezione -> no-op silenzioso, mai un crash) per velocizzare test consecutivi di PickUp su
# risorse diverse senza dover riavviare la partita. Gli item vengono semplicemente PERSI (nessun
# ripristino nel mondo/pool di origine, richiesta esplicita) — stesso trattamento "usa e getta" di
# T/Y sopra: DA RIMUOVERE (o spostare sotto un vero pannello/bottone debug) quando non servirà più.
func _debug_clear_selected_individual_backpack() -> void:
	if individual == null or not individual.is_selected:
		return
	individual.carried_resource_name = ""
	individual.carried_quantity = 0
	print("[DEBUG] Zaino svuotato per #%d %s" % [individual.id, individual.name])


# DEBUG "usa e getta" (2026-09-09, richiesta utente) — verifica la Task haul_resource end-to-end:
# a differenza di _debug_test_two_walk_task sopra (Walk+PickUp fisso su pebble, mai oltre), qui basta
# costruire i primi DUE step (Walk verso il bersaglio più vicino, PickUp) — il resto della sequenza
# (ricerca magazzino, Walk verso di esso, Unload, "cammina via") si costruisce DA SÉ durante
# l'esecuzione tramite Task.append_steps, chiamato da HumanIndividualActionService quando
# PickUpAction/UnloadAction scrivono le rispettive richieste in context (vedi
# _handle_pending_warehouse_search/_handle_pending_walk_away lì) — nessuna Task pre-costruita più
# lunga di due step necessaria qui.
#
# Bersaglio: la posizione pebble O stick lot disponibile più VICINA all'individuo, qualunque delle
# due risulti più vicina (stesso ordine di ricerca "posizione stone" di _debug_test_two_walk_task
# sopra, esteso anche a tree_claimed_lots/stick — nessuna priorità fissa fra i due tipi, a differenza
# di _try_assign_pickup_command_on_right_click che prova sempre PRIMA stone: qui la scelta "chi è più
# vicino" esercita entrambe le risorse a seconda di cosa capita nella macrocella di test).
func _debug_test_haul_resource_task() -> void:
	if individual == null:
		return
	var cell: LiveMacroCell = live_cells.get(individual.home_macro_coords)
	if cell == null or cell.macro_state == null:
		push_error("[HAUL TEST] Nessuna cella viva per la macrocella dell'individuo — impossibile trovare un bersaglio.")
		return

	var target_position := Vector2i(-1, -1)
	var target_resource_name := ""
	var best_distance := INF
	for pos in cell.macro_state.stone_positions:
		if int(cell.macro_state.pebble_quantities.get(pos, 0)) <= 0:
			continue
		var distance: float = individual.position.distance_to(Vector2(pos))
		if distance < best_distance:
			best_distance = distance
			target_position = pos
			target_resource_name = "pebble"
	for lot in cell.macro_state.tree_claimed_lots.keys():
		if TerrainScatteredResourceService.get_available(cell.macro_state, "stick", lot) <= 0:
			continue
		var distance: float = individual.position.distance_to(Vector2(lot))
		if distance < best_distance:
			best_distance = distance
			target_position = lot
			target_resource_name = "stick"

	if target_position == Vector2i(-1, -1):
		push_error("[HAUL TEST] Nessuna posizione pebble/stick disponibile nella macrocella corrente.")
		return

	var walk := WalkAction.new(Vector2(target_position))
	var pickup := PickUpAction.new(target_position, cell.macro_state, target_resource_name)
	var task := Task.new([walk, pickup])
	task.task_name = "task_haul_resource_name"
	task.step_descriptions = ["task_haul_resource_step_walk", "task_haul_resource_step_pickup"]
	# individual.stop() SOLO DOPO can_assign_task() (2026-09-13, richiesta utente, bugfix — stesso
	# principio degli altri assign/debug hook di questo file).
	var age_band := _resolve_age_band(individual)
	if not individual.can_assign_task(task, age_band):
		return
	individual.stop()
	# Stesso refresh pebble/stick di _assign_pickup_task (2026-09-09) — vedi quel commento gemello.
	pickup.resource_collected.connect(func(_res: String, _pos: Vector2i, _qty: int) -> void:
		_refresh_resource_visuals(cell)
	)
	individual.assign_task(task, age_band)
	print("[HAUL TEST] Task haul_resource (2 step iniziali) assegnata a #%d %s verso %s risorsa='%s' — il resto (ricerca magazzino/unload/allontanamento) si costruisce da sé durante l'esecuzione." % [
		individual.id, individual.name, target_position, target_resource_name
	])


# Effetto "usa e getta" (richiesta utente 2026-09-07 — "una piccola lampadina che parte dal
# pipottino e scompare verso l'alto") — puro codice, nessun .tscn, stesso principio già seguito da
# BuildingGhost/NotificationPopup per gli elementi transitori di questa scena. Guardia su
# live_cells.has(...) identica a _on_human_individual_born/_on_human_individual_died: nessun
# effetto se la macrocella dell'individuo non è (più) una cella viva del focus LOD.
func _spawn_idea_deposit_effect(individual: HumanIndividual) -> void:
	if not live_cells.has(individual.home_macro_coords):
		return
	var label := Label.new()
	label.text = "💡"
	label.z_index = 2
	# Font ridotto (richiesta utente 2026-09-07, poi ulteriormente rimpicciolito su feedback
	# successivo: "un po' piu' piccola ancora") — il default del tema è pensato per UI a schermo
	# intero, qui va scalata alla taglia del pipottino stesso (poche microcelle, vedi CELL_SIZE=10px).
	label.add_theme_font_size_override("font_size", 6)
	# Offset verticale iniziale (sopra la testa del pipottino, non sui suoi piedi) — stessa
	# conversione microcelle->pixel locali già in uso ovunque nel file (es.
	# _center_camera_on_individual).
	label.position = individual.position * MicroCellRenderer.CELL_SIZE + Vector2(-3, -12)
	live_cells[individual.home_macro_coords].container.add_child(label)

	# Salita più alta e dissolvenza più lenta (richiesta utente 2026-09-07, secondo giro di
	# ritocchi) — due durate separate invece di una sola condivisa: la salita resta rapida (0.9s,
	# "parte" visibilmente), la dissolvenza si allunga (2.0s) cosi' resta visibile più a lungo prima
	# di sparire del tutto.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 3.0)
	tween.chain().tween_callback(label.queue_free)


# Effetto "usa e getta" per un carico scartato (2026-09-14, richiesta utente — step C del piano
# "rerouting": "il terzo caso [nessun magazzino trovato] fa discard, rendiamolo esplicito con un
# simbolo sulla mappa che scompare dopo qualche secondo") — STESSO schema/STESSA posizione/STESSA
# guardia live_cells.has(...) di _spawn_idea_deposit_effect sopra (nessun effetto se la macrocella
# dell'individuo non è più una cella viva del focus LOD), icona fissa "🗑️" (non l'icona della
# risorsa scartata via IconRegistry: qui il messaggio è "qualcosa è andato perso qui", non "questa
# risorsa è disponibile qui" — le due cose andrebbero confuse visivamente con la stessa icona già
# usata per i mucchietti di stone/vegetazione sulla mappa).
func _spawn_carried_resource_discarded_effect(individual: HumanIndividual) -> void:
	if not live_cells.has(individual.home_macro_coords):
		return
	var label := Label.new()
	label.text = "🗑️"
	label.z_index = 2
	label.add_theme_font_size_override("font_size", 6)
	label.position = individual.position * MicroCellRenderer.CELL_SIZE + Vector2(-3, -12)
	live_cells[individual.home_macro_coords].container.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 3.0)
	tween.chain().tween_callback(label.queue_free)


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
		SelectionKind.DEAD_BODY:
			# Bugfix (richiesta utente, 2026-09-05): mancava, "centra" non faceva nulla per un
			# corpo selezionato (cadeva nel caso _: pass sotto). Stessa identica traduzione
			# cross-macrocella dei rami sopra — un corpo non ha un renderer proprio (non è disegnato
			# da MicroCellRenderer come vegetazione/edifici, vedi DeadBodyView), quindi la posizione
			# locale si ricava direttamente dal record (già in microcelle, stessa conversione *
			# CELL_SIZE già usata da DeadBodyView.setup_dead_body per piazzare il nodo).
			var dead_body_record := _find_dead_body_record(selected_dead_body_individual_id)
			if dead_body_record.is_empty():
				return
			var dead_body_macro_coords: Vector2i = dead_body_record["home_macro_coords"]
			var dead_body_local_position: Vector2 = dead_body_record["position"] * MicroCellRenderer.CELL_SIZE
			var dead_body_macro_offset := Vector2(dead_body_macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
			_animate_camera_to(dead_body_local_position + dead_body_macro_offset, animated)
		SelectionKind.STONE:
			# Stessa identica traduzione cross-macrocella dei rami sopra (2026-09-08, richiesta
			# utente) — get_stone_screen_position è l'equivalente per STONE di
			# get_individual_screen_position/get_building_screen_position.
			var stone_macro_coords: Vector2i = selected_stone["macro_coords"]
			var stone_cell: LiveMacroCell = live_cells.get(stone_macro_coords)
			if stone_cell == null or stone_cell.renderer == null:
				return
			var stone_local_position: Vector2 = stone_cell.renderer.get_stone_screen_position(selected_stone["position"])
			var stone_macro_offset := Vector2(stone_macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
			_animate_camera_to(stone_local_position + stone_macro_offset, animated)
		SelectionKind.STICK_LOT:
			# Nessun get_*_screen_position dedicato (2026-09-08, richiesta utente): il bersaglio è il
			# CENTRO del lotto stesso, non un oggetto puntiforme — stessa conversione lotto*CELL_SIZE
			# + metà cella già usata da _rebuild_stick_multimesh in MicroCellRenderer.
			var stick_lot_macro_coords: Vector2i = selected_stick_lot["macro_coords"]
			var stick_lot_cell: LiveMacroCell = live_cells.get(stick_lot_macro_coords)
			if stick_lot_cell == null or stick_lot_cell.renderer == null:
				return
			var lot: Vector2i = selected_stick_lot["lot"]
			var half: float = MicroCellRenderer.CELL_SIZE / 2.0
			var stick_lot_local_position := Vector2(lot.x * MicroCellRenderer.CELL_SIZE + half, lot.y * MicroCellRenderer.CELL_SIZE + half)
			var stick_lot_macro_offset := Vector2(stick_lot_macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
			_animate_camera_to(stick_lot_local_position + stick_lot_macro_offset, animated)
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
# `source` (2026-09-12, richiesta utente — "il movimento che porta alla persona, se cliccata nel
# menu edificio è molto più lento e a scatti rispetto a se lo fai da population o dall'info di
# quella persona, è un metodo diverso?") — SOLO diagnostico, mai letto per logica/comportamento:
# VERIFICATO leggendo il codice, NON è un metodo diverso — _on_building_resident_center_requested
# sotto chiama QUESTA STESSA funzione, invariata (vedi lì). L'ipotesi più probabile per lo scatto
# riportato: NON dipende da quale UI ha innescato la richiesta, ma da quanto è lontano il
# bersaglio dal centro attualmente caricato — se target.home_macro_coords != center_macro_coords,
# _set_movement_target sotto ricarica per intero la finestra di celle live (_reposition_live_
# cells, sincrona, potenzialmente costosa) PRIMA di avviare il tween della camera. Un individuo
# della lista Population è spesso già vicino al centro corrente (nessuna ricarica, tween fluido),
# mentre il residente di un edificio selezionato altrove sulla mappa può trovarsi lontano dalla
# propria casa in quel momento (Task in corso altrove) — `source` identifica nel log QUALE punto
# di chiamata ha innescato la richiesta, per confermare quale ramo scatena davvero il
# ricaricamento e quanto costa (vedi il log gemello in _set_movement_target sotto).
func _on_population_individual_center_requested(target: HumanIndividual, source: String = "unknown") -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
		print("[CENTER DEBUG] richiesta da '%s' per #%d %s: home_macro_coords=%s center_macro_coords=%s (%s)" % [
			source, target.id, target.name, target.home_macro_coords, center_macro_coords,
			"RICARICA NECESSARIA" if target.home_macro_coords != center_macro_coords else "già nel centro corrente"
		])
	# _clear_vegetation_selection/_clear_building_selection (bugfix, richiesta utente 2026-09-04,
	# scoperto mentre si aggiungeva la selezione edifici): PRIMA mancavano qui — selezionare un
	# individuo da questa lista mentre vegetazione/edificio erano già selezionati lasciava ENTRAMBI
	# selezionati (evidenziazione a schermo compresa), esattamente il difetto che la mutua
	# esclusione altrove (_unhandled_input, _select_vegetation, _select_building, ecc.) evita già.
	# ESTESO a mutua esclusione COMPLETA a 7 vie (2026-09-16, richiesta utente — questa funzione era
	# rimasta ferma "a 3 vie" da allora, mai aggiornata quando dead_body/stone/stick_lot/microcell
	# sono arrivati più tardi: stesso identico bug, solo con più tipi rimasti fuori nel frattempo).
	_clear_vegetation_selection()
	_clear_building_selection()
	_clear_dead_body_selection()
	_clear_stone_selection()
	_clear_stick_lot_selection()
	_clear_microcell_selection()
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
	_clear_building_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
	_clear_dead_body_selection()
	_clear_stone_selection()
	_clear_stick_lot_selection()
	_clear_microcell_selection()
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
	_clear_dead_body_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
	_clear_stone_selection()
	_clear_stick_lot_selection()
	_clear_microcell_selection()
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
	building_info_panel.show_building(building, _resolve_building_residents_display_data(building))
	# Titolo (Step 6, richiesta utente 2026-09-04) — stessa formula già in BuildingInfoPanel.
	var type_name: String = tr(building.rules.building_name) if building.rules != null else building.building_type_name
	game_info_tabs.set_selection_title(tr("selection_title_type").format({"type": type_name}))


# Dati di presentazione per la griglia residenti del pannello edificio (2026-09-12, richiesta
# utente — "quadrati simili a quelli dello storage per rappresentare individui residenti") —
# BuildingInfoPanel resta "muto" su human_individuals/game_data (stesso principio dichiarato in
# testa a quel file), quindi la risoluzione vive QUI: un Dictionary per residente
# ({"id","name","age","sex","is_child"}), già pronto per essere disegnato senza che il pannello debba
# richiamare HumanCalculator/game_data da sé. age_band calcolato con la STESSA formula già in uso
# ovunque nel progetto per età/fascia (vedi _update_individual_panel_content sopra) —
# game_data.era_effective_age_band_durations_male/female, mai le durate BASE di HumanRules
# direttamente (vedi _resolve_age_band sopra, ora usata anche qui). "is_child" = (age_band == CHILD
# OR age_band == INFANT) — ESTESO 2026-09-12, richiesta utente, collegamento di HumanTypes.AgeBand.
# INFANT al gameplay: un neonato deve continuare a mostrare l'icona/trattamento "bimbo/bimba" già
# usato per CHILD, non regredire a "adulto" solo perché ha una fascia propria oggi. TEENAGER/
# FERTILE_ADULT/MATURE_ADULT/OLD restano trattate tutte uguali, nessuna distinzione oltre
# child-o-infant/non-child. Array vuoto se l'edificio non è residenziale (max_residents<=0) —
# BuildingInfoPanel._refresh_residents_grid nasconde la griglia in quel caso, stesso principio già
# seguito per storage_slot_count<=0.
func _resolve_building_residents_display_data(building: Building) -> Array[Dictionary]:
	var residents_display_data: Array[Dictionary] = []
	if building.rules == null or building.rules.max_residents <= 0:
		return residents_display_data
	for individual in human_individuals:
		if individual.house_id != building.id:
			continue
		var age: int = game_data.year - individual.birth_year_virtual
		var age_band := _resolve_age_band(individual)
		residents_display_data.append({
			"id": individual.id,
			"name": individual.name,
			"age": age,
			"sex": individual.sex,
			"is_child": age_band == HumanTypes.AgeBand.CHILD or age_band == HumanTypes.AgeBand.INFANT,
		})
	return residents_display_data


# Reazione a BuildingInfoPanel.empty_all_requested (2026-09-11, richiesta utente — "abilita il
# button empty all con il comando che davvero azzera tutto il materiale... lo fai solo sparire dal
# gioco e dal deposito") — building.stored_resources.clear() è LETTERALMENTE tutto ciò che serve
# lato dati: la capacità/gli slot occupati sono sempre CALCOLATI da stored_resources (vedi
# BuildingStorageService.get_used_space/get_slots_used), mai tracciati altrove, quindi svuotare
# questo Dictionary libera automaticamente ogni slot per il prossimo deposito — nessuna altra
# contabilità da resettare. Nessuna destinazione per il materiale rimosso (richiesta esplicita
# utente, "per ora non pensiamo a dove vada") — semplicemente scompare, stesso trattamento
# "temporaneo, nessun sistema di scarico a terra" già accettato altrove nel progetto (vedi
# HumanIndividualActionService._handle_pending_warehouse_search, ramo discard_on_failure).
#
# Refresh ESPLICITO in ENTRAMBE le direzioni — pannello (show_building ri-letto subito, la griglia
# StorageGrid dentro BuildingInfoPanel si ricostruisce da sé) E mappa (_refresh_building_visuals,
# necessario per la nuova griglia di stoccaggio disegnata su MicroCellRenderer._draw_deposit_site_
# storage_grid — vedi lì: quella legge da una COPIA di Building.stored_resources passata da
# _buildings_for_cell, non dall'oggetto live, quindi senza questa chiamata resterebbe visibilmente
# sbagliata — mucchietti ancora disegnati per materiale che non esiste più — fino al prossimo
# trigger di refresh naturale).
func _on_empty_all_requested(building: Building) -> void:
	if building == null:
		return
	building.stored_resources.clear()
	building_info_panel.show_building(building, _resolve_building_residents_display_data(building))
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if live_cells.has(macro_coords):
		_refresh_building_visuals(live_cells[macro_coords])
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Deposito edificio #%d svuotato — tutto il materiale è scomparso dal gioco e dal deposito." % building.id)


# Reazione a BuildingInfoPanel.resident_center_requested (2026-09-12, richiesta utente — "puoi
# fare che la icona delle persone nella vista edificio funzioni come un centra su di loro?") —
# risolve l'id sul vero HumanIndividual (_find_human_individual_by_id, stessa scansione lineare
# già in uso altrove) e RIUSA _on_population_individual_center_requested TALE E QUALE (nessuna
# logica nuova qui): STESSO comportamento "deseleziona tutto -> seleziona il bersaglio -> lo rende
# il nuovo individuo controllato (_set_movement_target) -> centra la camera" già dietro al bottone
# "🎯" per-riga del pannello popolazione — un residente cliccato qui si comporta esattamente come
# se fosse stato cliccato lì, nessuna variante "solo centra senza selezionare" inventata apposta.
# individual_id non risolvibile (residente morto/rimosso nel frattempo tra la creazione della
# griglia e il click, caso limite) -> no-op silenzioso, mai un crash.
#
# TODO (2026-09-12, richiesta utente — "ancora il vai a individuo chiamato dal pannello vista
# edificio, rallenta molto... lascia un commento per ora, lo risolviamo più avanti"): NON ancora
# risolto, nessuna indagine ulteriore in questo giro (esplicitamente rimandata). Il bug del
# pannello Edifici (_recenter_live_cells_on che corrompeva individual.position, vedi
# _on_buildings_panel_center_requested sotto) è stato trovato e corretto, ma QUESTO percorso
# (residente cliccato dentro BuildingInfoPanel) chiama _on_population_individual_center_requested
# TALE E QUALE — la stessa funzione del bottone "🎯" del pannello popolazione, senza quella
# corruzione — eppure il rallentamento persiste secondo l'utente. I log [CENTER DEBUG] (vedi
# _on_population_individual_center_requested/_recenter_live_cells_on) sono già in place per
# quando si riprenderà l'indagine: confermeranno se si tratta solo del costo legittimo di
# _reposition_live_cells quando il residente è lontano dal centro corrente, o se c'è dell'altro
# non ancora scoperto.
func _on_building_resident_center_requested(individual_id: int) -> void:
	var target := _find_human_individual_by_id(individual_id)
	if target == null:
		return
	_on_population_individual_center_requested(target, "building_resident")


# Reazione a BuildingsInfoPanel.building_center_requested (2026-09-12, richiesta utente — "info
# panel edifici... con il bottoncino di vai lì come per le persone").
#
# BUGFIX (2026-09-12, richiesta utente — "lo scatto ferma anche il conteggio dei giorni per un
# attimo, mentre da pannello population non avviene, indaga meglio"): la prima versione chiamava
# QUI _recenter_live_cells_on(macro_coords), copiando il pattern di _set_movement_target — SBAGLIATO
# per un edificio, causa REALE trovata leggendo il codice:
#
# 1) INUTILE — la macrocella di un edificio è GIÀ permanentemente viva, per costruzione: non puoi
#    piazzare un edificio su terreno non visibile (quindi la sua cella è già live al momento del
#    piazzamento — vedi _place_building_at/_start_building_task_at), e _update_live_neighbor
#    (sopra) non disattiva MAI una cella che _macro_cell_has_buildings() trova vera. Nessun
#    ricaricamento serve MAI per raggiungere un edificio — a differenza di un individuo dalla
#    lista Population, che PUÒ trovarsi in una macrocella non ancora live.
#
# 2) DANNOSO — _recenter_live_cells_on riassegna center_macro_coords SENZA mai toccare `individual.
#    position` (che resta espresso nello spazio locale del VECCHIO centro). Nel percorso
#    _set_movement_target questo è innocuo perché individual VIENE RIASSEGNATO subito dopo
#    (individual = target), il cui .position è per costruzione già valido nel nuovo centro — qui
#    invece `individual` resta lo stesso individuo di prima, il cui .position numerico ora NON
#    rappresenta più nulla di coerente rispetto al nuovo center_macro_coords.
#    _update_live_neighbor (chiamata ogni frame da _process) usa PROPRIO individual.position per
#    decidere quali vicini attivare/disattivare (_compute_relevant_neighbor_offsets) — con un
#    centro sbagliato sotto i piedi, quei calcoli producono distanze incoerenti che possono
#    innescare un'attivazione/disattivazione di PIÙ celle contemporaneamente (invece del solito
#    scorrimento di una cella alla volta durante una camminata normale), un lavoro sincrono
#    potenzialmente pesante (rigenerazione vegetazione/pietre/MultiMesh per cella) — RIPETUTO ogni
#    frame finché lo stato non si risistema da sé. Questo spiega sia lo scatto camera SIA il "si
#    ferma il conteggio dei giorni": GameClockController._process (l'unico accumulatore del
#    calendario) condivide lo stesso main thread — un frame bloccato da questo lavoro sincrono
#    blocca ANCHE il rendering dell'etichetta giorno, che sembra "fermarsi" per la stessa durata,
#    pur non essendo un problema del calendario in sé.
#
# FIX: nessun _recenter_live_cells_on qui — _select_building trova già la cella viva (per il
# punto 1 sopra), poi _center_camera_on_selection() calcola la posizione ESATTA sullo schermo
# (building_cell.renderer.get_building_screen_position + offset rispetto al center_macro_coords
# CORRENTE, mai cambiato) e anima un tween puro — stessa identica meccanica, stesso costo, di un
# click diretto su un edificio già visibile: nessuna ricostruzione di celle, nessun frame bloccato.
func _on_buildings_panel_center_requested(building: Building) -> void:
	if building == null:
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	_select_building({"macro_coords": macro_coords, "building_id": building.id})
	_center_camera_on_selection()


# ============================================================================================
# Selezione di una posizione STONE — 2026-09-08, richiesta utente. Struttura gemella di
# _select_building/_clear_building_selection/_refresh_building_panel sopra: StoneInfoPanel mostra
# la quantità pebble esatta di quella posizione + lo stone aggregato della macrocella come
# contesto, risolti direttamente da MacroCellState (nessun oggetto "Stone" a sé, a differenza di
# Building — solo una posizione + due lookup) — questo pannello, come gli altri quattro, riceve
# solo dati già risolti.
# ============================================================================================

func _select_stone(hit: Dictionary) -> void:
	# Evidenziazione sulla mappa (2026-09-08, richiesta utente — mancava, a differenza di
	# vegetazione/edifici) — stesso schema del ciclo in _select_building: accende il contorno solo
	# sul renderer della cella del match, lo spegne su ogni altra cella viva.
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		if coords == hit["macro_coords"]:
			cell.renderer.set_selected_stone(hit["position"])
		else:
			cell.renderer.clear_selected_stone()

	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_vegetation_selection()
	_clear_building_selection()
	_clear_dead_body_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
	_clear_stick_lot_selection()
	_clear_microcell_selection()

	selected_stone = hit
	_selection_kind = SelectionKind.STONE
	_refresh_stone_panel()
	game_info_tabs.show_selection_tab()


func _clear_stone_selection() -> void:
	if selected_stone.is_empty():
		return
	selected_stone = {}
	_selection_kind = SelectionKind.NONE
	for cell in live_cells.values():
		if cell.renderer != null:
			cell.renderer.clear_selected_stone()
	stone_info_panel.clear()
	game_info_tabs.hide_selection_tab()


# Legge SOLO resource_quantity[ROCK] (aggregato dell'INTERA macrocella) — RIVISTO 2026-09-16,
# richiesta utente: la quantità ESATTA della singola posizione (pebble_quantities) non è più
# mostrata qui, solo tramite l'ispezione a doppio click (vedi StoneInfoPanel.gd). Nessuna gestione
# "marker bloccato": STONE non ha ancora un modo di sparire (nessun consumo implementato), stesso
# principio già dichiarato per gli edifici in _refresh_building_panel — l'unica via di
# invalidazione oggi resta lo scaricamento della macrocella, guardia difensiva sotto.
func _refresh_stone_panel() -> void:
	var cell: LiveMacroCell = live_cells.get(selected_stone["macro_coords"])
	if cell == null or cell.macro_state == null:
		_clear_stone_selection()
		return
	# "pos"/pebble_quantity ESATTO della singola posizione NON PIÙ letto qui (2026-09-16, richiesta
	# utente — vedi StoneInfoPanel.gd): quel dato resta comunque disponibile, ma solo tramite
	# l'ispezione a doppio click, non più nel pannello di selezione singola.
	var zone_stone_quantity: int = cell.macro_state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
	stone_info_panel.show_stone(zone_stone_quantity)
	game_info_tabs.set_selection_title(tr("selection_title_type").format({"type": tr("stone_selection_title")}))


# Assegna a `individual` (il bersaglio correntemente selezionato) una Task Walk->PickUp verso una
# posizione raccoglibile (2026-09-09, richiesta utente, Step 5/6 piano raccolta/trasporto — dal
# 2026-09-09 richiamata dal comando destro-click, vedi _try_assign_pickup_command_on_right_click
# sotto, non più da un'attivazione sinistro-click). Generalizzata su
# macro_coords/target_position/resource_name espliciti invece di un `hit: Dictionary` grezzo:
# StoneSelectorController.try_select e StickLotSelectorController.try_select tornano forme diverse
# ({"position"} vs {"lot"} per la stessa idea di "dove"), quindi ogni chiamante estrae il proprio
# campo e passa qui solo i tre valori già risolti — nessuna conoscenza della forma dell'hit
# necessaria in questa funzione, nessun secondo hit-test.
#
# macro_state: risolto da live_cells[macro_coords].macro_state — stesso identico riferimento che
# _refresh_stone_panel/_refresh_stick_lot_panel sopra usano per leggere pebble_quantities/
# stick_quantities, sempre disponibile a questo punto perché né stone_hit né stick_lot_hit possono
# vincere senza una cella viva con macro_state valido (vedi StoneSelectorController/
# StickLotSelectorController.try_select, che scartano ogni cella con macro_state == null).
#
# Nessun controllo sulla quantità disponibile alla posizione/lotto cliccato (richiesta esplicita
# utente, valida per entrambe le risorse): PickUpAction gestisce già il caso quantità 0
# (completamento immediato senza effetto, Step 2) — assegnare comunque la Task su una posizione già
# svuotata (una roccia già raccolta, un lotto senza alberi maturi) è un comportamento valido, il
# player semplicemente non ottiene nulla, nessuna logica aggiuntiva necessaria qui per intercettarlo
# prima.
func _assign_pickup_task(macro_coords: Vector2i, target_position: Vector2i, resource_name: String) -> void:
	var cell: LiveMacroCell = live_cells.get(macro_coords)
	if cell == null or cell.macro_state == null:
		return

	# TaskFactory.build_task (2026-09-10, richiesta utente — estensione TaskFactory per PICKUP)
	# SOSTITUISCE la costruzione manuale [WalkAction, PickUpAction] di prima: task_name/
	# step_descriptions/action_type per step arrivano ora da HAUL_RESOURCE_TASK_DEFINITION_PATH
	# (.tres, vedi gameplay/scripts/tasks/definitions/haul_resource.tres) invece che hardcoded qui —
	# stesse identiche chiavi tr() già in uso prima ("task_haul_resource_name"/_step_walk/_step_pickup,
	# vedi translations/strings.csv), solo la loro fonte cambia. La risoluzione del TARGET (qual è la
	# posizione pebble/stick, risolta dal chiamante di questa funzione) resta invariata, fuori da
	# questa funzione — TaskFactory non risolve target, solo costruisce Action dai valori già decisi
	# che gli vengono passati in `context`.
	#
	# Solo i primi due step [Walk, PickUp] nascono qui — invariato rispetto a prima: il resto della
	# catena (ricerca magazzino/Unload/"cammina via") continua a crescere a runtime via
	# Task.append_steps, guidato da context["pending_warehouse_search"]/["pending_walk_away_position"]
	# (vedi HumanIndividualActionService._handle_pending_warehouse_search/_handle_pending_walk_away) —
	# NON toccato da questo passo, funziona identico sia che i primi due step vengano da qui sia da
	# TaskFactory: quel meccanismo legge/scrive solo task.context, ignaro di come i suoi step siano
	# nati.
	var haul_resource_definition := load(HAUL_RESOURCE_TASK_DEFINITION_PATH) as TaskDefinition
	# DUE chiavi separate per la STESSA posizione logica (2026-09-10) — WalkAction._init vuole un
	# Vector2 (target), PickUpAction._init vuole un Vector2i (target_position): TaskFactory è
	# generica e passa context[chiave] così com'è al costruttore, senza conversioni implicite (e
	# GDScript non converte automaticamente Vector2i<->Vector2 su un parametro tipizzato) — una sola
	# chiave condivisa con un solo tipo concreto avrebbe fatto fallire la costruzione di uno dei due
	# step. "target_position" (Vector2) per WALK, "pickup_position" (Vector2i, il parametro originale
	# invariato) per PICKUP — vedi step_walk_to_position.tres/step_pickup_from_position.tres per
	# quale step legge quale chiave.
	#
	# Nessun erase() manuale qui dopo la chiamata a build_task (2026-09-10 — PRIMA di questo passo
	# c'era, vedi git blame): TaskFactory.build_task ora ripulisce DA SÉ, dopo la costruzione, tutte
	# le chiavi elencate nei context_keys dei propri step (vedi task_factory.gd, consumed_context_
	# keys) — struttura spostata lì così ogni futuro chiamante di build_task la ottiene gratis, senza
	# doversene ricordare (era il rischio esplicito di questa versione precedente: un erase() lato
	# chiamante, facile da dimenticare in una nuova Task futura).
	var context: Dictionary = {
		"target_position": Vector2(target_position),
		"pickup_position": target_position,
		"macro_state": cell.macro_state,
		"resource_name": resource_name,
	}
	var task := TaskFactory.build_task(haul_resource_definition, context)

	# task.step_appended (2026-09-12, richiesta utente — bugfix "il mucchietto non si aggiorna in
	# automatico quando viene fatto il deposito"): STESSO pattern di _debug_test_daydream_task sopra
	# (che copre solo la Task Daydream/ramo pensiero) — qui per la VERA catena di produzione
	# haul_resource, il cui UnloadAction (ramo FISICO, DepositKind.RESOURCE) non esiste ancora a
	# questo punto: nasce più tardi, dinamicamente, quando PickUpAction completa e
	# HumanIndividualActionService._handle_pending_warehouse_search lo accoda alla Task — vedi lì per
	# la costruzione `UnloadAction.new(candidate, UnloadAction.DepositKind.RESOURCE)`. Senza questo
	# listener, resource_deposited (vedi unload_action.gd) non avrebbe mai un ascoltatore per il
	# percorso di gioco reale, solo per il comando manuale "scarica qui"
	# (_try_assign_unload_command_on_right_click) — la griglia di stoccaggio del deposit site non si
	# sarebbe mai rinfrescata da sola dopo un haul_resource completo.
	task.step_appended.connect(func(action: Action) -> void:
		if action is UnloadAction:
			_reconnect_unload_action_signals(action as UnloadAction, individual)
	)

	# Rinfresca pebble/stick di QUESTA cella non appena la raccolta è davvero avvenuta (2026-09-09,
	# richiesta utente, bugfix "restano disegnati dopo la raccolta") — stesso principio già in uso
	# per UnloadAction.idea_completed/thought_deposited: PickUpAction non conosce il renderer, si
	# limita a segnalare l'evento, chi ha creato la Task (qui) decide come reagire. Rebuild
	# dell'intera macrocella (non solo la posizione raccolta — _refresh_resource_visuals non supporta
	# un aggiornamento per singola posizione), ma economico: poche decine di posizioni pebble/stick
	# per macrocella, stesso principio già accettato per il rebuild vegetazione (VegetationPosition
	# Service), solo su un numero di individui molto più piccolo.
	#
	# La PickUpAction non è più una variabile locale creata qui (nasce dentro TaskFactory.build_task)
	# — recuperata dagli step della Task risultante per tipo, non per indice fisso: più robusto se in
	# futuro haul_resource.tres guadagnasse step opzionali prima del PickUp (nessun caso oggi, ma
	# nessuna assunzione fragile sull'indice 1 necessaria per ottenere lo stesso risultato).
	#
	# _reconnect_pickup_action_signals riusata TALE E QUALE (2026-09-11, richiesta utente — chiudere
	# il gap gemello di SetupSite/Clear/Unload: "dopo un reload i signal non vengono ricollegati")
	# invece di connettere qui un lambda che catturi `cell`: `cell` NON è bindato al momento della
	# creazione, la funzione condivisa lo risolve da sé (da step.macro_state) al momento in cui
	# resource_collected emette DAVVERO, così questo stesso punto e _reconnect_loaded_task_signals
	# (dopo un reload, dove `cell` non sarebbe nemmeno disponibile: live_cells non è ancora popolato
	# dentro _ready()) non possono disallinearsi.
	for step in task.steps:
		if step is PickUpAction:
			_reconnect_pickup_action_signals(step as PickUpAction)
			break

	# Icona letta da IconRegistry (2026-09-11, richiesta utente — generalizzazione del meccanismo di
	# lampeggio: prima "✋" era hardcoded dentro _spawn_pickup_command_effect, ora vive nel registro
	# centrale insieme a tutte le altre icone, vedi IconRegistry.COMMAND_ICONS) — TRIGGER invariato:
	# ancora SUBITO al click destro (non a PickUpAction.activate()), stesso motivo di sempre — il
	# player deve vedere da dove è partita la Task anche mentre l'individuo sta ancora camminando.
	#
	# "❌" se il guard di assign_task rifiuta (2026-09-13, richiesta utente — bugfix: prima la
	# "manina" appariva comunque anche quando la Task non partiva mai, es. INFANT) — assign_task ora
	# ritorna bool, catturato qui per scegliere l'icona giusta invece di assumere sempre successo.
	var assigned := individual.assign_task(task, _resolve_age_band(individual))
	var command_icon_key := "pickup" if assigned else "task_rejected"
	_spawn_command_blink_effect(cell, target_position, IconRegistry.get_command_icon(command_icon_key))


# Numero di lampeggi e durata di ciascuna metà-ciclo (buio->chiaro o chiaro->buio) dell'effetto
# "lampeggio comando" sotto — BLINK_COUNT × BLINK_HALF_DURATION × 2 = durata totale visibile
# (2026-09-09, richiesta utente "lasciala lampeggiare un paio di secondi"): 5 × 0.2s × 2 = 2.0s
# esatti. GENERALIZZATE (2026-09-11, richiesta utente — "generalizza il metodo e cambia solo
# l'icona": prima solo per l'effetto "manina" di PickUpAction, ora condivise da qualunque icona
# registrata in IconRegistry.COMMAND_ICONS, vedi _spawn_command_blink_effect sotto) — RINOMINATE da
# PICKUP_COMMAND_EFFECT_* (nessun cambio di valore, solo il nome non è più specifico di un solo
# consumatore).
const COMMAND_BLINK_EFFECT_BLINK_COUNT: int = 5
const COMMAND_BLINK_EFFECT_BLINK_HALF_DURATION: float = 0.2


# Effetto "usa e getta" (2026-09-09, richiesta utente — nato come "una piccola manina che raccoglie
# sulla cella per far capire che faccio pick up lì", GENERALIZZATO 2026-09-11 a icona parametrica —
# vedi nota sopra) — stesso principio di _spawn_idea_deposit_effect sopra (puro codice, nessun
# .tscn, nessuno stato persistito). SUL BERSAGLIO (target_position), non sull'individuo, e SUBITO al
# momento in cui il comando viene impartito (mai quando l'individuo arriva a destinazione dopo aver
# camminato — RICHIESTA ESPLICITA UTENTE, 2026-09-11: "il martello deve comparire quando parte la
# task, non quando arriva il pipottino... anche per haul service la manina appare subito... credo
# serva coerenza" — un primo tentativo per il martello lo faceva lampeggiare all'arrivo, tramite un
# segnale Action.activated poi rimosso, vedi Action.gd/IconRegistry.COMMAND_ICONS per lo storico):
# ogni chiamante di questa funzione la invoca nello stesso identico istante in cui assegna la Task
# (individual.assign_task), mai in un secondo momento.
#
# NIENTE modulate colorato (bugfix 2026-09-09, richiesta utente — "non sembra nemmeno più una
# mano": un tentativo precedente tingeva il glifo d'azzurro via modulate, ma le emoji sono bitmap
# a colori propri — moltiplicare quei pixel per un blu ne rovinava la sagoma fino a renderla
# irriconoscibile. Colori nativi dell'emoji, nessun modulate custom) — vale per QUALUNQUE icona
# passata qui, non solo ✋.
#
# DENTRO la cella bersaglio, non sopra di essa (bugfix 2026-09-09, richiesta utente — "quando dico
# sopra intendo all'interno, sopra nella vista dall'alto": il tentativo precedente, un'intera
# CELL_SIZE più in alto del bordo superiore, finiva visivamente FUORI dal riquadro 10×10 della
# microcella, non solo "sopra" in senso di vista dall'alto). Riquadro allineato esattamente sulla
# cella (size/position = target_position × CELL_SIZE, nessun offset di riquadro), centrato sia
# orizzontalmente che verticalmente al suo interno via horizontal_alignment/vertical_alignment.
#
# clip_contents = true (secondo bugfix 2026-09-09, richiesta utente — "ancora leggermente fuori in
# basso a destra": il primo tentativo si affidava solo a un piccolo offset di compensazione per
# correggere la metrica asimmetrica del font emoji, insufficiente) — GARANZIA STRUTTURALE che il
# glifo non venga MAI disegnato fuori dal riquadro 10×10, qualunque sia la metrica reale del font
# (Control.clip_contents ritaglia il disegno di questo nodo al proprio rect, non solo quello di
# eventuali figli) — non dipende più dall'azzeccare esattamente l'offset per restare "dentro".
# COMMAND_BLINK_EFFECT_VISUAL_OFFSET sotto resta comunque per la centratura VISIVA fine — terzo
# giro di ritocco (richiesta utente, 2026-09-09: "ancora in basso a destra" dopo -1.5,-1.5, portato
# a -4,-5) — valore ARBITRARIO, stesso trattamento "da bilanciare" di ogni altra costante visiva di
# questo sistema, TARATO su ✋ — un'icona con metrica molto diversa (es. 🔨) potrebbe volere un
# ritocco proprio in futuro, oggi condiviso perché "abbastanza vicino" a occhio in entrambi i casi.
#
# Lampeggio via Tween.set_loops (alterna alpha 1.0<->0.15, COMMAND_BLINK_EFFECT_BLINK_COUNT volte)
# invece di una singola dissolvenza lineare come _spawn_idea_deposit_effect: qui la richiesta
# esplicita è "lampeggiare", non "svanire" — un segnale intermittente più simile a un marker
# temporaneo che a un effetto di particelle. chain().tween_callback(free) al termine, stesso
# principio di pulizia automatica già in uso sopra.
const COMMAND_BLINK_EFFECT_VISUAL_OFFSET: Vector2 = Vector2(-4.0, -5.0)

func _spawn_command_blink_effect(cell: LiveMacroCell, target_position: Vector2i, icon: String) -> void:
	if icon == "":
		return
	var label := Label.new()
	label.text = icon
	label.z_index = 2
	label.clip_contents = true
	label.add_theme_font_size_override("font_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(MicroCellRenderer.CELL_SIZE, MicroCellRenderer.CELL_SIZE)
	label.position = Vector2(target_position) * MicroCellRenderer.CELL_SIZE + COMMAND_BLINK_EFFECT_VISUAL_OFFSET
	cell.container.add_child(label)

	var tween := create_tween()
	tween.set_loops(COMMAND_BLINK_EFFECT_BLINK_COUNT)
	tween.tween_property(label, "modulate:a", 0.15, COMMAND_BLINK_EFFECT_BLINK_HALF_DURATION)
	tween.tween_property(label, "modulate:a", 1.0, COMMAND_BLINK_EFFECT_BLINK_HALF_DURATION)
	tween.chain().tween_callback(label.queue_free)


# Comando "vai e raccogli" via DESTRO (2026-09-09, richiesta utente — sostituisce l'attivazione via
# SINISTRO di Step 5/6: quel percorso condivideva il tasto con la selezione — click su un lotto già
# selezionato che diventava improvvisamente un comando in base a uno stato nascosto, `individual.
# is_selected` — ed era per di più spesso "rubato" dalla vegetazione, dato che un lotto stick
# coincide fisicamente con la microcella dell'albero). Richiamata da _unhandled_input PRIMA di
# individual_controller.handle_input (il movimento normale), il cui esito booleano decide se il
# movimento normale va saltato per QUESTO evento (true = comando consumato) o eseguito come sempre
# (false = nessun bersaglio raccoglibile qui, o nessun individuo selezionato).
#
# STONE prima di STICK_LOT (stesso ordine di priorità già in uso nel match map_hit_kind sopra per
# il sinistro) — required_button=MOUSE_BUTTON_RIGHT passato esplicitamente a entrambi i
# *SelectorController (default LEFT, per il loro chiamante di selezione esistente, invariato).
# Stesso gate `individual.is_selected` già usato da HumanIndividualController._try_set_target per
# il movimento normale: nessun individuo selezionato -> nessun comando possibile, comportamento
# coerente col resto del destro-click.
func _try_assign_pickup_command_on_right_click(event: InputEvent) -> bool:
	# Guard di tipo evento (2026-09-10, richiesta utente — BUGFIX log: senza questo, il corpo della
	# funzione — hit-test E i log di debug sotto — girava su OGNI evento _unhandled_input, incluso
	# InputEventMouseMotion ad ogni frame di movimento del mouse, non solo sul vero click destro:
	# stone_selector_controller.try_select/stick_lot_selector_controller.try_select filtrano già
	# internamente per tipo/pulsante come primissima riga — vedi StoneSelectorController.gd/
	# StickLotSelectorController.gd — quindi l'HIT-TEST stesso non aveva mai avuto un problema di
	# correttezza/performance reale (ritorna {} immediato per un motion event); il flooding era
	# interamente nei print di debug aggiunti in questo giro, che stavano PRIMA/DOPO quel filtro
	# interno e quindi lo ignoravano. Stesso identico filtro già usato da quei *SelectorController,
	# duplicato qui come guardia esplicita in testa alla funzione — non un fix di un bug preesistente
	# nella logica reale, solo la causa del flooding dei log.
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	# LOG DEBUG TEMPORANEO (2026-09-10, richiesta utente — indagine bug Build Task/pickup) — DA
	# RIMUOVERE una volta chiuso il bug.
	if individual == null or not individual.is_selected:
		if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[PICKUP CMD DEBUG] _try_assign_pickup_command_on_right_click: ritorna false (individual null o non selezionato).")
		return false

	# Fog of War (2026-09-13, richiesta utente — bugfix: un hit valido sui dati grezzi non basta più,
	# la microcella deve anche essere visibile con DETTAGLIO sufficiente — stesso tier is_detail_
	# fresh usato da FogOfWarRenderer per decidere se disegnare la risorsa affatto, mai consultato
	# finora da questo comando) — un hit che fallisce questo controllo viene trattato ESATTAMENTE
	# come "nessun hit trovato qui" (nessun return anticipato, si prosegue al candidato successivo/
	# al fallback finale), mai un errore o un comportamento diverso dal caso "niente sotto il click".
	var current_absolute_day := game_data.get_absolute_day()

	# Lista generica di candidati (2026-09-16, richiesta utente — Step 4 del piano plant_fiber) —
	# SOSTITUISCE la vecchia catena fissa "stone, poi stick, poi false" con una lista costruita da
	# _resolve_pickup_candidates, in ORDINE DI PRIORITÀ (stone, stick, plant_fiber — STESSO ordine
	# di prima, invariato: aggiungere un futuro quarto candidato richiede solo una nuova riga in
	# quella funzione). Nessun popup ancora (arriva in un passo successivo): con 0 candidati nessun
	# comando (comportamento invariato); con 1 candidato haul immediata (comportamento invariato,
	# indistinguibile da prima anche nel log); con 2+ candidati comportamento PROVVISORIO — vince
	# comunque il primo in ordine di priorità (STESSO esito che avresti avuto con la vecchia catena
	# fissa), ma ora loggato esplicitamente con [DBG_PICKUP] cosa c'era davvero sotto il click.
	var candidates: Array[Dictionary] = _resolve_pickup_candidates(event, current_absolute_day)
	if candidates.is_empty():
		if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[PICKUP CMD DEBUG] _try_assign_pickup_command_on_right_click: ritorna false (nessuna risorsa al click).")
		return false

	if candidates.size() > 1 and DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
		var candidate_descriptions: Array[String] = []
		for candidate in candidates:
			candidate_descriptions.append("%s(disponibile=%d)" % [candidate["resource_name"], candidate["available_quantity"]])
		print("[DBG_PICKUP] %d candidati alla stessa posizione: %s — priorità provvisoria (vince il primo, nessun popup ancora)." % [
			candidates.size(), ", ".join(candidate_descriptions)
		])

	var chosen: Dictionary = candidates[0]
	if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
		print("[PICKUP CMD DEBUG] _try_assign_pickup_command_on_right_click: ritorna TRUE — %s_hit=%s" % [chosen["resource_name"], str(chosen)])
	_assign_pickup_task(chosen["macro_coords"], chosen["position"], chosen["resource_name"])
	return true


# Costruisce la lista di candidati raccoglibili nella posizione del click, in ORDINE DI PRIORITÀ
# (2026-09-16, richiesta utente — Step 4) — un dict per candidato: {"resource_name", "macro_coords",
# "position", "available_quantity"}. Ogni voce ripete lo STESSO schema (hit-test del proprio
# *SelectorController + verifica FogOfWarVerificationService.is_detail_visible, ESATTAMENTE come
# prima di questo passo — un hit che fallisce la visibilità non entra in lista, stesso trattamento
# "nessun hit qui" di sempre). Aggiungere una futura risorsa scattered richiede solo un nuovo blocco
# qui, nessuna modifica al chiamante sopra.
#
# TUTTI i candidati leggono solo DATI (stone_positions/pebble_quantities via StoneSelectorController,
# tree_claimed_lots via StickLotSelectorController, shrub_claimed_lots via
# PlantFiberLotSelectorController — mai il renderer per altro che il calcolo della posizione del
# mouse), richiesta esplicita utente: plant_fiber non ha un proprio layer grafico, il click deve
# funzionare cliccando sugli arbusti disegnati per la vegetazione, non su un oggetto plant_fiber-
# specifico che non esiste.
#
# `required_button` (2026-09-16, richiesta utente — ispezione microcella doppio click) — default
# MOUSE_BUTTON_RIGHT invariato per il chiamante esistente (_try_assign_pickup_command_on_right_click,
# Step 4). L'ispezione con doppio click SINISTRO passa MOUSE_BUTTON_LEFT qui: STESSA fonte di verità
# richiesta esplicitamente dall'utente ("_resolve_pickup_candidates o una sua estrazione comune"),
# nessuna duplicazione tra "cosa posso raccogliere col destro" e "cosa mostro nell'ispezione".
func _resolve_pickup_candidates(event: InputEvent, current_absolute_day: int, required_button: int = MOUSE_BUTTON_RIGHT) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	var stone_hit := stone_selector_controller.try_select(event, live_cells, required_button)
	if not stone_hit.is_empty():
		if FogOfWarVerificationService.is_detail_visible(live_cells, stone_hit["macro_coords"], stone_hit["position"], current_absolute_day):
			candidates.append(_build_pickup_candidate("pebble", stone_hit["macro_coords"], stone_hit["position"]))
		elif DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[PICKUP CMD DEBUG] stone_hit=%s trovato ma cella non visibile con dettaglio, ignorato." % str(stone_hit))

	var stick_lot_hit := stick_lot_selector_controller.try_select(
		event, live_cells, required_button, macro_world.buildings if macro_world != null else []
	)
	if not stick_lot_hit.is_empty():
		if FogOfWarVerificationService.is_detail_visible(live_cells, stick_lot_hit["macro_coords"], stick_lot_hit["lot"], current_absolute_day):
			candidates.append(_build_pickup_candidate("stick", stick_lot_hit["macro_coords"], stick_lot_hit["lot"]))
		elif DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[PICKUP CMD DEBUG] stick_lot_hit=%s trovato ma cella non visibile con dettaglio, ignorato." % str(stick_lot_hit))

	var plant_fiber_lot_hit := plant_fiber_lot_selector_controller.try_select(
		event, live_cells, required_button, macro_world.buildings if macro_world != null else []
	)
	if not plant_fiber_lot_hit.is_empty():
		if FogOfWarVerificationService.is_detail_visible(live_cells, plant_fiber_lot_hit["macro_coords"], plant_fiber_lot_hit["lot"], current_absolute_day):
			candidates.append(_build_pickup_candidate("plant_fiber", plant_fiber_lot_hit["macro_coords"], plant_fiber_lot_hit["lot"]))
		elif DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[PICKUP CMD DEBUG] plant_fiber_lot_hit=%s trovato ma cella non visibile con dettaglio, ignorato." % str(plant_fiber_lot_hit))

	return candidates


# available_quantity (2026-09-16) — SOLO informativo per ora (log [DBG_PICKUP]/futuro popup di
# scelta): TerrainScatteredResourceService.get_available è la STESSA fonte di verità già usata da
# PickUpAction/TerrainScatteredResourceService.consume, nessun secondo calcolo. macro_state assente
# (cella non più viva tra l'hit-test e questa chiamata, caso limite) -> 0, mai un crash.
func _build_pickup_candidate(resource_name: String, macro_coords: Vector2i, position: Vector2i) -> Dictionary:
	var cell: LiveMacroCell = live_cells.get(macro_coords)
	var macro_state: MacroCellState = cell.macro_state if cell != null else null
	var available_quantity: int = TerrainScatteredResourceService.get_available(macro_state, resource_name, position) if macro_state != null else 0
	return {
		"resource_name": resource_name,
		"macro_coords": macro_coords,
		"position": position,
		"available_quantity": available_quantity,
	}


# Risolve in quale lotto/macrocella è caduto il click CORRENTE (2026-09-16, richiesta utente —
# ispezione microcella) — STESSA tecnica di StickLotSelectorController/PlantFiberLotSelectorController
# (cell.renderer.get_local_mouse_position(), mai il pixel disegnato) ma SENZA controllare alcuna
# Dictionary di "rivendicazione": qui serve sapere QUALE microcella è stata cliccata anche se è
# completamente vuota (per poter poi dire "Cella senza risorse"), a differenza di quei due
# controller che rispondono {} su un lotto non rivendicato. Bounds check esplicito (0..World.WIDTH/
# HEIGHT) al posto di un .has() su una Dictionary — è il modo con cui questa funzione scarta le
# celle vive che NON sono quella sotto il mouse (la loro local_mouse_position cade fuori range).
# {} se il click non cade in nessuna cella viva (fuori mappa/su un elemento UI, che comunque non
# genera _unhandled_input).
func _resolve_microcell_at_click() -> Dictionary:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		var click_lot := Vector2i(int(floor(local_mouse.x / MicroCellRenderer.CELL_SIZE)), int(floor(local_mouse.y / MicroCellRenderer.CELL_SIZE)))
		if click_lot.x < 0 or click_lot.x >= World.WIDTH or click_lot.y < 0 or click_lot.y >= World.HEIGHT:
			continue
		return {"macro_coords": coords, "lot": click_lot}
	return {}


# Ispezione microcella (2026-09-16, richiesta utente — doppio click sinistro, "cosa contiene questa
# cella") — SOLO informativa, NESSUNA assegnazione di Task/chiamata a _assign_pickup_task: funziona
# ANCHE senza un individuo selezionato (a differenza del click destro raccolta, che richiede
# individual.is_selected). Riusa _resolve_pickup_candidates passando MOUSE_BUTTON_LEFT come
# required_button — STESSA fonte di verità del click destro (richiesta esplicita utente), nessuna
# duplicazione tra "cosa posso raccogliere" e "cosa mostro nell'ispezione". Vegetazione (TREE/SHRUB/
# GRASS) letta da cell.renderer.vegetation_positions (Dictionary[WorldObjectType, Array[Vector2i]]
# di posizioni-GRIGLIA, non pixel — STESSA fonte già usata da GameScene per "is_currently_grass" in
# _try_assign_build_command_on_right_click/_debug_test_two_walk_task... vedi i due usi esistenti,
# righe ~3248/~6052 — mai disegno/rendering: è l'unico modo di sapere "c'è GRASS qui" perché GRASS
# non ha un equivalente di tree_claimed_lots/shrub_claimed_lots persistito per-lotto).
func _handle_microcell_inspection_double_click(event: InputEvent) -> void:
	var hit := _resolve_microcell_at_click()
	if hit.is_empty():
		return
	var macro_coords: Vector2i = hit["macro_coords"]
	var lot: Vector2i = hit["lot"]

	var current_absolute_day := game_data.get_absolute_day()

	# Fog of War (richiesta esplicita utente — mantenere il controllo): STESSO tier "dettaglio"
	# già usato da _try_assign_pickup_command_on_right_click/_resolve_pickup_candidates. Anche non
	# visibile la cella VIENE COMUNQUE selezionata (richiesta esplicita utente, punto 2: "qualunque
	# cosa ci sia sotto il cursore... il risultato finale deve essere la selezione della microcella")
	# — solo il contenuto mostrato cambia, un messaggio unico invece del report normale.
	if not FogOfWarVerificationService.is_detail_visible(live_cells, macro_coords, lot, current_absolute_day):
		_select_microcell({"macro_coords": macro_coords, "lot": lot, "lines": [tr("microcell_inspection_not_visible")]})
		return

	# Edificio/cantiere sulla cella (2026-09-16, richiesta utente) — SOLO messaggio dedicato, NESSUN
	# elenco risorse/vegetazione in questo caso (un edificio ha già consumato/ripulito quel lotto via
	# BuildingSiteClearingService, quindi sarebbe comunque vuoto — ma qui evitiamo di mostrare "Cella
	# senza risorse", fuorviante su una cella che in realtà un contenuto ce l'ha, solo non ispezionabile
	# da qui). La cella resta comunque quella selezionata (_select_microcell sotto), MAI l'edificio —
	# per i dettagli dell'edificio resta il click SINGOLO su di esso (_select_building, invariato).
	if _find_building_at_microcell(macro_coords, lot) != null:
		_select_microcell({"macro_coords": macro_coords, "lot": lot, "lines": [tr("microcell_inspection_building_occupied")]})
		return

	var candidates: Array[Dictionary] = _resolve_pickup_candidates(event, current_absolute_day, MOUSE_BUTTON_LEFT)
	# Filtro difensivo sul lotto esatto (2026-09-16) — _resolve_pickup_candidates cerca già solo
	# dentro la macrocella/posizione sotto il mouse di QUESTO stesso evento, quindi in pratica ogni
	# candidato ritornato è già su (macro_coords, lot); questo filtro non cambia mai nulla in
	# pratica, resta solo come guardia esplicita invece di fidarsi implicitamente.
	var lot_candidates: Array[Dictionary] = []
	for candidate in candidates:
		if candidate["macro_coords"] == macro_coords and candidate["position"] == lot:
			lot_candidates.append(candidate)

	var cell: LiveMacroCell = live_cells.get(macro_coords)
	var vegetation_positions: Dictionary = cell.renderer.vegetation_positions if cell != null and cell.renderer != null else {}
	var tree_present: bool = vegetation_positions.get(GameTypes.WorldObjectType.TREE, []).has(lot)
	var shrub_present: bool = vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []).has(lot)
	var grass_present: bool = vegetation_positions.get(GameTypes.WorldObjectType.GRASS, []).has(lot)

	var lines: Array[String] = []
	if lot_candidates.is_empty() and not tree_present and not shrub_present and grass_present:
		# Solo erba, nessuna risorsa raccoglibile (richiesta esplicita utente) — messaggio unico,
		# sostituisce la doppia sezione risorse/vegetazione sotto (sarebbe stata "Risorse: (nessuna)"
		# + "Vegetazione: Erba", più rumoroso del necessario per il caso più comune di tutti).
		lines.append(tr("microcell_inspection_only_grass"))
	elif lot_candidates.is_empty() and not tree_present and not shrub_present and not grass_present:
		lines.append(tr("microcell_inspection_empty"))
	else:
		if not lot_candidates.is_empty():
			lines.append(tr("microcell_inspection_resources_header"))
			for candidate in lot_candidates:
				lines.append(tr("microcell_inspection_resource_line").format({
					"resource": IconRegistry.get_resource_display_name(candidate["resource_name"]),
					"quantity": candidate["available_quantity"],
				}))
		if tree_present or shrub_present or grass_present:
			lines.append(tr("microcell_inspection_vegetation_header"))
			if tree_present:
				lines.append("- " + tr("microcell_inspection_tree"))
			if shrub_present:
				lines.append("- " + tr("microcell_inspection_shrub"))
			if grass_present:
				lines.append("- " + tr("microcell_inspection_grass"))

	_select_microcell({"macro_coords": macro_coords, "lot": lot, "lines": lines})


# ============================================================================================
# Selezione di una microcella (ispezione, doppio click sinistro) — Step "ispezione" (2026-09-16,
# richiesta utente). Struttura gemella di _select_stone/_clear_stone_selection: mutua esclusione a
# 7 vie (era "a 6" prima di questo passo — vedi i commenti "mutua esclusione a 6 vie" sparsi nelle
# altre 6 funzioni _select_*, ora ciascuna chiama anche _clear_microcell_selection). Evidenziazione
# quadrata sulla mappa come stick_lot/stone (vedi sotto — RIPRISTINATA 2026-09-16 dopo un primo giro
# senza, segnalato dall'utente come regressione visiva). `hit` contiene "lines" già COMPLETAMENTE
# risolte dal chiamante (_handle_microcell_inspection_double_click) — questa funzione/il refresh
# sotto restano "muti", non ricalcolano nulla.
# ============================================================================================

func _select_microcell(hit: Dictionary) -> void:
	# Evidenziazione sulla mappa (2026-09-16, richiesta utente — "hai tolto anche il quadrato rosso
	# sulla cella selezionata": ripristinato, STESSO schema di _select_stick_lot/_select_stone sopra
	# — quadrato sulla cella del match, spento su ogni altra cella viva).
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		if coords == hit["macro_coords"]:
			cell.renderer.set_selected_microcell(hit["lot"])
		else:
			cell.renderer.clear_selected_microcell()

	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_vegetation_selection()
	_clear_building_selection()
	_clear_dead_body_selection()
	_clear_stone_selection()
	_clear_stick_lot_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")

	selected_microcell = hit
	_selection_kind = SelectionKind.MICROCELL
	_refresh_microcell_panel()
	game_info_tabs.show_selection_tab()


func _clear_microcell_selection() -> void:
	if selected_microcell.is_empty():
		return
	selected_microcell = {}
	_selection_kind = SelectionKind.NONE
	for cell in live_cells.values():
		if cell.renderer != null:
			cell.renderer.clear_selected_microcell()
	micro_cell_inspection_panel.clear()
	game_info_tabs.hide_selection_tab()


# Nessuna rilettura dal vivo qui (a differenza di _refresh_stone_panel/_refresh_stick_lot_panel,
# che rileggono le quantità ad ogni chiamata) — "lines" è già il contenuto finale, risolto una volta
# sola al momento del doppio click da _handle_microcell_inspection_double_click. Nessun refresh
# periodico agganciato (stesso trattamento di stone/stick_lot/vegetazione, MAI individuo/edificio):
# se in futuro servisse un refresh giornaliero, andrebbe ricalcolato leggendo direttamente
# TerrainScatteredResourceService.get_available per macro_coords/lot già noti — non richiamando di
# nuovo _resolve_pickup_candidates, che dipende dalla posizione LIVE del mouse tramite un evento
# reale, non disponibile fuori da un vero click.
func _refresh_microcell_panel() -> void:
	var lot: Vector2i = selected_microcell["lot"]
	micro_cell_inspection_panel.show_inspection(selected_microcell.get("lines", []))
	game_info_tabs.set_selection_title(tr("microcell_inspection_title").format({"x": lot.x, "y": lot.y}))


# Comando "vai e scarica" via DESTRO su un edificio di stoccaggio (2026-09-09, richiesta utente) —
# stesso identico principio/stessa posizione nella catena di _try_assign_pickup_command_on_right_
# click sopra (provato subito dopo, mai in competizione spaziale: un edificio non condivide mai la
# propria microcella con una posizione stone/lotto stick, vedi BuildingVerificationService
# Criterio 6). `individual.is_selected` — stesso gate di sopra: nessun individuo selezionato,
# nessun comando.
#
# required_button=MOUSE_BUTTON_RIGHT passato esplicitamente a BuildingSelectorController.try_select
# (default LEFT, per il suo chiamante di selezione esistente in _unhandled_input sopra, invariato).
#
# Tre condizioni, in quest'ordine, TUTTE necessarie perché il comando scatti (altrimenti false,
# fallback al movimento normale — MAI un comando "parziale"/un errore silenzioso):
#   1. l'edificio colpito è di categoria STORAGE (rules.category — un hit su hut/pebble_circle
#      colpiti col destro resta movimento semplice, non un errore, semplicemente non è un target
#      valido per Unload);
#   2. lo zaino non è vuoto (carried_quantity > 0 — zaino vuoto non ha nulla da scaricare, stesso
#      principio "niente da fare" già seguito da PickUpAction quando _quantity_to_collect è 0);
#   3. BuildingStorageService.can_accept è vero per carried_resource_name (categoria della risorsa
#      trasportata compatibile con building.rules.accepted_categories — vedi BuildingStorageService.
#      gd). Nessun feedback "categoria rifiutata" in questo passo (nessuna UI per l'inventario
#      edificio ancora, richiesta esplicita) — semplicemente nessun comando, movimento normale.
#
# Posizione target tradotta nello spazio locale dell'INDIVIDUO (non dell'edificio) — stessa formula
# già in uso in _debug_test_daydream_task per lo Pebble Circle: building.micro_x/y sono locali alla
# macrocella DELL'EDIFICIO, non necessariamente quella corrente dell'individuo (offset zero, no-op,
# se invece coincidono).
func _try_assign_unload_command_on_right_click(event: InputEvent) -> bool:
	# Guard di tipo evento (2026-09-10, richiesta utente — aggiunto per coerenza con
	# _try_assign_pickup_command_on_right_click/_try_assign_build_command_on_right_click sopra,
	# stessa catena di _unhandled_input: questa funzione non ha mai avuto log di debug quindi non
	# produceva flooding, ma girava comunque su OGNI evento incluso il motion, senza necessità —
	# building_selector_controller.try_select filtra già internamente per tipo/pulsante, quindi
	# NON era un bug di correttezza, solo lavoro ridondante ad ogni frame di movimento del mouse).
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	# Tasto U tenuto premuto (2026-09-16, richiesta utente — bugfix "attivo questa Task spesso per
	# errore, e se nel frattempo lo zaino si svuota per altri motivi va in tilt"): PRIMA un semplice
	# click destro su un deposito bastava, troppo facile da innescare per sbaglio durante un click
	# destro "normale" (es. tentando di selezionare/muoversi vicino a un deposito). Stesso pattern
	# già in uso per il piazzamento istantaneo edifici (Sx+B, vedi _unhandled_input) — un comando
	# "veloce ma pericoloso" richiede un modificatore esplicito, non il solo click. Mnemonico U
	# libero per questo scopo (2026-09-16): prima era il tasto del test debug temporaneo
	# _debug_test_haul_resource_task (mai rimosso quando la vera Raccolta è arrivata, come il suo
	# stesso commento richiedeva) — vedi _unhandled_input, quel collegamento è stato tolto per fare
	# posto a questo.
	if not Input.is_key_pressed(KEY_U):
		return false
	if individual == null or not individual.is_selected:
		return false
	if individual.carried_quantity <= 0:
		return false

	var building_hit := building_selector_controller.try_select(
		event, live_cells, macro_world.buildings if macro_world != null else [], MOUSE_BUTTON_RIGHT
	)
	if building_hit.is_empty():
		return false

	var building := _find_building_by_id(building_hit["building_id"])
	if building == null or building.rules == null or building.rules.category != BuildingTypes.Category.STORAGE:
		return false
	if not BuildingStorageService.can_accept(building, individual.carried_resource_name):
		return false

	var macro_offset: Vector2 = Vector2(Vector2i(building.macro_x, building.macro_y) - individual.home_macro_coords) * World.WIDTH
	var building_position: Vector2 = Vector2(building.micro_x, building.micro_y) + macro_offset

	var walk := WalkAction.new(building_position)
	# DepositKind.RESOURCE esplicito (2026-09-10, richiesta utente — scollegare il ramo di
	# UnloadAction dalla nullità di target_building): `building` qui è già garantito non-null dalla
	# guardia sopra, stesso comportamento di ramo fisico di prima di questo passo.
	var unload := UnloadAction.new(building, UnloadAction.DepositKind.RESOURCE)
	# _reconnect_unload_action_signals (2026-09-12, richiesta utente — bugfix "il mucchietto non si
	# aggiorna in automatico quando viene fatto il deposito"): questo comando manuale "scarica qui"
	# costruisce il proprio UnloadAction direttamente (non via TaskFactory/task.step_appended come
	# _assign_pickup_task sopra), quindi va ricollegato qui, subito, stesso principio/stessa funzione
	# condivisa già in uso ovunque altro in questo file.
	_reconnect_unload_action_signals(unload, individual)
	var task := Task.new([walk, unload])
	# task_name/step_descriptions (2026-09-09) — stesso trattamento hardcoded già in uso per
	# "task_haul_resource" (_assign_pickup_task sopra): nessuna TaskDefinition "unload_resource"
	# esiste ancora (TaskFactory non supporta UNLOAD, vedi task_factory.gd).
	task.task_name = "task_unload_resource_name"
	task.step_descriptions = ["task_unload_resource_step_walk", "task_unload_resource_step_unload"]
	individual.assign_task(task, _resolve_age_band(individual))
	return true


# Guard max_builders (2026-09-14, richiesta utente — bugfix "più builder sullo stesso cantiere si
# intrappolano a vicenda": la VERA gestione multi-builder resta da progettare, questo è solo un
# guard temporaneo per impedire il caso rotto finché non c'è) — conta quanti ALTRI individui
# (esclude `excluding_individual`, che può sempre riprendere il PROPRIO cantiere) hanno già un
# "claim" sulla Build Task di `target_building`, sia come current_task ATTIVA sia come Task
# SOSPESA nella propria task_queue: un builder mandato temporaneamente a fare un'altra commissione
# deve continuare a "occupare" il proprio posto, altrimenti nella finestra in cui è sospeso un
# secondo individuo potrebbe intrufolarsi, ricreando lo stesso problema. Identificazione del target
# via _task_claims_building sotto (BUGFIX 2026-09-14: NON tramite task.context, ripulito da
# TaskFactory.build_task subito dopo la costruzione — letta invece dagli step stessi, che la
# portano come campo proprio dell'istanza). Scansione lineare di
# human_individuals (+ le poche voci di ciascuna task_queue, max TaskQueueService.MAX_QUEUE_SIZE) —
# stesso principio "O(N) accettabile finché N resta piccolo" già assunto ovunque in questo progetto.
func _count_other_individuals_claiming_build(target_building: Building, excluding_individual: HumanIndividual) -> int:
	var count := 0
	for other in human_individuals:
		if other == excluding_individual:
			continue
		if _task_claims_building(other.current_task, target_building):
			count += 1
			continue
		for queued_task in other.task_queue:
			if _task_claims_building(queued_task, target_building):
				count += 1
				break
	return count


# BUGFIX (2026-09-14, richiesta utente — guard max_builders confermato non funzionante: "ne lascia
# assegnare ancora un sacco") — PRIMA leggeva task.context.get("target_building"), SEMPRE null:
# TaskFactory.build_task (righe 224-230) ripulisce SEMPRE context dalle chiavi consumate per
# costruire gli step, "target_building" incluso — la chiave viene letta per costruire SetupSiteAction/
# ClearAction/BuildAction, poi CANCELLATA da context prima che diventi task.context. Letto ora
# invece direttamente dagli step (SetupSiteAction/ClearAction/BuildAction espongono target_building
# come campo proprio dell'istanza, MAI cancellato — sopravvive alla pulizia del context, e resta
# leggibile indipendentemente da quale step sia quello CORRENTE: scandisco tutti i 4 step della
# Task, non solo quello attivo). "target_building" in step (duck typing, non `is` per tipo — WalkAction
# non ha questo campo, la esclude naturalmente senza bisogno di elencare i tre tipi che ce l'hanno).
func _task_claims_building(task: Task, target_building: Building) -> bool:
	if task == null or task.task_name != "task_build_name":
		return false
	for step in task.steps:
		if "target_building" in step and step.target_building == target_building:
			return true
	return false


# Comando "vai e costruisci" via DESTRO su un edificio non ancora completo (2026-09-10, richiesta
# utente — prima porzione Build Task; RISCRITTA 2026-09-12, richiesta utente — sostituzione di
# _pending_build_tasks con un percorso generico "reassignable target", vedi
# TaskReassignmentService.gd/Building.gd) — STESSO identico pattern a due click di
# _try_assign_unload_command_on_right_click sopra (click sinistro seleziona l'individuo altrove in
# _unhandled_input, poi questo destro assegna), stesso gate `individual.is_selected`, stesso
# hit-test building_selector_controller.try_select con MOUSE_BUTTON_RIGHT, stessa risoluzione
# _find_building_by_id.
#
# NESSUNA distinzione tra prima assegnazione e riassegnazione dopo interruzione (richiesta esplicita
# utente, punto 2/3): building.has_resumable_task() (== not is_complete) resta la condizione di
# BASE — sia al primissimo click su un cantiere appena piazzato (construction_progress ancora
# vuoto) sia a un click successivo dopo che un primo individuo è stato interrotto (construction_
# progress con progresso parziale), questa funzione ricostruisce la Task da zero via
# TaskReassignmentService.reassign_task, che a sua volta chiama TaskFactory.build_task — sono i
# quattro step stessi (SetupSiteAction/ClearAction/BuildAction, get_stamina_delta) a fare da soli
# l'auto-skip quando construction_progress mostra lavoro già fatto, nessuna soglia/percentuale letta
# o confrontata qui. AGGIUNTO 2026-09-14 — il guard max_builders sopra si applica PRIMA di
# ricostruire qualunque cosa: un cantiere con has_resumable_task()==true può comunque rifiutare
# l'assegnazione se già al tetto di builder.
#
# extra_context fornisce le due chiavi che Building non può risolvere da sé (vedi Building.
# get_resumable_task_context): "macro_state" (World, irraggiungibile da un layer di simulazione) e
# "is_currently_grass" (il renderer live, layer di gameplay/rendering) — STESSA identica query di
# _start_building_task_at per lo stesso scopo (vedi lì per il motivo: GRASS non ha posizioni proprie
# in MacroCellState).
func _try_assign_build_command_on_right_click(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if individual == null or not individual.is_selected:
		return false

	var building_hit := building_selector_controller.try_select(
		event, live_cells, macro_world.buildings if macro_world != null else [], MOUSE_BUTTON_RIGHT
	)
	if building_hit.is_empty():
		return false

	var building_id: int = building_hit["building_id"]
	var hit_building := _find_building_by_id(building_id)
	if hit_building == null or not hit_building.has_resumable_task():
		return false

	var build_macro_coords := Vector2i(hit_building.macro_x, hit_building.macro_y)

	# Guard max_builders (2026-09-14, richiesta utente) — vedi _count_other_individuals_claiming_
	# build sopra per cosa conta come "claim". Rifiuto ESPLICITO qui, PRIMA di costruire qualunque
	# Task: stessa X (_spawn_command_blink_effect) già usata sotto per un rifiuto di assign_task,
	# più un alert giallo dedicato — STESSO canale/STESSO stile "alert" di MATERIAL_NEEDED (vedi
	# NotificationPopup, "quello giallo", richiesta utente) — a differenza del rifiuto sotto
	# (silenzioso lato notifica, solo la X), qui l'utente ha chiesto ESPLICITAMENTE anche un avviso
	# testuale con {current}/{max}.
	var max_builders: int = hit_building.rules.max_builders if hit_building.rules != null else 1
	var other_builders_count := _count_other_individuals_claiming_build(hit_building, individual)
	if other_builders_count >= max_builders:
		if live_cells.has(build_macro_coords):
			_spawn_command_blink_effect(
				live_cells[build_macro_coords],
				Vector2i(hit_building.micro_x, hit_building.micro_y),
				IconRegistry.get_command_icon("task_rejected")
			)
		if UserOptions.show_notification_popups:
			notification_popup.enqueue(
				NotificationTypes.NotificationPopupType.MATERIAL_NEEDED,
				tr("notification_build_capacity_full").format({
					"current": other_builders_count,
					"max": max_builders,
				})
			)
		return true

	var macro_state := macro_world.get_cell_state_at(hit_building.macro_x, hit_building.macro_y) if macro_world != null else null
	var is_currently_grass := false
	if live_cells.has(build_macro_coords):
		var current_grass_positions: Array = live_cells[build_macro_coords].renderer.vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
		is_currently_grass = current_grass_positions.has(Vector2i(hit_building.micro_x, hit_building.micro_y))
	var extra_context: Dictionary = {
		"macro_state": macro_state,
		"is_currently_grass": is_currently_grass,
	}
	var task := TaskReassignmentService.reassign_task(hit_building, individual, _resolve_age_band(individual), extra_context)
	if task == null:
		return false

	# Guard di assign_task rifiutato (2026-09-13, richiesta utente — bugfix: il "martelletto"
	# compariva comunque anche quando la Task non veniva mai davvero assegnata) — reassign_task
	# chiama individual.assign_task internamente e ritorna SEMPRE `task` non-null se è riuscita a
	# COSTRUIRLA, indipendentemente dall'esito del guard age_band (quel `null` sopra copre solo
	# "nessun target valido"/"nessuna TaskDefinition risolvibile", casi in cui non c'è nulla da
	# segnalare — restano silenziosi, invariati). Per distinguere "costruita ma rifiutata" da
	# "assegnata davvero" senza cambiare la firma di reassign_task (usata da un solo chiamante,
	# ma il suo contratto pubblico -> Task resta comunque più chiaro così) uso la stessa garanzia
	# già documentata su HumanIndividual.assign_task: se il guard scatta, individual.current_task
	# resta ESATTAMENTE quello di prima, quindi diverso per riferimento dal `task` appena costruito.
	#
	# task_queue.has(task) (2026-09-13, richiesta utente — bugfix "manina vs X": stesso motivo del
	# ramo "zaino occupato" appena introdotto in HumanIndividual.assign_task) — un individuo con lo
	# zaino occupato che riceve una Build Task NON la rifiuta: la accoda (current_task resta quello
	# di prima, per costruzione, IDENTICO a un vero rifiuto per il solo confronto per riferimento
	# sopra) e partirà da sola quando si libera. Senza questo controllo aggiuntivo, "accodata"
	# risulterebbe indistinguibile da "rifiutata dal guard età" — qui invece è un comando riuscito.
	if individual.current_task != task and not individual.task_queue.has(task):
		if live_cells.has(build_macro_coords):
			_spawn_command_blink_effect(
				live_cells[build_macro_coords],
				Vector2i(hit_building.micro_x, hit_building.micro_y),
				IconRegistry.get_command_icon("task_rejected")
			)
		return true

	# Collegamento signal SetupSiteAction.site_setup_completed / ClearAction.site_cleared (vedi
	# _reconnect_build_task_signals) — STESSO principio già in uso da _start_building_task_at prima
	# di questa riscrittura: resta qui (non in TaskReassignmentService, generico) perché è un
	# dettaglio specifico della Build Task, non del meccanismo di riassegnazione in sé.
	for step in task.steps:
		_reconnect_build_task_signals(step)

	# Lampeggio "martelletto" SUBITO al momento dell'assegnazione (2026-09-11, richiesta utente — "il
	# martello deve comparire quando parte la task, non quando arriva il pipottino dopo il walk...
	# anche per haul service la manina appare subito... credo serva coerenza") — STESSO trigger/
	# STESSO principio di _assign_pickup_task qui sotto: il comando è partito ORA (l'individuo è
	# stato assegnato alla Build Task), il player deve vederlo subito anche mentre l'individuo sta
	# ancora camminando verso il cantiere, non solo quando vi arriva. Una sola icona per l'intera
	# Build Task (chiave "build" in IconRegistry, non più una per step — vedi IconRegistry.gd per lo
	# storico del tentativo precedente, scartato).
	if live_cells.has(build_macro_coords):
		_spawn_command_blink_effect(
			live_cells[build_macro_coords],
			Vector2i(hit_building.micro_x, hit_building.micro_y),
			IconRegistry.get_command_icon("build")
		)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Task di costruzione assegnata a #%d %s per l'edificio #%d." % [individual.id, individual.name, building_id])
	return true


# ============================================================================================
# Selezione del "terreno" di una microcella TREE — click sul lotto invece che su un individuo
# preciso (2026-09-08, richiesta utente: "forse si puo' fare il clic sul terreno della microcella
# che mi dà le info della microcella aggregata"). Struttura gemella di _select_stone/
# _clear_stone_selection sopra, ma il bersaglio è l'intero lotto (StickLotSelectorController), non
# una posizione puntiforme — evidenziazione con un contorno QUADRATO (set_selected_stick_lot,
# perimetro della microcella) invece del cerchio usato per un oggetto singolo.
# ============================================================================================

func _select_stick_lot(hit: Dictionary) -> void:
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		if coords == hit["macro_coords"]:
			cell.renderer.set_selected_stick_lot(hit["lot"])
		else:
			cell.renderer.clear_selected_stick_lot()

	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_vegetation_selection()
	_clear_building_selection()
	_clear_dead_body_selection()
	_clear_stone_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
	_clear_microcell_selection()

	selected_stick_lot = hit
	_selection_kind = SelectionKind.STICK_LOT
	_refresh_stick_lot_panel()
	game_info_tabs.show_selection_tab()


func _clear_stick_lot_selection() -> void:
	if selected_stick_lot.is_empty():
		return
	selected_stick_lot = {}
	_selection_kind = SelectionKind.NONE
	for cell in live_cells.values():
		if cell.renderer != null:
			cell.renderer.clear_selected_stick_lot()
	terrain_scattered_resource_info_panel.clear()
	game_info_tabs.hide_selection_tab()


# Legge macro_state.stick_quantities (disponibilità ESATTA del lotto cliccato: capacity - harvested,
# vedi StickPoolService). NON più resource_quantity[TREE] (2026-09-09, richiesta utente — rimosso:
# quel valore è l'aggregato dell'INTERA macrocella, non ha alcun legame col lotto singolo cliccato,
# leggeva come "legno di questo lotto" mentre non lo era — vedi TerrainScatteredResourceInfoPanel
# per il rimpiazzo, un'etichetta "wood" puramente statica finché non esisterà un vero dato per
# lotto). Nessuna gestione "marker bloccato": stesso principio già dichiarato per stone — l'unica
# via di invalidazione oggi resta lo scaricamento della macrocella.
func _refresh_stick_lot_panel() -> void:
	var cell: LiveMacroCell = live_cells.get(selected_stick_lot["macro_coords"])
	if cell == null or cell.macro_state == null:
		_clear_stick_lot_selection()
		return
	var lot: Vector2i = selected_stick_lot["lot"]
	var stick_entry: Dictionary = cell.macro_state.stick_quantities.get(lot, {})
	var available_sticks: int = int(stick_entry.get("capacity", 0)) - int(stick_entry.get("harvested", 0))
	terrain_scattered_resource_info_panel.show_stick_lot(available_sticks)
	game_info_tabs.set_selection_title(tr("selection_title_type").format({"type": tr("stick_lot_selection_title")}))


# ============================================================================================
# Selezione di un corpo morto — Step 6 del sistema oggetti-scaduti (2026-09-05). Struttura gemella
# di _select_building/_clear_building_selection sopra: DeadBodyInfoPanel mostra sesso/età alla
# morte/causa/giorni rimanenti, risolti dal vero record in game_data.expired_objects via
# _find_dead_body_record — questo pannello, come gli altri tre, riceve solo dati già risolti.
# ============================================================================================

func _select_dead_body(hit: Dictionary) -> void:
	_deselect_all_human_individuals()
	human_individual_info_panel.clear()
	_clear_vegetation_selection()
	_clear_building_selection()
	_clear_stone_selection() # mutua esclusione a 7 vie (2026-09-16, prima "a 6 vie")
	_clear_stick_lot_selection()
	_clear_microcell_selection()

	selected_dead_body_individual_id = hit["individual_id"]
	_set_dead_body_view_selected(selected_dead_body_individual_id, true)
	_selection_kind = SelectionKind.DEAD_BODY
	_refresh_dead_body_panel()
	game_info_tabs.show_selection_tab()


func _clear_dead_body_selection() -> void:
	if selected_dead_body_individual_id == -1:
		return
	_set_dead_body_view_selected(selected_dead_body_individual_id, false)
	selected_dead_body_individual_id = -1
	_selection_kind = SelectionKind.NONE
	dead_body_info_panel.clear()
	game_info_tabs.hide_selection_tab()


# Accende/spegne il cerchiolino di selezione sulla DeadBodyView giusta (bugfix, 2026-09-05,
# richiesta utente: mancava rispetto a individui/edifici) — is_instance_valid() perché la view può
# essersi autodistrutta per scadenza (Step 5) nel frattempo, vedi dead_body_views. queue_redraw()
# esplicito: questa view non ha il meccanismo di early-out per-frame della classe base che lo
# farebbe scattare da solo per un cambio di is_selected.
#
# BUGFIX (2026-09-06, crash reale in game: "Trying to assign invalid previously freed instance")
# — `view` NON è più tipizzato DeadBodyView sulla riga di assegnazione: farlo (versione precedente)
# fa scattare il controllo di tipo di Godot SULL'ASSEGNAZIONE stessa, prima ancora che
# is_instance_valid() sotto potesse girare — se la view si era già autodistrutta (decomposizione
# scaduta), l'assegnazione tipizzata crashava invece di essere gestita dal controllo che il
# commento sopra descrive. is_instance_valid() lavora su un riferimento generico (mai un problema),
# solo l'USO (is_selected/queue_redraw) richiede il tipo vero — mai raggiunto se non valido. Pulizia
# della entry stantia (dead_body_views.erase) quando trovata invalida: evita di ripetere lo stesso
# controllo fallito ad ogni futura selezione/deselezione dello stesso individual_id.
func _set_dead_body_view_selected(individual_id: int, selected: bool) -> void:
	var view = dead_body_views.get(individual_id)
	if view == null:
		return
	if not is_instance_valid(view):
		dead_body_views.erase(individual_id)
		return
	view.is_selected = selected
	view.queue_redraw()


# Risolve selected_dead_body_individual_id sul vero record in game_data.expired_objects (scansione
# lineare — stesso costo già accettato altrove nel progetto, vedi _find_building_by_id) e popola
# dead_body_info_panel. Guardia "record non trovato -> deseleziona" (stesso principio difensivo di
# _refresh_building_panel): il record può sparire da sotto la selezione corrente in qualunque
# momento per via della pulizia annuale (Step 4) — nessun aggancio automatico a quell'evento in
# questo step (non richiesto), solo questa guardia quando il pannello viene ri-popolato.
func _refresh_dead_body_panel() -> void:
	var record := _find_dead_body_record(selected_dead_body_individual_id)
	if record.is_empty():
		_clear_dead_body_selection()
		return
	var data: Dictionary = record["type_specific_data"]
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY)
	var days_remaining := 0
	if rules != null:
		days_remaining = ExpiredObjectCalculator.get_days_remaining(record, rules, game_data.year, game_data.current_day)
	dead_body_info_panel.show_dead_body(int(data["sex"]), int(data["age_at_death"]), int(data["cause"]), days_remaining)
	# Titolo (stessa convenzione di individui/edifici sopra) — nome NON duplicato dentro il pannello.
	game_info_tabs.set_selection_title(tr("selection_title_name").format({"name": String(data["name"])}))


func _find_dead_body_record(individual_id: int) -> Dictionary:
	for record in game_data.expired_objects:
		if (
			record["object_type"] == ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY
			and record["individual_id"] == individual_id
		):
			return record
	return {}


# Filtra game_data.expired_objects per object_type == DEAD_BODY — candidati da passare a
# dead_body_selector_controller.try_select (vedi _unhandled_input). Scansione lineare ricostruita
# ad ogni click (stesso costo già accettato altrove nel progetto per array analoghi), nessuna
# cache: il numero di corpi vivi contemporaneamente resta piccolo per costruzione (la pulizia
# annuale, Step 4, li rimuove entro pochi anni).
func _get_dead_body_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in game_data.expired_objects:
		if record["object_type"] == ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY:
			result.append(record)
	return result


func _find_building_by_id(building_id: int) -> Building:
	if macro_world == null:
		return null
	for building in macro_world.buildings:
		if building.id == building_id:
			return building
	return null


# Gemella di _find_building_by_id sopra, per posizione invece che per id (2026-09-16, richiesta
# utente — ispezione microcella: "se la cella è occupata da un edificio..."). STESSO confronto
# macro_x/macro_y/micro_x/micro_y già usato da StickLotSelectorController._is_occupied_by_building/
# PlantFiberLotSelectorController._is_occupied_by_building — duplicato qui apposta (non riusato da
# quelle due classi, `_`-prefixed/private per convenzione) invece che esposto come utility condivisa.
func _find_building_at_microcell(macro_coords: Vector2i, lot: Vector2i) -> Building:
	if macro_world == null:
		return null
	for building in macro_world.buildings:
		if building.macro_x == macro_coords.x and building.macro_y == macro_coords.y \
				and building.micro_x == lot.x and building.micro_y == lot.y:
			return building
	return null


# Effetto nato-morto, popup nascita (2026-09-06) — serve solo per risolvere il NOME della madre da
# mostrare nel testo del popup (vedi _on_human_individual_born sotto): il resto del progetto oggi
# mostra sempre e solo l'id grezzo per mother_id/father_id (vedi HumanIndividualInfoPanel), questa
# è la prima volta che serve il nome vero. Scansione lineare su human_individuals: popolazioni di
# questa scala (decine di individui) rendono il costo trascurabile, stesso principio già accettato
# altrove nel progetto per liste di questa dimensione (es. _find_building_by_id sopra).
func _find_human_individual_by_id(individual_id: int) -> HumanIndividual:
	for individual in human_individuals:
		if individual.id == individual_id:
			return individual
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
# max_stamina/current_stamina (2026-09-04, rinominati da max_workforce/residual_workforce il
# 2026-09-06 — rename completo Workforce->Stamina, richiesta utente, nessuna modifica di
# comportamento): letti ENTRAMBI da target (campi reali su HumanIndividual, richiesta utente
# 2026-09-06) — max_stamina è ricalcolato ogni giorno (HumanStaminaIndividualService), current_
# stamina invece resta fermo al valore di creazione (nessun sistema di consumo/reset esiste
# ancora), quindi oggi i due numeri coincidono solo per chi non ha ancora un ricalcolo diverso da
# quello iniziale — non più una spia sempre-vera "corrente == massimo" come prima di questo
# passo, solo una coincidenza attuale.
func _select_individual(target: HumanIndividual) -> void:
	_update_individual_panel_content(target)
	game_info_tabs.show_selection_tab()


# Fascia d'età CORRENTE di un individuo, risolta al volo (2026-09-12, richiesta utente —
# collegamento di HumanTypes.AgeBand.INFANT al gameplay, Step 4: assign_task ora RICHIEDE questo
# dato dal chiamante, mai calcolato da sé — vedi il commento su HumanIndividual.assign_task per il
# perché) — STESSA identica formula già duplicata inline in questo file (_update_individual_panel_
# content sotto, _resolve_building_residents_display_data) e altrove nel progetto
# (HumanStaminaIndividualService, HumanCarryCapacityIndividualService, ecc.): centralizzata qui
# come UNICO punto di calcolo per i chiamanti di questo file, così un domani non possano
# disallinearsi tra loro. Mai persistita (stesso principio "sempre ricalcolata" di HumanIndividual.
# birth_year_virtual) — HumanCalculator.get_age_band resta la fonte di verità, questa funzione si
# limita a raccogliere i tre argomenti che richiede (durate EFFETTIVE per l'Era corrente, mai le
# durate BASE di HumanRules, stesso bugfix storico già fissato ovunque nel progetto).
func _resolve_age_band(target: HumanIndividual) -> HumanTypes.AgeBand:
	var age := float(game_data.year - target.birth_year_virtual)
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female, target.sex, age
	)


# Contenuto del pannello individuo (età/age_band/stamina), SEPARATO dal salto alla tab
# selezione sopra (bugfix, richiesta utente, 2026-09-05): _refresh_selected_individual_panel
# sotto lo chiama al rollover d'anno per aggiornare l'età SENZA rubare la tab attiva
# all'utente — prima riusava _select_individual per intero, che include SEMPRE
# game_info_tabs.show_selection_tab(), facendo saltare la UI sulla scheda 🔍 ad ogni cambio
# d'anno anche se l'utente stava guardando tutt'altra scheda (es. 🧍 Popolazione).
func _update_individual_panel_content(target: HumanIndividual) -> void:
	var age: int = game_data.year - target.birth_year_virtual
	var age_band := _resolve_age_band(target)
	# Moltiplicatori gravidanza/figlio a carico (2026-09-06) — SOLO display, migliorano
	# l'accuratezza del numero mostrato, nessun sistema di consumo stamina reale esiste ancora.
	# Stessa estrazione di valori primitivi dall'individuo già fatta sopra per sesso/età: la
	# funzione pura non riceve mai l'oggetto HumanIndividual intero.
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name)
	var max_stamina := HumanCalculator.get_max_stamina(
		human_folk.human_rules_ref, age_band, target.sex,
		target.is_pregnant, target.dependent_child_id != -1, era_rules
	)
	var current_stamina := target.current_stamina
	# "Cosa sta facendo" (2026-09-07, richiesta utente) — Task.get_activity_description() risolve
	# testo+tr() da current_task (vedi Task.gd); null = nessuna Task in corso, cioè Rest implicito
	# (vedi HumanIndividualActionService.apply_action), reso qui come stringa esplicita invece che
	# un pannello vuoto/ambiguo.
	# Id Task in coda (2026-09-16, richiesta utente — indagine "task assegnata due volte": da log
	# testuale task_name da solo non distingue due istanze diverse della stessa Task, es. una
	# Transport ripresa dalla coda vs una appena comandata — Task.id le distingue sempre, vedi
	# Task.gd) — mostrato SOLO se una Task è davvero in corso, mai per "A riposo".
	var activity_text: String = (
		"%s [#%d]" % [target.current_task.get_activity_description(), target.current_task.id]
		if target.current_task != null else tr("task_activity_idle")
	)

	# Capacità di trasporto (2026-09-08, richiesta utente) — a differenza di max_stamina sopra
	# (ricalcolato fresco qui ad ogni refresh pannello), max_carry_capacity è letto DIRETTAMENTE
	# da target: nessun secondo calcolo ridondante, il campo è già mantenuto aggiornato una volta
	# al giorno da HumanCarryCapacityIndividualService (vedi GameTimeService._on_day_advanced).
	# Spazio occupato = carried_quantity × SecondaryResourceRules.space_per_unit della risorsa
	# trasportata, lookup dal .tres corrispondente CALCOLATO AL VOLO qui (mai cachato) — nessuna
	# risorsa trasportata (carried_resource_name vuoto) o .tres non risolvibile => spazio occupato
	# 0, tutta la capacità risulta libera.
	var used_carry_space := 0.0
	if target.carried_resource_name != "":
		var carried_resource_rules := CaloricCalculator.get_caloric_source_rules(target.carried_resource_name)
		if carried_resource_rules != null:
			used_carry_space = float(target.carried_quantity) * carried_resource_rules.space_per_unit
	var free_carry_capacity: float = max(target.max_carry_capacity - used_carry_space, 0.0)

	# 5 nuovi parametri vitali (2026-09-13, richiesta utente) — stesso trattamento di
	# max_carry_capacity sopra: letti DIRETTAMENTE da target, nessun ricalcolo live (a differenza di
	# max_stamina, nessuno dei 5 ha modificatori volatili tipo gravidanza/figlio-a-carico) — i campi
	# sono già mantenuti aggiornati una volta al giorno da HumanVitalsIndividualService (vedi
	# GameTimeService._on_day_advanced).
	#
	# 6 nuove skill (2026-09-13, richiesta utente) — stesso identico trattamento: lette DIRETTAMENTE
	# da target, nessun ricalcolo (nessuna crescita esiste ancora, restano sempre 0.0 finché un
	# futuro sistema non le farà variare).
	#
	# Azioni in coda (2026-09-13, richiesta utente) — descrizioni già risolte qui, pannello resta
	# muto. Ordine INVERTITO rispetto a task_queue (che è LIFO, vedi TaskQueueService.
	# pop_suspended_task — l'ultima spinta è la prossima a riprendere): reverse-iterando si mostra
	# per prima "quella che riprenderà subito dopo l'attività corrente", il che è l'informazione più
	# utile per il player.
	# STESSA formula/STESSO metodo di activity_text sopra (2026-09-16, richiesta utente) —
	# Task.get_activity_description() invece del solo tr(task_name) grezzo: una Task sospesa in coda
	# ha ancora gli stessi `steps` di quando era attiva (haul_resource/transport mostrano quindi la
	# propria risorsa anche qui, vedi Task.gd), e Task.id (vedi commento su activity_text) permette
	# di distinguere in coda due Task con lo stesso nome/stessa risorsa.
	var queued_task_descriptions: Array[String] = []
	for i in range(target.task_queue.size() - 1, -1, -1):
		var queued_task: Task = target.task_queue[i]
		queued_task_descriptions.append("%s [#%d]" % [queued_task.get_activity_description(), queued_task.id])
	human_individual_info_panel.show_individual(
		target, max_stamina, current_stamina, activity_text,
		target.max_carry_capacity, free_carry_capacity,
		target.max_hunger, target.current_hunger,
		target.max_thirst, target.current_thirst,
		target.max_health, target.current_health,
		target.max_happiness, target.current_happiness,
		target.max_loyalty, target.current_loyalty,
		target.skill_leadership, target.skill_builder, target.skill_management,
		target.skill_transporter, target.skill_gathering, target.skill_cognition,
		target.skill_hunting,
		queued_task_descriptions
	)
	# Titolo header consolidato (2026-09-13, richiesta utente — "perché la riga del center è
	# vuota, mettici nome/sesso/età/fascia") — sostituisce sia il vecchio "Nome: {name}" sia la
	# IdentityLabel del corpo pannello (rimossa: sarebbe stata una seconda copia della STESSA
	# informazione su due righe diverse). Sesso ABBREVIATO (sex_male_short/sex_female_short —
	# "M"/"F") per stare compatti sulla stessa riga del bottone 🎯, stessa scelta già fatta per la
	# ex-IdentityLabel. Calcolato qui (non nel pannello, che resta "muto"): GameScene è l'unico
	# punto che decide il testo di questo header per OGNI tipo di selezione (vedi gli altri call
	# site di set_selection_title per edifici/vegetazione/ecc.).
	var identity_sex_text: String = tr("sex_female_short") if target.sex == HumanTypes.Sex.FEMALE else tr("sex_male_short")
	var identity_band_text: String = HumanTypes.AgeBand.keys()[age_band].capitalize()
	if target.is_pregnant:
		identity_band_text += ", " + tr("pregnant")
	game_info_tabs.set_selection_title(tr("individual_identity_line").format({
		"name": target.name, "sex": identity_sex_text, "age": age, "band": identity_band_text
	}))


# Ripopola la scheda 👨‍👩‍👧 con i dati correnti — stessa identica chiamata di _ready() (vedi lì),
# estratta per essere riusabile anche da _on_year_rolled_over sotto.
func _refresh_population_panel() -> void:
	human_population_info_panel.show_population(
		human_population_group.total_count, human_individuals, game_data.year,
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		human_folk.id, human_population_group.id, _compute_housing_capacity()
	)


# Somma di rules.max_residents sui soli edifici COMPLETI con max_residents > 0 (2026-09-12,
# richiesta utente — "quanto spazio abitativo esiste", per HumanPopulationInfoPanel.show_population)
# — STESSO identico criterio già usato da AssignHouseService.assign_pending_residents per decidere
# quali edifici hanno posti letto assegnabili (nessuna lettura esplicita di building.rules.category
# == RESIDENTIAL: quel service non lo fa, quindi nemmeno questo conteggio, per restare coerenti —
# un ipotetico futuro edificio non-RESIDENTIAL con max_residents > 0 conterebbe comunque qui,
# esattamente come conterebbe per l'assegnazione vera).
func _compute_housing_capacity() -> int:
	if macro_world == null:
		return 0
	var capacity := 0
	for building in macro_world.buildings:
		if building.rules == null or building.rules.max_residents <= 0:
			continue
		if not building.is_complete:
			continue
		capacity += building.rules.max_residents
	return capacity


# Gemella di _refresh_population_panel sopra, per la scheda 🏠 (2026-09-12, richiesta utente) —
# macro_world.buildings è già Array[Building], passato tale e quale (nessuna trasformazione,
# BuildingsInfoPanel.show_buildings fa già tutto il lavoro di presentazione). Chiamata da tre punti
# (vedi i call site): al piazzamento di un cantiere (nuovo edificio in lista, "in costruzione"),
# al completamento costruzione (stato -> "completo"), e da _on_year_rolled_over come rete di
# sicurezza periodica — STESSO schema di _refresh_population_panel, riusato per coerenza invece di
# inventare un meccanismo diverso.
func _refresh_buildings_panel() -> void:
	var buildings: Array[Building] = macro_world.buildings if macro_world != null else []
	buildings_info_panel.show_buildings(buildings)


# Reazione a GameInfoTabs.tab_changed (segnale NATIVO di TabContainer, nessuna estensione
# necessaria in GameInfoTabs.gd) — rinfresca task_debug_panel SOLO quando l'utente entra proprio
# sulla tab 🐞 (2026-09-12, richiesta utente): evitare di ricostruire quella lista ad ogni cambio
# tab qualunque (Population/Edifici/Selezione), lavoro sprecato per una scheda che l'utente
# potrebbe non aprire mai in quella sessione.
func _on_game_info_tab_changed(tab: int) -> void:
	if tab == GameInfoTabs.TAB_DEBUG:
		task_debug_panel.refresh()


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
			_update_individual_panel_content(member)
			return


# Gemella di _refresh_selected_individual_panel sopra, per SelectionKind.BUILDING (2026-09-09,
# richiesta utente) — _refresh_building_panel() già ri-risolve building_id dal roster vero
# (_find_building_by_id) e richiama building_info_panel.show_building(building), quindi riflette
# SEMPRE lo stato attuale di stored_resources: nessuna logica nuova da scrivere qui, solo il
# gancio giornaliero mancante (prima si aggiornava solo cambiando selezione).
func _refresh_selected_building_panel() -> void:
	if _selection_kind != SelectionKind.BUILDING:
		return
	_refresh_building_panel()


# Step 6 piano mortalità (2026-09-05): rimuove/libera la HumanIndividualView corrispondente
# all'individuo appena morto, ALLO STESSO indice che aveva in human_individuals nel momento in
# cui GameTimeService ha emesso il segnale (vedi commento alla connessione in _setup_clock) —
# human_individual_views è parallelo per indice a human_individuals, quindi va tenuto allineato
# qui, un solo punto, ogni volta che quest'ultimo perde un elemento.
#
# Se il morto era anche l'individuo selezionato (bugfix, richiesta utente, 2026-09-05: cliccare
# il suo nome ancora elencato nel pannello riportava su un posto vuoto E mostrava ancora i suoi
# dati/età come se fosse vivo), chiudiamo subito la selezione — stessa sequenza già usata da
# _clear_individual_selection altrove, no-op se il pannello non era comunque visibile. NOTO ma
# non affrontato: se era il bersaglio di movimento/streaming corrente (var individual, un ruolo
# indipendente dalla selezione), quel riferimento resta stantio — rimandato a un prossimo passo
# se si rivela un problema reale in gioco.
#
# Sistema notifiche (2026-09-05): accoda un popup DEATH se UserOptions.show_notification_popups —
# opzione utente/installazione (2026-09-05, non più di partita: vedi UserOptions, spostata da
# GameData dopo discussione con l'utente — nessuno vuole i popup attivi in un save e disattivi in
# un altro). Il flag riguarda SOLO questa riga, il log console [HUMAN DEATH] (in GameTimeService)
# resta sempre attivo indipendentemente, come richiesto. age_at_death/partner_freed/cause/day
# arrivano già calcolati dal segnale (vedi GameTimeService, che non sa nulla di UI/popup).
#
# cause/day (Step 9, 2026-09-05): parametri nuovi sulla firma del segnale — day sostituisce la
# lettura diretta di individual.scheduled_death_day di prima (che per una morte immediata di
# debug, causa MURDER, sarebbe rimasto -1, mai passando da quel campo). cause (Step 9e) ora
# costruisce la chiave di traduzione "death_cause_{nome_enum_minuscolo}" invece del fisso
# "death_cause_old_age" di prima — funziona per qualunque causa futura senza toccare questo file,
# a patto che esista la chiave tr() corrispondente (vedi strings.csv: death_cause_old_age/
# death_cause_murder).
func _on_human_individual_died(
	individual: HumanIndividual, index: int, age_at_death: int, partner_freed: bool,
	cause: DeathTypes.DeathCause, day: int
) -> void:
	if index < 0 or index >= human_individual_views.size():
		return
	var view := human_individual_views[index]
	human_individual_views.remove_at(index)
	if view != null and is_instance_valid(view):
		view.queue_free()
	if individual.is_selected:
		_clear_individual_selection()
	# Step 5 del sistema oggetti-scaduti (2026-09-05): comparsa della DeadBodyView nello STESSO
	# punto/segnale già usato per la comparsa del record expired_objects (Step 3, dentro
	# GameTimeService._kill_individual, appena prima che questo stesso segnale scattasse) — non
	# dentro GameTimeService stesso (dichiaratamente agnostico su UI/rendering, vedi il commento sul
	# segnale). Letto direttamente da `individual` (l'oggetto resta valido finché qualcuno lo
	# referenzia, anche se già rimosso da human_individuals) invece che da
	# game_data.expired_objects[-1]: stessi identici dati, senza dipendere da un indice fragile
	# nell'array. Nessuna view se home_macro_coords non è (più) una cella viva — stesso principio
	# del resto del progetto, niente si disegna fuori dal focus LOD.
	if live_cells.has(individual.home_macro_coords):
		var dead_body_view := DeadBodyView.new()
		live_cells[individual.home_macro_coords].container.add_child(dead_body_view)
		dead_body_view.setup_dead_body(
			individual.position, individual.sex, age_at_death, individual.hair_color, individual.clothing_color,
			game_data.year, day, human_folk.human_rules_ref if human_folk != null else null, game_data
		)
		dead_body_view.z_index = 1
		# Bugfix, 2026-09-05: serve per accendere il cerchiolino di selezione sulla view giusta se
		# questo corpo viene selezionato in seguito — vedi dead_body_views/_select_dead_body.
		dead_body_views[individual.id] = dead_body_view
	if UserOptions.show_notification_popups:
		var cause_key := "death_cause_%s" % String(DeathTypes.DeathCause.keys()[cause]).to_lower()
		notification_popup.enqueue(
			NotificationTypes.NotificationPopupType.DEATH,
			tr("notification_death").format({
				"name": individual.name,
				"cause": tr(cause_key),
				"age": age_at_death,
				"day": day
			})
		)
	# AssignHouseService (2026-09-12, richiesta utente — trigger 4c: "quando un individuo muore...
	# libera lo slot e prova a riassegnare eventuali individui in attesa, ma se non ce ne sono il
	# servizio semplicemente non fa nulla") — individual_died è EMESSO PRIMA della rimozione da
	# human_individuals dentro GameTimeService._kill_individual (vedi lì, commento esplicito "emesso
	# prima della rimozione, indice ancora valido"): `individual` è quindi ANCORA presente in
	# human_individuals in questo punto. Costruita qui una copia che lo ESCLUDE (mai una rimozione
	# vera qui — resta responsabilità esclusiva di GameTimeService, invariata) — altrimenti
	# occuperebbe ancora il proprio slot nel conteggio occupanti E verrebbe trattato erroneamente
	# come "in attesa di casa" lui stesso (il suo house_id non viene toccato da questo handler, resta
	# quello che aveva). Se `individual` occupava davvero uno slot residenziale, questo lo libera
	# automaticamente per il prossimo in coda per anzianità — se nessuno è in attesa, nessun effetto
	# (nessun turnover forzato di chi ha già casa, come richiesto).
	var living_individuals: Array[HumanIndividual] = []
	for other in human_individuals:
		if other != individual:
			living_individuals.append(other)
	AssignHouseService.assign_pending_residents(macro_world, living_individuals, game_data.year)


# Step 4 del piano riproduzione (2026-09-06) — schema simmetrico di _on_human_individual_died
# sopra: HumanBirthIndividualService aggiunge SEMPRE in coda a human_individuals (stesso array per
# riferimento di GameTimeService._human_individuals, mai a metà array), un append per volta, PRIMA
# di emettere individual_born una volta per ciascun neonato (anche con più nascite nello stesso
# giorno) — quindi human_individual_views.append(view) qui, chiamato una volta per segnale nello
# stesso ordine, mantiene il parallelismo per indice tra le due collezioni una volta processati
# tutti i segnali di questo giorno, nessun indice esplicito da gestire come per la rimozione.
# Stesso identico pattern di
# creazione view già usato in _ready() per il seeding iniziale (HumanIndividualView.new() ->
# parenta sotto il container della cella giusta -> setup() -> z_index -> append). Nessuna view se
# home_macro_coords non è (più) una cella viva — stesso principio già applicato a DeadBodyView in
# _on_human_individual_died: niente si disegna fuori dal focus LOD.
func _on_human_individual_born(individual: HumanIndividual) -> void:
	# AssignHouseService (2026-09-12, richiesta utente — trigger 4b: "quando nasce un nuovo
	# individuo") — chiamata PRIMA del guard "cella viva" sotto (l'assegnazione non ha nulla a che
	# fare col rendering, deve funzionare anche per una nascita fuori dal LOD corrente). Il neonato
	# è già presente in human_individuals a questo punto (HumanBirthIndividualService.gd lo aggiunge
	# SEMPRE in coda PRIMA di emettere individual_born, vedi il commento sotto su human_individual_
	# views) con house_id == -1 di default (HumanIndividual.gd) — è quindi già candidato "senza
	# casa" per questa stessa chiamata.
	AssignHouseService.assign_pending_residents(macro_world, human_individuals, game_data.year)
	if not live_cells.has(individual.home_macro_coords):
		return
	var view := HumanIndividualView.new()
	live_cells[individual.home_macro_coords].container.add_child(view)
	view.setup(individual, game_data, human_folk.human_rules_ref if human_folk != null else null)
	view.clock = clock
	view.z_index = 1
	human_individual_views.append(view)
	# Sistema notifiche, effetto nato-morto (2026-09-06) — stesso gate/schema di
	# _on_human_individual_died per la morte: UserOptions.show_notification_popups è
	# un'impostazione utente/installazione, non di partita. birth_verb/offspring_word dipendono dal
	# sesso tirato sul neonato (mai un fisso "nato/a" — a differenza di notification_death, qui il
	# sesso è già noto per certo, non serve una forma ambigua). mother_name risolto via
	# _find_human_individual_by_id sopra: la madre esiste di sicuro in questo istante (lo stesso
	# HumanBirthIndividualService l'ha appena processata), "?" resta solo un fallback difensivo.
	if UserOptions.show_notification_popups:
		var is_male := individual.sex == HumanTypes.Sex.MALE
		var mother := _find_human_individual_by_id(individual.mother_id)
		notification_popup.enqueue(
			NotificationTypes.NotificationPopupType.BIRTH,
			tr("notification_birth").format({
				"name": individual.name,
				"birth_verb": tr("birth_verb_male" if is_male else "birth_verb_female"),
				"offspring_word": tr("offspring_word_male" if is_male else "offspring_word_female"),
				"mother": mother.name if mother != null else "?",
			})
		)


# Effetto nato-morto (2026-09-06) — simmetrico a _on_human_individual_born sopra ma senza nessuna
# view da creare (nessun HumanIndividual è mai esistito, vedi GameTimeService.human_stillbirth):
# solo il popup di notifica, stesso gate UserOptions.show_notification_popups.
func _on_human_stillbirth(mother: HumanIndividual) -> void:
	if not UserOptions.show_notification_popups:
		return
	notification_popup.enqueue(
		NotificationTypes.NotificationPopupType.BIRTH,
		tr("notification_stillbirth").format({"mother": mother.name})
	)


# Sblocco Idea (2026-09-07, richiesta utente) — collegato a TechTreePanel.idea_completed: stesso
# identico NotificationPopup/stesso gate UserOptions.show_notification_popups di morte/nascita
# sopra (un'impostazione utente/installazione, non di partita — si disattiva insieme alle altre da
# Opzioni, richiesta esplicita). display_name è una chiave tr() (vedi Idea.gd), mai testo diretto —
# stesso trattamento già corretto in _refresh_building_slots_buildable/TechTreePanel.
func _on_idea_completed(idea_id: String) -> void:
	if not UserOptions.show_notification_popups:
		return
	var completed_idea := IdeaCalculator.get_idea(idea_id)
	var display_name: String = tr(completed_idea.display_name) if completed_idea != null else idea_id
	notification_popup.enqueue(
		NotificationTypes.NotificationPopupType.IDEA_COMPLETED,
		tr("notification_idea_completed").format({"idea": display_name})
	)


# Decadimento zaino (2026-09-09, richiesta utente, Step 3 decadimento) — stesso gate/stesso
# NotificationPopup di morte/nascita/idea sopra. resource_name/quantity arrivano già risolti dal
# segnale (GameTimeService.individual_resource_decayed non sa nulla di UI) — IconRegistry.
# get_resource_display_name per un nome leggibile invece del resource_name grezzo, stessa fonte già
# usata dal riquadro zaino/griglia storage magazzino (coerenza tra ogni punto che mostra il nome di
# una risorsa).
func _on_individual_resource_decayed(individual: HumanIndividual, resource_name: String, quantity: int) -> void:
	if not UserOptions.show_notification_popups:
		return
	notification_popup.enqueue(
		NotificationTypes.NotificationPopupType.RESOURCE_DECAYED,
		tr("notification_resource_decayed_individual").format({
			"name": individual.name,
			"quantity": NumberFormatter.format_int(quantity),
			"resource": IconRegistry.get_resource_display_name(resource_name),
		})
	)


# Gemella della funzione sopra, per il decadimento storage edifici (2026-09-09) — collegata a
# clock.building_resources_decayed (WorldTimeService, non GameTimeService: gli edifici decadono
# nel tick di scala mondo, vedi WorldTimeService._run_daily_building_resource_decay). Un ENQUEUE
# PER EVENTO (mai un unico popup aggregato per tutti gli eventi del giorno) — stesso principio "un
# enqueue per fatto" già seguito da morte/nascita, NotificationPopup accoda da sé senza sovrapporsi.
# building.rules null solo per dati incoerenti (mai in pratica, ogni Building vivo ha sempre rules
# risolte da BuildingCalculator) — fallback su building_type_name grezzo, stesso trattamento già in
# uso altrove nel progetto per lo stesso caso limite (es. GameScene._select_building).
func _on_building_resources_decayed(events: Array) -> void:
	if not UserOptions.show_notification_popups:
		return
	for event in events:
		var building: Building = event["building"]
		var building_display_name: String = (
			tr(building.rules.building_name) if building.rules != null else building.building_type_name
		)
		notification_popup.enqueue(
			NotificationTypes.NotificationPopupType.RESOURCE_DECAYED,
			tr("notification_resource_decayed_building").format({
				"quantity": NumberFormatter.format_int(int(event["quantity"])),
				"resource": IconRegistry.get_resource_display_name(String(event["resource_name"])),
				"building": building_display_name,
				"id": building.id,
			})
		)


# Cantiere bloccato per mancanza di materiale (2026-09-14, richiesta utente) — collegata a
# individual_action_service.building_material_blocked (vedi _setup_clock), emesso SOLO alla
# transizione false->true di Building.is_awaiting_material (mai ripetuto finché il blocco persiste
# — la garanzia "una volta sola" vive già in HumanIndividualActionService._resolve_material_shortage,
# questo handler si limita a mostrare il popup, stesso principio "componente muto" di ogni altro
# handler notifica qui). Testo GENERICO (richiesta esplicita punto 2: "non specifica su quantità/
# materiale") — stesso fallback building_display_name di _on_building_resources_decayed sopra.
func _on_building_material_blocked(building: Building) -> void:
	if not UserOptions.show_notification_popups:
		return
	var building_display_name: String = (
		tr(building.rules.building_name) if building.rules != null else building.building_type_name
	)
	notification_popup.enqueue(
		NotificationTypes.NotificationPopupType.MATERIAL_NEEDED,
		tr("notification_building_material_needed").format({"building": building_display_name})
	)


# Discard esplicito sulla mappa (2026-09-14, richiesta utente — collegata a
# individual_action_service.carried_resource_discarded, vedi _setup_clock/il commento sul segnale
# stesso) — SOLO l'effetto visivo (_spawn_carried_resource_discarded_effect, vedi sopra): nessun
# popup NotificationPopup per questo evento (richiesta esplicita, "un simbolo sulla mappa", non una
# notifica testuale — a differenza di _on_building_material_blocked sopra, che invece è un vero
# popup). resource_name/quantity ricevuti ma non ancora usati nell'effetto visivo stesso (solo
# nel log DebugLogging già stampato da _handle_pending_warehouse_search) — tenuti in firma per
# coerenza col segnale/per un futuro tooltip, senza dover cambiare la firma quando servirà davvero.
func _on_carried_resource_discarded(individual: HumanIndividual, resource_name: String, quantity: int) -> void:
	_spawn_carried_resource_discarded_effect(individual)


# Step 6 piano mortalità (2026-09-05): rinfresca la scheda 👨‍👩‍👧 DOPO che tutte le rimozioni/
# total_count del giorno sono già stati applicati (vedi GameTimeService.human_population_changed
# per il perché non basta agganciarsi a individual_died sopra: quel segnale scatta PRIMA della
# rimozione vera, mostrerebbe ancora dati vecchi). Bugfix, richiesta utente, 2026-09-05: la view
# spariva subito ma il pannello popolazione restava coi dati vecchi fino al prossimo rollover
# d'anno, l'unico altro punto che lo richiamava. Stesso motivo copre ora anche le nascite (vedi
# GameTimeService._run_annual_human_births, che emette lo stesso segnale).
func _on_human_population_changed() -> void:
	_refresh_population_panel()


# Bugfix (richiesta utente, 2026-09-05 — vedi commento alla connessione in _setup_clock): tiene
# sincronizzati i due pannelli umani col passare degli anni, non solo su un nuovo popolamento/una
# nuova selezione manuale.
func _on_year_rolled_over() -> void:
	_refresh_population_panel()
	_refresh_selected_individual_panel()
	# Rete di sicurezza periodica per la scheda 🏠 (2026-09-12, richiesta utente) — stesso principio
	# di _refresh_population_panel sopra.
	_refresh_buildings_panel()
	# Snapshot edifici/anno (2026-09-12, richiesta utente — tab Statistiche/Edifici, vedi GameData.
	# building_snapshots) — STESSO schema di GameTimeService._on_year_rolled_over per
	# population_snapshots, ma scritto QUI (non lì): GameTimeService non possiede macro_world/
	# buildings (vedi i suoi campi, solo human_individuals/folk/population_group), mentre GameScene
	# li ha già a portata di mano per _refresh_buildings_panel appena sopra.
	game_data.building_snapshots[game_data.year] = macro_world.buildings.size() if macro_world != null else 0


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
# Sintomo 2 (movimento residuo) — STORICO, RISOLTO IN MODO DIVERSO (2026-09-02 -> 2026-09-12): a
# quell'epoca, sia `target.stop()` (sul NUOVO bersaglio, rimosso dal bugfix 2026-09-07 sotto) sia
# poi `individual.is_moving = false; individual.path.clear()` (sul VECCHIO bersaglio, bugfix
# 2026-09-12) tentavano di "ripulire" un residuo di movimento al cambio di selezione. ENTRAMBI
# gli approcci sono stati infine RIMOSSI del tutto (2026-09-12, richiesta utente — bug reale
# confermato con test in-game: due individui con haul_resource attiva in parallelo, selezionarne
# uno secondo congelava per sempre il WalkAction del primo, perché is_moving=false su un individuo
# con una Task DAVVERO in corso non viene mai più rimesso a true da nessun altro punto del codice —
# WalkAction.is_complete() confronta position/target, mai più vero se position smette di avanzare):
# il motivo originale del 2026-09-02 (evitare un'animazione di cammino "congelata" quando
# l'individuo smetteva di essere PROCESSATO) non esiste più da quando GameScene._process avanza
# TUTTI gli individui con una Task attiva ad ogni frame, indipendentemente dalla selezione — non
# c'è quindi più nulla da "fermare" quando la selezione cambia: is_moving/path del vecchio bersaglio
# restano quello che erano, e continuano ad evolvere per conto proprio nel ciclo di _process
# esattamente come per qualunque altro individuo non selezionato. Cambiare selezione oggi non
# esegue PIÙ alcuna azione sul vecchio bersaglio — zero effetti collaterali sul suo stato di
# movimento/Task, per costruzione.
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
	# NESSUNA azione sul vecchio bersaglio (`individual`, prima di essere sovrascritto sotto) — vedi
	# il commento di testa alla funzione, "Sintomo 2", per la storia completa di cosa viveva qui e
	# perché è stato rimosso del tutto (non solo "svuotato", proprio eliminato — nessun `if target !=
	# individual` residuo): cambiare selezione non deve avere ALCUN effetto collaterale sullo stato
	# di movimento/Task di chi si sta deselezionando, ora che _process lo avanza comunque.
	_recenter_live_cells_on(target.home_macro_coords)

	individual = target
	individual_controller.setup(individual, live_cells[center_macro_coords].renderer, game_data)


# Estratta da _set_movement_target sopra (2026-09-12, richiesta utente — pannello edifici, bottone
# "vai lì": la STESSA ri-ancoratura dello streaming live_cells serviva anche per un edificio, non
# solo per un individuo) — ri-ancora l'intero streaming (camera+center_macro_coords+live_cells+LOD)
# su `macro_coords`, ESATTAMENTE come faceva prima solo questa porzione di _set_movement_target,
# generalizzata al parametro. No-op se `macro_coords` è già il centro corrente (stesso guard di
# prima). NON tocca `individual`/individual_controller — quella parte resta specifica di
# _set_movement_target, che la applica DOPO aver chiamato questo helper.
#
# Timing DIAGNOSTICO (2026-09-12, richiesta utente — "il movimento che porta alla persona... è
# molto più lento e a scatti... puoi capire/mettere log dedicati?", vedi il commento esteso in
# _on_population_individual_center_requested per l'ipotesi) — misura SOLO _reposition_live_cells,
# il sospetto principale per lo scatto riportato (ricostruzione sincrona di più MicroCellRenderer
# quando il bersaglio è lontano dal centro corrente). Stesso stile Time.get_ticks_usec() già in
# uso in _on_day_advanced per lo stesso scopo.
func _recenter_live_cells_on(macro_coords: Vector2i) -> void:
	if macro_coords == center_macro_coords:
		return
	if _center_camera_tween != null:
		_center_camera_tween.kill()
	camera.position -= Vector2(macro_coords - center_macro_coords) * MACRO_CELL_PIXELS
	var _debug_old_center_macro_coords := center_macro_coords
	center_macro_coords = macro_coords
	var _debug_reposition_start_usec := Time.get_ticks_usec()
	_reposition_live_cells()
	if DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
		var _debug_reposition_elapsed_ms: float = (Time.get_ticks_usec() - _debug_reposition_start_usec) / 1000.0
		print("[CENTER DEBUG] _reposition_live_cells %s -> %s = %.1fms" % [
			_debug_old_center_macro_coords, center_macro_coords, _debug_reposition_elapsed_ms
		])
	_refresh_lod_focus_region()
	_update_center_info_panel()


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
	game_info_tabs.set_selection_title(tr("selection_title_type").format({"type": GameTypes.WorldObjectType.keys()[object_type].capitalize()}))

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
# Step 9d piano mortalità (2026-09-05): bottone "Kill (debug)" di HumanIndividualInfoPanel —
# individual arriva già risolto nel segnale (vedi HumanIndividualInfoPanel._current_individual),
# nessuna riscansione di human_individuals qui. null possibile solo se il segnale scattasse a
# pannello già svuotato (non dovrebbe: il bottone non è raggiungibile da un pannello nascosto) —
# guardia difensiva comunque, stesso principio del resto del file. La rimozione vera/il log/il
# DeathEvent/il popup passano tutti dal normale percorso individual_died già esistente
# (GameTimeService.kill_individual_now -> _kill_individual, vedi lì).
func _on_kill_requested(individual: HumanIndividual) -> void:
	if individual == null:
		return
	game_time_service.kill_individual_now(individual)


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
			stone_service.generate_if_needed(cell.macro_state, cell.macro_cell)
			cell.renderer.set_stone_positions(cell.macro_state.stone_positions)
			# Pebble (2026-09-08, richiesta utente) — NON più sincronizzato qui a parte (2026-09-09,
			# richiesta utente, bugfix "pebble/stick restano disegnati dopo la raccolta"): la prima
			# sincronizzazione avviene già dentro _refresh_resource_visuals sotto (chiamata poche righe
			# più giù), insieme a stick e con lo stesso filtro FoW — un'unica fonte di verità per
			# QUANDO risincronizzare pebble/stick, invece di due percorsi paralleli (uno qui, uno lì)
			# facili da disallineare in futuro. MacroCellState.pebble_quantities è comunque già
			# popolato da generate_if_needed insieme a stone_positions, pronto per quella chiamata.

			# _refresh_building_visuals PRIMA di _refresh_resource_visuals (ordine invertito rispetto
			# a prima, 2026-08-30/Proposta 2): quest'ultima ora filtra cosa costruire nel renderer in
			# base a FogOfWarRenderer.compute_visible_positions, che legge anche _building_visible_
			# positions — se girasse prima di _refresh_building_visuals, alla primissima attivazione di
			# una cella-edificio quell'insieme sarebbe ancora vuoto e le posizioni vicino all'edificio
			# verrebbero scartate dal primo rebuild (si autocorregge al refresh successivo, ma
			# nessun motivo di lasciare quella finestra scorretta quando basta invertire due righe).
			_refresh_building_visuals(cell)
			_refresh_resource_visuals(cell)
			# Bugfix reload "bastoncini agli angoli spariti" (2026-09-15) — vedi il commento esteso su
			# _create_build_site_placeholder_nodes/_restore_build_site_placeholders_for_cell.
			_restore_build_site_placeholders_for_cell(cell)

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
	# Stessa cura di vegetazione/edifici sopra (2026-09-08, richiesta utente — evidenziazione STONE
	# appena aggiunta): il renderer che sta per essere distrutto è quello che possiede il contorno.
	if not selected_stone.is_empty() and selected_stone["macro_coords"] == coords:
		_clear_stone_selection()
	# Stessa cura di stone sopra (2026-09-08, richiesta utente — click sul terreno TREE): il
	# renderer che sta per essere distrutto è quello che possiede il contorno quadrato del lotto.
	if not selected_stick_lot.is_empty() and selected_stick_lot["macro_coords"] == coords:
		_clear_stick_lot_selection()
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

	var lod_result := LODOrchestrator.new().set_focus_region(
		macro_world, focus_live_cells, SeasonCalculator.get_season_for_day(game_data.current_day)
	)
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
# _process per OGNI individuo attivo (2026-09-12, richiesta utente — piano multi-individuo, Step 4:
# PRIMA operava solo sul singolo `individual` selezionato/controllato dal player, letto da un campo
# di GameScene invece che da un parametro — senza questa generalizzazione un individuo non
# selezionato che cammina fuori dal bordo della propria macrocella, es. una Task haul_resource/Build
# con un target in una macrocella adiacente, non verrebbe mai rilevato: home_macro_coords/posizione
# resterebbero disallineate per sempre). Un controllo per asse, non un unico controllo combinato:
# in caso di uscita diagonale (entrambi gli assi fuori range nello stesso frame) i due controlli
# vengono comunque eseguiti in sequenza nella stessa chiamata, gestendo il caso come due
# attraversamenti 4-connessi consecutivi (es. prima verso est, poi verso nord) invece di
# richiedere un vicino diagonale non previsto (sempre e solo N/S/E/O).
func _check_macro_cell_border_crossing(target_individual: HumanIndividual) -> void:
	if macro_world == null:
		return

	if target_individual.position.x < 0.0:
		_attempt_macro_cell_transition(target_individual, -1, 0)
	elif target_individual.position.x >= float(World.WIDTH):
		_attempt_macro_cell_transition(target_individual, 1, 0)

	if target_individual.position.y < 0.0:
		_attempt_macro_cell_transition(target_individual, 0, -1)
	elif target_individual.position.y >= float(World.HEIGHT):
		_attempt_macro_cell_transition(target_individual, 0, 1)


# Gestisce un tentativo di uscita in direzione (dx, dy) per `target_individual` — sempre un solo
# asse alla volta, l'altro è sempre 0 (vedi _check_macro_cell_border_crossing sopra). Se la
# macrocella adiacente non esiste (bordo del mondo) o la microcella di ingresso è acqua,
# l'individuo resta all'ultima posizione valida (_block_border_crossing, nessun attraversamento).
# Altrimenti conferma subito il cambio macrocella riusando lo stesso percorso di caricamento di
# _ready() (_activate_live_cell, di norma già eseguito in anticipo da _update_live_neighbor SOLO
# per il bersaglio della camera — vedi la rete di sicurezza sotto per il caso raro/per chiunque
# altro in cui non lo sia ancora).
#
# GENERALIZZATA (2026-09-12, richiesta utente — piano multi-individuo, Step 4) — origin_macro_coords
# ora letta da `target_individual.home_macro_coords` (PRIMA: da `center_macro_coords`, che coincide
# con la macrocella del bersaglio SOLO perché prima esisteva un solo bersaglio possibile, quello
# della camera): usare ancora center_macro_coords qui per un individuo qualunque avrebbe calcolato
# la macrocella di destinazione partendo dal posto SBAGLIATO ogni volta che target_individual non è
# quello selezionato. Il resto della funzione si divide ora in due parti — vedi `is_camera_focus`
# sotto: (1) aggiornamento posizione/home_macro_coords/view, SEMPRE eseguito per QUALUNQUE
# individuo (serve al modello di simulazione, indipendente da chi è selezionato); (2) ri-ancoraggio
# di camera/streaming/LOD (center_macro_coords, camera.position, _reposition_live_cells,
# _refresh_lod_focus_region, _update_center_info_panel, individual_controller.setup),
# ESEGUITO SOLO quando target_individual è il bersaglio della camera — quella macchina esiste UNA
# volta sola per l'intera scena (una sola camera), non ha senso ri-ancorarla su un individuo che il
# player non sta nemmeno guardando.
func _attempt_macro_cell_transition(target_individual: HumanIndividual, dx: int, dy: int) -> void:
	var origin_macro_coords := target_individual.home_macro_coords
	var target_x := origin_macro_coords.x + dx
	var target_y := origin_macro_coords.y + dy
	var target_cell := macro_world.get_cell_at(target_x, target_y)

	if target_cell == null:
		_block_border_crossing(target_individual, dx, dy)
		return

	# Posizione di ingresso nella macrocella adiacente: la posizione "avvolge" dal lato opposto,
	# preservando la parte frazionaria per continuità visiva (uscire a x=100.3 verso est entra a
	# x=0.3 nella macrocella a est, non uno snap secco a 0.0). Solo l'asse attraversato cambia.
	var entry_position := target_individual.position
	if dx == 1:
		entry_position.x -= float(World.WIDTH)
	elif dx == -1:
		entry_position.x += float(World.WIDTH)
	if dy == 1:
		entry_position.y -= float(World.HEIGHT)
	elif dy == -1:
		entry_position.y += float(World.HEIGHT)

	if _is_entry_microcell_water(target_cell, entry_position):
		_block_border_crossing(target_individual, dx, dy)
		return

	# Ribasamento GENERALIZZATO a ogni step posizionale non ancora completato, current_task E
	# task_queue (2026-09-16, richiesta utente, fix bordo macrocella per le task perditempo, CAUSA
	# A) — PRIMA di questo passo veniva ribasato SOLO il WalkAction ATTIVO: una Task multi-Walk che
	# risolve TUTTI i propri target assoluti in un colpo solo all'assegnazione (Wander/Play/Leisure
	# Rest, ma il meccanismo è generico, vale per qualunque Task con lo stesso schema — es. il Walk
	# di haul_resource/transport verso una posizione fissa) lasciava le gambe FUTURE e le Task
	# sospese in coda nel vecchio sistema di riferimento, puntando a un target sbagliato quando
	# diventavano attive. Task.rebase_positional_targets (Task.gd) fa il lavoro vero: ribasa
	# Action.target per ogni step da current_step_index in poi la cui `target` sia un Vector2 (solo
	# WalkAction/RunAction lo valorizzano così — ogni altra Action, es. quelle basate su
	# target_building, si ri-deriva da sola da home_macro_coords, già aggiornato più sotto, quindi
	# non ha bisogno di alcun ribasamento esplicito qui).
	# Ribasamento del WalkAction attivo, NON un semplice arresto (2026-09-12, richiesta utente —
	# CORREZIONE di un bug gemello a quello risolto in _set_movement_target: qui viveva prima
	# `target_individual.is_moving = false` e basta — corretto per NON azzerare più current_task/
	# TaskDebugRegistry come il vecchio `.stop()` pieno, ma comunque distruttivo in un modo più
	# sottile: un WalkAction realmente in corso lasciato con is_moving=false non riparte mai da
	# solo, perché nessun altro punto del codice lo rimette a true per QUESTO stesso step — la Task
	# risultava "in corso" per sempre senza mai avanzare, stesso identico sintomo del bug in
	# _set_movement_target, innescato però da un attraversamento di bordo invece che da un cambio di
	# selezione). A differenza del caso _set_movement_target — dove rimuovere l'azione basta, perché
	# lì non cambia nulla nel riferimento spaziale dell'individuo — QUI il motivo per cui il vecchio
	# codice toccava lo stato di movimento resta legittimo: `target` di una WalkAction è un Vector2
	# scritto UNA SOLA VOLTA al costruttore (vedi WalkAction.gd, _init) e mai più aggiornato da
	# nessun altro punto del codice — dopo un attraversamento bordo, position viene ri-basata sulla
	# NUOVA macrocella (entry_position sopra) ma `target` resterebbe espresso nel riferimento della
	# VECCHIA, rendendo WalkAction.is_complete() (position == target) non più vero per costruzione:
	# la destinazione ASSOLUTA non è cambiata, solo il sistema di riferimento locale in cui va
	# espressa — quindi la correzione giusta è ribasare `target` con lo STESSO offset appena
	# applicato a position (non azzerare nulla), poi far ripartire lo step con activate() più sotto,
	# una volta che home_macro_coords/position sono già quelli nuovi.
	#
	# `frame_offset` è lo stesso spostamento già usato per entry_position sopra, ricavato per
	# differenza (position non è ancora stata sovrascritta a questo punto della funzione) invece di
	# ricalcolarlo una seconda volta. `current_action is WalkAction` come guardia (non un controllo
	# su is_moving) — è l'UNICA Action che porta mai is_moving a true (vedi Action.gd/WalkAction.gd),
	# quindi se questo ramo è stato raggiunto (position uscita dal range, possibile solo per un
	# movimento reale) lo step attivo è per costruzione sempre una WalkAction; difensivo comunque —
	# nessun effetto se non lo fosse.
	var frame_offset := entry_position - target_individual.position
	var current_action: Action = null
	if target_individual.current_task != null:
		current_action = target_individual.current_task.get_current_action()
		var rebased_current := target_individual.current_task.rebase_positional_targets(frame_offset)
		if rebased_current > 0 and DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[BORDER] Individuo #%d %s: ribasati %d step posizionali di current_task '%s' (offset=%s)." % [
				target_individual.id, target_individual.name, rebased_current,
				target_individual.current_task.task_name, str(frame_offset)
			])
	# Task sospese in coda (2026-09-16) — STESSA ribasatura, stesso motivo: una Task ferma in
	# task_queue (es. haul_resource interrotta da un bisogno stamina mentre l'individuo è poi
	# tornato a Wander) può restare sospesa attraverso più attraversamenti di bordo prima di essere
	# ripresa — se il suo primo step futuro fosse un target assoluto già risolto, lo ritroverebbe
	# nel riferimento sbagliato al momento della ripresa.
	for queued_task in target_individual.task_queue:
		var rebased_queued := queued_task.rebase_positional_targets(frame_offset)
		if rebased_queued > 0 and DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
			print("[BORDER] Individuo #%d %s: ribasati %d step posizionali di una task in coda '%s' (offset=%s)." % [
				target_individual.id, target_individual.name, rebased_queued, queued_task.task_name, str(frame_offset)
			])

	var target_macro_coords := Vector2i(target_x, target_y)
	# is_camera_focus (2026-09-12) — vedi commento di testa alla funzione: separa l'aggiornamento
	# di simulazione (sempre) dal ri-ancoraggio di camera/streaming/LOD (solo per il bersaglio della
	# camera, che oggi coincide sempre con `individual`, il campo selezionato/controllato).
	var is_camera_focus := target_individual == individual

	if is_camera_focus:
		game_data.player_macro_cell_x = target_x
		game_data.player_macro_cell_y = target_y
		center_macro_coords = target_macro_coords

	# Rete di sicurezza — SEMPRE valutata, non solo per il bersaglio della camera (2026-09-12): non
	# dovrebbe capitare quasi mai per il bersaglio della camera stesso, dato il pre-caricamento per
	# prossimità (_update_live_neighbor gira ogni frame, ben prima che raggiunga davvero il bordo
	# vero, vedi LIVE_NEIGHBOR_ACTIVATE_MARGIN — ma quel pre-caricamento resta legato SOLO a lui);
	# per chiunque altro non c'è alcun pre-caricamento equivalente in corsa (_activate_all_
	# individual_cells gira una sola volta, in _ready() — vedi commento lì), quindi questa è
	# l'unica rete che garantisce che la cella di destinazione esista prima di riparentarvi la view.
	if not live_cells.has(target_macro_coords):
		_activate_live_cell(target_x, target_y)

	target_individual.position = entry_position
	# Aggiorna home_macro_coords e riparenta la HumanIndividualView sotto il nuovo container,
	# esattamente come farebbe _activate_live_cell per un renderer qualsiasi — GENERALIZZATO
	# (2026-09-12): PRIMA questo commento diceva "il bersaglio è l'UNICO individuo la cui macrocella
	# fisica cambia davvero (chiunque altro resta dov'era, mai mosso da nulla)", vero SOLO perché
	# prima nessun altro individuo veniva mai avanzato in autonomia — ora qualunque individuo attivo
	# può attraversare un bordo, quindi questo aggiornamento vale per `target_individual` chiunque
	# esso sia, non più solo per il bersaglio della camera. reparent() invece di
	# remove_child+add_child manuali: nessuna differenza pratica qui (HumanIndividualView._process
	# sovrascrive comunque position da zero subito dopo, ad ogni frame), ma è l'API dedicata di
	# Godot per lo scopo.
	target_individual.home_macro_coords = target_macro_coords
	var target_view_index := human_individuals.find(target_individual)
	if target_view_index != -1:
		human_individual_views[target_view_index].reparent(live_cells[target_macro_coords].container)

	# Fa RIPARTIRE lo step (2026-09-12) — ORA che position/home_macro_coords sono già quelli nuovi:
	# activate() su WalkAction/RunAction (vedi rispettivi .gd) scrive target_position dal `target`
	# GIÀ ribasato sopra e rimette is_moving a true, quindi il movimento prosegue nello stesso frame
	# verso la STESSA destinazione assoluta di prima, solo espressa nel riferimento locale corretto
	# — nessun frame "fermo" in mezzo, stesso principio già seguito da HumanIndividualActionService.
	# apply_action quando una Task avanza da uno step al successivo. Sempre eseguito (non solo per
	# il bersaglio della camera): il movimento di simulazione di un individuo non dipende da chi il
	# player sta guardando.
	#
	# GENERALIZZATO a `current_action.target is Vector2` (2026-09-16, richiesta utente, fix bordo
	# macrocella) — PRIMA il guard era `current_action is WalkAction`, quindi RunAction (l'unica
	# altra Action con un target posizionale, usata dalla Play Task) non veniva MAI riattivata dopo
	# un attraversamento: il target veniva comunque ribasato (Task.rebase_positional_targets sopra
	# lo copre già, essendo generico su Action.target), ma individual.target_position/is_moving
	# restavano quelli VECCHI finché quello step non fosse ridiventato attivo da capo — bug gemello
	# a quello di WalkAction, mai notato perché Play è CHILD-only e oggi comunque disattivata
	# insieme a Wander/Leisure Rest (WANDER_ENABLED/LEISURE_REST_ENABLED). Stesso guard generico già
	# usato da Task.rebase_positional_targets, nessun secondo elenco di classi da tenere allineato.
	if current_action != null and current_action.target is Vector2:
		current_action.activate(target_individual, target_individual.current_task.context)

	if not is_camera_focus:
		# Nessun ri-ancoraggio di camera/streaming/LOD per un individuo che il player non sta
		# guardando (vedi commento di testa alla funzione) — la sua cella è comunque già viva
		# (attivata sopra se mancante), quindi la sua HumanIndividualView continua a disegnarsi
		# correttamente senza che nulla della "vista" cambi.
		return

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


# Piano "trasporto neonati" (2026-09-06) — sincronizza la posizione (e, se serve, la macrocella/
# view) del figlio a carico di `mother`, se ce n'è uno. Vedi HumanIndividual.dependent_child_id per
# il ciclo di vita completo del campo: questa QUERY fa da sola la propria manutenzione (lo riporta a
# -1 quando il figlio non si trova più — morto — o ha superato la soglia d'età), nessun altro punto
# del codice lo tocca mai in scrittura a parte HumanBirthIndividualService (che lo valorizza una
# volta alla nascita). Funzione già generica fin dall'origine (prende `mother` come parametro, non
# legge mai `individual`/`center_macro_coords` di GameScene) — GENERALIZZATO IL CHIAMANTE (2026-09-12,
# richiesta utente, piano multi-individuo, Step 6): PRIMA veniva invocata una sola volta per frame,
# solo sul bersaglio selezionato/controllato dal player; ora _process la chiama per OGNI individuo
# attivo (con una Task in corso, vedi active_individuals lì), DOPO _check_macro_cell_border_crossing
# per QUELLO STESSO individuo (stesso ordine di sempre — se ha appena attraversato un bordo,
# home_macro_coords/position sono già quelli nuovi quando si sincronizza un suo eventuale figlio a
# carico, nello stesso frame). Costo O(1) nel caso comune (dependent_child_id == -1, la stragrande
# maggioranza delle madri in ogni momento), una ricerca lineare mirata SOLO quando c'è davvero un
# figlio da trasportare (mai una scansione generale "chi ha un figlio piccolo" ad ogni frame — è
# esattamente il costo che volevamo evitare).
func _sync_dependent_child_position(mother: HumanIndividual) -> void:
	if mother.dependent_child_id == -1:
		return
	var child: HumanIndividual = null
	for candidate in human_individuals:
		if candidate.id == mother.dependent_child_id:
			child = candidate
			break
	if child == null:
		# Non trovato (morto) — auto-manutenzione: pulisce il riferimento, mai più cercato nei
		# prossimi frame finché questa madre non avrà un nuovo figlio a carico.
		mother.dependent_child_id = -1
		return
	# age_band != INFANT (2026-09-12, richiesta utente — collegamento di HumanTypes.AgeBand.INFANT
	# al gameplay) SOSTITUISCE il precedente confronto numerico "child_age >= individual_controller.
	# min_movement_age_years()" (funzione rimossa, vedi HumanIndividualController.gd) — stessa
	# identica formula già in uso ovunque nel progetto, qui via _resolve_age_band.
	var child_age_band := _resolve_age_band(child)
	if child_age_band != HumanTypes.AgeBand.INFANT:
		# Cresciuto abbastanza — auto-manutenzione: pulisce il riferimento e smette di muoverlo;
		# resta semplicemente fermo dov'era, come chiunque altro non sia il bersaglio corrente,
		# finché non diventa lui stesso il bersaglio (a quel punto risponde ai comandi come tutti).
		mother.dependent_child_id = -1
		return
	# "Sempre a lato" (richiesta utente) — perpendicolare a facing_direction, STESSA identica
	# formula usata alla nascita (vedi HumanBirthIndividualService.DEPENDENT_CHILD_SIDE_OFFSET):
	# nessun "salto" percettibile la prima volta che la madre si muove dopo il parto.
	child.position = mother.position + mother.facing_direction.orthogonal() * HumanBirthIndividualService.DEPENDENT_CHILD_SIDE_OFFSET
	if child.home_macro_coords != mother.home_macro_coords:
		# La madre ha appena attraversato un bordo (_check_macro_cell_border_crossing è già girato
		# questo stesso frame, PRIMA di questa chiamata — vedi _process) — il figlio la segue nella
		# stessa nuova macrocella: stesso trattamento già applicato a lei in
		# _attempt_macro_cell_transition (home_macro_coords + riparentaggio della view), qui
		# ripetuto per lui. Guardie difensive (indice valido, cella viva): una nascita avvenuta
		# fuori da qualunque cella viva non avrebbe mai ricevuto una view (stesso principio "niente
		# si disegna fuori dal focus LOD" di DeadBodyView) — qui semplicemente non c'è nulla da
		# riparentare in quel caso, non un errore.
		child.home_macro_coords = mother.home_macro_coords
		var child_view_index := human_individuals.find(child)
		if child_view_index != -1 and child_view_index < human_individual_views.size() and live_cells.has(mother.home_macro_coords):
			human_individual_views[child_view_index].reparent(live_cells[mother.home_macro_coords].container)


# Ferma `target_individual` esattamente al bordo della macrocella ATTUALE (mai un'intera microcella
# indietro) sull'asse (dx, dy) che ha tentato l'uscita — usato sia per il bordo del mondo
# (nessuna macrocella adiacente) sia per un'acqua di destinazione (_is_entry_microcell_water).
# GENERALIZZATA (2026-09-12, richiesta utente — piano multi-individuo, Step 4): parametro esplicito
# invece del campo `individual` di GameScene, stesso motivo di _attempt_macro_cell_transition sopra.
# `individual.stop()` (pieno) SOSTITUITO con is_moving/path (stesso bugfix/stesso principio di
# _attempt_macro_cell_transition sopra — vedi quel commento per il dettaglio): un blocco al bordo
# non deve cancellare la Task di `target_individual`, solo il tragitto che l'ha portato lì.
#
# CASO DIVERSO da _attempt_macro_cell_transition (verificato esplicitamente, richiesta utente,
# 2026-09-12) — lì "far ripartire lo step" era possibile perché la destinazione ASSOLUTA restava
# raggiungibile, solo espressa nel riferimento sbagliato (ribasata con successo, vedi quella
# funzione). QUI non c'è alcuna macrocella nuova in cui ribasare `target`: il motivo per cui questa
# funzione viene chiamata è proprio che non esiste una macrocella adiacente (bordo del mondo) o che
# la destinazione è acqua — la destinazione del WalkAction è quindi GENUINAMENTE irraggiungibile in
# questa direzione, non solo espressa nel riferimento sbagliato. `is_moving = false` qui resta
# quindi legittimo (l'individuo non può proseguire, punto), ma la Task ATTIVA in questo caso
# specifico non riparte da sola (nessun altro punto la fa avanzare/interrompere quando il target
# resta semplicemente irraggiungibile) — GAP NOTO, non risolto in questo passo (fuori scope: servirebbe
# un meccanismo di "fallimento Task"/target irraggiungibile che oggi non esiste per nessuna Action,
# non solo per Walk), segnalato qui per quando servirà davvero risolverlo. Caso raro in pratica: un
# target di Task calcolato oltre il bordo del mondo o dentro l'acqua (es. WarehouseSelectionService/
# ThoughtTargetSelectionService già filtrano per edifici validi, ma un futuro target non filtrato
# allo stesso modo potrebbe incapparci).
func _block_border_crossing(target_individual: HumanIndividual, dx: int, dy: int) -> void:
	if dx == 1:
		target_individual.position.x = float(World.WIDTH) - BORDER_CLAMP_EPSILON
	elif dx == -1:
		target_individual.position.x = 0.0
	if dy == 1:
		target_individual.position.y = float(World.HEIGHT) - BORDER_CLAMP_EPSILON
	elif dy == -1:
		target_individual.position.y = 0.0
	target_individual.is_moving = false
	target_individual.path.clear()

	# CAUSA B (2026-09-16, richiesta utente, fix bordo macrocella) — PRIMA di questo passo, il
	# blocco sopra (clamp + is_moving=false) bastava a se stesso per QUALUNQUE Task: nessun altro
	# punto del codice rimette mai is_moving a true per LO STESSO step, e WalkAction/RunAction.
	# is_complete() confrontava position con target — bloccata sul bordo, mai più uguale al target
	# oltre il bordo — quindi quello step (e la Task intera) restava bloccato PER SEMPRE, l'unico
	# sblocco era il tasto H (individual.stop()).
	#
	# Da qui in poi: SOLO per le task perditempo (Task.is_idle_activity, vedi Task.gd/
	# task_definition.gd — oggi wander.tres/play.tres/leisure_rest.tres) una gamba bloccata al
	# bordo viene considerata CONCLUSA invece che bloccata — non hanno una destinazione "vera" da
	# raggiungere per forza (il punto è "passare il tempo", non arrivare esattamente lì), quindi
	# saltare alla gamba successiva è un compromesso ragionevole e invisibile al giocatore. Il
	# criterio è ESPLICITO (il campo Task.is_idle_activity), MAI un confronto su task_name.
	#
	# PER OGNI ALTRA TASK (haul_resource/build/transport/Rest/Emergency Rest/qualunque futura Task
	# di lavoro) il comportamento resta ESATTAMENTE quello di prima — richiesta esplicita
	# dell'utente ("per tutte le altre task NON cambiare il comportamento sul bordo bloccato"): uno
	# step bloccato al bordo per una di queste resta bloccato per sempre, stesso sintomo di sempre,
	# nessuna chiamata a finish_current_step per loro. Non essendo mai stato isolato un caso reale
	# in cui una Task di LAVORO arrivi a un bordo bloccato durante il normale gameplay (i target di
	# haul_resource/transport/build sono sempre risorse/edifici già dentro la macrocella
	# dell'individuo o raggiunti tramite Building.macro_x/y, mai un punto arbitrario che potrebbe
	# cadere fuori mappa), questo resta un rischio noto ma non affrontato in questo passo.
	var blocked_task := target_individual.current_task
	var is_idle_task := blocked_task != null and blocked_task.is_idle_activity
	if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
		print("[BORDER] Individuo #%d %s: movimento bloccato al bordo (dx=%d dy=%d — macrocella inesistente o ingresso in acqua) — task=%s is_idle_activity=%s." % [
			target_individual.id, target_individual.name, dx, dy,
			("'%s'" % blocked_task.task_name if blocked_task != null else "(nessuna)"), str(is_idle_task)
		])
	if not is_idle_task:
		return
	var blocked_action := blocked_task.get_current_action()
	if not (blocked_action is WalkAction or blocked_action is RunAction):
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_SAFETY_LOGS:
		print("[BORDER] Individuo #%d %s: gamba di '%s' (task perditempo) considerata conclusa — avanzo allo step successivo." % [
			target_individual.id, target_individual.name, blocked_task.task_name
		])
	individual_action_service.finish_current_step(target_individual, blocked_task, macro_world, game_data)


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

	# Pool bastoni (2026-09-08, richiesta utente) — pigro, agganciato qui perché è esattamente il
	# punto "questa macrocella viene effettivamente ridisegnata" (stesso principio di StonePositionService/
	# VegetationPositionService): no-op immediato per ogni lotto già fresco rispetto all'ultimo
	# checkpoint growth, vedi StickPoolService per il design completo.
	#
	# Filtro FoW su stick/pebble (2026-09-09, richiesta utente) — stesso filtro già in uso per la
	# vegetazione (_filter_vegetation_positions_by_visibility sotto): prima d'ora pebble/stick
	# disegnavano OGNI posizione incondizionatamente, anche sotto FROZEN_OVERLAY_COLOR/nero pieno,
	# dove la vegetazione viene già nascosta — risultato: bastoncini/sassi a piena definizione in
	# zone dove l'albero/cespuglio sorgente non è nemmeno disegnato (segnalato dall'utente).
	# `set_pebble_quantities` spostato QUI (non più un rebuild una tantum all'attivazione della
	# macrocella, vedi il vecchio commento in _activate_cell) — stessa cadenza/stesso trigger di
	# stick (checkpoint/movimento/taglio/edificio/pickup, vedi PickUpAction.resource_collected
	# sotto), non due percorsi di refresh paralleli per due risorse che condividono lo stesso bisogno.
	StickPoolService.refresh_macrocell(cell.macro_state, game_data)
	# plant_fiber (2026-09-16, richiesta utente — Step 2) — STESSA cadenza/STESSO trigger di stick
	# appena sopra, nessun rendering ancora agganciato (Step 3, non ancora fatto): ancora nessuna
	# set_plant_fiber_quantities su cell.renderer.
	PlantFiberPoolService.refresh_macrocell(cell.macro_state, game_data)
	if cell.renderer != null:
		cell.renderer.set_stick_quantities(_filter_positions_by_visibility(cell, cell.macro_state.stick_quantities))
		cell.renderer.set_pebble_quantities(_filter_positions_by_visibility(cell, cell.macro_state.pebble_quantities))

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


# Gemella di _filter_vegetation_positions_by_visibility sopra, ma per un Dictionary FLAT
# posizione->valore (MacroCellState.pebble_quantities: Vector2i -> int; stick_quantities:
# Vector2i -> Dictionary) invece che nested per WorldObjectType — 2026-09-09, richiesta utente:
# pebble/stick non avevano ALCUN filtro FoW prima d'ora (disegnavano ogni posizione
# incondizionatamente, anche sotto FROZEN_OVERLAY_COLOR/nero pieno), a differenza della
# vegetazione. Stessa fonte/stesso principio di sopra — chiamata separatamente (non condivide il
# `visible` già calcolato per la vegetazione in questa stessa _refresh_resource_visuals): tenerla
# autonoma, come l'altra, invece di introdurre uno stato condiviso tra le due per un risparmio
# marginale (compute_visible_positions è limitato al raggio di visibilità, non all'intera griglia).
func _filter_positions_by_visibility(cell: LiveMacroCell, positions: Dictionary) -> Dictionary:
	if cell.fog_of_war_renderer == null:
		return positions
	var visible := cell.fog_of_war_renderer.compute_visible_positions(game_data.get_absolute_day())
	var filtered: Dictionary = {}
	for pos in positions:
		if visible.has(Vector2i(pos.x, pos.y)):
			filtered[pos] = positions[pos]
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
	# Human_individual_views (2026-09-07, stesso bugfix di animal_renderers sopra): create durante
	# il seeding iniziale in _ready(), PRIMA che questa funzione giri, quindi il loro view.clock =
	# clock fatto lì è ancora null — corretto qui una volta che clock esiste davvero.
	for view in human_individual_views:
		view.clock = clock


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
# era il placeholder "statistiche" disabilitato — attivato (Step A del piano statistiche,
# 2026-09-05): apre StatisticsPanel, ancora vuoto (solo struttura tab, nessun contenuto).
func _on_primary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"statistics":
			# buildings (2026-09-12, richiesta utente — tab Statistiche/Edifici) — macro_world.buildings
			# già Array[Building], stesso principio "dati già pronti" di _refresh_buildings_panel.
			statistics_panel.open_dialog(
				game_data, human_individuals, macro_world.buildings if macro_world != null else []
			)
		# Slot 1, accanto alle statistiche (2026-09-07, richiesta utente) — 💡, apre TechTreePanel.
		&"tech_tree":
			tech_tree_panel.open_dialog(human_folk)


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
		&"toggle_idle_fallback":
			# Interruttore GLOBALE del fallback perditempo (2026-09-16, richiesta utente) — SOLO
			# stato di sessione su IdleTaskAssignmentService (mai GameSettings/un salvataggio, a
			# differenza di toggle_animals_visibility/toggle_flora_updates sopra): set_fallback_
			# enabled stampa già il log [IDLE FALLBACK], questa riga si limita a rispecchiare il
			# nuovo stato nel testo del bottone.
			IdleTaskAssignmentService.set_fallback_enabled(not IdleTaskAssignmentService.fallback_enabled)
			debug_bar.set_idle_fallback_label(IdleTaskAssignmentService.fallback_enabled)


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
	# Quale sagoma disegnare durante l'anteprima (2026-09-07, richiesta utente, Pebble Circle) — vedi
	# BuildingGhost.building_type_name: prima di questo passo l'unico tipo esistente (hut) rendeva
	# superfluo dirglielo esplicitamente.
	_building_ghost.building_type_name = building_type_name
	add_child(_building_ghost)


# Mappatura action_id -> nome tipo edificio (per BuildingCalculator.get_building_rules) — tenuta
# come funzione dedicata invece di un valore hardcoded dentro _place_building_at, esattamente
# perché arrivasse un secondo tipo senza dover toccare quel metodo (Pebble Circle, 2026-09-07).
func _building_type_name_for_action(action_id: StringName) -> String:
	match action_id:
		&"build_hut":
			return "hut"
		&"build_pebble_circle":
			return "pebble_circle"
		&"build_deposit_site":
			return "deposit_site"
		# Stick Tent (2026-09-12, richiesta utente — collegamento UI/rendering) — stesso schema
		# degli altri tre, azione "build_stick_tent" cablata in BuildBar._ready sopra.
		&"build_stick_tent":
			return "stick_tent"
		_:
			return ""


func _clear_building_ghost() -> void:
	if _building_ghost == null:
		return
	_building_ghost.queue_free()
	_building_ghost = null
	_selected_building_type_name = ""


# ============================================================================================
# Demolizione (2026-09-12, richiesta utente — "attiva il bottone Demolisci già presente in UI:
# demolizione immediata, nessuna Task/tempo per ora, con conferma prima di eseguire") — bottone
# main_row (BuildBar.DEMOLISH_MAIN_ROW_SLOT_INDEX), ascoltato QUI (non da _on_build_submenu_action_
# pressed sopra, che resta per submenu_row/i tipi edificio): entrare in modalità "seleziona
# bersaglio" (_demolish_mode_active), un click sinistro sull'edificio colpito apre
# DemolishConfirmationDialog, solo alla conferma esplicita _demolish_building esegue davvero.
# ============================================================================================

func _on_build_main_row_action_pressed(action_id: StringName) -> void:
	if action_id != BuildBar.DEMOLISH_ACTION:
		return
	_set_demolish_mode(not _demolish_mode_active)


# Entra/esce dalla modalità targeting (2026-09-12) — annullabile ricliccando il bottone stesso
# (sopra) o con il destro nel mondo (vedi il gate in _unhandled_input) — STESSO doppio modo di
# uscita già offerto dal modo piazzamento edificio (_building_ghost: destro annulla, sinistro
# consuma). set_slot_toggled riusa qui il significato "acceso mentre la modalità è impegnata",
# stesso principio del toggle mostra/nascondi già documentato in IconButtonRow.gd — a riposo il
# bottone Demolisci resta comunque pienamente abilitato/a piena luminosità (enabled=true da
# BuildBar._ready), set_slot_toggled(false) qui lo attenua leggermente SOLO per differenziare
# visivamente "modalità non attiva" da "in attesa di un click sull'edificio da demolire".
func _set_demolish_mode(active: bool) -> void:
	_demolish_mode_active = active
	build_bar.main_row.set_slot_toggled(BuildBar.DEMOLISH_MAIN_ROW_SLOT_INDEX, active)


# Consuma il click mentre la modalità è attiva (chiamata SOLO da _unhandled_input, gate in testa
# alla funzione) — hit o miss, la modalità termina comunque qui (un singolo tentativo per
# attivazione, stesso principio "un click, poi il modo si chiude" già seguito da _try_assign_
# build_command_on_right_click per l'assegnazione, non un modo persistente da disattivare a parte).
# Nessuna demolizione qui dentro: solo l'apertura della conferma, se il click ha colpito un edificio
# vero — _demolish_building (sotto) è l'UNICO punto che muta stato, chiamato solo da
# _on_demolish_confirmed.
func _try_pick_demolish_target(event: InputEvent) -> void:
	var building_hit := building_selector_controller.try_select(
		event, live_cells, macro_world.buildings if macro_world != null else []
	)
	_set_demolish_mode(false)
	if building_hit.is_empty():
		return
	var target_building := _find_building_by_id(building_hit["building_id"])
	if target_building == null:
		return
	var display_name: String = tr(target_building.rules.building_name) if target_building.rules != null else target_building.building_type_name
	demolish_confirmation_dialog.open_dialog(target_building, display_name, target_building.id)


func _on_demolish_confirmed(building: Variant) -> void:
	_demolish_building(building)


# Demolizione VERA (2026-09-12, richiesta utente, punto 2) — funzione unica, chiamata solo dopo
# conferma esplicita nel dialog. Operazione one-shot: `building` viene rimosso da macro_world.
# buildings all'ultima riga di mutazione qui sotto, quindi nessuna doppia chiamata è possibile per
# lo STESSO Building (non resta più raggiungibile da nessun building_id/click successivo) — NESSUN
# flag di idempotenza necessario, a differenza di ClearAction.space_reserved (che invece doveva
# proteggersi da una ricostruzione ripetuta della STESSA Action per lo stesso edificio ancora vivo).
func _demolish_building(building: Building) -> void:
	if building == null or macro_world == null:
		return

	# 1) Interrompi qualunque Task il cui target sia questo edificio — sia una Build Task in corso
	# (SetupSite/Clear/Build, context["target_building"]) sia una assegnata ma non ancora avviata
	# (stesso context, nessuna distinzione: il primo step di qualunque Task del genere è sempre
	# Walk, che non legge target_building affatto, ma il context è condiviso da TUTTI gli step della
	# stessa Task fin dalla creazione via TaskFactory.build_task — vedi Task.context). Nessun
	# riferimento diretto building->individuo esiste oggi (vedi il report): scansione lineare di
	# human_individuals, stesso costo già accettato altrove nel progetto per questo stesso array
	# (es. AssignHouseService sopra). other.stop() qui SENZA il resolve_idle_individual aggiunto a
	# _stop_selected_individual_task (tasto H, 2026-09-14 bugfix) — deliberato, non un'omissione:
	# demolire l'edificio target invalida la Task, ma un eventuale resume dalla coda/fallback
	# perditempo per un individuo NON selezionato qui è fuori scope di questo fix (limitato al tasto
	# H su richiesta utente); resta il comportamento "nessun fallback automatico" di prima.
	for other in human_individuals:
		var other_task: Task = other.current_task
		if other_task != null and other_task.context.get("target_building") == building:
			other.stop()

	# 2) Residenti: libera gli slot (house_id torna a -1, stesso valore di default di HumanIndividual
	# senza casa) — solo se l'edificio era residenziale, stesso guard già usato da AssignHouseService/
	# dai tre trigger esistenti (max_residents > 0).
	if building.rules != null and building.rules.max_residents > 0:
		for occupant in human_individuals:
			if occupant.house_id == building.id:
				occupant.house_id = -1

	# 3) Storage perso — azzerato semplicemente, nessuna materializzazione a terra (stesso principio
	# "la merce scartata sparisce" già applicato ad haul_resource, vedi HumanIndividual.
	# discard_carried_resource).
	building.stored_resources.clear()

	# 4) Libera lo spazio dedicato SOLO se era stato davvero riservato — is_complete=true copre sia
	# il percorso Build Task (ClearAction.on_complete lo riserva, poi BuildAction completa) sia il
	# piazzamento istantaneo Sx+B (_place_building_at riserva lo spazio direttamente, MAI passando da
	# construction_progress["space_reserved"] — quel campo resta vuoto per quel percorso, vedi
	# Building.construction_progress) — building.is_complete da solo non basterebbe a coprire un
	# cantiere ancora in corso il cui ClearAction è già completato ma BuildAction no (is_complete
	# ancora false, spazio già riservato): construction_progress["space_reserved"] copre esattamente
	# quel caso intermedio. Le due condizioni insieme coprono ESATTAMENTE gli stessi casi in cui lo
	# spazio è stato incrementato in tutto il progetto (_place_building_at riga ~4929, ClearAction.
	# on_complete riga ~212) — nessun altro punto lo incrementa mai.
	var space_was_reserved: bool = building.is_complete or bool(building.construction_progress.get("space_reserved", false))
	if space_was_reserved and building.rules != null:
		var state := macro_world.get_cell_state_at(building.macro_x, building.macro_y)
		if state != null:
			var current_building_space := state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
			state.set_dedicated_space(GameTypes.WorldObjectType.BUILDING, max(0, current_building_space - building.rules.required_space))

	# 5) Placeholder visivi residui (rametti) — no-op se l'edificio era già completo (mai spawnati, o
	# già rimossi da _on_building_construction_completed), stesso guard get_node_or_null già dentro
	# questa funzione.
	_remove_build_site_placeholders(building)

	# 6) Rimozione vera dall'unica fonte di verità (macro_world.buildings) — DOPO aver letto/mutato
	# tutto ciò che sopra dipende ancora dall'oggetto vivo (rules/construction_progress/macro_x/
	# macro_y), PRIMA dei refresh sotto (che rileggono macro_world.buildings da zero).
	#
	# is_demolished = true (2026-09-12, richiesta utente — bugfix "deposito nel vuoto") — SUBITO
	# PRIMA dell'erase, sullo stesso oggetto: vedi Building.is_demolished per il perché questo flag
	# serve (un individuo con una Task già in corso verso questo edificio tiene un riferimento
	# diretto che resta valido anche dopo che l'edificio sparisce da questa lista).
	building.is_demolished = true
	macro_world.buildings.erase(building)

	# Chiudi il pannello se era proprio questo l'edificio selezionato (stesso principio già seguito
	# da _clear_building_selection altrove: nessun pannello che punti a un Building non più
	# raggiungibile).
	if not selected_building.is_empty() and int(selected_building.get("building_id", -1)) == building.id:
		_clear_building_selection()

	# Refresh visivo della cella (torna a mostrare il terreno/vegetazione sottostante — nessun
	# intervento esplicito sul ciclo di crescita: ResourceGrowthService legge già get_empty_space()
	# al bisogno, ora più ampio grazie al decremento al punto 4) e dei due pannelli coinvolti.
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if live_cells.has(macro_coords):
		_refresh_building_visuals(live_cells[macro_coords])
	_refresh_buildings_panel()
	# Un edificio is_village_center appena demolito può riaprire lo slot Pebble Circle nella BuildBar
	# (vedi _building_type_availability) — stesso ricalcolo completo/idempotente già usato altrove,
	# non un caso speciale scritto qui.
	_refresh_building_slots_buildable()

	print("[DEMOLISH] Edificio #%d (%s) demolito." % [
		building.id, tr(building.rules.building_name) if building.rules != null else building.building_type_name
	])

	# 7) Ricolloca eventuali individui rimasti senza casa (punto 2/3) in altri posti liberi, poi
	# rinfresca la scheda 👨‍👩‍👧 — stesso identico bugfix appena applicato al trigger "edificio
	# completato" (2026-09-12): AssignHouseService non è mai seguito da un human_population_changed
	# in questo percorso (il conteggio popolazione non cambia demolendo un edificio), quindi senza
	# questa chiamata esplicita i nuovi house_id (sia i -1 del punto 2 sia le riassegnazioni qui)
	# non si vedrebbero nella scheda fino al prossimo rollover d'anno.
	AssignHouseService.assign_pending_residents(macro_world, human_individuals, game_data.year)
	_refresh_population_panel()


# Vincoli di disponibilità PER TIPO in BuildBar (2026-09-07, richiesta utente — GENERALIZZATA da
# _refresh_pebble_circle_buildable, che copriva solo is_village_center) — vive QUI, non in
# BuildingVerificationService.is_position_buildable (che deve restare legata solo a
# terreno/spazio/sovrapposizioni di UNA posizione, mai a "questo tipo è disponibile ovunque nel
# mondo/per questo Folk": un vincolo concettualmente diverso, di disponibilità del TIPO, non di
# validità della POSIZIONE). GameScene fa il controllo vero (l'unico punto che già possiede
# macro_world/human_folk), BuildBar.set_building_buildable si limita a riflettere il risultato sullo
# slot corrispondente — build_bar resta muta su World/Building/Folk, come da principio dichiarato
# in BuildBar.gd. Itera BuildingCalculator.list_building_type_names() (stesso elenco-per-convenzione
# già usato altrove) invece di un elenco hardcoded: un futuro terzo tipo con is_village_center o
# required_idea_id viene coperto da solo, senza toccare questa funzione.
#
# PUNTO DI AGGANCIO per un futuro completamento Idea (richiesta utente, 2026-09-07): quando esisterà
# una vera logica che aggiunge un id a human_folk.completed_ideas, quel punto dovrà richiamare
# QUESTA STESSA funzione per aggiornare subito gli slot che diventano disponibili — nessun secondo
# meccanismo da costruire, il ricalcolo qui è già completo/idempotente (rilegge lo stato attuale di
# completed_ideas ad ogni chiamata, non un delta). Non ancora collegato a nulla in questo passo.
func _refresh_building_slots_buildable() -> void:
	for building_type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(building_type_name)
		if rules == null:
			continue
		var availability := _building_type_availability(rules)
		build_bar.set_building_buildable(building_type_name, availability["is_buildable"], availability["disabled_tooltip"])


# Estratta da _refresh_building_slots_buildable (2026-09-07, richiesta utente — bugfix incoerenza
# Pebble Circle: un fantasma già APERTO prima che un vincolo di tipo scattasse continuava a piazzare
# all'infinito, perché solo l'APERTURA di una nuova selezione in BuildBar veniva controllata, mai il
# singolo PIAZZAMENTO dentro una selezione già in corso) — stessa identica logica, ora riusabile sia
# qui (per riflettere lo stato sulla BuildBar) sia da _place_building_at (per un ricontrollo al
# momento del piazzamento vero e proprio, indipendente da quando il fantasma è stato aperto).
# Ritorna {"is_buildable": bool, "disabled_tooltip": String} — la tooltip è calcolata comunque
# anche quando il chiamante (_place_building_at) non la userà mai, per non duplicare la logica in
# due posti.
func _building_type_availability(rules: BuildingRules) -> Dictionary:
	if rules.is_village_center:
		var village_center_exists := false
		if macro_world != null:
			for building in macro_world.buildings:
				if building.rules != null and building.rules.is_village_center:
					village_center_exists = true
					break
		if village_center_exists:
			return {"is_buildable": false, "disabled_tooltip": tr("build_bar_pebble_circle_disabled_tooltip")}
	if rules.required_idea_id != "" and (human_folk == null or not human_folk.completed_ideas.has(rules.required_idea_id)):
		var required_idea := IdeaCalculator.get_idea(rules.required_idea_id)
		# tr() su display_name (2026-09-07, bugfix — vedi Idea.gd/TechTreePanel per gli altri due
		# punti che devono fare lo stesso): non è più testo diretto, è una chiave tr() come
		# BuildingRules.building_name.
		var required_idea_display_name: String = tr(required_idea.display_name) if required_idea != null else rules.required_idea_id
		return {
			"is_buildable": false,
			"disabled_tooltip": tr("build_bar_requires_idea_tooltip").format({"idea": required_idea_display_name}),
		}
	return {"is_buildable": true, "disabled_tooltip": ""}


# Piazzamento ISTANTANEO (2026-09-10, richiesta utente — RIDOTTO a bypass debug/test: prima
# porzione Build Task, il click sinistro semplice ora passa da _start_building_task_at sotto invece
# di qui, vedi _unhandled_input. Questa funzione resta raggiungibile SOLO tenendo premuto B mentre
# si clicca, "Sx+B" — comportamento INVARIATO, is_complete=true da subito, current_durability già a
# rules.max_durability, niente min_construction_days/required_labor/materiali/tech consultati, come
# prima di questo passo) — completo immediatamente. Verifica di edificabilità
# (BuildingVerificationService) ricollegata 2026-08-30, ricostruita da zero passo per passo — vedi
# il service per lo stato attuale dei criteri.
# Il fantasma di norma NON viene rimosso da qui: resta al chiamante (_unhandled_input) l'aver
# deciso di continuare il modo piazzamento dopo un piazzamento riuscito — ECCEZIONE per i tipi
# is_village_center (2026-09-07, richiesta utente, punto 2 del bugfix Pebble Circle): quel fantasma
# si chiude DA SOLO subito dopo un piazzamento riuscito, invece di restare aperto come per la
# capanna — non avrebbe senso invitare a "piazzarne un altro in fila" per un tipo che diventa
# indisponibile dopo il primo (vedi la chiamata a _clear_building_ghost in fondo alla funzione).
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
	# Ricontrollo al momento del piazzamento (2026-09-07, richiesta utente, punto 1 del bugfix
	# Pebble Circle) — NON basta che BuildBar avesse disabilitato lo slot: quel controllo scatta solo
	# quando si APRE una nuova selezione, mai dentro una selezione/fantasma già aperto PRIMA che il
	# vincolo diventasse vero (es. fantasma Pebble Circle aperto quando non ne esisteva ancora uno,
	# poi il player continuava a piazzarne altri nella stessa sessione di click). Stessa identica
	# logica già usata per la BuildBar (_building_type_availability), qui riapplicata al singolo
	# tipo che si sta effettivamente piazzando ORA — non in BuildingVerificationService.
	# is_position_buildable, che resta legata solo a terreno/spazio/sovrapposizioni di una posizione.
	if not _building_type_availability(rules)["is_buildable"]:
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
	# Nessuna fase "cantiere in attesa" per il piazzamento istantaneo (2026-09-11, richiesta utente,
	# resa grayscale del cantiere non ancora allestito) — vedi Building.site_setup_complete.
	building.site_setup_complete = true
	building.current_durability = rules.max_durability
	building.built_year = game_data.year
	building.rotation = _building_ghost.rotation_dir
	macro_world.buildings.append(building)
	# Rinfresca la scheda 🏠 (2026-09-12, richiesta utente) — nuovo edificio in lista, già completo
	# per questo piazzamento istantaneo (B+click).
	_refresh_buildings_panel()

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

	# Aggiorna SUBITO la disponibilità di TUTTI gli slot BuildBar (2026-09-07, richiesta utente) —
	# non solo se questo piazzamento era esso stesso uno Pebble Circle: chiamata incondizionata,
	# costo trascurabile con pochi edifici/tipi (vedi _refresh_building_slots_buildable), niente da
	# guadagnare filtrando prima per tipo.
	_refresh_building_slots_buildable()

	# Chiusura automatica del fantasma per i tipi is_village_center (2026-09-07, richiesta utente,
	# punto 2 del bugfix Pebble Circle — vedi il commento in testa alla funzione) — DOPO il refresh
	# sopra, non prima: _clear_building_ghost azzera _selected_building_type_name, che
	# _refresh_building_slots_buildable non usa comunque, ma l'ordine "aggiorna stato, poi chiudi UI"
	# resta il più naturale dei due.
	if rules.is_village_center:
		_clear_building_ghost()


# Piazzamento REALE (2026-09-10, richiesta utente — prima porzione Build Task, sostituisce
# _place_building_at sopra come percorso del click sinistro SEMPLICE) — NON completa
# immediatamente: crea SOLO un Building con is_complete=false (current_durability/built_year restano
# ai default -1/0, coerenti col loro stesso significato documentato "non ancora completato/
# costruito" su Building.gd, nessun valore fittizio inventato qui) — NESSUNA Task costruita/
# assegnata qui.
#
# RISCRITTA 2026-09-12 (richiesta utente — sostituzione di _pending_build_tasks con un percorso
# generico di riassegnazione Task): questa funzione PRIMA costruiva anche la Build Task completa
# [Walk, SetupSite, Clear, Build] via TaskFactory e la teneva in _pending_build_tasks in attesa di
# un click destro — quella parte è stata rimossa per intero. Oggi la Task viene costruita da zero
# SOLO al momento del click destro, da _try_assign_build_command_on_right_click via
# TaskReassignmentService.reassign_task (che legge Building.get_resumable_task_definition_path/
# get_resumable_task_context) — identico sia al primissimo click su questo cantiere sia a un click
# successivo dopo che un individuo precedente è stato interrotto a metà (construction_progress con
# progresso parziale, auto-skip già confermato sicuro sui quattro step). Questa funzione resta
# quindi responsabile SOLO degli effetti "one-shot" del piazzamento (Building.new/
# allocate_building_id/buildings.append/refresh visivi) — mai invocata da una riassegnazione.
#
# AGGIORNATO 2026-09-11 — BuildingSiteClearingService.clear_microcell e la riserva di
# dedicated_space[BUILDING] avvengono dentro ClearAction.on_complete (terzo step), non in questa
# funzione — la vegetazione sulla microcella del cantiere resta quindi visibile/intatta durante
# Walk e SetupSiteAction, sparisce solo quando ClearAction completa (vedi GameScene._on_site_cleared
# per il refresh visivo che segue). current_durability/built_year restano ai default (0/-1) fino al
# QUARTO step: BuildAction.on_complete li valorizza davvero (current_durability direttamente,
# built_year tramite GameScene._on_building_construction_completed — vedi quei due file per il
# perché built_year non è risolto dentro BuildAction stessa).
# construction_started_day NON valorizzato qui (richiesta esplicita punto 1b — "resta invariato per
# ora... sarà in un giro successivo") — resta senza consumatore anche dopo il quarto step, nessuna
# richiesta di collegarlo è mai arrivata.
#
# DA SEGNALARE (2026-09-10, richiesta esplicita di verifica punto 1d) — query che al momento in cui
# questa nota fu scritta NON controllavano building.is_complete e quindi trattavano già un cantiere
# in corso come un edificio pienamente funzionante, appena il Building entra in macro_world.buildings:
#   - WarehouseSelectionService.find_best / BuildingStorageService (can_accept/get_max_depositable) /
#     _try_assign_unload_command_on_right_click sopra — GAP CHIUSO (2026-09-11, richiesta utente):
#     can_accept()/get_max_depositable() ora rifiutano qualunque building con is_complete=false, un
#     solo guard che copre store() (deposito automatico via haul_resource), la selezione del
#     magazzino più vicino e il comando manuale a destro-click, senza ripetere il controllo in
#     ciascuno — vedi BuildingStorageService.gd.
#   - ThoughtTargetSelectionService.find_best/has_thought_accepting_building (stesso discorso per
#     accepts_thoughts — un cantiere Pebble Circle accetterebbe già pensieri prima di essere finito)
#     — ANCORA APERTO, dominio diverso (pensieri, non risorse fisiche), non toccato in questo passo.
# AGGIORNATO 2026-09-11 — a differenza di quanto valeva quando questa nota fu scritta,
# MicroCellRenderer._draw_buildings NON disegna più lo sprite completo a prescindere da is_complete
# (vedi la resa "cantiere in attesa"/cartello WIP introdotta lo stesso giorno): oggi un edificio
# incompleto non mostra mai la propria sagoma vera, solo un cartello "work in progress" (finché
# site_setup_complete è false) o nulla (dopo, solo i bastoncini) — feedback visivo "in corso" quindi
# più ricco di quanto questa nota originale descrivesse, non solo i 4 placeholder di
# _spawn_build_site_placeholders.
func _start_building_task_at(world_position: Vector2) -> void:
	# LOG DEBUG TEMPORANEO (2026-09-10, richiesta utente — indagine bug "il pipottino cammina
	# sempre verso lo stesso punto in basso a destra") — DA RIMUOVERE una volta chiuso il bug.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD DEBUG] _start_building_task_at: world_position ricevuto=%s" % str(world_position))
	if macro_world == null:
		return
	var rules := BuildingCalculator.get_building_rules(_selected_building_type_name)
	if rules == null:
		return
	if not _building_type_availability(rules)["is_buildable"]:
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
	# LOG DEBUG TEMPORANEO — vedi nota sopra.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD DEBUG] _start_building_task_at: risolto in macro=(%d,%d) micro=%s" % [
			target_cell.macro_x, target_cell.macro_y, str(micro_pos)
		])
	var state := macro_world.get_cell_state_at(target_cell.macro_x, target_cell.macro_y)
	if state == null:
		return

	var building := Building.new(rules, target_cell.macro_x, target_cell.macro_y, _selected_building_type_name)
	building.id = macro_world.allocate_building_id()
	building.micro_x = micro_pos.x
	building.micro_y = micro_pos.y
	building.is_complete = false
	building.rotation = _building_ghost.rotation_dir
	macro_world.buildings.append(building)
	# Rinfresca la scheda 🏠 (2026-09-12, richiesta utente) — nuovo cantiere in lista, "in
	# costruzione" (is_complete è già false qui sopra).
	_refresh_buildings_panel()
	# LOG DEBUG TEMPORANEO — vedi nota sopra.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD DEBUG] _start_building_task_at: Building #%d creato — macro=(%d,%d) micro=(%d,%d)" % [
			building.id, building.macro_x, building.macro_y, building.micro_x, building.micro_y
		])

	_refresh_building_visuals(target_cell)

	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Cantiere per %s #%d avviato in (%d,%d) micro=(%d,%d) — in attesa di assegnazione (click destro su un individuo selezionato)." % [
		_selected_building_type_name, building.id, target_cell.macro_x, target_cell.macro_y, micro_pos.x, micro_pos.y
	])

	_refresh_building_slots_buildable()
	if rules.is_village_center:
		_clear_building_ghost()


# Placeholder visivo "rametti" (2026-09-10, richiesta utente, punto 4 — "nessun asset vero, solo
# placeholder per vedere che succede qualcosa nel mondo"; RIDISEGNATI 2026-09-11, richiesta utente:
# "molto più sottili... devono sembrare rami un po' storti piantati nel terreno" — prima erano
# semplici quadratini 2x2, non leggibili come legno) — 4 Polygon2D sottili e affusolati (vedi
# _twig_polygon: un esagono stretto che si assottiglia dalla base alla punta, con un "piegamento"
# orizzontale a metà altezza per un profilo non rettilineo), uno per angolo della microcella del
# cantiere, figli di cell.container (stesso spazio locale/stessa convenzione pixel di
# _spawn_idea_deposit_effect/_spawn_command_blink_effect sopra — puro codice, nessun .tscn).
# Collegato a SetupSiteAction.site_setup_completed (vedi _start_building_task_at) — spawna SOLO al
# completamento dell'azione, mai incrementale/parziale durante il giorno di lavoro (richiesta
# esplicita: "a fine azione, non incrementale"). "Usa e getta" nel senso originale (RESTAVANO a
# schermo per sempre, nulla li rimuoveva — né ClearAction, che tocca solo la vegetazione, né alcun
# altro collegamento) fino al 2026-09-11: ORA (quarto e ultimo step della Build Task) rimossi da
# GameScene._on_building_construction_completed quando BuildAction completa davvero, vedi
# _BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX sotto per come vengono ritrovati.
const _BUILD_SITE_PLACEHOLDER_HEIGHT: float = 2.2
const _BUILD_SITE_PLACEHOLDER_BASE_WIDTH: float = 0.35
const _BUILD_SITE_PLACEHOLDER_TIP_WIDTH: float = 0.08
const _BUILD_SITE_PLACEHOLDER_BEND: float = 0.7
const _BUILD_SITE_PLACEHOLDER_MARGIN: float = 1.5
const _BUILD_SITE_PLACEHOLDER_COLOR := Color(0.35, 0.24, 0.13)

# Prefisso nome nodo per il gruppo dei 4 rametti di UN edificio (2026-09-11, richiesta utente,
# quarto step — "rimuovi i 4 placeholder... valuta se serve un riferimento salvato da qualche parte
# per poterli rimuovere") — i 4 Polygon2D non erano referenziati da nessuna parte (nati "usa e
# getta", nessuna variabile li teneva). SOLUZIONE: invece di un Dictionary building.id -> Array[Node]
# tenuto a parte in GameScene (un secondo registro da tenere sincronizzato con l'albero dei nodi,
# rischio di disallineamento se un nodo sparisse per altre vie — es. la cella viva si disattiva),
# li raggruppo sotto UN Node2D contenitore, FIGLIO di cell.container esattamente come prima erano i
# 4 Polygon2D direttamente, con un nome deterministico da building.id — ritrovabile via
# get_node_or_null(String) quando serve, senza registro separato: l'albero dei nodi STESSO è la
# fonte di verità (se la cella non è più viva, il gruppo non esiste più comunque — stesso identico
# comportamento "usa e getta" già accettato, solo ora anche rimovibile quando serve).
const _BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX := "BuildSitePlaceholders_"

func _spawn_build_site_placeholders(building: Building) -> void:
	if building == null:
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if not live_cells.has(macro_coords):
		return
	var cell: LiveMacroCell = live_cells[macro_coords]
	# GUARD anti-duplicazione (2026-09-12, richiesta utente — bugfix idempotenza confermato
	# nell'indagine precedente: questa funzione creava sempre un nuovo Node2D senza verificare se
	# esisteva già uno per lo stesso building.id — SetupSiteAction.site_setup_completed può in
	# teoria essere ri-emesso da un'istanza ricostruita da zero che si auto-skippa immediatamente
	# perché site_setup_days_done è già oltre soglia, richiamando questo listener una seconda volta
	# e producendo un secondo gruppo di 4 rametti orfano — _remove_build_site_placeholders cerca
	# solo il nome esatto, quindi rimuoverebbe sempre e solo il primo). STESSO nome/STESSO pattern
	# già usato da _remove_build_site_placeholders per ritrovare il gruppo — se esiste già, no-op:
	# i placeholder ci sono già, nulla da rifare (nemmeno il refresh sotto, già applicato la prima
	# volta).
	if cell.container.get_node_or_null(_BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX + str(building.id)) != null:
		return
	# Fine della fase "cantiere in attesa" (2026-09-11, richiesta utente) — DOPO aver risolto/
	# validato `cell` sopra, prima di spawnare i placeholder: refresh esplicito, non implicito nel
	# prossimo redraw casuale, così il cartello "work in progress" sparisce nello STESSO frame in
	# cui compaiono i 4 rametti, vedi Building.site_setup_complete/MicroCellRenderer._draw_buildings/
	# _draw_construction_wip_marker.
	building.site_setup_complete = true
	_refresh_building_visuals(cell)
	_create_build_site_placeholder_nodes(building, cell)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Cantiere edificio #%d allestito (4 placeholder posizionati)." % building.id)


# Bugfix (2026-09-15, richiesta utente — "resta il fatto che se un cantiere è in costruzione, si
# vedono i 4 bastoncini agli angoli, se salvo e rientro non li vedo più"): i 4 Polygon2D sotto sono
# SOLO figli di cell.container, mai persistiti — al reload l'intera scena (e ogni LiveMacroCell) è
# ricostruita da zero, quindi vanno rispawnati per ogni cantiere già oltre la fase "allestimento"
# (site_setup_complete=true, il booleano VERO invece è persistito su Building e sopravvive al
# reload). Il vecchio unico punto di spawn era SOLO il segnale SetupSiteAction.site_setup_completed
# (vedi _spawn_build_site_placeholders sopra) — un evento "successo UNA VOLTA", mai ri-emesso per
# uno step ormai storico (già superato, magari da sessioni precedenti) di una Task ricostruita da
# salvataggio: _reconnect_loaded_task_signals ricollega il segnale ma non c'è più nulla che lo
# faccia scattare di nuovo. FIX: nodo-creazione estratta a parte (_create_build_site_placeholder_
# nodes, stessa funzione riusata da entrambi i punti, mai duplicata) e richiamata anche da
# _restore_build_site_placeholders_for_cell sotto, invocata da _activate_live_cell per OGNI cella
# viva (copre sia il reload sia una cella-edificio riattivata dopo essere stata smontata) — stesso
# guard anti-duplicazione (get_node_or_null) già in uso sopra, quindi un no-op sicuro se i
# placeholder esistono già (es. cantiere avviato e allestito nella sessione corrente, cella mai
# smontata).
func _create_build_site_placeholder_nodes(building: Building, cell: LiveMacroCell) -> void:
	var cell_origin := Vector2(building.micro_x, building.micro_y) * MicroCellRenderer.CELL_SIZE
	var corner_offsets: Array[Vector2] = [
		Vector2(_BUILD_SITE_PLACEHOLDER_MARGIN, _BUILD_SITE_PLACEHOLDER_MARGIN),
		Vector2(MicroCellRenderer.CELL_SIZE - _BUILD_SITE_PLACEHOLDER_MARGIN, _BUILD_SITE_PLACEHOLDER_MARGIN),
		Vector2(_BUILD_SITE_PLACEHOLDER_MARGIN, MicroCellRenderer.CELL_SIZE - _BUILD_SITE_PLACEHOLDER_MARGIN),
		Vector2(MicroCellRenderer.CELL_SIZE - _BUILD_SITE_PLACEHOLDER_MARGIN, MicroCellRenderer.CELL_SIZE - _BUILD_SITE_PLACEHOLDER_MARGIN),
	]
	# Contenitore (2026-09-11) — vedi _BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX sopra: nome
	# deterministico da building.id, unico per edificio (due cantieri non possono mai collidere sullo
	# stesso nome). position/rotation di default (0,0 / 0) — i 4 Polygon2D figli restano posizionati
	# in coordinate LOCALI a cell.container esattamente come prima (cell_origin + corner_offsets[i]),
	# nessun offset aggiuntivo introdotto da questo contenitore.
	var placeholder_group := Node2D.new()
	placeholder_group.name = _BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX + str(building.id)
	cell.container.add_child(placeholder_group)
	for i in range(corner_offsets.size()):
		# RNG locale seedata per istanza (building.id, indice angolo) — stesso principio già seguito
		# altrove nel progetto (es. MicroCellRenderer._pebble_blob_polygon) per una forma "diversa ma
		# stabile" invece di randf_range() globale: qui non è strettamente necessario (il nodo, una
		# volta creato, non viene mai ricalcolato), ma tiene questo codice coerente con lo stile del
		# resto del renderer. Seed IDENTICO a prima di questo refactor (building.id * 4 + i): stessa
		# forma esatta prima e dopo un reload, nessuna differenza visiva tra "spawnato in sessione" e
		# "ripristinato al reload".
		var rng := RandomNumberGenerator.new()
		rng.seed = building.id * 4 + i
		var stake := Polygon2D.new()
		stake.polygon = _twig_polygon(rng)
		stake.color = _BUILD_SITE_PLACEHOLDER_COLOR
		stake.position = cell_origin + corner_offsets[i]
		stake.rotation = rng.randf_range(-PI, PI)
		stake.z_index = 1
		placeholder_group.add_child(stake)


# Chiamata da _activate_live_cell per OGNI cella viva (reload compreso) — vedi il commento esteso
# su _create_build_site_placeholder_nodes sopra per il perché. Un solo giro sui building di questa
# cella; niente da fare per un edificio completo (is_complete, i placeholder sono già stati rimossi
# da _on_building_construction_completed) o ancora nella fase "cartiere in attesa" (site_setup_
# complete ancora false, disegna solo il cartello WIP — vedi MicroCellRenderer._draw_buildings).
func _restore_build_site_placeholders_for_cell(cell: LiveMacroCell) -> void:
	if macro_world == null:
		return
	for building in macro_world.buildings:
		if building.macro_x != cell.macro_x or building.macro_y != cell.macro_y:
			continue
		if building.is_complete or not building.site_setup_complete:
			continue
		if cell.container.get_node_or_null(_BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX + str(building.id)) != null:
			continue
		_create_build_site_placeholder_nodes(building, cell)


# Poligono di un singolo rametto: base ferma a (0,0) (il punto piantato nel terreno), punta verso
# l'alto (-y) che si assottiglia da _BUILD_SITE_PLACEHOLDER_BASE_WIDTH a _BUILD_SITE_PLACEHOLDER_
# TIP_WIDTH, con un piegamento orizzontale casuale a metà altezza (`bend`, in entrambe le direzioni)
# per un profilo "storto" invece di un segmento perfettamente dritto — un esagono a 6 vertici (3 per
# lato: base, metà, punta), non una vera "stroke" con normali per segmento: sufficiente per una
# forma così piccola/sottile, nessun bisogno della complessità di un vero offset perpendicolare.
# `rng` passata dal chiamante (stesso principio di _pebble_blob_polygon) per variare altezza/
# piegamento per istanza restando deterministica rispetto al seed.
func _twig_polygon(rng: RandomNumberGenerator) -> PackedVector2Array:
	var height: float = _BUILD_SITE_PLACEHOLDER_HEIGHT * rng.randf_range(0.8, 1.2)
	var bend: float = rng.randf_range(-_BUILD_SITE_PLACEHOLDER_BEND, _BUILD_SITE_PLACEHOLDER_BEND)
	var base_half_width: float = _BUILD_SITE_PLACEHOLDER_BASE_WIDTH / 2.0
	var tip_half_width: float = _BUILD_SITE_PLACEHOLDER_TIP_WIDTH / 2.0
	var mid_half_width: float = (base_half_width + tip_half_width) / 2.0
	return PackedVector2Array([
		Vector2(-base_half_width, 0.0),
		Vector2(bend * 0.4 - mid_half_width, -height * 0.5),
		Vector2(bend - tip_half_width, -height),
		Vector2(bend + tip_half_width, -height),
		Vector2(bend * 0.4 + mid_half_width, -height * 0.5),
		Vector2(base_half_width, 0.0),
	])


# Collega a UN singolo step i segnali che GameScene deve ascoltare per reagire visivamente — STESSA
# lista/STESSI handler sia per uno step appena nato da TaskFactory (_start_building_task_at) sia
# per uno step RICOSTRUITO da un salvataggio (_reconnect_loaded_task_signals sotto, chiamata da
# _ready() dopo il caricamento) — funzione unica apposta (2026-09-11, richiesta utente: "chiudere
# il gap segnalato... dopo il reload i signal non vengono ricollegati") così i due punti di
# collegamento non possono disallinearsi nel tempo (un domani un terzo signal aggiunto qui vale
# automaticamente per entrambi i chiamanti). Nessun tipo riconosciuto: no-op silenzioso —
# WalkAction/RestAction/ThinkAction non hanno nulla da ricollegare qui.
#
# PickUpAction.resource_collected e UnloadAction.idea_completed/thought_deposited hanno lo STESSO
# gap gemello (segnalati, poi chiusi in un giro successivo — vedi _reconnect_pickup_action_signals/
# _reconnect_unload_action_signals sotto) ma NON passano da questa funzione: hanno un proprio
# handler dedicato, chiamato a parte da _reconnect_loaded_task_signals (per il reload) e dai
# rispettivi punti di creazione in-sessione (_assign_pickup_task/_debug_test_daydream_task) — non
# generalizzati qui perché il loro segnale di completamento è per-istanza con un bind aggiuntivo
# (l'individuo proprietario), diverso dal semplice "un signal, nessun parametro extra" di
# SetupSite/Clear/Build sotto.
func _reconnect_build_task_signals(step: Action) -> void:
	if step is SetupSiteAction:
		(step as SetupSiteAction).site_setup_completed.connect(_spawn_build_site_placeholders)
	elif step is ClearAction:
		(step as ClearAction).site_cleared.connect(_on_site_cleared)
	elif step is BuildAction:
		# Quarto step (2026-09-11) — STESSO principio dei due sopra: la mutazione VERA (is_complete/
		# current_durability) avviene già dentro BuildAction.on_complete, questo segnale serve solo
		# al refresh VISIVO (rimozione placeholder + sprite pieno, vedi
		# GameScene._on_building_construction_completed).
		(step as BuildAction).building_construction_completed.connect(_on_building_construction_completed)


# Ricollega i segnali persi dalla ricostruzione da salvataggio (2026-09-11, richiesta utente —
# chiude il gap: "dopo un reload i signal site_setup_completed/site_cleared non vengono
# ricollegati... verifica se lo stesso gap esiste anche per UnloadAction") — chiamata UNA VOLTA da
# _ready(), SOLO nel ramo "salvataggio appena caricato" (vedi il chiamante per il perché del guard
# `not returning`). Itera ogni individuo/ogni step della sua current_task ricostruita da
# TaskPersistenceService.deserialize_task (via GameLoadService): quegli step sono istanze Action
# COMPLETAMENTE NUOVE, i cui segnali (site_setup_completed/site_cleared/building_construction_
# completed/idea_completed/thought_deposited/resource_collected) non sono mai stati collegati da
# nessuno — GameLoadService stesso non sa nulla di questi segnali, si limita a ricostruire dati.
#
# CONFERMATO: lo stesso identico gap esiste anche per UnloadAction.idea_completed/thought_deposited
# e per PickUpAction.resource_collected — con precisazioni, vedi _reconnect_unload_action_signals/
# _reconnect_pickup_action_signals sotto per il dettaglio (e, per Unload, un gap RESIDUO diverso,
# non coperto qui, legato a task.step_appended).
#
# _reconnect_build_task_signals riusata TALE E QUALE (non duplicata) — stessa funzione già chiamata
# da _start_building_task_at per la creazione in-sessione, vedi lì: un domani un terzo signal
# aggiunto lì vale automaticamente anche qui, senza rischio di disallineamento tra i due punti.
func _reconnect_loaded_task_signals() -> void:
	for member in human_individuals:
		if member.current_task == null:
			continue
		# Conteggio SOLO per il log di conferma sotto (2026-09-11, richiesta utente — "verificare che
		# la riconnessione funzioni davvero, prima di procedere oltre") — nessuna logica di
		# ricollegamento qui: quella resta interamente dentro _reconnect_build_task_signals/
		# _reconnect_unload_action_signals/_reconnect_pickup_action_signals, invariate, questo blocco
		# si limita a CONTARE cosa hanno già fatto guardando lo stesso `step` da fuori.
		var setup_site_count := 0
		var clear_count := 0
		var unload_count := 0
		var pickup_count := 0
		var build_count := 0
		# jump_count (2026-09-13, richiesta utente, feedback visivo minimo Play Task) — STESSO
		# identico gap gemello: un JumpAction ricostruito da TaskPersistenceService.deserialize_task
		# dopo un reload è un'istanza NUOVA, il cui `jumped` non è mai stato collegato da nessuno —
		# stessa causa/stessa soluzione già chiusa qui per SetupSite/Clear/Unload/PickUp/Build.
		var jump_count := 0
		for step in member.current_task.steps:
			_reconnect_build_task_signals(step)
			if step is SetupSiteAction:
				setup_site_count += 1
			elif step is ClearAction:
				clear_count += 1
			elif step is UnloadAction:
				_reconnect_unload_action_signals(step as UnloadAction, member)
				unload_count += 1
			elif step is PickUpAction:
				_reconnect_pickup_action_signals(step as PickUpAction)
				pickup_count += 1
			elif step is BuildAction:
				build_count += 1
			elif step is JumpAction:
				_reconnect_jump_action_signals(step as JumpAction, member)
				jump_count += 1
		var reconnected_total := setup_site_count + clear_count + unload_count + pickup_count + build_count + jump_count
		if reconnected_total > 0 and DebugLogging.ENABLED and DebugLogging.SHOW_RECONNECT_FACTORY_LOGS:
			print("[RECONNECT DEBUG] Individuo #%d: ricollegati %d signal (tipi: SetupSite=%d, Clear=%d, Unload=%d, PickUp=%d, Build=%d, Jump=%d) dopo reload" % [
				member.id, reconnected_total, setup_site_count, clear_count, unload_count, pickup_count, build_count, jump_count
			])


# STESSI 4 listener/STESSO ordine già collegati in _debug_test_daydream_task (idea_completed x3,
# thought_deposited x1) — estratti qui (2026-09-11) come funzione condivisa così quel test debug e
# _reconnect_loaded_task_signals sopra non possano divergere. `individual` passato esplicitamente
# (non chiuso per closure su `self.individual`, il campo "individuo attualmente controllato dal
# player"): il proprietario REALE di questo UnloadAction è `member` nel chiamante sopra, che in
# teoria potrebbe non coincidere con l'individuo selezionato al momento del reload — stesso
# principio già seguito da _spawn_idea_deposit_effect.bind(individual) nel punto di creazione
# originale.
#
# GAP RESIDUO NON coperto qui (segnalato esplicitamente, non un'omissione silenziosa) — questi 4
# listener sono oggi collegati SOLO da _debug_test_daydream_task, e SOLO tramite task.step_appended:
# l'UnloadAction del ramo pensiero nasce DINAMICAMENTE quando ThinkAction completa (vedi
# HumanIndividualActionService._handle_pending_thought_target_search), non è mai uno step statico
# già presente in current_task.steps finché quel momento non arriva. Un salvataggio fatto PRIMA che
# l'UnloadAction venga accodato (es. a metà ThinkAction) non ha ancora nessuna istanza su cui
# ricollegare questi 4 listener — richiederebbe ricollegare anche task.step_appended stesso (un
# meccanismo Task-level, non Action-level: "lo stesso intervento" chiesto copre la ricostruzione di
# step GIÀ presenti, non un secondo canale in attesa di uno step futuro di un hook di debug
# temporaneo) — fuori scope in questo passo, segnalato per completezza.
func _reconnect_unload_action_signals(deposit: UnloadAction, individual_ref: HumanIndividual) -> void:
	deposit.idea_completed.connect(func(_idea_id: String) -> void: _refresh_building_slots_buildable())
	deposit.idea_completed.connect(_on_idea_completed)
	deposit.idea_completed.connect(func(_idea_id: String) -> void:
		if tech_tree_panel.visible:
			tech_tree_panel.refresh_content()
	)
	deposit.thought_deposited.connect(_spawn_idea_deposit_effect.bind(individual_ref))
	# resource_deposited (2026-09-12, richiesta utente — bugfix "il mucchietto non si aggiorna in
	# automatico quando viene fatto il deposito") — a differenza dei tre sopra (SOLO ramo pensiero),
	# questo scatta SOLO dal ramo FISICO: connesso incondizionatamente qui comunque, stesso principio
	# "un solo punto collega tutto ciò che questa classe può emettere" già seguito per gli altri —
	# innocuo per un'istanza che non lo emetterà mai (ramo pensiero), vedi unload_action.gd.
	deposit.resource_deposited.connect(_on_resource_deposited)


# Collega PickUpAction.resource_collected (2026-09-11, richiesta utente — gap gemello di
# SetupSite/Clear/Unload: "il signal di completamento è oggi connesso solo da _assign_pickup_task
# al momento della creazione in-sessione, mai da GameLoadService dopo un reload") — riusata TALE E
# QUALE sia da _assign_pickup_task (creazione in-sessione) sia da _reconnect_loaded_task_signals
# (reload da salvataggio), STESSO principio di _reconnect_build_task_signals/
# _reconnect_unload_action_signals sopra: un solo punto, i due chiamanti non possono disallinearsi.
#
# `cell` RISOLTO DENTRO il listener, non ricevuto come parametro/bind() — DEVIAZIONE rispetto alla
# primissima versione di questo collegamento (che catturava `cell` per closure da _assign_pickup_
# task, disponibile lì subito): quella cattura non è utilizzabile qui, perché al reload
# _reconnect_loaded_task_signals gira DENTRO _ready(), PRIMA che live_cells sia popolato. Cercata
# per riferimento tra live_cells.values() confrontando .macro_state con step.macro_state (campo
# pubblico già presente su PickUpAction, iniettato dal costruttore) — scansione lineare accettabile,
# live_cells conta al più poche celle vive contemporaneamente, stesso principio "pochi elementi,
# nessun indice dedicato" già seguito altrove nel progetto (es. TaskPersistenceService.
# _find_building_by_id). Nessun refresh se la cella non è (più) viva quando il segnale scatta
# davvero (macrocella nel frattempo disattivata) — coerente con _refresh_resource_visuals, che
# comunque non avrebbe nulla da rinfrescare per una cella non più live.
func _reconnect_pickup_action_signals(step: PickUpAction) -> void:
	step.resource_collected.connect(func(_res: String, _pos: Vector2i, _qty: int) -> void:
		for cell in live_cells.values():
			if cell.macro_state == step.macro_state:
				_refresh_resource_visuals(cell)
				break
	)


# Collega JumpAction.jumped (2026-09-13, richiesta utente, feedback visivo minimo per la Play
# Task) — STESSO principio di _reconnect_pickup_action_signals/_reconnect_unload_action_signals
# sopra (bind dell'individuo proprietario, un handler dedicato invece di passare da
# _reconnect_build_task_signals — quella resta per i signal "senza bind aggiuntivo" di SetupSite/
# Clear/Build, vedi quel commento): riusata TALE E QUALE sia da _assign_play_task (creazione
# in-sessione) sia da _reconnect_loaded_task_signals (reload da salvataggio) sotto.
func _reconnect_jump_action_signals(step: JumpAction, individual_ref: HumanIndividual) -> void:
	step.jumped.connect(_on_individual_jumped.bind(individual_ref))


# Reazione a JumpAction.jumped — risolve la HumanIndividualView dell'individuo (stessa ricerca
# per-indice parallela human_individuals/human_individual_views già in uso altrove, es.
# _sync_dependent_child_position) e le chiede il piccolo scatto verticale, vedi
# HumanIndividualView.trigger_jump_bounce. No-op silenzioso se la view non è (più) risolvibile
# (individuo morto/rimosso tra l'emissione del segnale e la sua ricezione — non dovrebbe succedere
# nello stesso frame, ma resta una guardia difensiva economica coerente con lo stile del progetto).
func _on_individual_jumped(individual_ref: HumanIndividual) -> void:
	var view_index := human_individuals.find(individual_ref)
	if view_index != -1 and view_index < human_individual_views.size():
		human_individual_views[view_index].trigger_jump_bounce()


# Reazione a ClearAction.site_cleared (2026-09-11, richiesta utente, terzo step della Build Task)
# — la mutazione VERA (BuildingSiteClearingService.clear_microcell + riserva dedicated_space
# [BUILDING]) è già avvenuta dentro ClearAction.on_complete PRIMA che questo segnale venga emesso
# (stesso principio di UnloadAction.on_complete, ramo fisico: chi ha già il macro_state muta lo
# stato da sé, il segnale serve solo a chi NON ce l'ha — qui GameScene, per il refresh VISIVO).
# STESSO schema di _place_building_at dopo BuildingSiteClearingService.clear_microcell:
# needs_full_vegetation_recompute invalida la cache posizioni di QUESTA cella viva (i dati sono
# cambiati, la vegetazione rimossa deve sparire dal disegno SUBITO, non al prossimo trigger
# naturale), poi _refresh_resource_visuals la rigenera davvero.
func _on_site_cleared(building: Building) -> void:
	if building == null:
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if not live_cells.has(macro_coords):
		return
	var cell: LiveMacroCell = live_cells[macro_coords]
	cell.needs_full_vegetation_recompute = true
	_refresh_resource_visuals(cell)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Cantiere edificio #%d ripulito — vegetazione rimossa, spazio riservato per l'edificio." % building.id)


# Reazione a UnloadAction.resource_deposited (2026-09-12, richiesta utente — bugfix "il mucchietto
# non si aggiorna in automatico quando viene fatto il deposito"): building.stored_resources è già
# stato mutato PRIMA che questo segnale venga emesso (stesso principio di _on_site_cleared/
# _on_building_construction_completed sopra), quindi qui basta un refresh esplicito della cella —
# _buildings_for_cell ricalcola slot_breakdown da BuildingStorageService.get_slot_breakdown ogni
# volta che viene chiamato, quindi il refresh cattura naturalmente il nuovo contenuto dei mucchietti.
func _on_resource_deposited(building: Building) -> void:
	if building == null:
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if not live_cells.has(macro_coords):
		return
	_refresh_building_visuals(live_cells[macro_coords])


# Reazione a BuildAction.building_construction_completed (2026-09-11, richiesta utente, quarto e
# ultimo step della Build Task) — building.is_complete/current_durability sono già stati valorizzati
# DENTRO BuildAction.on_complete PRIMA che questo segnale venga emesso (stesso principio di
# ClearAction.on_complete/_on_site_cleared sopra: chi ha già i dati muta lo stato da sé, il segnale
# serve solo a chi NON ce l'ha — qui GameScene). built_year INVECE è responsabilità di QUESTO
# handler (vedi il commento esteso in BuildAction.on_complete per il perché: quella classe non ha
# un riferimento a game_data, il cui valore può essere cambiato nel tempo intercorso tra la
# creazione della Task e il completamento — qui invece game_data è sempre quello CORRENTE, letto
# esattamente quando serve). STESSO valore/STESSA fonte di GameScene._place_building_at
# (game_data.year), solo risolto nel momento giusto invece che al piazzamento istantaneo.
#
# NIENTE walk-away qui (richiesta esplicita utente, "resta per un prompt a parte") — a differenza
# di UnloadAction.on_complete (ramo fisico), che scrive context["pending_walk_away_position"]
# consumato da HumanIndividualActionService._handle_pending_walk_away: quel canale non viene
# toccato da questa Task, l'individuo resta esattamente dov'è quando la Build Task finisce.
func _on_building_construction_completed(building: Building) -> void:
	if building == null:
		return
	building.built_year = game_data.year
	# Log spostato QUI (2026-09-12, richiesta utente — riordino cosmetico, nessuna modifica di
	# logica): prima appariva DOPO assign_pending_residents sotto, facendo comparire "[ASSIGN
	# HOUSE]" nei log prima di "completato!" anche se is_complete/built_year erano già impostati a
	# quel punto — ora l'ordine dei print rispecchia l'ordine logico reale.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[BUILD] Edificio #%d completato! (anno=%d)" % [building.id, building.built_year])
	# Rinfresca la scheda 🏠 (2026-09-12, richiesta utente) — lo stato passa da "in costruzione" a
	# "completo" proprio qui, la lista deve rifletterlo subito, non aspettare il rollover d'anno.
	_refresh_buildings_panel()
	# AssignHouseService (2026-09-12, richiesta utente — trigger 4a: "quando un edificio
	# residenziale completa la costruzione") — SOLO se max_residents > 0 (un edificio non
	# residenziale, es. Pebble Circle/Deposit Site, non ha senso farlo passare da qui: nessun posto
	# da riempire, la funzione stessa sarebbe comunque un no-op per quell'edificio dato che nessun
	# building con max_residents<=0 viene mai considerato candidato lì dentro, ma il controllo qui
	# evita il giro a vuoto). Chiamata PRIMA del guard "cella viva" sotto — l'assegnazione non ha
	# nulla a che fare col rendering, deve funzionare anche per una macrocella fuori dal LOD corrente.
	if building.rules != null and building.rules.max_residents > 0:
		AssignHouseService.assign_pending_residents(macro_world, human_individuals, game_data.year)
		# BUGFIX (2026-09-12, richiesta utente — "dopo assign house non si aggiorna il pop tab con
		# il simbolino di house a chi ne riceve una, restano solo i primi assignatari"): a
		# differenza dei due ALTRI trigger di AssignHouseService (morte/nascita, vedi
		# _on_human_individual_died/_on_human_individual_born), che sono comunque sempre seguiti a
		# ruota da un human_population_changed (vedi GameTimeService, e _on_human_population_changed
		# sotto che rinfresca la scheda 👨‍👩‍👧) perché il conteggio popolazione cambia per forza in
		# quei due casi, il completamento di un edificio NON cambia il conteggio popolazione — nessun
		# segnale lo segue mai, quindi senza questa chiamata esplicita la scheda popolazione restava
		# con l'icona 🏠 vecchia (mostrando solo chi l'aveva già da un refresh precedente) fino al
		# prossimo rollover d'anno.
		_refresh_population_panel()
	_remove_build_site_placeholders(building)
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if not live_cells.has(macro_coords):
		return
	var cell: LiveMacroCell = live_cells[macro_coords]
	# Refresh ESPLICITO necessario (2026-09-11, richiesta utente — "verifica se serve esplicito o se
	# il renderer lo fa già automaticamente") — CONFERMATO: serve. MicroCellRenderer._draw_buildings
	# legge is_complete/site_setup_complete dalla COPIA che gli è stata passata da set_buildings
	# (vedi _buildings_for_cell/_refresh_building_visuals), non dall'oggetto Building live stesso —
	# scrivere building.is_complete=true (già fatto in BuildAction.on_complete) non fa scattare da
	# solo alcun queue_redraw(): senza questa chiamata la sagoma vera dell'edificio (capanna/Stone
	# Circle/Deposit Site, finalmente disegnabile ora che is_complete=true) resterebbe invisibile
	# fino al prossimo trigger di refresh casuale (es. il player che si muove).
	_refresh_building_visuals(cell)


# Rimuove il gruppo dei 4 rametti spawnati da _spawn_build_site_placeholders per QUESTO edificio
# (2026-09-11, richiesta utente, quarto step — "rimuovi i 4 placeholder... trova come sono
# referenziati") — vedi _BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX sopra per come il gruppo viene
# nominato/ritrovato. Nessun errore se il gruppo non esiste (cella non più viva, o il cantiere non è
# mai arrivato a spawnarli — es. una microcella già priva di vegetazione dove SetupSiteAction/
# ClearAction completano nello stesso giorno ma i placeholder SONO comunque sempre spawnati da
# SetupSiteAction, indipendentemente dalla vegetazione — questo ramo difensivo copre solo il caso
# "cella non più viva", non un vero caso mancante oggi).
func _remove_build_site_placeholders(building: Building) -> void:
	if building == null:
		return
	var macro_coords := Vector2i(building.macro_x, building.macro_y)
	if not live_cells.has(macro_coords):
		return
	var cell: LiveMacroCell = live_cells[macro_coords]
	var placeholder_group := cell.container.get_node_or_null(_BUILD_SITE_PLACEHOLDER_GROUP_NAME_PREFIX + str(building.id))
	if placeholder_group != null:
		placeholder_group.queue_free()


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
# l'id, e da Pebble Circle 2026-09-07 il tipo, e da Build Task 2026-09-11 lo stato di completamento,
# e da Storage Grid 2026-09-11 lo slot_breakdown per il solo deposit_site) inclusi — vedi
# MicroCellRenderer.set_buildings/buildings (Array[Dictionary], {"position","rotation","id",
# "building_type_name","is_complete","site_setup_complete","slot_breakdown"}). Funzione separata
# invece di arricchire quella sopra: _building_positions_for_cell resta usata anche per
# l'esclusione vegetazione, dove rotazione/id/tipo non servono a nessuno.
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
			var entry: Dictionary = {
				"position": Vector2i(building.micro_x, building.micro_y),
				"rotation": building.rotation,
				"id": building.id,
				# "building_type_name" (2026-09-07, richiesta utente, Pebble Circle) — prima di
				# questo passo tutti gli edifici erano capanne, quindi MicroCellRenderer._draw_
				# buildings non aveva bisogno di distinguere: ora sì, vedi lì.
				"building_type_name": building.building_type_name,
				# "is_complete"/"site_setup_complete" (2026-09-11, richiesta utente — cartello "work
				# in progress" sul cantiere non ancora allestito, poi solo bastoncini una volta
				# allestito, MAI la sagoma vera finché is_complete resta false) — vedi Building.
				# is_complete/site_setup_complete/MicroCellRenderer._draw_buildings.
				"is_complete": building.is_complete,
				"site_setup_complete": building.site_setup_complete,
			}
			# "slot_breakdown" (2026-09-11, richiesta utente — "sul deposit site... disegna gli
			# oggetti che ci sono, tipo mucchietti") — SOLO per deposit_site ("solo su questo",
			# richiesta esplicita: hut ha storage anche lui ma non è in scope qui), calcolato con la
			# STESSA fonte già usata da BuildingInfoPanel._refresh_storage_grid (BuildingStorageService.
			# get_slot_breakdown), così la griglia disegnata sulla mappa e quella nel pannello non
			# possono mai disallinearsi. Non aggiunto per gli altri tipi — nessun costo per loro,
			# nessuna chiave da ignorare.
			if building.building_type_name == "deposit_site":
				entry["slot_breakdown"] = BuildingStorageService.get_slot_breakdown(building)
			result.append(entry)
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
		&"options":
			# false = niente scelta lingua qui (richiesta utente, 2026-09-05) — solo il toggle
			# notifiche, unico campo pertinente a partita in corso. Vedi OptionsMenu.open_menu.
			options_menu.open_menu(false)
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


# Banner persistente "selezione Transport a metà" (2026-09-14, richiesta utente) — costruito via
# codice, nessun .tscn, stesso principio/stessa posizione di notification_popup (istanziato in
# _setup_clock, sotto CanvasLayer per restare in overlay sopra il resto della UI). PanelContainer +
# Label (non un semplice Label nudo): sopra la mappa un testo senza sfondo sarebbe illeggibile in
# certe zone/temi — sfondo giallo semi-opaco, STESSO colore "alert" già usato da NotificationPopup
# per MATERIAL_NEEDED (coerenza visiva: "giallo" = "richiede attenzione" ovunque in questa UI).
# Ancorato in alto al centro (PRESET_CENTER_TOP), nascosto di default (`visible = false`) — mostrato/
# nascosto ai tre punti che cambiano _debug_transport_source_building (vedi il commento sul campo
# transport_selection_banner in testa al file), mai ricreato.
func _setup_transport_selection_banner() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.7, 0.15, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	transport_selection_banner = PanelContainer.new()
	transport_selection_banner.add_theme_stylebox_override("panel", style)
	transport_selection_banner.visible = false
	transport_selection_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transport_selection_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	transport_selection_banner.position.y = 12

	transport_selection_banner_label = Label.new()
	transport_selection_banner_label.text = tr("transport_selection_banner_text")
	transport_selection_banner_label.add_theme_font_size_override("font_size", 13)
	transport_selection_banner_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	transport_selection_banner.add_child(transport_selection_banner_label)

	$CanvasLayer.add_child(transport_selection_banner)


func _setup_clock() -> void:
	clock = GameClockController.new()
	add_child(clock)
	# Sistema notifiche (2026-09-05) — istanziato qui indipendentemente dal ramo macro_world==null
	# sotto (nessuna dipendenza dal mondo, un componente UI puro), sotto CanvasLayer per restare in
	# overlay sopra il resto della UI.
	notification_popup = NotificationPopup.new()
	$CanvasLayer.add_child(notification_popup)
	_setup_transport_selection_banner()
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
	# human_individuals/human_folk/human_population_group passati per riferimento (Step 5/6 piano
	# mortalità, 2026-09-05): GameTimeService li usa per agganciare HumanMortalityIndividualService.
	# check_mortality a year_rolled_over e la rimozione reale a day_advanced — sempre gli STESSI
	# oggetti di GameScene, mai una copia.
	game_time_service = GameTimeService.new()
	game_time_service.connect_to_clock(clock, game_data, human_individuals, human_folk, human_population_group, macro_world, individual_action_service)
	# Step 6 piano mortalità (2026-09-05): GameTimeService rimuove l'individuo morto da
	# human_individuals (stesso array, per riferimento) ma non sa nulla di human_individual_views
	# (rendering, di competenza esclusiva di GameScene) — questo segnale, emesso PRIMA della
	# rimozione con l'indice ancora valido, è il punto in cui liberiamo/rimuoviamo la view
	# corrispondente ALLO STESSO indice, per non sfasare le due collezioni parallele.
	game_time_service.individual_died.connect(_on_human_individual_died)
	# Step 4 del piano riproduzione (2026-09-06) — schema simmetrico di individual_died sopra:
	# GameTimeService/HumanBirthIndividualService aggiungono già il neonato a human_individuals
	# (stesso array, per riferimento) ma non sanno nulla di human_individual_views — questo
	# segnale, emesso DOPO l'aggiunta, è il punto in cui creiamo la view corrispondente, tenendo
	# le due collezioni parallele per indice (il neonato è sempre l'ULTIMO elemento di
	# human_individuals in questo momento, mai inserito a metà array).
	game_time_service.individual_born.connect(_on_human_individual_born)
	# Effetto nato-morto (2026-09-06) — simmetrico a individual_born sopra, stesso schema.
	game_time_service.human_stillbirth.connect(_on_human_stillbirth)
	game_time_service.human_population_changed.connect(_on_human_population_changed)
	# Decadimento zaino/storage edificio (2026-09-09, richiesta utente, Step 3 decadimento) — stesso
	# gate UserOptions.show_notification_popups/stesso NotificationPopup di morte/nascita/idea sopra.
	# individual_resource_decayed vive su game_time_service (stesso canale di individual_died/born
	# sopra); building_resources_decayed vive invece su clock (WorldTimeService, non GameTimeService,
	# gestisce il decadimento edifici — vedi WorldTimeService._run_daily_building_resource_decay).
	game_time_service.individual_resource_decayed.connect(_on_individual_resource_decayed)
	clock.building_resources_decayed.connect(_on_building_resources_decayed)
	# Cantiere bloccato per mancanza di materiale (2026-09-14, richiesta utente) — vive su
	# individual_action_service (già un campo di GameScene, la STESSA istanza che guida apply_action
	# ogni frame), non su game_time_service: la rilevazione avviene dentro HumanIndividualActionService.
	# _resolve_material_shortage, chiamata sia dal ciclo per-frame sia dal ritentativo giornaliero.
	# Stesso gate UserOptions.show_notification_popups/stesso NotificationPopup di ogni altro evento
	# sopra — vedi _on_building_material_blocked.
	individual_action_service.building_material_blocked.connect(_on_building_material_blocked)
	# Discard esplicito sulla mappa (2026-09-14, richiesta utente — step C del piano "rerouting":
	# "rendiamo esplicito il discard con un simbolo sulla mappa che scompare dopo qualche secondo")
	# — stesso principio/stessa posizione della connessione sopra, effetto puramente visivo (nessun
	# gate su UserOptions.show_notification_popups, quello vale per i popup di NotificationPopup,
	# non per un effetto sulla mappa come _spawn_idea_deposit_effect — vedi _on_carried_resource_
	# discarded).
	individual_action_service.carried_resource_discarded.connect(_on_carried_resource_discarded)
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
	# Refresh giornaliero del pannello individuo selezionato (2026-09-06, richiesta utente) — PRIMA
	# dell'early-return sotto, stesso motivo di _maybe_prune_fog_of_war_memories sopra: deve girare
	# anche nei giorni "vuoti" (nessun checkpoint/animali cambiati), non solo quando il resto della
	# funzione prosegue. Stesso canale già esistente usato per il refresh ANNUALE (GameScene.
	# _on_year_rolled_over, connesso direttamente a clock.year_rolled_over) — MAI attraverso
	# GameTimeService, che non ha né deve avere un riferimento a GameScene (resta agnostico rispetto
	# a UI/pannelli, per design). Costo misurato con un dato reale (non assunto trascurabile) —
	# stesso stile/convenzione di HumanStaminaIndividualService/DebugLogging.SHOW_STAMINA_RECALC_LOGS.
	var _debug_panel_refresh_start_usec := Time.get_ticks_usec()
	_refresh_selected_individual_panel()
	# Refresh giornaliero del pannello edificio selezionato (2026-09-09, richiesta utente — "il
	# pannello non si aggiorna quando sparisce qualcosa, devo cambiare click e tornare lì") — stesso
	# identico principio/stessa posizione di _refresh_selected_individual_panel appena sopra: prima
	# dell'early-return sotto, gira anche nei giorni "vuoti". BuildingStorageService.get_slot_
	# breakdown è già economico (al più storage_slot_count slot), nessun costo misurato qui a
	# differenza del pannello individuo.
	_refresh_selected_building_panel()
	# Refresh giornaliero della scheda 🐞 (2026-09-12, richiesta utente — bugfix "il pannello debug
	# task non si riempie mai di nessuna task": prima si aggiornava solo al cambio scheda/al
	# rollover ANNUALE, troppo raro per un test rapido — spostato qui, stesso canale/stessa cadenza
	# di _refresh_selected_individual_panel/_refresh_selected_building_panel sopra). SOLO se è la
	# tab attualmente attiva (a differenza di quelle due, sempre rinfrescate incondizionatamente:
	# questa resta la meno probabile ad essere aperta, nessun bisogno di lavorare quando non è
	# visibile) — il bottone "🔄" nel pannello resta comunque il modo primario/immediato di
	# aggiornarla, questo è solo un ripasso automatico di cortesia.
	if game_info_tabs.current_tab == GameInfoTabs.TAB_DEBUG:
		task_debug_panel.refresh()
	if DebugLogging.ENABLED and DebugLogging.SHOW_SELECTED_PANEL_REFRESH_LOGS:
		var panel_refresh_elapsed_ms := (Time.get_ticks_usec() - _debug_panel_refresh_start_usec) / 1000.0
		print("[SELECTED PANEL REFRESH] anno=%d giorno=%d: %.3f ms" % [
			game_data.year, game_data.current_day, panel_refresh_elapsed_ms
		])
	# [DBG_TASK] (2026-09-16, richiesta utente — gated dalla categoria DAILY_SUMMARY, riordino log di
	# debug: prima un const locale DEBUG_TASK_LOG a questo file, default true; ora
	# DebugLogging.SHOW_DAILY_SUMMARY_LOGS, stesso default true, stesso comportamento a impostazioni
	# invariate). Ricalcola qui lo STESSO filtro di GameScene._process/active_individuals (current_task
	# non nullo e non concluso) — sola lettura, non condivide stato con quel ciclo (che vive in una
	# variabile locale a _process, irraggiungibile da qui). Elenco per-individuo ESTESO a TUTTA la
	# popolazione (2026-09-16, richiesta utente — "stampa tutti gli individui, non solo i primi 10"):
	# PRIMA filtrava via INFANT/CHILD ("adulto" = age_band diverso da INFANT/CHILD) — nessun limite
	# numerico a 10 individui è mai esistito nel codice (verificato), ma quel filtro per età escludeva
	# comunque una parte della popolazione dall'elenco dettagliato; rimosso, ora stampa OGNI individuo
	# senza eccezioni. Nessuna correzione qui anche a fronte di anomalie evidenti nei numeri stampati
	# — solo dati grezzi.
	if DebugLogging.ENABLED and DebugLogging.SHOW_DAILY_SUMMARY_LOGS:
		var debug_active_individuals_count := 0
		for debug_member in human_individuals:
			if debug_member.current_task != null and not debug_member.current_task.is_finished():
				debug_active_individuals_count += 1
		print("[DBG_TASK] anno=%d giorno=%d — individui totali=%d, active_individuals=%d" % [
			game_data.year, game_data.current_day, human_individuals.size(), debug_active_individuals_count
		])
		for debug_member in human_individuals:
			var debug_task_name: String = debug_member.current_task.task_name if debug_member.current_task != null else "null"
			print("[DBG_TASK]   #%d %s: current_task=%s, task_queue.size()=%d, current_stamina=%.1f, carried_resource_name='%s'" % [
				debug_member.id, debug_member.name, debug_task_name, debug_member.task_queue.size(),
				debug_member.current_stamina, debug_member.carried_resource_name
			])

	if not (checkpoint_ran or animals_changed):
		# Filtrato ai soli dintorni di un checkpoint stagionale (richiesta utente, 2026-09-05 —
		# stesso motivo/helper di WorldTimeService.advance_day/GameClockController._process: un log
		# per ogni giorno era troppo rumoroso).
		if DebugLogging.SHOW_DAILY_TIMING_LOGS and SeasonCalculator.is_near_seasonal_checkpoint(game_data.current_day):
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
		# Filtrato ai soli dintorni di un checkpoint stagionale, stesso motivo/helper dei due
		# blocchi sopra/sotto (richiesta utente, 2026-09-05).
		if DebugLogging.SHOW_DAILY_TIMING_LOGS and SeasonCalculator.is_near_seasonal_checkpoint(game_data.current_day):
			var vegetation_refresh_ms: float = (Time.get_ticks_usec() - vegetation_refresh_start_usec) / 1000.0
			print("[GAMESCENE DAY] rebuild vegetazione (%d/%d celle vive rinfrescate — solo prossimità, checkpoint_ran=%s flora_daily_updates_enabled=%s) = %.1fms" % [
				proximity_cells.size(), live_cells.size(), "si" if checkpoint_ran else "no", "si" if flora_daily_updates_enabled else "no", vegetation_refresh_ms
			])
	else:
		_update_info_panel()

	if DebugLogging.SHOW_DAILY_TIMING_LOGS and SeasonCalculator.is_near_seasonal_checkpoint(game_data.current_day):
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
