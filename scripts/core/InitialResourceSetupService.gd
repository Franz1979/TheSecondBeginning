class_name InitialResourceSetupService
extends RefCounted

const TEST_AREA_SIZE: int = 10
const MIN_STONE_MICROCELLS: int = 50
const MAX_STONE_MICROCELLS: int = 500
const MIN_TREE_MICROCELLS: int = 50
const MAX_TREE_MICROCELLS: int = 500
const MIN_GRASS_MICROCELLS: int = 50
const MAX_GRASS_MICROCELLS: int = 200
const MIN_SHRUB_MICROCELLS: int = 50
const MAX_SHRUB_MICROCELLS: int = 200
const RIVER_SPACE: int = 3000
const MIN_FISH_CAPACITY_RATIO: float = 0.02
const MAX_FISH_CAPACITY_RATIO: float = 0.06


func populate_resources(world: World) -> void:
	reserve_river_space(world)
	populate_fish(world)
	var area := _get_population_area(world)
	populate_stone(world, area)
	populate_trees(world, area)
	populate_grass(world, area)
	populate_shrub(world, area)


# A differenza di stone/trees/grass/shrub (confinati a _get_population_area, un residuo di
# test), FISH viene seminato su OGNI cella d'acqua dell'intero mondo: water_dedicated_space è
# gated dalla capacità fisica della cella (ResourceCalculator.get_water_capacity_space), quindi
# non richiede un'area di test per restare limitato/controllato.
func populate_fish(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var capacity := ResourceCalculator.get_water_capacity_space(cell, state)
		if capacity <= 0:
			continue

		var max_density := ResourceCalculator.get_water_max_density(GameTypes.WorldObjectType.FISH, cell.water_type)
		if max_density <= 0.0:
			continue

		var dedicated_space: int = int(round(capacity * randf_range(MIN_FISH_CAPACITY_RATIO, MAX_FISH_CAPACITY_RATIO)))
		if dedicated_space <= 0:
			continue
		var quantity: int = int(round(max_density * dedicated_space))

		state.set_water_space(GameTypes.WorldObjectType.FISH, dedicated_space)
		state.set_resource_quantity(GameTypes.WorldObjectType.FISH, quantity)


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
	_seed_subtype_composition(state, GameTypes.WorldObjectType.TREE, cell.biome, dedicated_microcells)

	print("Trees popolato SOLO in (", test_x, ",", test_y, ") quantity=", quantity, " space=", dedicated_microcells)


func populate_grass(world: World, area: Rect2i) -> void:
	# TEST TEMPORANEO: solo una cella specifica, forzando la presenza
	var test_x := 50
	var test_y := 50

	var cell := world.get_cell_at(test_x, test_y)
	var state := world.get_cell_state_at(test_x, test_y)
	if cell == null or state == null:
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.GRASS,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	if max_density <= 0.0:
		print("Grass non generato in (", test_x, ",", test_y, ") per max_density=0 — terrain=", cell.terrain_base, " biome=", cell.biome)
		return

	var available_space: int = state.get_empty_space()
	if available_space <= 0:
		print("Grass non generato in (", test_x, ",", test_y, ") per spazio esaurito")
		return

	var max_possible: int = min(MAX_GRASS_MICROCELLS, available_space)
	var min_possible: int = min(MIN_GRASS_MICROCELLS, max_possible)
	var dedicated_microcells: int = randi_range(min_possible, max_possible)
	var quantity: int = int(round(max_density * dedicated_microcells))

	state.set_resource_quantity(GameTypes.WorldObjectType.GRASS, quantity)
	state.set_dedicated_space(GameTypes.WorldObjectType.GRASS, dedicated_microcells)

	print("Grass popolato SOLO in (", test_x, ",", test_y, ") quantity=", quantity, " space=", dedicated_microcells)


func populate_shrub(world: World, area: Rect2i) -> void:
	# TEST TEMPORANEO: solo una cella specifica, forzando la presenza
	var test_x := 50
	var test_y := 50

	var cell := world.get_cell_at(test_x, test_y)
	var state := world.get_cell_state_at(test_x, test_y)
	if cell == null or state == null:
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.SHRUB,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	if max_density <= 0.0:
		print("Shrub non generato in (", test_x, ",", test_y, ") per max_density=0 — terrain=", cell.terrain_base, " biome=", cell.biome)
		return

	var available_space: int = state.get_empty_space()
	if available_space <= 0:
		print("Shrub non generato in (", test_x, ",", test_y, ") per spazio esaurito")
		return

	var max_possible: int = min(MAX_SHRUB_MICROCELLS, available_space)
	var min_possible: int = min(MIN_SHRUB_MICROCELLS, max_possible)
	var dedicated_microcells: int = randi_range(min_possible, max_possible)
	var quantity: int = int(round(max_density * dedicated_microcells))

	state.set_resource_quantity(GameTypes.WorldObjectType.SHRUB, quantity)
	state.set_dedicated_space(GameTypes.WorldObjectType.SHRUB, dedicated_microcells)
	_seed_subtype_composition(state, GameTypes.WorldObjectType.SHRUB, cell.biome, dedicated_microcells)

	print("Shrub popolato SOLO in (", test_x, ",", test_y, ") quantity=", quantity, " space=", dedicated_microcells)


# Semina la composizione iniziale dei sottotipi (se registrati per resource_type) in proporzione
# a initial_ratio_by_biome del bioma della cella. Se nessun sottotipo ha un rapporto positivo per
# quel bioma (biome non coperto nei dati), ripiega su pesi uguali per non lasciare
# sum(subtype_composition) disallineato da dedicated_space appena assegnato sopra.
func _seed_subtype_composition(
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	biome: GameTypes.Biome,
	total_space: int
) -> void:
	var subtype_rules := ResourceCalculator.get_subtype_rules(resource_type)
	if subtype_rules.is_empty() or total_space <= 0:
		return

	var weights: Dictionary = {}
	for rule in subtype_rules:
		var ratio: float = float(rule.initial_ratio_by_biome.get(biome, 0.0))
		if ratio > 0.0:
			weights[rule.subtype_name] = ratio

	if weights.is_empty():
		for rule in subtype_rules:
			weights[rule.subtype_name] = 1.0

	state.apply_subtype_space_delta(resource_type, total_space, weights)
