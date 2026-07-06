class_name InitialResourceSetupService
extends RefCounted

const TEST_AREA_SIZE: int = 10
const MIN_STONE_MICROCELLS: int = 50
const MAX_STONE_MICROCELLS: int = 500
const MIN_TREE_MICROCELLS: int = 50
const MAX_TREE_MICROCELLS: int = 500
const RIVER_SPACE: int = 3000


func populate_resources(world: World) -> void:
	reserve_river_space(world)
	var area := _get_population_area(world)
	populate_stone(world, area)
	populate_trees(world, area)


func reserve_river_space(world: World) -> void:
	var river_count := 0
	for cell in world.cells:
		if cell.water_type == GameTypes.WaterType.RIVER:
			river_count += 1
			var state := world.get_cell_state_at(cell.x, cell.y)
			if state != null:
				state.set_river_space(RIVER_SPACE)

func _get_population_area(world: World) -> Rect2i:
	var start_x := (World.WIDTH - TEST_AREA_SIZE) / 2
	var start_y := (World.HEIGHT - TEST_AREA_SIZE) / 2
	return Rect2i(start_x, start_y, TEST_AREA_SIZE, TEST_AREA_SIZE)


func populate_stone(world: World, area: Rect2i) -> void:
	for y in range(area.position.y, area.position.y + area.size.y):
		for x in range(area.position.x, area.position.x + area.size.x):
			var cell := world.get_cell_at(x, y)
			var state := world.get_cell_state_at(x, y)
			if cell == null or state == null:
				continue

			var chance := ResourceCalculator.get_presence_chance(
				GameTypes.WorldObjectType.ROCK,
				cell.terrain_base,
				cell.biome,
				cell.coast_type
			)
			if randf() > chance:
				continue

			var max_density := ResourceCalculator.get_max_density(
				GameTypes.WorldObjectType.ROCK,
				cell.terrain_base,
				cell.biome,
				cell.coast_type
			)
			if max_density <= 0.0:
				continue

			var available_space: int = state.get_empty_space()
			if available_space <= 0:
				continue

			var max_possible: int = min(MAX_STONE_MICROCELLS, available_space)
			var min_possible: int = min(MIN_STONE_MICROCELLS, max_possible)
			var dedicated_microcells: int = randi_range(min_possible, max_possible)
			var quantity: int = int(round(max_density * dedicated_microcells))

			state.set_resource_quantity(GameTypes.WorldObjectType.ROCK, quantity)
			state.set_dedicated_space(GameTypes.WorldObjectType.ROCK, dedicated_microcells)

	print("Stone popolato nell'area ", area)


func populate_trees(world: World, area: Rect2i) -> void:
	# TEST TEMPORANEO: solo una cella specifica, forzando la presenza
	var test_x := 50
	var test_y := 50

	var cell := world.get_cell_at(test_x, test_y)
	var state := world.get_cell_state_at(test_x, test_y)
	if cell == null or state == null:
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.TREE,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	if max_density <= 0.0:
		print("Trees non generato in (", test_x, ",", test_y, ") per max_density=0 — terrain=", cell.terrain_base, " biome=", cell.biome)
		return

	var available_space: int = state.get_empty_space()
	if available_space <= 0:
		print("Trees non generato in (", test_x, ",", test_y, ") per spazio esaurito")
		return

	var max_possible: int = min(MAX_TREE_MICROCELLS, available_space)
	var min_possible: int = min(MIN_TREE_MICROCELLS, max_possible)
	var dedicated_microcells: int = randi_range(min_possible, max_possible)
	var quantity: int = int(round(max_density * dedicated_microcells))

	state.set_resource_quantity(GameTypes.WorldObjectType.TREE, quantity)
	state.set_dedicated_space(GameTypes.WorldObjectType.TREE, dedicated_microcells)

	print("Trees popolato SOLO in (", test_x, ",", test_y, ") quantity=", quantity, " space=", dedicated_microcells)
