class_name MapGenerator

func generate(world: World) -> void:
	_set_all_plain(world)
	_generate_lakes(world)


func _set_all_plain(world: World) -> void:
	for cell in world.cells:
		cell.terrain_base = GameTypes.TerrainBase.PLAIN
		cell.water_type = GameTypes.WaterType.NONE
		cell.coast_type = GameTypes.CoastType.NONE
		cell.cover = GameTypes.Cover.GRASSLAND


func _generate_lakes(world: World) -> void:
	var lake_count := randi_range(2, 4)

	for i in range(lake_count):
		_generate_lake(world)


func _generate_lake(world: World) -> void:
	var center_x := randi_range(6, world.WIDTH - 6)
	var center_y := randi_range(6, world.HEIGHT - 6)
	var radius := randi_range(1, 5)

	for cell in world.cells:
		var distance := Vector2(cell.x, cell.y).distance_to(Vector2(center_x, center_y))

		if distance <= radius:
			cell.terrain_base = GameTypes.TerrainBase.WATER
			cell.water_type = GameTypes.WaterType.LAKE
			cell.cover = GameTypes.Cover.NONE
