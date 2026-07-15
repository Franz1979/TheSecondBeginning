class_name ResourceMigrationService
extends RefCounted

const MIGRATABLE_TYPES := [
	GameTypes.WorldObjectType.GRASS,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
]

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1),  # nord
	Vector2i(0, 1),   # sud
	Vector2i(1, 0),   # est
	Vector2i(-1, 0),  # ovest
]


func compute_transfers(world: World, leftover_surplus: Dictionary) -> Array:
	var transfers: Array = []
	var ordered_types := ResourceCalculator.get_types_ordered_by_succession(MIGRATABLE_TYPES)

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in ordered_types:
			_compute_transfers_for_cell(world, cell, state, resource_type, leftover_surplus, transfers)

	return transfers


func apply_transfers(world: World, transfers: Array) -> void:
	for transfer in transfers:
		_apply_transfer(world, transfer)


func _compute_transfers_for_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	leftover_surplus: Dictionary,
	transfers: Array
) -> void:
	var cell_key := Vector2i(cell.x, cell.y)
	var surplus_quantity: float = 0.0
	if leftover_surplus.has(cell_key):
		surplus_quantity = leftover_surplus[cell_key].get(resource_type, 0.0)

	if cell.x == 50 and cell.y == 50:
		print("[MIGRATION 50,50] %s: residual_surplus_from_encroachment=%.3f" % [
			GameTypes.WorldObjectType.keys()[resource_type], surplus_quantity
		])

	if surplus_quantity <= 0.0:
		return
	#print("DEBUG MIGRATION cella (", cell.x, ",", cell.y, ") surplus=", surplus_quantity)

	var growth_rate := ResourceCalculator.get_growth_rate(
		resource_type,
		cell.terrain_base,
		cell.biome,
		cell.coast_type
	)
	if growth_rate <= 0.0:
		return

	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return

	var per_neighbor_raw: float = surplus_quantity / NEIGHBOR_OFFSETS.size()

	for offset in NEIGHBOR_OFFSETS:
		var neighbor_x: int = cell.x + offset.x
		var neighbor_y: int = cell.y + offset.y
		var neighbor_cell := world.get_cell_at(neighbor_x, neighbor_y)
		if neighbor_cell == null:
			continue

		if randf() > growth_rules.migration_chance:
			#print("DEBUG MIGRATION verso (", neighbor_x, ",", neighbor_y, ") FALLITA per chance")
			continue

		var neighbor_growth_rate := ResourceCalculator.get_growth_rate(
			resource_type,
			neighbor_cell.terrain_base,
			neighbor_cell.biome,
			neighbor_cell.coast_type
		)
		var destination_factor: float = 0.0
		if growth_rate > 0.0:
			destination_factor = min(neighbor_growth_rate / growth_rate, 1.0)

		var potential_quantity: float = per_neighbor_raw * destination_factor * growth_rules.migration_success_rate
		var migrated_quantity: float = min(potential_quantity, float(growth_rules.max_migration_per_year))
		
		#print("DEBUG MIGRATION verso (", neighbor_x, ",", neighbor_y, ") destination_factor=", destination_factor, " migrated_quantity=", migrated_quantity)
		
		if cell.x == 50 and cell.y == 50:
			print("[MIGRATION 50,50]   -> (%d,%d) %s: migrated_quantity=%.3f" % [
				neighbor_x, neighbor_y, GameTypes.WorldObjectType.keys()[resource_type], migrated_quantity
			])

		if migrated_quantity <= 0.0:
			continue

		transfers.append({
			"target_x": neighbor_x,
			"target_y": neighbor_y,
			"resource_type": resource_type,
			"quantity": migrated_quantity,
		})


func _apply_transfer(world: World, transfer: Dictionary) -> void:
	var target_x: int = transfer["target_x"]
	var target_y: int = transfer["target_y"]
	var resource_type: GameTypes.WorldObjectType = transfer["resource_type"]
	var quantity: float = transfer["quantity"]

	var target_cell := world.get_cell_at(target_x, target_y)
	var target_state := world.get_cell_state_at(target_x, target_y)
	if target_cell == null or target_state == null:
		return

	var max_density := ResourceCalculator.get_max_density(
		resource_type,
		target_cell.terrain_base,
		target_cell.biome,
		target_cell.coast_type
	)
	if max_density <= 0.0:
		return

	var empty_space: int = target_state.get_empty_space()
	if empty_space <= 0:
		return

	var max_quantity_acceptable: float = float(empty_space) * max_density
	var quantity_applied: float = min(quantity, max_quantity_acceptable)

	var current_quantity: int = target_state.get_resource_quantity(resource_type)
	var new_total_quantity: int = current_quantity + int(round(quantity_applied))

	var new_space: int = int(ceil(float(new_total_quantity) / max_density))

	target_state.set_dedicated_space(resource_type, new_space)
	target_state.set_resource_quantity(resource_type, new_total_quantity)
