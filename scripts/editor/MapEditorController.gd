class_name MapEditorController
extends CellSelectorController

enum TerrainBrush {
	NONE,
	WATER,
	PLAIN,
	HILL,
	MOUNTAIN
}

var current_terrain_brush: TerrainBrush = TerrainBrush.NONE
var current_water_type: GameTypes.WaterType = GameTypes.WaterType.SEA
var current_biome: GameTypes.Biome = GameTypes.Biome.NONE
var is_painting: bool = false
var last_painted_x: int = -1
var last_painted_y: int = -1


func set_terrain_brush(brush: TerrainBrush) -> void:
	current_terrain_brush = brush
	print("Terrain brush selected: ", brush)

func set_water_type(water_type: GameTypes.WaterType) -> void:
	current_water_type = water_type
	print("Water type selected: ", water_type)

func set_biome(biome: GameTypes.Biome) -> void:
	current_biome = biome
	print("Biome selected: ", biome)

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if event.pressed:
				_paint_at_mouse_position()

	if event is InputEventMouseMotion:
		if is_painting:
			_paint_at_mouse_position()

func _apply_terrain_brush_to_cell(cell: MacroCellData) -> void:
	match current_terrain_brush:
		TerrainBrush.NONE:
			return
		TerrainBrush.WATER:
			cell.terrain_base = GameTypes.TerrainBase.WATER
			cell.water_type = current_water_type
			cell.coast_type = GameTypes.CoastType.NONE
			cell.biome = GameTypes.Biome.NONE
			if current_water_type == GameTypes.WaterType.RIVER:
				cell.terrain_base = GameTypes.TerrainBase.PLAIN
			else:
				cell.river_shape = GameTypes.RiverShape.NONE
		TerrainBrush.PLAIN:
			cell.terrain_base = GameTypes.TerrainBase.PLAIN
			cell.water_type = GameTypes.WaterType.NONE
			cell.coast_type = GameTypes.CoastType.NONE
			cell.river_shape = GameTypes.RiverShape.NONE
			cell.biome = current_biome
		TerrainBrush.HILL:
			cell.terrain_base = GameTypes.TerrainBase.HILL
			cell.water_type = GameTypes.WaterType.NONE
			cell.coast_type = GameTypes.CoastType.NONE
			cell.river_shape = GameTypes.RiverShape.NONE
			cell.biome = current_biome
		TerrainBrush.MOUNTAIN:
			cell.terrain_base = GameTypes.TerrainBase.MOUNTAIN
			cell.water_type = GameTypes.WaterType.NONE
			cell.coast_type = GameTypes.CoastType.NONE
			cell.river_shape = GameTypes.RiverShape.NONE
			cell.biome = current_biome


func _paint_at_mouse_position() -> void:
	var cell := _get_cell_under_mouse()

	if cell == null:
		return
	if current_terrain_brush == TerrainBrush.NONE:
		var state := world.get_cell_state_at(cell.x, cell.y)
		cell_selected.emit(cell, state)
		return

	var cell_x := cell.x
	var cell_y := cell.y

	if cell_x == last_painted_x and cell_y == last_painted_y:
		return

	last_painted_x = cell_x
	last_painted_y = cell_y

	_apply_terrain_brush_to_cell(cell)
	
	_update_river_shape_around(cell.x, cell.y)
	_update_coast_type_around(cell.x, cell.y)
	renderer.queue_redraw()

func _update_river_shape_around(cell_x: int, cell_y: int) -> void:
	for y in range(cell_y - 1, cell_y + 2):
		for x in range(cell_x - 1, cell_x + 2):
			_update_single_river_shape(x, y)

func _update_coast_type_around(cell_x: int, cell_y: int) -> void:
	for y in range(cell_y - 1, cell_y + 2):
		for x in range(cell_x - 1, cell_x + 2):
			_update_single_coast_type(x, y)

func _update_single_coast_type(x: int, y: int) -> void:
	var cell: MacroCellData = world.get_cell_at(x, y)
	if cell == null:
		return

	if cell.terrain_base == GameTypes.TerrainBase.WATER:
		cell.coast_type = GameTypes.CoastType.NONE
		return

	if _is_near_sea(x, y):
		match cell.terrain_base:
			GameTypes.TerrainBase.MOUNTAIN:
				cell.coast_type = GameTypes.CoastType.CLIFF
			GameTypes.TerrainBase.HILL:
				cell.coast_type = GameTypes.CoastType.SEMI_CLIFF
			GameTypes.TerrainBase.PLAIN:
				cell.coast_type = GameTypes.CoastType.BEACH
			_:
				cell.coast_type = GameTypes.CoastType.NONE
	else:
		cell.coast_type = GameTypes.CoastType.NONE


func _is_near_sea(cell_x: int, cell_y: int) -> bool:
	for y in range(cell_y - 1, cell_y + 2):
		for x in range(cell_x - 1, cell_x + 2):
			if x == cell_x and y == cell_y:
				continue
			var other: MacroCellData = world.get_cell_at(x, y)
			if other == null:
				continue
			if other.terrain_base == GameTypes.TerrainBase.WATER and other.water_type == GameTypes.WaterType.SEA:
				return true
	return false

func _update_single_river_shape(x: int, y: int) -> void:
	var cell: MacroCellData = world.get_cell_at(x, y)

	if cell == null:
		return

	if cell.water_type != GameTypes.WaterType.RIVER:
		cell.river_shape = GameTypes.RiverShape.NONE
		return

	var has_top: bool = _is_river_at(x, y - 1)
	var has_right: bool = _is_river_at(x + 1, y)
	var has_bottom: bool = _is_river_at(x, y + 1)
	var has_left: bool = _is_river_at(x - 1, y)

	if has_top and has_bottom:
		cell.river_shape = GameTypes.RiverShape.VERTICAL
	elif has_left and has_right:
		cell.river_shape = GameTypes.RiverShape.HORIZONTAL
	elif has_top and has_right:
		cell.river_shape = GameTypes.RiverShape.CORNER_TOP_RIGHT
	elif has_right and has_bottom:
		cell.river_shape = GameTypes.RiverShape.CORNER_RIGHT_BOTTOM
	elif has_bottom and has_left:
		cell.river_shape = GameTypes.RiverShape.CORNER_BOTTOM_LEFT
	elif has_left and has_top:
		cell.river_shape = GameTypes.RiverShape.CORNER_LEFT_TOP
	elif has_top or has_bottom:
		cell.river_shape = GameTypes.RiverShape.VERTICAL
	elif has_left or has_right:
		cell.river_shape = GameTypes.RiverShape.HORIZONTAL
	else:
		cell.river_shape = GameTypes.RiverShape.VERTICAL

func _is_river_at(x: int, y: int) -> bool:
	var cell: MacroCellData = world.get_cell_at(x, y)

	if cell == null:
		return false

	return cell.water_type == GameTypes.WaterType.RIVER
