class_name FaunaMigrationService
extends RefCounted

# Pipeline diretta (vedi FaunaGrowthService): calcola e applica i trasferimenti nella stessa
# chiamata, a differenza di ResourceMigrationService che è spezzato in compute_transfers/
# apply_transfers solo per servire lo schema "seed bank" della vegetazione (surplus calcolato
# a fine primavera, applicato all'inizio di quella successiva). Né FISH né BIRDS hanno bisogno
# di quel rinvio, quindi non c'è nessuno split da replicare qui. Due domini fisicamente separati
# (acqua/water_dedicated_space, terra/terrestrial_dedicated_space), stessa formula di
# migrazione — vedi _migrate_water_resource_in_cell/_migrate_land_resource_in_cell.
const WATER_MIGRATABLE_TYPES := [
	GameTypes.WorldObjectType.FISH,
]
const LAND_MIGRATABLE_TYPES := [
	GameTypes.WorldObjectType.BIRDS,
]

const NEIGHBOR_OFFSETS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]


func migrate_fauna(world: World) -> void:
	# Aggregato per resource_type (mai per cella/vicino — stesso motivo di
	# ParametricResourceSetupService/FaunaGrowthService): {"cells_with_surplus",
	# "transfer_attempts","skipped_by_chance","total_migrated_quantity"}.
	var migration_by_type: Dictionary = {}

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		for resource_type in WATER_MIGRATABLE_TYPES:
			_migrate_water_resource_in_cell(world, cell, state, resource_type, migration_by_type)
		for resource_type in LAND_MIGRATABLE_TYPES:
			_migrate_land_resource_in_cell(world, cell, state, resource_type, migration_by_type)

	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		for resource_type in migration_by_type.keys():
			var m: Dictionary = migration_by_type[resource_type]
			print(
				"[FAUNA MIGRATION SUMMARY] %s: celle_con_surplus=%d tentativi=%d skip_per_chance=%d quantita_totale_migrata=%.1f" % [
					GameTypes.WorldObjectType.keys()[resource_type], m["cells_with_surplus"],
					m["transfer_attempts"], m["skipped_by_chance"], m["total_migrated_quantity"]
				]
			)


func _accumulate_migration(migration_by_type: Dictionary, resource_type: GameTypes.WorldObjectType) -> Dictionary:
	var m: Dictionary = migration_by_type.get(
		resource_type,
		{"cells_with_surplus": 0, "transfer_attempts": 0, "skipped_by_chance": 0, "total_migrated_quantity": 0.0}
	)
	migration_by_type[resource_type] = m
	return m


func _migrate_water_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	migration_by_type: Dictionary
) -> void:
	var surplus := ResourceCalculator.get_water_growth_surplus(resource_type, cell, state)
	if surplus <= 0.0:
		return

	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return

	# Il surplus va diviso solo tra i vicini realmente navigabili (acqua con capacità fisica >
	# 0), non per NEIGHBOR_OFFSETS.size() fisso: altrimenti la quota destinata a un vicino di
	# terra andrebbe sprecata ogni anno invece di essere ridistribuita tra i vicini d'acqua
	# realmente disponibili. "Valido" qui è una proprietà geografica (è acqua?), separata dal
	# roll probabilistico di migration_chance sotto (un evento annuale, non strutturale).
	var valid_neighbors: Array = []
	for offset in NEIGHBOR_OFFSETS:
		var neighbor_x: int = cell.x + offset.x
		var neighbor_y: int = cell.y + offset.y
		var neighbor_cell := world.get_cell_at(neighbor_x, neighbor_y)
		var neighbor_state := world.get_cell_state_at(neighbor_x, neighbor_y)
		if neighbor_cell == null or neighbor_state == null:
			continue
		if ResourceCalculator.get_water_capacity_space(neighbor_cell, neighbor_state) <= 0:
			continue
		valid_neighbors.append({
			"x": neighbor_x, "y": neighbor_y, "cell": neighbor_cell, "state": neighbor_state
		})

	if valid_neighbors.is_empty():
		return

	var per_neighbor_raw: float = surplus / valid_neighbors.size()

	var m: Dictionary = {}
	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		m = _accumulate_migration(migration_by_type, resource_type)
		m["cells_with_surplus"] = int(m["cells_with_surplus"]) + 1

	for neighbor in valid_neighbors:
		var chance_roll := randf()
		if chance_roll > growth_rules.migration_chance:
			if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
				m["skipped_by_chance"] = int(m["skipped_by_chance"]) + 1
			continue

		# Nessun "destination_factor" come in ResourceMigrationService (lì confronta il
		# growth_rate del vicino con quello di origine, un affinamento legato all'encroachment
		# terrestre): qui l'unico gate strutturale è "il vicino è acqua" (già filtrato sopra), la
		# capacità sfruttabile del vicino fa già da freno naturale in _apply_water_transfer sotto.
		var migrated_quantity: float = min(
			per_neighbor_raw * growth_rules.migration_success_rate,
			float(growth_rules.max_migration_per_year)
		)
		if migrated_quantity <= 0.0:
			continue

		var applied := _apply_water_transfer(neighbor.cell, neighbor.state, resource_type, migrated_quantity)
		if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
			m["transfer_attempts"] = int(m["transfer_attempts"]) + 1
			m["total_migrated_quantity"] = float(m["total_migrated_quantity"]) + applied


# Ritorna la quantità EFFETTIVAMENTE applicata (può essere < quantity se la cella di destinazione
# non ha abbastanza spazio libero) — usata dal chiamante solo per l'aggregato diagnostico, 0.0 se
# il trasferimento non è avvenuto per nessun motivo.
func _apply_water_transfer(
	target_cell: MacroCellData,
	target_state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	quantity: float
) -> float:
	var max_density := ResourceCalculator.get_water_max_density(resource_type, target_cell.water_type)
	if max_density <= 0.0:
		return 0.0

	# Capacità sfruttabile del vicino, non fisica: altrimenti la migrazione potrebbe spingere la
	# cella di destinazione oltre il proprio tetto ecologico, aggirando usable_capacity_ratio.
	var capacity := ResourceCalculator.get_water_usable_capacity_space(resource_type, target_cell, target_state)
	var empty_space: int = target_state.get_empty_water_space(capacity)
	if empty_space <= 0:
		return 0.0

	var max_quantity_acceptable: float = float(empty_space) * max_density
	var quantity_applied: float = min(quantity, max_quantity_acceptable)
	if quantity_applied <= 0.0:
		return 0.0

	var current_space: int = target_state.get_water_space(resource_type)
	var current_quantity: int = target_state.get_resource_quantity(resource_type)
	var new_total_quantity: int = current_quantity + int(round(quantity_applied))

	# Stesso clamp di ResourceMigrationService._apply_transfer: quantity/space possono
	# disallinearsi per arrotondamenti indipendenti (qui, crescita/mortalità), il min() con lo
	# spazio disponibile garantisce che il trasferimento non sfori mai la capacità della cella.
	var new_space: int = min(int(ceil(float(new_total_quantity) / max_density)), current_space + empty_space)

	target_state.set_water_space(resource_type, new_space)
	target_state.set_resource_quantity(resource_type, new_total_quantity)
	return quantity_applied


# Gemella di _migrate_water_resource_in_cell sopra, sul budget terrestrial_dedicated_space:
# stessa formula (surplus -> vicini idonei -> roll migration_chance -> quantità capata da
# migration_success_rate/max_migration_per_year), solo il filtro vicini e gli accessori sono
# quelli del dominio terra (get_land_capacity_space invece di get_water_capacity_space, ecc.).
func _migrate_land_resource_in_cell(
	world: World,
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	migration_by_type: Dictionary
) -> void:
	var surplus := ResourceCalculator.get_land_growth_surplus(resource_type, cell, state)
	if surplus <= 0.0:
		return

	var growth_rules := ResourceCalculator.get_growth_rules(resource_type)
	if growth_rules == null:
		return

	var valid_neighbors: Array = []
	for offset in NEIGHBOR_OFFSETS:
		var neighbor_x: int = cell.x + offset.x
		var neighbor_y: int = cell.y + offset.y
		var neighbor_cell := world.get_cell_at(neighbor_x, neighbor_y)
		var neighbor_state := world.get_cell_state_at(neighbor_x, neighbor_y)
		if neighbor_cell == null or neighbor_state == null:
			continue
		if ResourceCalculator.get_land_capacity_space(neighbor_cell, neighbor_state) <= 0:
			continue
		valid_neighbors.append({
			"x": neighbor_x, "y": neighbor_y, "cell": neighbor_cell, "state": neighbor_state
		})

	if valid_neighbors.is_empty():
		return

	var per_neighbor_raw: float = surplus / valid_neighbors.size()

	var m: Dictionary = {}
	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		m = _accumulate_migration(migration_by_type, resource_type)
		m["cells_with_surplus"] = int(m["cells_with_surplus"]) + 1

	for neighbor in valid_neighbors:
		var chance_roll := randf()
		if chance_roll > growth_rules.migration_chance:
			if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
				m["skipped_by_chance"] = int(m["skipped_by_chance"]) + 1
			continue

		var migrated_quantity: float = min(
			per_neighbor_raw * growth_rules.migration_success_rate,
			float(growth_rules.max_migration_per_year)
		)
		if migrated_quantity <= 0.0:
			continue

		var applied := _apply_land_transfer(neighbor.cell, neighbor.state, resource_type, migrated_quantity)
		if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
			m["transfer_attempts"] = int(m["transfer_attempts"]) + 1
			m["total_migrated_quantity"] = float(m["total_migrated_quantity"]) + applied


# Ritorna la quantità EFFETTIVAMENTE applicata — vedi nota su _apply_water_transfer sopra.
func _apply_land_transfer(
	target_cell: MacroCellData,
	target_state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	quantity: float
) -> float:
	var max_density := ResourceCalculator.get_max_density(resource_type, target_cell.terrain_base, target_cell.biome, target_cell.coast_type)
	if max_density <= 0.0:
		return 0.0

	var capacity := ResourceCalculator.get_land_usable_capacity_space(resource_type, target_cell, target_state)
	var empty_space: int = target_state.get_empty_terrestrial_space(capacity)
	if empty_space <= 0:
		return 0.0

	var max_quantity_acceptable: float = float(empty_space) * max_density
	var quantity_applied: float = min(quantity, max_quantity_acceptable)
	if quantity_applied <= 0.0:
		return 0.0

	var current_space: int = target_state.get_terrestrial_space(resource_type)
	var current_quantity: int = target_state.get_resource_quantity(resource_type)
	var new_total_quantity: int = current_quantity + int(round(quantity_applied))

	var new_space: int = min(int(ceil(float(new_total_quantity) / max_density)), current_space + empty_space)

	target_state.set_terrestrial_space(resource_type, new_space)
	target_state.set_resource_quantity(resource_type, new_total_quantity)
	return quantity_applied
