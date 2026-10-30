class_name AnimalSelectorController
extends RefCounted

# Click-detection su un singolo individuo animale (2026-09-25, richiesta utente — selezione degli
# animali) — stessa forma di VegetationSelectorController/StoneSelectorController: cerca fra TUTTE
# le celle vive (e tutte le specie di ciascuna, LiveMacroCell.animal_renderers) l'individuo più
# vicino al click entro il raggio di tolleranza, e lo restituisce come Dictionary
# {"macro_coords": Vector2i, "species": String, "individual_id": int, "distance": float (px)} —
# {} se nessuno. La distanza è in pixel locali della cella, come per vegetazione/pietre/edifici,
# così GameScene._unhandled_input la confronta direttamente con gli altri tipi.
#
# Solo gli animali VISIBILI sono selezionabili (AnimalGroupRenderer.is_individual_visible: stesso
# test fog of war del disegno, FogOfWarRenderer.is_animal_visible_at, più il toggle "animali"):
# non si può cliccare un animale che non si vede.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/AnimalGroupRenderer
# Tolleranza generosa, molto più larga del disegno (un coniglio adulto è ~2 px, un cucciolo ~1 px):
# stesso raggio già usato per gli umani (HumanIndividualSelectorController.SELECT_RADIUS_MICROCELLS,
# 0.8 microcelle contro un corpo di ~2.2 px).
const SELECT_RADIUS_MICROCELLS: float = 0.8


# `required_button` (2026-09-26, caccia step 2): sinistro per la selezione, destro per il comando di
# caccia (GameScene._try_assign_hunt_command_on_right_click) — stesso parametro del selettore edifici.
#
# Seconda sorgente (2026-10-28, lupi passo L1b): `wild_visit_views` (id del gruppo -> WildAnimalVisitView), gli animali
# selvatici seguiti per individuo in visita. Un loro hit ha in più "wild_group_id" (id del WildAnimalGroup) e
# "individual_id" è l'id del WildAnimal; vince comunque il più vicino tra tutte le sorgenti.
func try_select(event: InputEvent, live_cells: Dictionary, required_button: int = MOUSE_BUTTON_LEFT,
		wild_visit_views: Dictionary = {}) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
		return {}

	var best: Dictionary = {}
	var best_distance: float = SELECT_RADIUS_MICROCELLS * CELL_SIZE
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		for species in cell.animal_renderers:
			# Non tipizzata: un renderer già liberato (es. subito dopo un caricamento) darebbe errore all'assegnazione.
			var renderer_node = cell.animal_renderers[species]
			if not is_instance_valid(renderer_node) or not renderer_node.are_animals_shown():
				continue
			var local_mouse: Vector2 = renderer_node.get_local_mouse_position()
			for individual in renderer_node.get_individuals():
				if not renderer_node.is_individual_visible(individual):
					continue
				var distance: float = local_mouse.distance_to(individual.position * CELL_SIZE)
				if distance < best_distance:
					best_distance = distance
					best = {
						"macro_coords": coords,
						"species": String(species),
						"individual_id": individual.id,
						"distance": distance,
					}
	for group_id in wild_visit_views:
		var view = wild_visit_views[group_id]
		if not is_instance_valid(view) or view.visit == null:
			continue
		var view_mouse: Vector2 = view.get_local_mouse_position()
		for entry in view.get_selectable_animals():
			var distance: float = view_mouse.distance_to(entry["position"] * CELL_SIZE)
			if distance < best_distance:
				best_distance = distance
				best = {
					"macro_coords": view.visit.macro_coords,
					"species": view.visit.species,
					"individual_id": int(entry["id"]),
					"wild_group_id": int(group_id),
					"distance": distance,
				}
	return best
