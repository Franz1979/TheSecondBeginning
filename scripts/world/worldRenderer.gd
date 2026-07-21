class_name WorldRenderer
extends Node2D

const CELL_SIZE: int = 10
const COLOR_EVENT_MARKER_FRESH := Color(1.0, 0.0, 0.0, 0.9)        # anno in cui l'evento è avvenuto
const COLOR_EVENT_MARKER_RECOVERING := Color(1.0, 0.55, 0.0, 0.75) # anni successivi, fino a esaurimento del bonus
const COLOR_DROUGHT_MARKER_FRESH := Color(0.55, 0.35, 0.05, 0.9)        # marrone, anno della siccità
const COLOR_DROUGHT_MARKER_RECOVERING := Color(0.85, 0.65, 0.15, 0.75)  # giallo ocra, anni successivi
const COLOR_SEA_FLOOD_MARKER_FRESH := Color(0.05, 0.35, 0.55, 0.9)        # blu intenso, anno dell'inondazione
const COLOR_SEA_FLOOD_MARKER_RECOVERING := Color(0.55, 0.75, 0.85, 0.75)  # azzurro salino, anni successivi
const COLOR_PAINT_FLASH := Color(1.0, 1.0, 1.0, 1.0)
const PAINT_FLASH_DURATION: float = 0.35 # secondi, feedback visivo di una cella appena dipinta nel map editor

const RENDERED_EVENT_TYPES := [
	GameTypes.NaturalEventType.FIRE,
	GameTypes.NaturalEventType.DROUGHT,
	GameTypes.NaturalEventType.SEA_FLOOD,
]

var world: World
var game_data: GameData
var show_resource_overlay: bool = true

var selected_cell: MacroCellData = null
var flashing_cells: Dictionary = {} # Vector2i -> secondi rimanenti

func set_selected_cell(cell: MacroCellData) -> void:
	selected_cell = cell
	queue_redraw()

func flash_cell(x: int, y: int) -> void:
	flashing_cells[Vector2i(x, y)] = PAINT_FLASH_DURATION

# game_data is optional: MapEditorScene has no calendar/simulation, so it calls setup(world)
# and event markers simply never draw there (guarded in _draw_event_markers).
func setup(_world: World, _game_data: GameData = null) -> void:
	world = _world
	game_data = _game_data
	queue_redraw()


func _process(delta: float) -> void:
	if flashing_cells.is_empty():
		return
	var expired: Array = []
	for pos in flashing_cells.keys():
		flashing_cells[pos] -= delta
		if flashing_cells[pos] <= 0.0:
			expired.append(pos)
	for pos in expired:
		flashing_cells.erase(pos)
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

		draw_rect(rect, TerrainColors.GRID, false, 1.0)

		if selected_cell != null and cell.x == selected_cell.x and cell.y == selected_cell.y:
			draw_rect(rect, Color(1, 0, 0, 1), false, 2.0)

		var flash_time: float = flashing_cells.get(Vector2i(cell.x, cell.y), -1.0)
		if flash_time > 0.0:
			var flash_color := COLOR_PAINT_FLASH
			flash_color.a = clamp(flash_time / PAINT_FLASH_DURATION, 0.0, 1.0)
			draw_rect(rect, flash_color, false, 3.0)


const COLOR_STONE_OVERLAY := Color(0.35, 0.35, 0.35, 0.85)
const COLOR_TREE_OVERLAY := Color(0.10, 0.45, 0.15, 0.85)
const COLOR_GRASS_OVERLAY := Color(0.85, 0.75, 0.20, 0.85)
const COLOR_SHRUB_OVERLAY := Color(0.45, 0.60, 0.15, 0.85)

const RESOURCE_ROW_TYPES := [
	GameTypes.WorldObjectType.ROCK,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.GRASS,
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
		var row_y: float = rect.position.y + border + row_height * i
		var row_rect := Rect2(rect.position.x + border, row_y, inner_size, row_height)

		var space: int = state.get_dedicated_space(resource_type)
		if space <= 0:
			continue

		var proportion: float = clamp(float(space) / float(MacroCellState.TOTAL_SPACE), 0.0, 1.0)
		var width: float = max(1.0, row_rect.size.x * proportion)

		draw_rect(Rect2(row_rect.position.x, row_rect.position.y, width, row_rect.size.y), RESOURCE_ROW_COLORS[resource_type])

func _draw_event_markers(cell: MacroCellData, rect: Rect2) -> void:
	if game_data == null:
		return
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return

	var current_absolute_day := game_data.get_absolute_day()
	for event_type in RENDERED_EVENT_TYPES:
		if not state.is_event_bonus_visible(event_type, current_absolute_day):
			continue

		var is_fresh: bool = state.is_event_bonus_fresh(event_type, current_absolute_day)

		match event_type:
			GameTypes.NaturalEventType.DROUGHT:
				var color: Color = COLOR_DROUGHT_MARKER_FRESH if is_fresh else COLOR_DROUGHT_MARKER_RECOVERING
				_draw_circle_mark(rect, color)
			GameTypes.NaturalEventType.SEA_FLOOD:
				var color: Color = COLOR_SEA_FLOOD_MARKER_FRESH if is_fresh else COLOR_SEA_FLOOD_MARKER_RECOVERING
				_draw_square_mark(rect, color)
			_:
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


func _draw_circle_mark(rect: Rect2, color: Color) -> void:
	var center := rect.position + rect.size / 2.0
	var radius: float = rect.size.x * 0.35
	draw_arc(center, radius, 0.0, TAU, 16, color, 2.0)


func _draw_square_mark(rect: Rect2, color: Color) -> void:
	var margin: float = rect.size.x * 0.2
	var inner := Rect2(rect.position + Vector2(margin, margin), rect.size - Vector2(margin, margin) * 2.0)
	draw_rect(inner, color, false, 2.0)


func get_cell_color(cell: MacroCellData) -> Color:
	return TerrainColors.get_cell_color(cell)


func _draw_river_cell(cell: MacroCellData, rect: Rect2) -> void:
	draw_rect(rect, TerrainColors.PLAIN)

	var center_x: float = rect.position.x + rect.size.x / 2.0
	var center_y: float = rect.position.y + rect.size.y / 2.0
	var thickness: float = rect.size.x * 0.45

	match cell.river_shape:
		GameTypes.RiverShape.VERTICAL:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y), TerrainColors.RIVER)

		GameTypes.RiverShape.HORIZONTAL:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_TOP_RIGHT:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_RIGHT_BOTTOM:
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_BOTTOM_LEFT:
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_LEFT_TOP:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			
		GameTypes.RiverShape.FULL:
			draw_rect(rect, TerrainColors.RIVER)

		_:
			draw_rect(rect, TerrainColors.RIVER)
			
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
