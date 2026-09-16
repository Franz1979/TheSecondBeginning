class_name PlantFiberLotSelectorController
extends RefCounted

# Hit-test per il click sul "terreno" di una microcella SHRUB (2026-09-16, richiesta utente — Step 4
# del piano plant_fiber) — MIRROR ESATTO di StickLotSelectorController.gd (TREE -> stick), qui per
# SHRUB -> plant_fiber: stesso identico algoritmo (risolvi in quale lotto è caduto il click,
# verifica che sia "rivendicato" — MacroCellState.shrub_claimed_lots, stesso store letto da
# IndividualVegetationService/VegetationPoolService — ed escludi un lotto occupato da un edificio),
# duplicato deliberatamente invece di generalizzare StickLotSelectorController (che resta usato
# anche dal click SINISTRO/pannello info in GameScene — nessun rischio di toccarlo per questa
# feature, stesso principio "nessuna classe condivisa tra usi diversi" già seguito ovunque in questo
# progetto, es. VegetationPoolService._claimed_lots_store vs IndividualVegetationService._claimed_
# lots_store).
#
# plant_fiber NON ha un proprio layer di rendering (richiesta esplicita utente — "rappresentata
# visivamente dagli arbusti stessi, nessun layer grafico dedicato"): il click funziona quindi
# cliccando sugli arbusti disegnati per la vegetazione, esattamente come per stick prima di questo
# passo — questo controller legge SOLO dati (shrub_claimed_lots), mai il renderer per altro che il
# calcolo della posizione del mouse (get_local_mouse_position, stesso identico uso non-visivo già
# fatto da StickLotSelectorController).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer


# Ritorna {"macro_coords": Vector2i, "lot": Vector2i} se il click è caduto dentro una microcella
# SHRUB di una delle celle vive, {} altrimenti — STESSA firma/STESSO contratto di
# StickLotSelectorController.try_select.
func try_select(event: InputEvent, live_cells: Dictionary, required_button: int = MOUSE_BUTTON_LEFT, buildings: Array = []) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
		return {}

	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null or cell.macro_state == null:
			continue

		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		var click_lot := Vector2i(int(floor(local_mouse.x / CELL_SIZE)), int(floor(local_mouse.y / CELL_SIZE)))

		if not cell.macro_state.shrub_claimed_lots.has(click_lot):
			continue
		if _is_occupied_by_building(buildings, coords, click_lot):
			continue
		return {"macro_coords": coords, "lot": click_lot}

	return {}


static func _is_occupied_by_building(buildings: Array, macro_coords: Vector2i, lot: Vector2i) -> bool:
	for building in buildings:
		if building.macro_x == macro_coords.x and building.macro_y == macro_coords.y \
				and building.micro_x == lot.x and building.micro_y == lot.y:
			return true
	return false
