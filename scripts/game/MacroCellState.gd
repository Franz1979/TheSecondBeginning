class_name MacroCellState

extends RefCounted

var x: int
var y: int

var micro_seed: int

var occupied_cells: Dictionary = {}


func _init(_x: int, _y: int) -> void:
	x = _x
	y = _y

	micro_seed = hash(str(x) + "_" + str(y))


func get_occupied_cells(
	object_type: GameTypes.WorldObjectType
) -> int:
	return int(occupied_cells.get(object_type, 0))


func set_occupied_cells(
	object_type: GameTypes.WorldObjectType,
	amount: int
) -> void:
	occupied_cells[object_type] = max(amount, 0)


func add_occupied_cells(
	object_type: GameTypes.WorldObjectType,
	amount: int
) -> void:
	set_occupied_cells(
		object_type,
		get_occupied_cells(object_type) + amount
	)
