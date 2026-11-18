class_name DirtGroundSnapshot3D
extends RefCounted

# Le mattonelle dell'edificio "Terra battuta" finite di una cella, come le disegna il 2D: microcella e lati che
# confinano con un altro fondo o edificio ("dirt_neighbors", bit 1 << lato, ordine N, E, S, O). Array paralleli.

var positions: Array[Vector2i] = []
var neighbor_masks := PackedByteArray()


func size() -> int:
	return positions.size()
