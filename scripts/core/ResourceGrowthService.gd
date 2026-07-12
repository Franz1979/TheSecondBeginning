class_name ResourceGrowthService
extends RefCounted

const GROWABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
]


func grow_resources(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in GROWABLE_TYPES:
			_grow_resource_in_cell(world, cell, state, resource_type)


func _grow_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
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

	state.set_dedicated_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)
