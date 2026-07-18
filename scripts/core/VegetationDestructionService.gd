class_name VegetationDestructionService
extends RefCounted

const DESTRUCTIBLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]


# Distribuisce total_budget (unità di dedicated_space da distruggere) sulle celle colpite,
# in proporzione uguale per cella, poi dentro ogni cella pesato per fragility * space
# (stesso schema usato da FireEventEffectService e riusabile da qualunque evento distruttivo).
func destroy_in_cells(
	world: World,
	affected_cells: Array[Vector2i],
	total_budget: int,
	fragility_weight_by_succession_level: Array[float]
) -> void:
	if affected_cells.is_empty() or total_budget <= 0:
		return

	var per_cell_budget := int(round(float(total_budget) / affected_cells.size()))

	for cell_pos in affected_cells:
		var cell := world.get_cell_at(cell_pos.x, cell_pos.y)
		var state := world.get_cell_state_at(cell_pos.x, cell_pos.y)
		if cell == null or state == null:
			continue
		_destroy_in_cell(cell, state, per_cell_budget, fragility_weight_by_succession_level)


func _destroy_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	cell_budget: int,
	fragility_weight_by_succession_level: Array[float]
) -> void:
	if cell_budget <= 0:
		return

	var weighted_present: Array = []
	var total_weight := 0.0

	for resource_type in DESTRUCTIBLE_TYPES:
		var space: int = state.get_dedicated_space(resource_type)
		if space <= 0:
			continue

		var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
		if growth_rules == null:
			continue

		var level: int = growth_rules.succession_level
		var fragility := 0.0
		if level < fragility_weight_by_succession_level.size():
			fragility = fragility_weight_by_succession_level[level]
		if fragility <= 0.0:
			continue

		var weight: float = fragility * float(space)
		weighted_present.append({"type": resource_type, "weight": weight, "space": space})
		total_weight += weight

	if total_weight <= 0.0:
		return

	for entry in weighted_present:
		var share: int = int(round(cell_budget * (entry["weight"] / total_weight)))
		var destroyed: int = min(share, entry["space"])
		if destroyed <= 0:
			continue

		var new_space: int = entry["space"] - destroyed
		var max_density := ResourceCalculator.get_max_density(
			entry["type"], cell.terrain_base, cell.biome, cell.coast_type
		)
		state.apply_subtype_space_delta(entry["type"], -destroyed)
		state.set_dedicated_space(entry["type"], new_space)
		state.set_resource_quantity(entry["type"], int(round(new_space * max_density)))
