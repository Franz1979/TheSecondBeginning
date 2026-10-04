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
# Corpo disteso sulla lastra di un cumulo (2026-10-04, cumulo sepolcrale passo 3a): sta dentro la microcella del cumulo,
# quindi vale solo un click sulla SAGOMA (rettangolo orizzontale attorno al corpo, mezza lunghezza e mezza larghezza in
# microcelle, un po' più larghe del disegno di un adulto); il resto della cella seleziona il cumulo. Un click sulla
# sagoma vince sempre ("on_slab": true nel risultato, GameScene gli dà la precedenza sull'edificio). Lo stesso
# rettangolo, ruotato, è la sagoma del comando diretto col click destro (find_body_at_silhouette).
const SLAB_BODY_HALF_LENGTH: float = 0.26
const SLAB_BODY_HALF_WIDTH: float = 0.14


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
		if BodyBurialService.is_on_slab(candidate):
			var delta := (mouse_pos_microcells - candidate_local_position).abs()
			if delta.x <= SLAB_BODY_HALF_LENGTH and delta.y <= SLAB_BODY_HALF_WIDTH:
				return {"individual_id": candidate["individual_id"], "distance": distance, "on_slab": true}
			continue
		if distance <= best_distance:
			best_distance = distance
			best = {"individual_id": candidate["individual_id"], "distance": distance}
	return best


# Margine attorno alla sagoma per il comando diretto (click destro, 2026-10-04): poco più di mezzo pixel per lato.
const SILHOUETTE_MARGIN_MICROCELLS: float = 0.06


# Comando diretto "Seppellisci" (2026-10-04, click destro): individual_id del corpo la cui SAGOMA (stesso rettangolo
# del corpo sulla lastra, ruotato come è disegnato, più SILHOUETTE_MARGIN_MICROCELLS) contiene il click; -1 se
# nessuno. `rotation_by_id`: individual_id -> rotazione della sua DeadBodyView (assente = 0, dritto come sulla lastra).
# Il più vicino al centro se le sagome si sovrappongono.
func find_body_at_silhouette(
	event: InputEvent, reference_node: Node2D, dead_bodies: Array[Dictionary], center_macro_coords: Vector2i,
	rotation_by_id: Dictionary, required_button: int = MOUSE_BUTTON_RIGHT
) -> int:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != required_button:
		return -1
	if reference_node == null or dead_bodies.is_empty():
		return -1
	var mouse_pos_microcells: Vector2 = reference_node.get_local_mouse_position() / CELL_SIZE
	var best_id := -1
	var best_distance := INF
	for candidate in dead_bodies:
		var home: Vector2i = candidate["home_macro_coords"]
		var candidate_local_position: Vector2 = candidate["position"] + Vector2(home - center_macro_coords) * World.WIDTH
		var body_id := int(candidate["individual_id"])
		var local := (mouse_pos_microcells - candidate_local_position).rotated(-float(rotation_by_id.get(body_id, 0.0)))
		if absf(local.x) > SLAB_BODY_HALF_LENGTH + SILHOUETTE_MARGIN_MICROCELLS:
			continue
		if absf(local.y) > SLAB_BODY_HALF_WIDTH + SILHOUETTE_MARGIN_MICROCELLS:
			continue
		var distance := local.length()
		if distance < best_distance:
			best_distance = distance
			best_id = body_id
	return best_id
