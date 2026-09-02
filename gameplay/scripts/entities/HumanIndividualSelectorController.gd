class_name HumanIndividualSelectorController
extends RefCounted

# Hit-test per il click su un individuo umano QUALSIASI tra quelli visibili (leader + resto del
# gruppo) — analogo a VegetationSelectorController per la vegetazione, ma più semplice: la mappa
# giocabile è comunque tutta raggiungibile da un solo reference_node (il renderer della cella
# CENTRALE, sempre a offset di container zero — vedi GameScene._reposition_live_cells), a
# differenza della vegetazione, che scansiona ogni LiveMacroCell viva separatamente perché non
# esiste un singolo renderer/spazio locale comune a tutte.
#
# DEBITO CORRETTO (2026-09-02, stesso tipo già risolto in HumanIndividualView/GameScene per Bug 2
# — vedi lì per il commento gemello): l'assunzione precedente qui era "ogni HumanIndividual vive
# SEMPRE nello stesso spazio locale della cella centrale" (vera finché la formazione rigida teneva
# gli extra incollati al leader, rotta da Step 1+2 del piano movimento indipendente — un individuo
# lasciato indietro resta nella sua macrocella fisica, che può smettere di essere il centro).
# candidate.position è locale a candidate.home_macro_coords (vedi HumanIndividual), NON
# necessariamente a center_macro_coords: try_select traduce esplicitamente ogni candidato nello
# spazio locale del centro (stessa formula di offset già usata da GameScene._reposition_live_cells
# per i container, qui in unità microcella invece che pixel) prima di confrontarlo con
# mouse_pos_microcells, che è SEMPRE locale al centro per costruzione (reference_node è il
# renderer della cella centrale).
#
# Sostituisce HumanIndividualController._try_select (rimossa da lì, richiesta utente 2026-09-02):
# la selezione è ora un concern separato dal movimento, che resta esclusivo del bersaglio corrente
# tramite HumanIndividualController/HumanIndividualMovementService — questa classe non tocca mai
# is_selected né alcun altro stato, si limita a rispondere "quale individuo, se non nessuno" al
# chiamante (GameScene), che decide mutua esclusione/popup.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView
const SELECT_RADIUS_MICROCELLS: float = 0.8 # stessa tolleranza già in uso per il leader, invariata


# Ritorna l'HumanIndividual più vicino al click entro SELECT_RADIUS_MICROCELLS, o null se il click
# non è sinistro/non è un click/nessun individuo è abbastanza vicino. Non modifica `individuals` né
# alcuno dei suoi elementi: il chiamante decide cosa fare col risultato. center_macro_coords: le
# coordinate macro ASSOLUTE della cella a cui reference_node appartiene (vedi sopra per il perché
# serve tradurre candidate.position prima del confronto).
func try_select(
	event: InputEvent, reference_node: Node2D, individuals: Array[HumanIndividual], center_macro_coords: Vector2i
) -> HumanIndividual:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return null
	if reference_node == null or individuals.is_empty():
		return null

	var mouse_pos_microcells: Vector2 = reference_node.get_local_mouse_position() / CELL_SIZE

	var best: HumanIndividual = null
	var best_distance: float = SELECT_RADIUS_MICROCELLS
	for candidate in individuals:
		# Stessa formula di offset di GameScene._reposition_live_cells (coords - center) *
		# ampiezza-cella, qui in microcelle (World.WIDTH) invece che in pixel (MACRO_CELL_PIXELS) —
		# per un candidato la cui home_macro_coords coincide col centro (il caso comune, e SEMPRE
		# vero per il bersaglio corrente) l'offset è Vector2.ZERO, nessuna differenza rispetto a
		# prima di questo fix.
		var offset := Vector2(candidate.home_macro_coords - center_macro_coords) * World.WIDTH
		var candidate_local_position := candidate.position + offset
		var distance := candidate_local_position.distance_to(mouse_pos_microcells)
		if distance <= best_distance:
			best_distance = distance
			best = candidate
	return best
