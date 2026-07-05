class_name WorldRenderer
extends Node2D

const CELL_SIZE: int = 10
const COLOR_SEA := Color(0.10, 0.30, 0.90)
const COLOR_PLAIN := Color(0.60, 0.90, 0.60)
const COLOR_HILL := Color(0.82, 0.68, 0.45)
const COLOR_MOUNTAIN := Color(0.45, 0.25, 0.10)
const COLOR_BEACH := Color(0.95, 0.85, 0.55)
const COLOR_SEMI_CLIFF := Color(0.72, 0.72, 0.72)
const COLOR_CLIFF := Color(0.55, 0.55, 0.55)
const COLOR_LAKE := Color(0.15, 0.50, 0.95)
const COLOR_RIVER := Color(0.20, 0.60, 1.00)
const COLOR_GRID := Color(0, 0, 0, 0.15)

var world: World
var show_resource_overlay: bool = true


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
		if cell.water_type == GameTypes.WaterType.RIVER:
			_draw_river_cell(cell, rect)
		else:
			draw_rect(rect, color)

		if show_resource_overlay:
			_draw_resource_overlay(cell, rect)

		draw_rect(rect, COLOR_GRID, false, 1.0)


func _draw_resource_overlay(cell: MacroCellData, rect: Rect2) -> void:
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return
	var stone_quantity: int = state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
	if stone_quantity <= 0:
		return
	var alpha: float = clamp(float(stone_quantity) / 5000.0, 0.0, 0.85)
	draw_rect(rect, Color(0.3, 0.3, 0.3, alpha))


func get_cell_color(cell: MacroCellData) -> Color:
	match cell.water_type:
		GameTypes.WaterType.SEA:
			return COLOR_SEA
		GameTypes.WaterType.LAKE:
			return COLOR_LAKE
		GameTypes.WaterType.RIVER:
			return COLOR_RIVER

	match cell.terrain_base:
		GameTypes.TerrainBase.WATER:
			return COLOR_SEA
		GameTypes.TerrainBase.PLAIN:
			match cell.coast_type:
				GameTypes.CoastType.BEACH:
					return COLOR_BEACH
				_:
					return COLOR_PLAIN
		GameTypes.TerrainBase.HILL:
			match cell.coast_type:
				GameTypes.CoastType.SEMI_CLIFF:
					return COLOR_SEMI_CLIFF
				_:
					return COLOR_HILL
		GameTypes.TerrainBase.MOUNTAIN:
			match cell.coast_type:
				GameTypes.CoastType.CLIFF:
					return COLOR_CLIFF
				_:
					return COLOR_MOUNTAIN
		_:
			return Color.MAGENTA
func _draw_river_cell(cell: MacroCellData, rect: Rect2) -> void:
	draw_rect(rect, COLOR_PLAIN)

	var center_x: float = rect.position.x + rect.size.x / 2.0
	var center_y: float = rect.position.y + rect.size.y / 2.0
	var thickness: float = rect.size.x * 0.45

	match cell.river_shape:
		GameTypes.RiverShape.VERTICAL:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y), COLOR_RIVER)

		GameTypes.RiverShape.HORIZONTAL:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x, thickness), COLOR_RIVER)

		GameTypes.RiverShape.CORNER_TOP_RIGHT:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), COLOR_RIVER)
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), COLOR_RIVER)

		GameTypes.RiverShape.CORNER_RIGHT_BOTTOM:
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), COLOR_RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), COLOR_RIVER)

		GameTypes.RiverShape.CORNER_BOTTOM_LEFT:
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), COLOR_RIVER)
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), COLOR_RIVER)

		GameTypes.RiverShape.CORNER_LEFT_TOP:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), COLOR_RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), COLOR_RIVER)
			
		GameTypes.RiverShape.FULL:
			draw_rect(rect, COLOR_RIVER)

		_:
			draw_rect(rect, COLOR_RIVER)
			
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos: Vector2 = get_local_mouse_position()

			var cell_x: int = int(mouse_pos.x / CELL_SIZE)
			var cell_y: int = int(mouse_pos.y / CELL_SIZE)

			var cell := _get_cell_at(cell_x, cell_y)

			#if cell != null:
				#print(
				#	"Cella x=", cell.x,
				#	" y=", cell.y,
				#	" terrain_base=", cell.terrain_base,
				#	" water_type=", cell.water_type,
				#	" river_shape=", cell.river_shape,
				#	" coast_type=", cell.coast_type,
				#	" biome=", cell.biome
				#)


func _get_cell_at(x: int, y: int) -> MacroCellData:
	if world == null:
		return null

	for cell in world.cells:
		if cell.x == x and cell.y == y:
			return cell

	return null
