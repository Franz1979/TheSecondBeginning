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


# Unisce gli effetti di `other` in questo (le notifiche in coda, dopo le proprie).
func merge(other: GameEffects) -> void:
	if other == null:
		return
	notifications.append_array(other.notifications)
	cells_to_refresh.merge(other.cells_to_refresh)
	panels_to_refresh.merge(other.panels_to_refresh)
	pending_refresh = pending_refresh or other.pending_refresh


func is_empty() -> bool:
	return notifications.is_empty() and cells_to_refresh.is_empty() and panels_to_refresh.is_empty() and not pending_refresh
