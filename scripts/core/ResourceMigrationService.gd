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

	# Istantanea della composizione locale al momento del calcolo (prima che la mortalità
	# dello stesso anno la modifichi) — i sottotipi che migrano portano con sé questa
	# proporzione di origine (Regola 4), non quella (eventualmente diversa) che la cella di
	# origine avrà quando i trasferimenti verranno applicati più avanti nella stessa pipeline.
	var origin_subtype_weights: Dictionary = {}
	if not ResourceCalculator.get_subtype_rules(resource_type).is_empty():
		origin_subtype_weights = state.get_subtype_composition(resource_type).duplicate()

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
			"subtype_weights": origin_subtype_weights,
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

	# Filtra i sottotipi non idonei a bioma/terrain della cella di destinazione (Regola 4):
	# le unità corrispondenti vengono scartate dal totale trasferito, non solo dalla
	# composizione, così l'aggregato applicato sotto resta sempre coerente con la somma dei
	# sottotipi effettivamente arrivati. Se resource_type non ha sottotipi (subtype_weights
	# vuoto), il trasferimento procede come oggi, invariato.
	var subtype_weights: Dictionary = transfer.get("subtype_weights", {})
	var filtered_weights: Dictionary = {}
	if not subtype_weights.is_empty():
		var subtype_rules := ResourceCalculator.get_subtype_rules(resource_type)
		var original_total := 0.0
		for amount in subtype_weights.values():
			original_total += float(amount)

		var filtered_total := 0.0
		for rule in subtype_rules:
			var amount: float = float(subtype_weights.get(rule.subtype_name, 0))
			if amount <= 0.0:
				continue
			if not rule.is_suitable_for(target_cell.biome, target_cell.terrain_base):
				continue
			filtered_weights[rule.subtype_name] = amount
			filtered_total += amount

		if filtered_total <= 0.0:
			return # tutti i sottotipi trasferiti erano non idonei alla cella di destinazione
		if original_total > 0.0:
			quantity *= filtered_total / original_total

	var empty_space: int = target_state.get_empty_space()
	if empty_space <= 0:
		return

	var max_quantity_acceptable: float = float(empty_space) * max_density
	var quantity_applied: float = min(quantity, max_quantity_acceptable)

	var current_space: int = target_state.get_dedicated_space(resource_type)
	var current_quantity: int = target_state.get_resource_quantity(resource_type)
	var new_total_quantity: int = current_quantity + int(round(quantity_applied))

	# quantity/space possono essere leggermente disallineati per arrotondamenti indipendenti
	# fatti altrove (es. mortalità): ricalcolare lo spazio da zero con ceil() potrebbe quindi
	# chiedere più spazio di quanto risultasse davvero libero. Il clamp garantisce che questo
	# trasferimento non faccia mai sforare il budget totale della cella (TOTAL_SPACE).
	var new_space: int = min(int(ceil(float(new_total_quantity) / max_density)), current_space + empty_space)

	if not filtered_weights.is_empty():
		target_state.apply_subtype_space_delta(resource_type, new_space - current_space, filtered_weights)

	target_state.set_dedicated_space(resource_type, new_space)
	target_state.set_resource_quantity(resource_type, new_total_quantity)
