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


func is_empty() -> bool:
	return notifications.is_empty() and cells_to_refresh.is_empty() and panels_to_refresh.is_empty() and not pending_refresh 		and neighbor_refresh_buildings.is_empty() and marker_buildings.is_empty() and site_placeholder_buildings.is_empty() 		and vegetation_cells.is_empty() and removed_building_ids.is_empty() and storage_tasks_to_wire.is_empty()
