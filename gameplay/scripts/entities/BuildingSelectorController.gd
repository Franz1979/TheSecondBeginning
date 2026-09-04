class_name BuildingSelectorController
extends RefCounted

# Hit-test per il click su un edificio esistente — Step 4 del piano "centra generalizzato +
# selezione edifici" (richiesta utente, 2026-09-04), analogo a VegetationSelectorController ma più
# semplice: un edificio ha un'unica posizione precisa per microcella (ancoraggio al CENTRO, stesso
# esatto punto disegnato da MicroCellRenderer._draw_buildings — "ground" lì), nessun lotto/densità/
# stato bloccato, e un id stabile (Building.id, mai riderivato — a differenza di Vector3i per la
# vegetazione, che invece si rigenera ad ogni refresh). Solo click SINISTRO, stesso principio di
# VegetationSelectorController (il destro resta esclusivamente movimento del player).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView
# Stesso raggio del recinto disegnato (MicroCellRenderer.BUILDING_FENCE_RADIUS) — cliccare dentro
# il recinto seleziona l'edificio, coerente col suo vero ingombro visivo invece di una tolleranza
# arbitraria scollegata da cosa si vede a schermo.
const CLICK_RADIUS_PX: float = MicroCellRenderer.BUILDING_FENCE_RADIUS


# Ritorna {"macro_coords": Vector2i, "building_id": int, "distance": float (px, spazio locale
# della cella del match)} per l'edificio più vicino al click entro CLICK_RADIUS_PX, in una delle
# celle vive, {} altrimenti. Il chiamante (GameScene) risolve building_id sul vero oggetto Building
# (macro_world.buildings, scansione lineare — stesso costo già accettato altrove nel progetto per
# lo stesso array) e decide cosa farne — questo controller non tocca mai selected_building.
func try_select(event: InputEvent, live_cells: Dictionary, buildings: Array) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return {}

	var best: Dictionary = {}
	var best_distance: float = CLICK_RADIUS_PX
	var half: float = CELL_SIZE / 2.0

	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue
		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		for building in buildings:
			if building.macro_x != coords.x or building.macro_y != coords.y:
				continue
			var screen_pos := Vector2(building.micro_x * CELL_SIZE + half, building.micro_y * CELL_SIZE + half)
			var distance: float = local_mouse.distance_to(screen_pos)
			if distance < best_distance:
				best_distance = distance
				best = {"macro_coords": coords, "building_id": building.id, "distance": distance}

	return best
