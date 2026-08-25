class_name IndividualController
extends RefCounted

# Input handling per l'individuo controllabile — stesso pattern di CellSelectorController
# (RefCounted, converte mouse->coordinate tramite CELL_SIZE, GameScene resta il chiamante che
# lo istanzia e gli inoltra gli eventi da _unhandled_input, questo controller non decide altro
# che selezione/target). Schema confermato con l'utente: click sinistro seleziona/deseleziona,
# click destro (solo con un individuo selezionato) imposta il target di movimento.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/IndividualView
const SELECT_RADIUS_MICROCELLS: float = 2.0 # tolleranza di click attorno alla posizione dell'individuo

var individual: Individual
var reference_node: Node2D # nodo il cui spazio locale coincide con la griglia microcella (renderer)


func setup(p_individual: Individual, p_reference_node: Node2D) -> void:
	individual = p_individual
	reference_node = p_reference_node


func handle_input(event: InputEvent) -> void:
	if individual == null or reference_node == null:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	var mouse_pos_microcells: Vector2 = reference_node.get_local_mouse_position() / CELL_SIZE

	if event.button_index == MOUSE_BUTTON_LEFT:
		_try_select(mouse_pos_microcells)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_try_set_target(mouse_pos_microcells)


func _try_select(mouse_pos_microcells: Vector2) -> void:
	individual.is_selected = individual.position.distance_to(mouse_pos_microcells) <= SELECT_RADIUS_MICROCELLS


func _try_set_target(mouse_pos_microcells: Vector2) -> void:
	if not individual.is_selected:
		return
	individual.set_target(Vector2(
		clamp(mouse_pos_microcells.x, 0.0, float(World.WIDTH - 1)),
		clamp(mouse_pos_microcells.y, 0.0, float(World.HEIGHT - 1))
	))
