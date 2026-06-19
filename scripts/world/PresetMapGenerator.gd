class_name PresetMapGenerator
extends RefCounted


func generate_island(world: World) -> void:
	var center_x := World.WIDTH / 2
	var center_y := World.HEIGHT / 2

	for cell in world.cells:

		var dx := cell.x - center_x
		var dy := cell.y - center_y

		var distance := sqrt(dx * dx + dy * dy)

		var radius := 35.0

		radius += sin(cell.x * 0.15) * 4
		radius += cos(cell.y * 0.12) * 4

		if distance <= radius -1.5 :
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
			
