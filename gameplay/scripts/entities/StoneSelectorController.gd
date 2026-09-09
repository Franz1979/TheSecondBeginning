class_name StoneSelectorController
extends RefCounted

# Hit-test per il click su una singola posizione STONE (microcella, 2026-09-08, richiesta utente)
# — stesso identico pattern di VegetationSelectorController.try_select, qui su
# macro_state.stone_positions (Array[Vector2i], una pietra = una posizione) invece che su
# vegetation_positions (Array[Vector3i], individui con sottotipo/età propri): STONE non ha
# "individui" in quel senso, solo posizioni discrete + (da questa sessione) una quantità pebble
# per posizione — vedi StoneInfoPanel per cosa viene mostrato una volta selezionata.
#
# Click SINISTRO di default (selezione/ispezione), stessa convenzione di ogni altro
# *SelectorController in questo progetto — ma vedi required_button su try_select sotto (2026-09-09):
# GameScene lo richiama anche col DESTRO per risolvere il bersaglio del comando "vai e raccogli",
# separato dalla selezione (il destro resta altrimenti movimento puro del player).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/VegetationSelectorController

# Il blob-pietra disegnato ha raggio 6.5-7.5 (MicroCellRenderer.STONE_BLOB_VERTEX_COUNT/
# _build_stone_variant_mesh) — comparabile o maggiore di CELL_SIZE=10, molto più grande della
# chioma di un singolo individuo vegetale (VegetationSelectorController.CLICK_RADIUS_PX = 4.5).
# 7.0 approssima il raggio medio reale del blob, coerente col vero ingombro visivo invece di una
# tolleranza scollegata da cosa si vede a schermo — stesso principio già usato da
# BuildingSelectorController.CLICK_RADIUS_PX (raggio del recinto disegnato).
const CLICK_RADIUS_PX: float = 7.0


# Ritorna {"macro_coords": Vector2i, "position": Vector2i, "distance": float (px, spazio locale
# della cella del match)} per la posizione STONE più vicina al click entro CLICK_RADIUS_PX, in una
# delle celle vive, {} altrimenti. Il chiamante (GameScene) decide cosa fare col risultato — questo
# controller non tocca mai selected_stone.
#
# required_button (2026-09-09, richiesta utente — split selezione/comando raccolta): default
# MOUSE_BUTTON_LEFT invariato per il chiamante di selezione esistente. GameScene lo richiama anche
# con MOUSE_BUTTON_RIGHT per il comando "vai e raccogli" (stesso hit-test, nessuna duplicazione),
# separato per costruzione dalla selezione sinistro-click — nessun altro cambiamento alla logica di
# hit-test sotto.
func try_select(event: InputEvent, live_cells: Dictionary, required_button: int = MOUSE_BUTTON_LEFT) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
		return {}

	var best: Dictionary = {}
	var best_distance: float = CLICK_RADIUS_PX

	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null or cell.macro_state == null:
			continue

		# Spazio locale DI QUESTA cella — stesso principio già usato da
		# VegetationSelectorController/BuildingSelectorController.
		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		var click_lot := Vector2i(int(floor(local_mouse.x / CELL_SIZE)), int(floor(local_mouse.y / CELL_SIZE)))

		for pos in cell.macro_state.stone_positions:
			# Solo la posizione cliccata + le 8 adiacenti: il jitter di centro è piccolo (±0.8px,
			# vedi MicroCellRenderer.get_stone_screen_position) ma il RAGGIO del blob (fino a 7.5px)
			# da solo può sconfinare visivamente nella cella vicina — stessa tolleranza/stesso
			# motivo già usato da VegetationSelectorController per chioma/offset.
			if abs(pos.x - click_lot.x) > 1 or abs(pos.y - click_lot.y) > 1:
				continue

			var screen_pos: Vector2 = cell.renderer.get_stone_screen_position(pos)
			var distance: float = local_mouse.distance_to(screen_pos)
			if distance < best_distance:
				best_distance = distance
				best = {"macro_coords": coords, "position": pos, "distance": distance}

	return best
