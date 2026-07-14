class_name NaturalEventInstance
extends RefCounted

var event_type: GameTypes.NaturalEventType
var year: int
var center_x: int
var center_y: int
var intensity_index: int
var radius: int
var affected_cells: Array[Vector2i] = []

func _init(
	_event_type: GameTypes.NaturalEventType,
	_year: int,
	_center_x: int,
	_center_y: int,
	_intensity_index: int,
	_radius: int
) -> void:
	event_type = _event_type
	year = _year
	center_x = _center_x
	center_y = _center_y
	intensity_index = _intensity_index
	radius = _radius
