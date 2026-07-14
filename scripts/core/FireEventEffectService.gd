class_name FireEventEffectService
extends RefCounted

const DESTRUCTIBLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.TREE,
]

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),  # nord
	Vector2i(0, 1),   # sud
	Vector2i(1, 0),   # est
	Vector2i(-1, 0),  # ovest
]


func apply(world: World, event: NaturalEventInstance, rules: FireEventRules) -> void:
	var center_pos := Vector2i(event.center_x, event.center_y)
	var center_state := world.get_cell_state_at(event.center_x, event.center_y)
	if center_state == null or not _is_flammable(center_state, rules):
		print("[FIRE] anno=%d fulmine caduto in (%d,%d) ma nulla da bruciare" % [
			event.year, event.center_x, event.center_y
		])
		return

	var burned_lookup: Dictionary = {center_pos: true}
	var affected_cells: Array[Vector2i] = [center_pos]
	var current_wave: Array[Vector2i] = [center_pos]

	for iteration in range(rules.max_spread_iterations):
		if current_wave.is_empty():
			break

		var next_wave: Array[Vector2i] = []
		for cell_pos in current_wave:
			for offset in NEIGHBOR_OFFSETS:
				var neighbor_pos: Vector2i = cell_pos + offset
				if burned_lookup.has(neighbor_pos):
					continue
				if _manhattan_distance(neighbor_pos, center_pos) > event.radius:
					continue

				var neighbor_state := world.get_cell_state_at(neighbor_pos.x, neighbor_pos.y)
				if neighbor_state == null or not _is_flammable(neighbor_state, rules):
					continue
				if randf() > rules.spread_probability_to_neighbors:
					continue

				burned_lookup[neighbor_pos] = true
				affected_cells.append(neighbor_pos)
				next_wave.append(neighbor_pos)

		current_wave = next_wave

	event.affected_cells = affected_cells

	_destroy_vegetation(world, event, rules)

	for cell_pos in affected_cells:
		var state := world.get_cell_state_at(cell_pos.x, cell_pos.y)
		if state == null:
			continue
		state.register_growth_bonus(
			GameTypes.NaturalEventType.FIRE, rules.post_event_growth_multiplier, rules.post_event_growth_duration_years
		)

	print("[FIRE] anno=%d centro=(%d,%d) intensita=%d raggio=%d celle_bruciate=%d" % [
		event.year, event.center_x, event.center_y, event.intensity_index, event.radius, affected_cells.size()
	])


func _is_flammable(state: MacroCellState, rules: FireEventRules) -> bool:
	return _vegetation_level(state) >= rules.flammability_threshold


# Highest succession_level among renewable resource types actually present in the cell,
# or -1 if there is no vegetation at all (never flammable, regardless of threshold).
func _vegetation_level(state: MacroCellState) -> float:
	var level := -1.0
	for resource_type in DESTRUCTIBLE_TYPES:
		if state.get_dedicated_space(resource_type) <= 0:
			continue
		var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
		if growth_rules == null:
			continue
		level = max(level, float(growth_rules.succession_level))
	return level


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _destroy_vegetation(world: World, event: NaturalEventInstance, rules: FireEventRules) -> void:
	if event.affected_cells.is_empty():
		return

	var total_budget := 0
	if event.intensity_index < rules.cells_destroyed_by_intensity.size():
		total_budget = rules.cells_destroyed_by_intensity[event.intensity_index]
	if total_budget <= 0:
		return

	var per_cell_budget := int(round(float(total_budget) / event.affected_cells.size()))

	for cell_pos in event.affected_cells:
		var cell := world.get_cell_at(cell_pos.x, cell_pos.y)
		var state := world.get_cell_state_at(cell_pos.x, cell_pos.y)
		if cell == null or state == null:
			continue
		_destroy_in_cell(cell, state, per_cell_budget, rules)


# ROCK dedicated_space and river_space are never in DESTRUCTIBLE_TYPES/considered here,
# so they are never touched by fire destruction.
func _destroy_in_cell(cell: MacroCellData, state: MacroCellState, cell_budget: int, rules: FireEventRules) -> void:
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
		if level < rules.fragility_weight_by_succession_level.size():
			fragility = rules.fragility_weight_by_succession_level[level]
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
		state.set_dedicated_space(entry["type"], new_space)
		state.set_resource_quantity(entry["type"], int(round(new_space * max_density)))
