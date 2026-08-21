class_name WorldProcessors
extends RefCounted


func generate_coasts(world: World) -> void:
	for cell in world.cells:

		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			continue

		if not _is_adjacent_to_sea(world, cell):
			continue

		match cell.terrain_base:
			GameTypes.TerrainBase.PLAIN:
				cell.coast_type = GameTypes.CoastType.BEACH

			GameTypes.TerrainBase.HILL:
				cell.coast_type = GameTypes.CoastType.SEMI_CLIFF

			GameTypes.TerrainBase.MOUNTAIN:
				cell.coast_type = GameTypes.CoastType.CLIFF


func _is_adjacent_to_sea(world: World, cell: MacroCellData) -> bool:
	for other in world.cells:

		if other.terrain_base != GameTypes.TerrainBase.WATER:
			continue
		if other.water_type != GameTypes.WaterType.SEA:
			continue

		var dx :int = abs(other.x - cell.x)
		var dy :int= abs(other.y - cell.y)

		if dx + dy == 1:
			return true

	return false
