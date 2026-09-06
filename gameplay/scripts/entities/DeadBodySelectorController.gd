class_name DeadBodySelectorController
extends RefCounted

# Hit-test per il click su un corpo morto (Step 6 del sistema oggetti-scaduti, 2026-09-05) —
# stesso stile/principio di HumanIndividualSelectorController: RefCounted, non un nodo; un solo
# reference_node (il renderer della cella CENTRALE), stessa formula di offset per candidati la cui
# home_macro_coords non coincide col centro, STESSA unità di misura (microcelle) — il risultato è
# quindi DIRETTAMENTE confrontabile con quello del selettore individui vivi, nessuna conversione
# di unità necessaria quando GameScene deve decidere chi vince tra i due (vedi _unhandled_input).
#
# I candidati sono Dictionary (game_data.expired_objects filtrati per object_type == DEAD_BODY),
# non oggetti con identità stabile come HumanIndividual — individual_id (unico per corpo: un
# individuo muore una volta sola) fa da id stabile per il chiamante, che può così riferirsi al
# corpo selezionato senza tenere un riferimento diretto al Dictionary (che la pulizia annuale,
# Step 4, può rimuovere da game_data.expired_objects in qualunque momento).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView
# Stessa tolleranza di HumanIndividualSelectorController.SELECT_RADIUS_MICROCELLS — un corpo
# occupa uno spazio comparabile a un individuo vivo, nessuna ragione per una soglia diversa.
const SELECT_RADIUS_MICROCELLS: float = 0.8


# Ritorna {"individual_id": int, "distance": float} per il corpo più vicino al click entro
# SELECT_RADIUS_MICROCELLS, {} altrimenti (click destro, evento non di click, o nessun corpo
# abbastanza vicino). Il chiamante (GameScene) risolve individual_id sul vero record in
# game_data.expired_objects (scansione lineare — stesso costo già accettato altrove nel progetto
# per array analoghi, es. GameScene._find_building_by_id) — questo controller non tocca mai
# selected_dead_body_individual_id.
func try_select(
	event: InputEvent, reference_node: Node2D, dead_bodies: Array[Dictionary], center_macro_coords: Vector2i
) -> Dictionary:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return {}
	if reference_node == null or dead_bodies.is_empty():
		return {}

	var mouse_pos_microcells: Vector2 = reference_node.get_local_mouse_position() / CELL_SIZE

	var best: Dictionary = {}
	var best_distance: float = SELECT_RADIUS_MICROCELLS
	for candidate in dead_bodies:
		# Stessa formula di offset di HumanIndividualSelectorController.try_select — un corpo
		# comparso in una macrocella diversa dal centro corrente va tradotto nello spazio locale
		# del centro prima del confronto (candidate["position"] è locale alla SUA home_macro_coords).
		var home: Vector2i = candidate["home_macro_coords"]
		var offset := Vector2(home - center_macro_coords) * World.WIDTH
		var candidate_local_position: Vector2 = candidate["position"] + offset
		var distance := candidate_local_position.distance_to(mouse_pos_microcells)
		if distance <= best_distance:
			best_distance = distance
			best = {"individual_id": candidate["individual_id"], "distance": distance}
	return best
