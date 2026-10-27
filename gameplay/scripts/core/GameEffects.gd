class_name GameEffects
extends RefCounted

# Effetti per la PRESENTAZIONE (2026-10-17, refactoring GameScene blocco 0 — docs/design/gamescene_refactoring.md):
# cosa la scena deve mostrare dopo che un servizio ha cambiato lo stato di gioco. Un servizio non tocca mai nodi,
# popup, renderer o celle vive: riempie un GameEffects e la scena lo esegue (GameScene._apply_effects). La futura
# scena 3D consumerà lo stesso oggetto a modo suo. Da non confondere con TaskCompletionEffects/SkillActionEffects,
# che sono effetti di GIOCO (skill, vitali), non di presentazione.
#
# Ridisegni e refresh sono insiemi (un edificio o un pannello chiesto più volte si aggiorna una volta sola);
# le notifiche sono in ordine e si mostrano tutte. Nuovi tipi di effetto si aggiungono qui quando un blocco del
# refactoring ne ha bisogno, insieme al loro ramo in GameScene._apply_effects.

enum PanelKind {
	POPULATION,           # GameScene._refresh_population_panel
	BUILDINGS,            # GameScene._refresh_buildings_panel
	SELECTED_INDIVIDUAL,  # GameScene._refresh_selected_individual_panel
	SELECTED_BUILDING,    # GameScene._refresh_selected_building_panel
	WAREHOUSE,            # GameScene._refresh_warehouse_panel
	BUILD_BAR,            # GameScene._refresh_building_slots_buildable (slot costruibili della barra)
	DEAD_BODY,            # GameScene._refresh_dead_body_panel, se un corpo è selezionato (2026-10-24, 5B.6)
}

# {"type": NotificationTypes.NotificationPopupType, "text": String, "requires_ack": bool}, nell'ordine di arrivo.
var notifications: Array[Dictionary] = []
# Macrocelle (Vector2i) i cui edifici vanno ridisegnati -> true. Le celle non vive si ignorano in GameScene.
var cells_to_refresh: Dictionary = {}
# GameEffects.PanelKind -> true.
var panels_to_refresh: Dictionary = {}
# Il riquadro "In sospeso" va ricalcolato.
var pending_refresh: bool = false
# Edifici (2026-10-17, blocco 3) le cui celle vicine vanno ridisegnate (fondi che si saldano, edifici lineari):
# id edificio -> Building.
var neighbor_refresh_buildings: Dictionary = {}
# Edifici di cui ridisegnare solo la sagoma (stato "da demolire" e simili, senza ricalcolo di movimento e cammino): id -> Building.
var marker_buildings: Dictionary = {}
# Cantieri appena nati sul posto (miglioramento) che vogliono i rametti del cantiere: id -> Building.
var site_placeholder_buildings: Dictionary = {}
# Macrocelle (Vector2i) la cui vegetazione va ricalcolata da capo (spazio occupato cambiato) -> true.
var vegetation_cells: Dictionary = {}
# Edifici spariti dal mondo (id -> true): se uno è selezionato, la selezione si chiude.
var removed_building_ids: Dictionary = {}
# Task create da un servizio i cui step vanno collegati come quelli del trasporto (griglia del magazzino):
# [{"task": Task, "owner": HumanIndividual}], in ordine.
var storage_tasks_to_wire: Array[Dictionary] = []
# Task nuove da collegare ai segnali della scena (2026-10-18, blocco 5d — wire_task), in ordine.
var tasks_to_wire: Array[Dictionary] = []
# Icone di comando (2026-10-18, blocco 5d; dal 5B.2 a punto): {macro, point, key}, `point` in coordinate di microcella
# continue; solo se la cella è viva.
var command_icons: Array[Dictionary] = []
# Cantieri completati dalla simulazione (2026-10-18, blocco 5e — giorni minimi di costruzione maturati): la scena esegue
# lo stesso percorso del completamento da parte di un costruttore (GameScene._on_building_construction_completed).
var buildings_completed: Array[Building] = []
# Passaggi di macrocella degli individui, in ordine (individual_moved).
var individual_moves: Array[Dictionary] = []
# Individui appena entrati nella popolazione (visitatori accolti): la scena crea le viste, in ordine.
var individuals_added: Array[HumanIndividual] = []
# Task di scarico da collegare (UnloadAction: re-routing, avvisi) — GameScene._reconnect_unload_action_signals.
var unload_tasks_to_wire: Array[Dictionary] = []
# Chiavi dei lavori della bacheca non più in attesa (2026-10-24, 5B.0): la scena toglie le icone lampeggianti.
var forgotten_job_board_waits: Array[String] = []
# Specie domestiche appena addomesticate per la prima volta (2026-10-26, DomesticationPointsService): la scena fa
# scattare le scoperte ANIMAL_DOMESTICATED.
var animals_domesticated: Array[String] = []


func notify(popup_type: NotificationTypes.NotificationPopupType, text: String, requires_ack: bool = false) -> void:
	notifications.append({"type": popup_type, "text": text, "requires_ack": requires_ack})


func refresh_cell(macro_coords: Vector2i) -> void:
	cells_to_refresh[macro_coords] = true


func refresh_building_cell(building: Building) -> void:
	refresh_cell(Vector2i(building.macro_x, building.macro_y))


func refresh_panel(panel: PanelKind) -> void:
	panels_to_refresh[panel] = true


func refresh_pending() -> void:
	pending_refresh = true


func refresh_neighbors(building: Building) -> void:
	neighbor_refresh_buildings[building.id] = building


func refresh_marker(building: Building) -> void:
	marker_buildings[building.id] = building


func spawn_site_placeholders(building: Building) -> void:
	site_placeholder_buildings[building.id] = building


func refresh_vegetation(macro_coords: Vector2i) -> void:
	vegetation_cells[macro_coords] = true


func building_removed(building_id: int) -> void:
	removed_building_ids[building_id] = true


func wire_storage_task(task: Task, owner: HumanIndividual) -> void:
	storage_tasks_to_wire.append({"task": task, "owner": owner})


# Collegamenti dei segnali di una task nuova (2026-10-18, blocco 5d), per tipo:
#   BUILD_STEPS: GameScene._reconnect_build_task_signals su ogni step (allestimento, sgombero, costruzione, taglio, cava...);
#   PICKUP: _wire_pickup_task (raccolta e scarico aggiunto dopo);
#   BUTCHER: _wire_butcher_task;
#   HAUL_ZONE: _connect_haul_zone_step_appended (raccolta di zona: step aggiunti strada facendo);
#   MATERIAL_SUPPLY: _connect_material_supply_step_appended (rifornimento automatico di Build e Produce, 2026-10-24 5B.4);
#   STEP_SIGNALS: _ensure_step_signals (magazzino, caccia, corpo in spalla — sepoltura, 2026-10-24 5B.6).
# Le task arrivano già accodate (le code non attivano nulla): collegarle subito dopo equivale a prima.
enum WireKind { BUILD_STEPS, PICKUP, BUTCHER, HAUL_ZONE, MATERIAL_SUPPLY, STEP_SIGNALS }


func wire_task(kind: WireKind, task: Task, owner: HumanIndividual) -> void:
	if task != null:
		tasks_to_wire.append({"kind": kind, "task": task, "owner": owner})


func building_completed(building: Building) -> void:
	buildings_completed.append(building)


# Icona di comando sulla microcella `microcell` della macrocella `macro` (2026-10-18, blocco 5d): al suo centro.
func command_icon_at_microcell(macro: Vector2i, microcell: Vector2i, key: String) -> void:
	command_icon_at_point(macro, Vector2(microcell) + Vector2(0.5, 0.5), key)


# Icona di comando nel punto `point` (coordinate di microcella continue) della macrocella `macro` (2026-10-24, 5B.2).
func command_icon_at_point(macro: Vector2i, point: Vector2, key: String) -> void:
	command_icons.append({"macro": macro, "point": point, "key": key})


# Individuo passato in un'altra macrocella (2026-10-18, blocco 5b — IndividualBorderService): la scena sposta la vista
# sotto la cella `macro` (attivandola se serve, come rete di sicurezza) e, se `is_focus`, ri-ancora centro, telecamera e
# LOD di (dx, dy). `is_child`: figlio a carico che segue la madre (solo la vista, e solo se la cella è viva). In ordine.
func individual_moved(member: HumanIndividual, macro: Vector2i, step: Vector2i, is_focus: bool, is_child: bool) -> void:
	individual_moves.append({"member": member, "macro": macro, "step": step, "is_focus": is_focus, "is_child": is_child})


# Individuo appena entrato nella popolazione (2026-10-18, blocco 5c): la scena ne crea la vista.
func individual_added(member: HumanIndividual) -> void:
	individuals_added.append(member)


# Task con UnloadAction da collegare ai segnali della scena (2026-10-18, blocco 5c: la dote dei visitatori).
func wire_unload_task(task: Task, owner: HumanIndividual) -> void:
	unload_tasks_to_wire.append({"task": task, "owner": owner})


# Lavori della bacheca non più in attesa (2026-10-24, 5B.0 — CommandFeedback.forget_job_board_waits, che cancella anche
# l'attesa in GameData).
func job_board_waits_forgotten(job_keys: Array[String]) -> void:
	forgotten_job_board_waits.append_array(job_keys)


# Prima addomesticazione di una specie domestica (2026-10-26).
func animal_domesticated(species: String) -> void:
	animals_domesticated.append(species)


# Unisce gli effetti di `other` in questo (le notifiche in coda, dopo le proprie).
func merge(other: GameEffects) -> void:
	if other == null:
		return
	notifications.append_array(other.notifications)
	cells_to_refresh.merge(other.cells_to_refresh)
	panels_to_refresh.merge(other.panels_to_refresh)
	pending_refresh = pending_refresh or other.pending_refresh
	neighbor_refresh_buildings.merge(other.neighbor_refresh_buildings)
	marker_buildings.merge(other.marker_buildings)
	site_placeholder_buildings.merge(other.site_placeholder_buildings)
	vegetation_cells.merge(other.vegetation_cells)
	removed_building_ids.merge(other.removed_building_ids)
	storage_tasks_to_wire.append_array(other.storage_tasks_to_wire)
	tasks_to_wire.append_array(other.tasks_to_wire)
	command_icons.append_array(other.command_icons)
	buildings_completed.append_array(other.buildings_completed)
	individual_moves.append_array(other.individual_moves)
	individuals_added.append_array(other.individuals_added)
	unload_tasks_to_wire.append_array(other.unload_tasks_to_wire)
	forgotten_job_board_waits.append_array(other.forgotten_job_board_waits)
	animals_domesticated.append_array(other.animals_domesticated)


func is_empty() -> bool:
	return notifications.is_empty() and cells_to_refresh.is_empty() and panels_to_refresh.is_empty() and not pending_refresh 		and neighbor_refresh_buildings.is_empty() and marker_buildings.is_empty() and site_placeholder_buildings.is_empty() 		and vegetation_cells.is_empty() and removed_building_ids.is_empty() and storage_tasks_to_wire.is_empty() \
		and individual_moves.is_empty() and individuals_added.is_empty() and unload_tasks_to_wire.is_empty() \
		and tasks_to_wire.is_empty() and command_icons.is_empty() and buildings_completed.is_empty() \
		and forgotten_job_board_waits.is_empty() and animals_domesticated.is_empty()
