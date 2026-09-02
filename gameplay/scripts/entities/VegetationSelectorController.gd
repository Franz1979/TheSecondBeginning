class_name VegetationSelectorController
extends RefCounted

# Hit-test per il click su un singolo individuo di vegetazione (TREE/SHRUB) — analogo a
# HumanIndividualController per il player, ma multi-cella: itera OGNI LiveMacroCell viva (centro +
# vicini attivi dello streaming, vedi GameScene.live_cells) invece di un solo reference_node,
# perché la vegetazione cliccabile non è mai limitata alla sola cella centrale.
#
# Solo click SINISTRO: il destro resta esclusivamente il movimento del player (vedi
# HumanIndividualController._try_set_target) — un click destro non viene mai considerato un tentativo
# di selezione vegetale. Priorità concordata esplicitamente con l'utente: la vegetazione vince
# entro il proprio raggio di hit-test (più piccolo/preciso del raggio di selezione del player) —
# ma SOLO se è davvero il bersaglio più vicino al click: la distanza del candidato migliore viene
# restituita nel risultato (vedi "distance") apposta perché GameScene possa confrontarla con la
# distanza del player e lasciare vincere quest'ultimo se è oggettivamente più vicino, anche se
# entrambi ricadono nel raggio di click della vegetazione (caso concreto: player fermo proprio
# accanto a una pianta). Se non trova nulla, GameScene passa la mano a individual_controller
# esattamente come prima dell'introduzione di questo controller — nessuna modifica al flusso
# player quando non si clicca vicino a una pianta.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView
const CLICK_RADIUS_PX: float = 4.5 # tolleranza attorno al punto-schermo risolto di un individuo
const CANDIDATE_TYPES: Array[GameTypes.WorldObjectType] = [
	GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB,
]


# Ritorna {"macro_coords": Vector2i, "object_type": GameTypes.WorldObjectType, "individual_key":
# Vector3i, "distance": float (px, spazio locale della cella del match)} se il click ha colpito un
# individuo in una delle celle vive, {} altrimenti (click destro, evento non di click, o nessun
# hit). Il chiamante (GameScene) decide cosa fare col risultato — questo controller non tocca mai
# selected_vegetation/individual_controller.
func try_select(event: InputEvent, live_cells: Dictionary) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return {}

	var best: Dictionary = {}
	var best_distance: float = CLICK_RADIUS_PX

	for coords in live_cells:
		var cell: LiveMacroCell = live_cells[coords]
		if cell.renderer == null:
			continue

		# Spazio locale DI QUESTA cella (il container ha il proprio offset nello streaming multi-
		# cella, vedi GameScene._reposition_live_cells) — stesso principio già usato da
		# HumanIndividualController.handle_input con reference_node.get_local_mouse_position().
		var local_mouse: Vector2 = cell.renderer.get_local_mouse_position()
		var click_lot := Vector2i(int(floor(local_mouse.x / CELL_SIZE)), int(floor(local_mouse.y / CELL_SIZE)))

		for object_type in CANDIDATE_TYPES:
			# Candidati vivi (vegetation_positions, Array[Vector3i]) E slot bloccati (cut_positions/
			# dead_positions, Array[Dictionary] — vedi IndividualVegetationService.get_cut_positions/
			# get_dead_positions) insieme: un ceppo/rovo cliccabile è altrettanto un "individuo" ai
			# fini della selezione, solo con uno stato diverso (GameScene lo rideriva da sé via
			# has_individual/has_blocked_marker, non serve propagarlo qui).
			var candidate_keys: Array = cell.renderer.vegetation_positions.get(object_type, []).duplicate()
			for entry in cell.renderer.cut_positions.get(object_type, []):
				candidate_keys.append(entry["key"])
			for entry in cell.renderer.dead_positions.get(object_type, []):
				candidate_keys.append(entry["key"])

			for individual_key in candidate_keys:
				# Solo il lotto cliccato + gli 8 adiacenti: canopy/offset possono sconfinare
				# visivamente nel lotto vicino (jitter/disk-offset + raggio chioma), un individuo
				# ancorato altrove non può comunque risultare il più vicino entro CLICK_RADIUS_PX.
				var lot_pos := Vector2i(individual_key.x, individual_key.y)
				if abs(lot_pos.x - click_lot.x) > 1 or abs(lot_pos.y - click_lot.y) > 1:
					continue

				var screen_pos: Vector2 = cell.renderer.get_individual_screen_position(object_type, individual_key)
				var distance: float = local_mouse.distance_to(screen_pos)
				if distance < best_distance:
					best_distance = distance
					best = {"macro_coords": coords, "object_type": object_type, "individual_key": individual_key, "distance": distance}

	return best
