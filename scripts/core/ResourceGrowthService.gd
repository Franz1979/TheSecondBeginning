class_name ResourceGrowthService
extends RefCounted

const GROWABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]


func grow_resources(world: World, game_data: GameData) -> void:
	# Growth deliberately reverses the shared ascending-succession order (used as-is by
	# encroachment/migration/mortality): each type's growth is capped by empty_space read
	# fresh at call time, so whichever type grows first claims the cell's freed space first.
	# Highest succession (TREE) goes first here so the climax type gets first claim on newly
	# freed space, matching real succession (mature stands hold ground rather than losing it
	# back to pioneer species every year). Temporary fix — will need rethinking once growth
	# moves to day-granularity/seasons.
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(GROWABLE_TYPES)
	ordered_types.reverse()

	var current_absolute_day := game_data.get_absolute_day()
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in ordered_types:
			_grow_resource_in_cell(world, cell, state, resource_type, current_absolute_day)


func _grow_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	current_absolute_day: int
) -> void:
	var current_space: int = state.get_dedicated_space(resource_type)
	if current_space <= 0:
		return

	#print("DEBUG growth cella (", cell.x, ",", cell.y, ") current_space=", current_space)

	var growth_rate := ResourceCalculator.get_growth_rate(
		resource_type,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	#print("DEBUG growth_rate=", growth_rate)
	if growth_rate <= 0.0:
		return

	growth_rate *= state.get_active_growth_multiplier(current_absolute_day)

	var empty_space: int = state.get_empty_space()
	var max_reachable_space: int = current_space + empty_space
	#print("DEBUG empty_space=", empty_space, " max_reachable=", max_reachable_space)
	if max_reachable_space <= 0:
		return

	var new_space_float: float = current_space + growth_rate * current_space * (1.0 - float(current_space) / float(max_reachable_space))
	var new_space: int = int(round(min(new_space_float, max_reachable_space)))
	#print("DEBUG new_space_float=", new_space_float, " new_space=", new_space)

	var max_density := ResourceCalculator.get_max_density(
		resource_type,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	var new_quantity: int = int(round(new_space * max_density))
	#print("DEBUG new_quantity=", new_quantity)

	if cell.x == 50 and cell.y == 50:
		print("[GROWTH 50,50] %s: space %d -> %d | quantity -> %d" % [
			GameTypes.WorldObjectType.keys()[resource_type], current_space, new_space, new_quantity
		])

	var subtype_weights := ResourceCalculator.get_biome_weighted_subtype_composition(resource_type, state, cell.biome)
	state.apply_subtype_space_delta(resource_type, new_space - current_space, subtype_weights)
	state.set_dedicated_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)
