class_name FaunaMigrationService
extends RefCounted

# Pipeline diretta (vedi FaunaGrowthService): calcola e applica i trasferimenti nella stessa
# chiamata, a differenza di ResourceMigrationService che è spezzato in compute_transfers/
# apply_transfers solo per servire lo schema "seed bank" della vegetazione (surplus calcolato
# a fine primavera, applicato all'inizio di quella successiva). FISH non ha bisogno di quel
# rinvio, quindi non c'è nessuno split da replicare qui.
const MIGRATABLE_TYPES := [
	GameTypes.WorldObjectType.FISH,
]

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]


func migrate_fauna(world: World) -> void:
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in MIGRATABLE_TYPES:
			_migrate_resource_in_cell(world, cell, state, resource_type)


func _migrate_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType
) -> void:
	var surplus := ResourceCalculator.get_water_growth_surplus(resource_type, cell, state)
	if surplus <= 0.0:
		return

	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return

	var per_neighbor_raw: float = surplus / NEIGHBOR_OFFSETS.size()

	for offset in NEIGHBOR_OFFSETS:
		var neighbor_x: int = cell.x + offset.x
		var neighbor_y: int = cell.y + offset.y
		var neighbor_cell := world.get_cell_at(neighbor_x, neighbor_y)
		var neighbor_state := world.get_cell_state_at(neighbor_x, neighbor_y)
		if neighbor_cell == null or neighbor_state == null:
			continue

		if randf() > growth_rules.migration_chance:
			continue

		# Nessun "destination_factor" come in ResourceMigrationService (lì confronta il
		# growth_rate del vicino con quello di origine, un affinamento legato all'encroachment
		# terrestre): qui l'unico gate è "il vicino è acqua", la capacità del vicino fa già da
		# freno naturale in _apply_transfer sotto.
		var neighbor_capacity := ResourceCalculator.get_water_capacity_space(neighbor_cell, neighbor_state)
		if neighbor_capacity <= 0:
			continue

		var migrated_quantity: float = min(
			per_neighbor_raw * growth_rules.migration_success_rate,
			float(growth_rules.max_migration_per_year)
		)
		if migrated_quantity <= 0.0:
			continue

		_apply_transfer(neighbor_cell, neighbor_state, resource_type, migrated_quantity)


func _apply_transfer(
	target_cell: MacroCellData,
	target_state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	quantity: float
) -> void:
	var max_density := ResourceCalculator.get_water_max_density(resource_type, target_cell.water_type)
	if max_density <= 0.0:
		return

	# Capacità sfruttabile del vicino, non fisica: altrimenti la migrazione potrebbe spingere la
	# cella di destinazione oltre il proprio tetto ecologico, aggirando usable_capacity_ratio.
	var capacity := ResourceCalculator.get_water_usable_capacity_space(resource_type, target_cell, target_state)
	var empty_space: int = target_state.get_empty_water_space(capacity)
	if empty_space <= 0:
		return

	var max_quantity_acceptable: float = float(empty_space) * max_density
	var quantity_applied: float = min(quantity, max_quantity_acceptable)
	if quantity_applied <= 0.0:
		return

	var current_space: int = target_state.get_water_space(resource_type)
	var current_quantity: int = target_state.get_resource_quantity(resource_type)
	var new_total_quantity: int = current_quantity + int(round(quantity_applied))

	# Stesso clamp di ResourceMigrationService._apply_transfer: quantity/space possono
	# disallinearsi per arrotondamenti indipendenti (qui, crescita/mortalità), il min() con lo
	# spazio disponibile garantisce che il trasferimento non sfori mai la capacità della cella.
	var new_space: int = min(int(ceil(float(new_total_quantity) / max_density)), current_space + empty_space)

	target_state.set_water_space(resource_type, new_space)
	target_state.set_resource_quantity(resource_type, new_total_quantity)
