class_name ResourceEncroachmentService
extends RefCounted

const ENCROACHABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]


func encroach_resources(world: World) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	# Processing order follows succession_level ascending (grass, then shrub, then trees, ...)
	# so that when two encroachers target the same weaker resource in the same cell/year,
	# the lower succession level always gets first claim on it, regardless of how
	# ENCROACHABLE_TYPES is ordered or extended in the future.
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(ENCROACHABLE_TYPES)

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in ordered_types:
			var surplus := ResourceCalculator.compute_growth_surplus(resource_type, cell, state)

			if cell.x == 50 and cell.y == 50:
				print("[ENCROACH 50,50] %s: surplus=%.3f dedicated_space=%d empty_space=%d" % [
					GameTypes.WorldObjectType.keys()[resource_type], surplus,
					state.get_dedicated_space(resource_type), state.get_empty_space()
				])

			if surplus <= 0.0:
				continue

			var leftover := _encroach_resource_in_cell(cell, state, resource_type, surplus)

			if cell.x == 50 and cell.y == 50:
				print("[ENCROACH 50,50] %s: encroached=%.3f leftover_to_migration=%.3f" % [
					GameTypes.WorldObjectType.keys()[resource_type], surplus - leftover, leftover
				])

			if leftover > 0.0:
				_store_leftover(leftover_surplus, cell, resource_type, leftover)

	return leftover_surplus


func _encroach_resource_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	surplus: float
) -> float:
	# Rule 1: encroachment only when this resource's desired growth exceeds available
	# space/density (surplus > 0 is guaranteed by the caller) — same trigger migration uses,
	# rather than requiring the whole macro cell to be literally at 0 empty space.
	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return surplus

	var weaker_types := _get_weaker_types_present(state, resource_type, growth_rules.succession_level)
	if weaker_types.is_empty():
		# Rule 6: no weaker level available, everything goes to migration.
		if cell.x == 50 and cell.y == 50:
			print("[ENCROACH 50,50]   %s has no weaker type present in cell -> skip" % [
				GameTypes.WorldObjectType.keys()[resource_type]
			])
		return surplus

	var own_max_density := ResourceCalculator.get_max_density(
		resource_type, cell.terrain_base, cell.biome, cell.coast_type
	)
	if own_max_density <= 0.0:
		return surplus

	# Rule 4: encroachment is capped at max_encroachment_per_year regardless of surplus size.
	# The cap applies to the final realized quantity (same as max_migration_per_year does for
	# migration), not to the surplus before efficiency is applied — otherwise a low efficiency
	# would shrink an already-capped small budget twice and round away to nothing.
	var remaining_budget: float = float(growth_rules.max_encroachment_per_year)
	var remaining_surplus: float = surplus

	if cell.x == 50 and cell.y == 50:
		print("[ENCROACH 50,50]   %s remaining_budget=%.3f own_max_density=%.4f weaker_types=%s" % [
			GameTypes.WorldObjectType.keys()[resource_type], remaining_budget, own_max_density, str(weaker_types)
		])

	# Rule 3: consume the farthest (lowest succession level) target fully before moving closer.
	for weak_type in weaker_types:
		if remaining_budget <= 0.0:
			break

		var weak_space: int = state.get_dedicated_space(weak_type)
		if weak_space <= 0:
			continue

		var weak_growth_rules := ResourceCalculator.get_growth_rules(weak_type)
		if weak_growth_rules == null:
			continue

		var efficiency := ResourceCalculator.get_encroachment_efficiency(
			growth_rules, weak_growth_rules.succession_level
		)
		if efficiency <= 0.0:
			continue

		var weak_max_density := ResourceCalculator.get_max_density(
			weak_type, cell.terrain_base, cell.biome, cell.coast_type
		)

		var potential_quantity: float = remaining_surplus * efficiency
		var max_quantity_from_space: float = float(weak_space) * own_max_density
		var quantity_gained: float = min(potential_quantity, remaining_budget, max_quantity_from_space)
		if quantity_gained <= 0.0:
			continue

		var space_taken: int = min(int(round(quantity_gained / own_max_density)), weak_space)
		if space_taken <= 0:
			# Rounds down to no actual space transferred: nothing to apply, no budget spent.
			continue

		# Re-derive the applied quantity from the rounded space so quantity stays
		# consistent with space * density (same invariant used everywhere else).
		var applied_quantity: float = space_taken * own_max_density

		if cell.x == 50 and cell.y == 50:
			print("[ENCROACH 50,50]   vs %s: weak_space=%d efficiency=%.4f applied_quantity=%.3f space_taken=%d" % [
				GameTypes.WorldObjectType.keys()[weak_type], weak_space, efficiency, applied_quantity, space_taken
			])

		# Lato perdente: proporzione locale pura, invariata. La competizione territoriale
		# (chi prende spazio a chi) non è un giudizio di idoneità climatica del sottotipo —
		# solo growth/mortality usano il moltiplicatore di bioma, l'encroachment no.
		var new_weak_space: int = weak_space - space_taken
		state.apply_subtype_space_delta(weak_type, -space_taken)
		state.set_dedicated_space(weak_type, new_weak_space)
		state.set_resource_quantity(weak_type, int(round(new_weak_space * weak_max_density)))

		var gain_weights := ResourceCalculator.get_biome_weighted_subtype_composition(resource_type, state, cell.biome)
		state.apply_subtype_space_delta(resource_type, space_taken, gain_weights)
		state.set_dedicated_space(resource_type, state.get_dedicated_space(resource_type) + space_taken)
		state.add_resource_quantity(resource_type, int(round(applied_quantity)))

		remaining_budget -= applied_quantity
		remaining_surplus -= applied_quantity

	return max(remaining_surplus, 0.0)


func _get_weaker_types_present(
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	own_succession_level: GameTypes.SuccessionLevel
) -> Array:
	var candidates: Array = []

	for candidate_type in ENCROACHABLE_TYPES:
		if candidate_type == resource_type:
			continue
		if state.get_dedicated_space(candidate_type) <= 0:
			continue

		var candidate_rules := ResourceCalculator.get_growth_rules(candidate_type)
		if candidate_rules == null:
			continue
		if candidate_rules.succession_level >= own_succession_level:
			continue

		candidates.append({"type": candidate_type, "level": candidate_rules.succession_level})

	candidates.sort_custom(func(a, b): return a["level"] < b["level"])

	var sorted_types: Array = []
	for entry in candidates:
		sorted_types.append(entry["type"])
	return sorted_types


func _store_leftover(
	leftover_surplus: Dictionary,
	cell: MacroCellData,
	resource_type: GameTypes.WorldObjectType,
	leftover: float
) -> void:
	var cell_key := Vector2i(cell.x, cell.y)
	if not leftover_surplus.has(cell_key):
		leftover_surplus[cell_key] = {}
	leftover_surplus[cell_key][resource_type] = leftover
