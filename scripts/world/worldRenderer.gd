class_name WorldRenderer
extends Node2D

const CELL_SIZE: int = 10
const COLOR_WATER := Color(0.10, 0.30, 0.90)
const COLOR_PLAIN := Color(0.60, 0.90, 0.60)
const COLOR_HILL := Color(0.82, 0.68, 0.45)
const COLOR_MOUNTAIN := Color(0.45, 0.25, 0.10)
const COLOR_BEACH := Color(0.95, 0.85, 0.55)
const COLOR_CLIFF := Color(0.55, 0.55, 0.55)

var world: World

func setup(_world: World) -> void:
	world = _world
	queue_redraw()

func _draw() -> void:
	if world == null:
		return

	for cell in world.cells:
		var color := get_cell_color(cell)

		var rect := Rect2(
			cell.x * CELL_SIZE,
			cell.y * CELL_SIZE,
			CELL_SIZE,
			CELL_SIZE
		)

		draw_rect(rect, color)


func get_cell_color(cell: MacroCellData) -> Color:
	
	match cell.coast_type:
		GameTypes.CoastType.BEACH:
			return COLOR_BEACH

		GameTypes.CoastType.CLIFF:
			return COLOR_CLIFF
	match cell.terrain_base:
		GameTypes.TerrainBase.WATER:
			return COLOR_WATER

		GameTypes.TerrainBase.PLAIN:
			return COLOR_PLAIN

		GameTypes.TerrainBase.HILL:
			return COLOR_HILL

		GameTypes.TerrainBase.MOUNTAIN:
			return COLOR_MOUNTAIN

		_:
			return Color.MAGENTA
