class_name PresetMapGenerator
extends RefCounted

func generate_island(world: World) -> void:
	_generate_island_shape(world)
	_generate_island_mountains(world)
	_generate_island_river(world)
	_generate_river_shapes(world)
	_update_island_coasts(world)
	
func _generate_island_shape(world: World) -> void:
	var center_x := World.WIDTH / 2
	var center_y := World.HEIGHT / 2

	for cell in world.cells:

		var dx := cell.x - center_x
		var dy := cell.y - center_y

		var distance := sqrt(dx * dx + dy * dy)

		var radius := 35.0

		radius += sin(cell.x * 0.15) * 4
		radius += cos(cell.y * 0.12) * 4

		var bump_x := center_x - 18
		var bump_y := center_y - 18
		var bump_radius := 20.0

		var bump_dx := cell.x - bump_x
		var bump_dy := cell.y - bump_y
		var bump_distance := sqrt(bump_dx * bump_dx + bump_dy * bump_dy)

		if bump_distance <= bump_radius:
			radius += 12.0 * (1.0 - bump_distance / bump_radius)

		if distance <= radius - 1.5:
			cell.terrain_base = GameTypes.TerrainBase.PLAIN
			cell.water_type = GameTypes.WaterType.NONE
			cell.coast_type = GameTypes.CoastType.NONE

		elif distance <= radius:
			cell.terrain_base = GameTypes.TerrainBase.PLAIN
			cell.water_type = GameTypes.WaterType.NONE
			cell.coast_type = GameTypes.CoastType.BEACH

		else:
			cell.terrain_base = GameTypes.TerrainBase.WATER
			cell.water_type = GameTypes.WaterType.SEA
			cell.coast_type = GameTypes.CoastType.NONE
			
func _generate_island_mountains(world: World) -> void:
	var mountain_x := World.WIDTH / 2 - 22
	var mountain_y := World.HEIGHT / 2 - 18

	for cell in world.cells:
		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			continue

		if cell.coast_type == GameTypes.CoastType.BEACH:
			continue

		var dx := cell.x - mountain_x
		var dy := cell.y - mountain_y
		var distance := sqrt(dx * dx + dy * dy)

		if distance <= 8:
			cell.terrain_base = GameTypes.TerrainBase.MOUNTAIN

		elif distance <= 15:
			cell.terrain_base = GameTypes.TerrainBase.HILL
			
		var mountain2_x := World.WIDTH / 2 - 14
		var mountain2_y := World.HEIGHT / 2 - 12
		
		var dx2 := cell.x - mountain2_x
		var dy2 := cell.y - mountain2_y
		var distance2 := sqrt(dx2 * dx2 + dy2 * dy2)
		
		if distance <= 8 or distance2 <= 5:
			cell.terrain_base = GameTypes.TerrainBase.MOUNTAIN

		elif distance <= 15 or distance2 <= 10:
			cell.terrain_base = GameTypes.TerrainBase.HILL
			
func _update_island_coasts(world: World) -> void:
	for cell in world.cells:
		if cell.terrain_base == GameTypes.TerrainBase.MOUNTAIN:
			if _is_near_sea(world, cell):
				cell.coast_type = GameTypes.CoastType.CLIFF

		elif cell.terrain_base == GameTypes.TerrainBase.HILL:
			if _is_near_sea(world, cell):
				cell.coast_type = GameTypes.CoastType.SEMI_CLIFF

func _is_near_sea(world: World, cell: MacroCellData) -> bool:
	for other in world.cells:
		if other.terrain_base != GameTypes.TerrainBase.WATER:
			continue
		if other.water_type != GameTypes.WaterType.SEA:
			continue

		var dx: int = abs(other.x - cell.x)
		var dy: int = abs(other.y - cell.y)

		if dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0):
			return true

	return false


func _generate_island_river(world: World) -> void:
	var current_x: int = World.WIDTH / 2 - 10
	var current_y: int = World.HEIGHT / 2 - 8

	var max_steps: int = 80

	for i in range(max_steps):

		var current_cell := _get_cell_at(world, current_x, current_y)

		if current_cell == null:
			return

		if current_cell.terrain_base == GameTypes.TerrainBase.WATER:
			return

		current_cell.water_type = GameTypes.WaterType.RIVER

		if current_cell.terrain_base != GameTypes.TerrainBase.MOUNTAIN:
			current_cell.terrain_base = GameTypes.TerrainBase.PLAIN

		var next_x: int = current_x
		var next_y: int = current_y + 1

		if i % 4 == 0:
			next_x += 1
		elif i % 7 == 0:
			next_x -= 1

		var previous_x: int = current_x
		var previous_y: int = current_y

		current_x = next_x
		current_y = next_y

		# Se il fiume si è mosso in diagonale,
		# riempi la cella intermedia per evitare buchi.
		if current_x != previous_x and current_y != previous_y:

			var bridge_cell := _get_cell_at(
				world,
				current_x,
				previous_y
			)

			if bridge_cell != null:
				bridge_cell.water_type = GameTypes.WaterType.RIVER

				if bridge_cell.terrain_base != GameTypes.TerrainBase.MOUNTAIN:
					bridge_cell.terrain_base = GameTypes.TerrainBase.PLAIN
					
func _get_cell_at(world: World, x: int, y: int) -> MacroCellData:
	for cell in world.cells:
		if cell.x == x and cell.y == y:
			return cell

	return null


func _generate_river_shapes(world: World) -> void:
	for cell in world.cells:
		if cell.water_type != GameTypes.WaterType.RIVER:
			continue

		var has_top: bool = _is_river_at(world, cell.x, cell.y - 1)
		var has_right: bool = _is_river_at(world, cell.x + 1, cell.y)
		var has_bottom: bool = _is_river_at(world, cell.x, cell.y + 1)
		var has_left: bool = _is_river_at(world, cell.x - 1, cell.y)

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
			
			
func _is_river_at(world: World, x: int, y: int) -> bool:
	var cell := _get_cell_at(world, x, y)

	if cell == null:
		return false

	return cell.water_type == GameTypes.WaterType.RIVER
