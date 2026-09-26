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


func try_select(event: InputEvent, live_cells: Dictionary) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return {}

	var best: Dictionary = {}
	var best_distance: float = SELECT_RADIUS_MICROCELLS * CELL_SIZE
	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		for species in cell.animal_renderers:
			var renderer_node: AnimalGroupRenderer = cell.animal_renderers[species]
			if renderer_node == null or not renderer_node.are_animals_shown():
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
	return best
