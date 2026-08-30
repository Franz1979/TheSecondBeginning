class_name FaunaGrowthService
extends RefCounted

# Servizio indipendente dalla pipeline vegetale (ResourceGrowthService/Encroachment/Migration/
# Mortality, che gira su dedicated_space con lo schema "seed bank" a due tempi stagionali):
# niente encroachment né rinvio all'anno successivo. Growth/migration/mortality per la fauna
# "passiva" restano tre checkpoint stagionali separati (vedi WorldTimeService: fine primavera/
# estate/autunno), ciascuno nel proprio servizio (FaunaGrowthService/FaunaMigrationService/
# FaunaMortalityService). Nome generico ("Fauna", non "Fish") perché copre più di una risorsa
# non vegetale: FISH (dominio acqua, water_dedicated_space) e BIRDS (dominio terra,
# terrestrial_dedicated_space) condividono la stessa formula di crescita logistica, applicata a
# due budget fisicamente separati — vedi _grow_water_resource_in_cell/_grow_land_resource_in_cell.
const WATER_GROWABLE_TYPES := [
	GameTypes.WorldObjectType.FISH,
]
const LAND_GROWABLE_TYPES := [
	GameTypes.WorldObjectType.BIRDS,
]


func grow_fauna(world: World) -> void:
	# Aggregato per resource_type (mai per cella — con centinaia di celle già popolate un log
	# per-cella ogni anno satura l'output console esattamente come il seeding, vedi
	# ParametricResourceSetupService): {"count","space_before_sum","space_after_sum",
	# "quantity_after_sum"}. Nessuna suddivisione per water_type/terreno qui: la distribuzione
	# geografica è già spiegata dal log di seeding, non serve ripeterla ogni anno.
	var growth_by_type: Dictionary = {}

	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		# LOD0 (2026-08-30, richiesta utente: FISH/BIRDS trattati come vegetazione — sono campi
		# macrocella, non PopulationGroup): macrocella mai scoperta dentro una sessione con focus
		# attivo — congelata, nessuna crescita finché il player non ci arriva.
		if LODOrchestrator.is_vegetation_frozen(world, state):
			continue

		for resource_type in WATER_GROWABLE_TYPES:
			_grow_water_resource_in_cell(cell, state, resource_type, growth_by_type)
		for resource_type in LAND_GROWABLE_TYPES:
			_grow_land_resource_in_cell(cell, state, resource_type, growth_by_type)

	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		for resource_type in growth_by_type.keys():
			var g: Dictionary = growth_by_type[resource_type]
			print(
				"[FAUNA GROWTH SUMMARY] %s: celle_cresciute=%d spazio_totale %d->%d quantita_totale=%d" % [
					GameTypes.WorldObjectType.keys()[resource_type], g["count"],
					g["space_before_sum"], g["space_after_sum"], g["quantity_after_sum"]
				]
			)


func _accumulate_growth(
	growth_by_type: Dictionary, resource_type: GameTypes.WorldObjectType,
	space_before: int, space_after: int, quantity_after: int
) -> void:
	var g: Dictionary = growth_by_type.get(
		resource_type, {"count": 0, "space_before_sum": 0, "space_after_sum": 0, "quantity_after_sum": 0}
	)
	g["count"] = int(g["count"]) + 1
	g["space_before_sum"] = int(g["space_before_sum"]) + space_before
	g["space_after_sum"] = int(g["space_after_sum"]) + space_after
	g["quantity_after_sum"] = int(g["quantity_after_sum"]) + quantity_after
	growth_by_type[resource_type] = g


func _grow_water_resource_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	growth_by_type: Dictionary
) -> void:
	# Capacità sfruttabile (usable_capacity_ratio_*), non fisica: la crescita satura verso questo
	# tetto ridotto, non verso TOTAL_SPACE/river_space — vedi
	# ResourceCalculator.get_water_usable_capacity_space.
	var capacity := ResourceCalculator.get_water_usable_capacity_space(resource_type, cell, state)
	if capacity <= 0:
		return

	var current_space: int = state.get_water_space(resource_type)
	if current_space <= 0:
		return

	var growth_rate := ResourceCalculator.get_water_growth_rate(resource_type, cell.water_type)
	if growth_rate <= 0.0:
		return

	var empty_space: int = state.get_empty_water_space(capacity)
	var max_reachable_space: int = current_space + empty_space
	if max_reachable_space <= 0:
		return

	var new_space_float: float = current_space + growth_rate * current_space * (1.0 - float(current_space) / float(max_reachable_space))
	var new_space: int = int(round(min(new_space_float, max_reachable_space)))

	var max_density := ResourceCalculator.get_water_max_density(resource_type, cell.water_type)
	var new_quantity: int = int(round(new_space * max_density))

	state.set_water_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)

	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		_accumulate_growth(growth_by_type, resource_type, current_space, new_space, new_quantity)


# Gemella di _grow_water_resource_in_cell sopra, sul budget terrestrial_dedicated_space invece
# che water_dedicated_space: stessa identica formula di crescita logistica, solo le funzioni/
# accessori sono quelli del dominio terra (ResourceCalculator.get_land_*, asse Terrain/Biome/
# Coast invece di WaterType — vedi analisi BIRDS: nessun asse indipendente necessario, a
# differenza di FISH).
func _grow_land_resource_in_cell(
	cell: MacroCellData,
	state: MacroCellState,
	resource_type: GameTypes.WorldObjectType,
	growth_by_type: Dictionary
) -> void:
	var capacity := ResourceCalculator.get_land_usable_capacity_space(resource_type, cell, state)
	if capacity <= 0:
		return

	var current_space: int = state.get_terrestrial_space(resource_type)
	if current_space <= 0:
		return

	var growth_rate := ResourceCalculator.get_growth_rate(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	if growth_rate <= 0.0:
		return

	var empty_space: int = state.get_empty_terrestrial_space(capacity)
	var max_reachable_space: int = current_space + empty_space
	if max_reachable_space <= 0:
		return

	var new_space_float: float = current_space + growth_rate * current_space * (1.0 - float(current_space) / float(max_reachable_space))
	var new_space: int = int(round(min(new_space_float, max_reachable_space)))

	var max_density := ResourceCalculator.get_max_density(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	var new_quantity: int = int(round(new_space * max_density))

	state.set_terrestrial_space(resource_type, new_space)
	state.set_resource_quantity(resource_type, new_quantity)

	if DebugLogging.ENABLED and DebugLogging.SHOW_FAUNA_DIAGNOSTICS_LOGS:
		_accumulate_growth(growth_by_type, resource_type, current_space, new_space, new_quantity)
