class_name Individual
extends RefCounted

# Stato puro del singolo individuo controllabile in GameScene — nessuna grafica, nessun
# bisogno/statistica/inventario/IA (scope futuro, deliberatamente escluso qui). Stesso principio
# di PopulationGroup: RefCounted, non Node — la resa visiva vive solo in IndividualView, che
# legge questo stato ma non viceversa.
#
# position/target_position sono in coordinate MICROCELLA continue (float), locali alla
# macrocella corrente caricata da GameScene — stesso spazio di MicroCellRenderer/
# AnimalGroupRenderer (CELL_SIZE = 10px per microcella), NON le coordinate macro di
# GameData.player_macro_cell_x/y (quelle restano di competenza di GameScene).

var position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
# Waypoint intermedi per un futuro pathfinding — vuoto oggi: IndividualMovementService muove
# sempre in linea retta verso target_position finché questo campo non verrà popolato altrove.
var path: Array[Vector2] = []
var move_speed: float = 4.5 # microcelle/secondo — in linea con AnimalRules.hop_speed (boar/mouflon)
var is_selected: bool = false


func set_target(target: Vector2) -> void:
	target_position = target
	is_moving = true
	path.clear()


func stop() -> void:
	is_moving = false
	path.clear()
