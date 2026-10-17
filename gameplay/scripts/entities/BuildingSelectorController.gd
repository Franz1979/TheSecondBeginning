class_name BuildingSelectorController
extends RefCounted

# Hit-test per il click su un edificio esistente — Step 4 del piano "centra generalizzato +
# selezione edifici" (richiesta utente, 2026-09-04), analogo a VegetationSelectorController ma più
# semplice: un edificio ha un'unica posizione precisa per microcella (ancoraggio al CENTRO, stesso
# esatto punto disegnato da MicroCellRenderer._draw_buildings — "ground" lì), nessun lotto/densità/
# stato bloccato, e un id stabile (Building.id, mai riderivato — a differenza di Vector3i per la
# vegetazione, che invece si rigenera ad ogni refresh).
#
# `required_button` (2026-09-09, richiesta utente — comando "vai e scarica" su un edificio di
# stoccaggio) — DEFAULT LEFT invariato (selezione/BuildingInfoPanel, comportamento esistente),
# stesso pattern già in uso da StoneSelectorController/StickLotSelectorController: il chiamante per
# il comando destro (GameScene._try_assign_unload_command_on_right_click) lo passa esplicitamente
# a MOUSE_BUTTON_RIGHT. Prima di questo passo il filtro era hardcoded a MOUSE_BUTTON_LEFT — un
# click destro su un edificio non produceva mai un hit qui, cadeva sempre nel movimento semplice.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView
# Stesso raggio del recinto disegnato (MicroCellRenderer.BUILDING_FENCE_RADIUS) — cliccare dentro
# il recinto seleziona l'edificio, coerente col suo vero ingombro visivo invece di una tolleranza
# arbitraria scollegata da cosa si vede a schermo.
const CLICK_RADIUS_PX: float = MicroCellRenderer.BUILDING_FENCE_RADIUS
# Distanza di un click dentro un edificio grande (vedi try_select): appena sotto CLICK_RADIUS_PX.
const LARGE_BUILDING_HIT_DISTANCE_PX: float = CLICK_RADIUS_PX * 0.99


# Ritorna {"macro_coords": Vector2i, "building_id": int, "distance": float (px, spazio locale
# della cella del match)} per l'edificio più vicino al click entro CLICK_RADIUS_PX, in una delle
# celle vive, {} altrimenti. Il chiamante (GameScene) risolve building_id sul vero oggetto Building
# (macro_world.buildings, scansione lineare — stesso costo già accettato altrove nel progetto per
# lo stesso array) e decide cosa farne — questo controller non tocca mai selected_building.
func try_select(event: InputEvent, live_cells: Dictionary, buildings: Array, required_button: int = MOUSE_BUTTON_LEFT) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
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
			# Edifici grandi (2026-10-17): si selezionano cliccando dentro il rettangolo, con una distanza "debole" appena sotto
			# CLICK_RADIUS_PX invece di 0 — un individuo, un mucchio o un altro oggetto sotto il click (entro il raggio) vince
			# sempre, altrimenti dentro lo spiazzo non si selezionerebbe nient'altro. 1x1: dal centro, come prima.
			if building.rules != null and BuildingFootprint.is_large(building.rules):
				var rect := Rect2(Vector2(building.micro_x, building.micro_y) * CELL_SIZE, Vector2(BuildingFootprint.size_of(building)) * CELL_SIZE)
				distance = LARGE_BUILDING_HIT_DISTANCE_PX if rect.has_point(local_mouse) else INF
			if distance < best_distance:
				best_distance = distance
				best = {"macro_coords": coords, "building_id": building.id, "distance": distance}

	return best
