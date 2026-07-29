class_name WorldTimeService
extends RefCounted

# Advances the calendar by exactly one day, then runs whichever seasonal simulation
# checkpoint(s) fall on the resulting day (see _run_seasonal_checkpoints), plus the animal
# consumption pass (see _run_daily_animal_consumption), che a differenza dei checkpoint
# stagionali gira OGNI giorno, non solo ai confini di stagione. Ritorna le due cause di
# cambiamento separate (non fuse in un solo bool) così i chiamanti che vogliono trattarle
# diversamente — vedi MacroCellScene, che ridisegna sempre ai checkpoint stagionali ma
# l'aggiornamento guidato dal solo consumo animale lo rende opzionale — possono farlo senza
# dover indovinare quale delle due è effettivamente scattata.
func advance_day(world: World, game_data: GameData) -> Dictionary:
	var year_rolled_over := game_data.advance_day()
	var animals_changed := _run_daily_animal_consumption(world, game_data)
	var checkpoint_ran := _run_seasonal_checkpoints(world, game_data, year_rolled_over)
	return {"checkpoint_ran": checkpoint_ran, "animals_changed": animals_changed}


# Gira ogni giorno (non solo ai checkpoint stagionali): il fabbisogno calorico degli animali
# non aspetta il cambio di stagione. Vedi AnimalConsumptionService per la formula.
func _run_daily_animal_consumption(world: World, game_data: GameData) -> bool:
	var current_season := SeasonCalculator.get_season_for_day(game_data.current_day)
	return AnimalConsumptionService.new().apply_daily_consumption(world, current_season)

# Debug/emergency fast-forward (the "+1" button): advances a full 365 days one at a time (via
# advance_day) so every seasonal checkpoint crossed along the way still runs, in chronological
# order, exactly once — instead of jumping straight to day 0 and running everything at once.
func force_advance_to_year_end(world: World, game_data: GameData) -> void:
	for i in range(GameData.DAYS_PER_YEAR):
		advance_day(world, game_data)

# Dispatches to the seasonal pipeline steps whose checkpoint day matches game_data.current_day:
#   - start of spring: apply last autumn's pending migration surplus (compute + apply transfers)
#   - end of spring: growth + encroachment, leftover surplus stored as this year's pending surplus
#   - start of each season: evaluate natural event types whose reference_season matches
#   - end of autumn (year rollover): mortality
# Order within a shared day matters only for SPRING's start (migration before any future
# spring-referenced event type), chosen to mirror the original pipeline's resource-then-events
# ordering.
func _run_seasonal_checkpoints(world: World, game_data: GameData, year_rolled_over: bool) -> bool:
	var day := game_data.current_day
	var checkpoint_ran := false

	if day == SeasonCalculator.get_season_day_range(GameTypes.Season.SPRING).x:
		_run_migration_checkpoint(world, game_data)
		checkpoint_ran = true

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING):
		_run_growth_checkpoint(world, game_data)
		checkpoint_ran = true

	if day == SeasonCalculator.get_season_end_day(GameTypes.Season.SUMMER):
		_run_fauna_migration_checkpoint(world)
		checkpoint_ran = true

	for season in [GameTypes.Season.WINTER, GameTypes.Season.SPRING, GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]:
		if day == SeasonCalculator.get_season_day_range(season).x:
			_run_secondary_resource_stock_debug_checkpoint(world, SeasonCalculator.get_previous_season(season), season)
			_run_natural_events_checkpoint(world, game_data, season)
			checkpoint_ran = true

	if year_rolled_over:
		_run_mortality_checkpoint(world)
		checkpoint_ran = true

	return checkpoint_ran


func _run_growth_checkpoint(world: World, game_data: GameData) -> void:
	# Maturazione PRIMA di growth/encroachment: opera sulla composizione young/adult/old
	# ereditata dagli anni precedenti, cosicché le nascite di growth in questo stesso ciclo
	# (età 0) non vengano mai incluse nella maturazione dello stesso anno in cui compaiono —
	# vedi ResourceAgeBandService.
	ResourceAgeBandService.new().mature_age_bands(world)

	var growth_service := ResourceGrowthService.new()
	growth_service.grow_resources(world, game_data)
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(world)
	_store_pending_migration_surplus(world, leftover_surplus)

	# FISH cresce sullo stesso checkpoint di fine primavera della vegetazione, ma su un budget
	# separato (water_dedicated_space): nessuna interazione con
	# encroachment/pending_migration_surplus terrestri. Migration e mortality per FISH sono
	# invece in checkpoint propri (fine estate/fine autunno, vedi sotto) — a differenza della
	# vegetazione, growth->migration->mortality per FISH restano tre momenti separati dell'anno
	# invece che un'unica pipeline diretta, per poter osservare l'evoluzione di ciascuna fase.
	FaunaGrowthService.new().grow_fauna(world)


# Fine estate: unico checkpoint per la migrazione FISH, nessuno sfasamento all'anno successivo
# come lo schema "seed bank" della vegetazione (_run_migration_checkpoint sotto).
func _run_fauna_migration_checkpoint(world: World) -> void:
	FaunaMigrationService.new().migrate_fauna(world)


func _run_mortality_checkpoint(world: World) -> void:
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(world)

	# Stesso checkpoint di fine autunno (year_rolled_over) della mortalità vegetale, su
	# water_dedicated_space invece che dedicated_space.
	FaunaMortalityService.new().apply_fauna_mortality(world)


func _run_migration_checkpoint(world: World, game_data: GameData) -> void:
	var migration_service := ResourceMigrationService.new()
	var leftover_surplus := _collect_pending_migration_surplus(world)
	var transfers := migration_service.compute_transfers(world, leftover_surplus)
	migration_service.apply_transfers(world, transfers)
	_clear_pending_migration_surplus(world)


func _run_natural_events_checkpoint(world: World, game_data: GameData, season: GameTypes.Season) -> void:
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(world, game_data, season)


# TEMPORANEO — nessun vero registro di fonti a stock persistente esiste ancora, solo questo
# elenco hardcoded delle fonti oggi implementate con la rispettiva risorsa primaria. Non gira
# in partita normale: richiede DebugLogging.ENABLED.
const _DEBUG_SECONDARY_SOURCES := [
	{"resource_name": "berry", "primary_resource_type": GameTypes.WorldObjectType.SHRUB},
	{"resource_name": "acorn", "primary_resource_type": GameTypes.WorldObjectType.TREE},
	{"resource_name": "fruit", "primary_resource_type": GameTypes.WorldObjectType.TREE},
]

func _run_secondary_resource_stock_debug_checkpoint(
	world: World, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	if not DebugLogging.ENABLED:
		return
	for source in _DEBUG_SECONDARY_SOURCES:
		var rules := CaloricCalculator.get_caloric_source_rules(source["resource_name"])
		if rules == null:
			continue
		for state in world.cell_states:
			var cell := world.get_cell_at(state.x, state.y)
			if cell == null:
				continue
			CaloricCalculator.update_secondary_resource_stock(
				rules, cell, state, source["primary_resource_type"], previous_season, new_season
			)


func _store_pending_migration_surplus(world: World, leftover_surplus: Dictionary) -> void:
	for cell_key in leftover_surplus.keys():
		var state := world.get_cell_state_at(cell_key.x, cell_key.y)
		if state == null:
			continue
		for resource_type in leftover_surplus[cell_key].keys():
			var surplus_quantity = leftover_surplus[cell_key][resource_type]
			state.pending_migration_surplus[resource_type] = surplus_quantity
			if DebugLogging.ENABLED and cell_key.x == 50 and cell_key.y == 50:
				print("[SURPLUS SAVED 50,50] %s: %.3f accantonato" % [
					GameTypes.WorldObjectType.keys()[resource_type], surplus_quantity
				])


func _collect_pending_migration_surplus(world: World) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	for state in world.cell_states:
		if state.pending_migration_surplus.is_empty():
			continue
		if DebugLogging.ENABLED and state.x == 50 and state.y == 50:
			for resource_type in state.pending_migration_surplus.keys():
				print("[SURPLUS APPLIED 50,50] %s: %.3f applicato" % [
					GameTypes.WorldObjectType.keys()[resource_type], state.pending_migration_surplus[resource_type]
				])
		leftover_surplus[Vector2i(state.x, state.y)] = state.pending_migration_surplus.duplicate()
	return leftover_surplus


func _clear_pending_migration_surplus(world: World) -> void:
	for state in world.cell_states:
		state.pending_migration_surplus.clear()
