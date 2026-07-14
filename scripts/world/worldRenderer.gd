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
const COLOR_EVENT_MARKER_FRESH := Color(1.0, 0.0, 0.0, 0.9)        # anno in cui l'evento è avvenuto
const COLOR_EVENT_MARKER_RECOVERING := Color(1.0, 0.55, 0.0, 0.75) # anni successivi, fino a esaurimento del bonus

const RENDERED_EVENT_TYPES := [
	GameTypes.NaturalEventType.FIRE,
]

var world: World
var show_resource_overlay: bool = true

var selected_cell: MacroCellData = null

func set_selected_cell(cell: MacroCellData) -> void:
	selected_cell = cell
	queue_redraw()

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

		_draw_event_markers(cell, rect)

		draw_rect(rect, COLOR_GRID, false, 1.0)

		if selected_cell != null and cell.x == selected_cell.x and cell.y == selected_cell.y:
			draw_rect(rect, Color(1, 0, 0, 1), false, 2.0)


const COLOR_STONE_OVERLAY := Color(0.35, 0.35, 0.35, 0.85)
const COLOR_TREE_OVERLAY := Color(0.10, 0.45, 0.15, 0.85)
const COLOR_GRASS_OVERLAY := Color(0.85, 0.75, 0.20, 0.85)
const COLOR_SHRUB_OVERLAY := Color(0.45, 0.60, 0.15, 0.85)

const RESOURCE_ROW_TYPES := [
	GameTypes.WorldObjectType.ROCK,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
]

const RESOURCE_ROW_COLORS := {
	GameTypes.WorldObjectType.ROCK: COLOR_STONE_OVERLAY,
	GameTypes.WorldObjectType.TREE: COLOR_TREE_OVERLAY,
	GameTypes.WorldObjectType.GRASS: COLOR_GRASS_OVERLAY,
	GameTypes.WorldObjectType.SHRUB: COLOR_SHRUB_OVERLAY,
}


func _draw_resource_overlay(cell: MacroCellData, rect: Rect2) -> void:
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return

	var border: float = 1.0
	var inner_size: float = rect.size.x - border * 2.0
	if inner_size <= 0:
		return

	var row_height: float = inner_size / RESOURCE_ROW_TYPES.size()

	for i in range(RESOURCE_ROW_TYPES.size()):
		var resource_type: GameTypes.WorldObjectType = RESOURCE_ROW_TYPES[i]
		var space: int = state.get_dedicated_space(resource_type)
		if space <= 0:
			continue

		var total_occupied: int = state.get_total_dedicated_space()
		if total_occupied <= 0:
			continue

		var row_y: float = rect.position.y + border + row_height * i
		var row_rect := Rect2(rect.position.x + border, row_y, inner_size, row_height)

		_draw_proportional_row(row_rect, state, resource_type, total_occupied)


func _draw_proportional_row(
	row_rect: Rect2,
	state: MacroCellState,
	highlight_type: GameTypes.WorldObjectType,
	total_occupied: int
) -> void:
	var remaining_width: float = row_rect.size.x
	var current_x: float = row_rect.position.x

	for i in range(RESOURCE_ROW_TYPES.size()):
		var resource_type: GameTypes.WorldObjectType = RESOURCE_ROW_TYPES[i]
		var space: int = state.get_dedicated_space(resource_type)
		if space <= 0:
			continue

		var is_last: bool = (i == RESOURCE_ROW_TYPES.size() - 1) or _is_last_present(state, i)
		var width: float
		if is_last:
			width = remaining_width
		else:
			var proportion: float = float(space) / float(total_occupied)
			width = floor(row_rect.size.x * proportion)
			remaining_width -= width

		if resource_type == highlight_type:
			draw_rect(Rect2(current_x, row_rect.position.y, width, row_rect.size.y), RESOURCE_ROW_COLORS[resource_type])

		current_x += width


func _is_last_present(state: MacroCellState, from_index: int) -> bool:
	for i in range(from_index + 1, RESOURCE_ROW_TYPES.size()):
		var resource_type: GameTypes.WorldObjectType = RESOURCE_ROW_TYPES[i]
		if state.get_dedicated_space(resource_type) > 0:
			return false
	return true
	
func _draw_event_markers(cell: MacroCellData, rect: Rect2) -> void:
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return

	for event_type in RENDERED_EVENT_TYPES:
		var bonus := state.get_active_event_bonus(event_type)
		if bonus.is_empty():
			continue

		var is_fresh: bool = bonus["years_remaining"] == bonus["total_duration"]
		var color: Color = COLOR_EVENT_MARKER_FRESH if is_fresh else COLOR_EVENT_MARKER_RECOVERING
		_draw_x_mark(rect, color)


func _draw_x_mark(rect: Rect2, color: Color) -> void:
	var margin: float = rect.size.x * 0.15
	var top_left := rect.position + Vector2(margin, margin)
	var top_right := rect.position + Vector2(rect.size.x - margin, margin)
	var bottom_left := rect.position + Vector2(margin, rect.size.y - margin)
	var bottom_right := rect.position + Vector2(rect.size.x - margin, rect.size.y - margin)

	draw_line(top_left, bottom_right, color, 2.0)
	draw_line(top_right, bottom_left, color, 2.0)


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
