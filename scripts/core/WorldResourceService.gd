class_name WorldResourceService
extends RefCounted

const TEST_AREA_SIZE: int = 10
const MIN_STONE_MICROCELLS: int = 50
const MAX_STONE_MICROCELLS: int = 500


func populate_resources(world: World) -> void:
	populate_stone(world)


func populate_stone(world: World) -> void:
	var start_x := (World.WIDTH - TEST_AREA_SIZE) / 2
	var start_y := (World.HEIGHT - TEST_AREA_SIZE) / 2

	for y in range(start_y, start_y + TEST_AREA_SIZE):
		for x in range(start_x, start_x + TEST_AREA_SIZE):
			var cell := world.get_cell_at(x, y)
			var state := world.get_cell_state_at(x, y)
			if cell == null or state == null:
				continue

			var chance := ResourceCalculator.get_presence_chance(GameTypes.WorldObjectType.ROCK)
			if randf() > chance:
				continue

			var max_density := ResourceCalculator.get_max_density(
				GameTypes.WorldObjectType.ROCK,
				cell.terrain_base,
				cell.biome,
				cell.coast_type
			)
			print("DEBUG cella (", x, ",", y, ") terrain=", cell.terrain_base, " biome=", cell.biome, " coast=", cell.coast_type, " max_density=", max_density)
			if max_density <= 0.0:
				continue

			var dedicated_microcells := randi_range(MIN_STONE_MICROCELLS, MAX_STONE_MICROCELLS)
			var quantity := int(round(max_density * dedicated_microcells))

			state.set_resource_quantity(GameTypes.WorldObjectType.ROCK, quantity)
			state.set_dedicated_space(GameTypes.WorldObjectType.ROCK, dedicated_microcells)

	print("Stone popolato nell'area centrale ", start_x, ",", start_y, " - ", start_x + TEST_AREA_SIZE - 1, ",", start_y + TEST_AREA_SIZE - 1)
