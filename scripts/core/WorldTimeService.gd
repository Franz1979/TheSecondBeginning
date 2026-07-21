class_name WorldTimeService
extends RefCounted

# Advances the calendar by exactly one day, then runs whichever seasonal simulation
# checkpoint(s) fall on the resulting day (see _run_seasonal_checkpoints). Returns true if any
# checkpoint ran, so callers know whether world state actually changed and a redraw is needed.
func advance_day(world: World, game_data: GameData) -> bool:
	var year_rolled_over := game_data.advance_day()
	return _run_seasonal_checkpoints(world, game_data, year_rolled_over)

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

	for season in [GameTypes.Season.WINTER, GameTypes.Season.SPRING, GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]:
		if day == SeasonCalculator.get_season_day_range(season).x:
			_run_natural_events_checkpoint(world, game_data, season)
			checkpoint_ran = true

	if year_rolled_over:
		_run_mortality_checkpoint(world)
		checkpoint_ran = true

	return checkpoint_ran


func _run_growth_checkpoint(world: World, game_data: GameData) -> void:
	var growth_service := ResourceGrowthService.new()
	growth_service.grow_resources(world, game_data)
	var encroachment_service := ResourceEncroachmentService.new()
	var leftover_surplus := encroachment_service.encroach_resources(world)
	_store_pending_migration_surplus(world, leftover_surplus)


func _run_mortality_checkpoint(world: World) -> void:
	var mortality_service := ResourceMortalityService.new()
	mortality_service.apply_mortality(world)


func _run_migration_checkpoint(world: World, game_data: GameData) -> void:
	var migration_service := ResourceMigrationService.new()
	var leftover_surplus := _collect_pending_migration_surplus(world)
	var transfers := migration_service.compute_transfers(world, leftover_surplus)
	migration_service.apply_transfers(world, transfers)
	_clear_pending_migration_surplus(world)


func _run_natural_events_checkpoint(world: World, game_data: GameData, season: GameTypes.Season) -> void:
	var natural_event_service := NaturalEventService.new()
	natural_event_service.trigger_events(world, game_data, season)


func _store_pending_migration_surplus(world: World, leftover_surplus: Dictionary) -> void:
	for cell_key in leftover_surplus.keys():
		var state := world.get_cell_state_at(cell_key.x, cell_key.y)
		if state == null:
			continue
		for resource_type in leftover_surplus[cell_key].keys():
			var surplus_quantity = leftover_surplus[cell_key][resource_type]
			state.pending_migration_surplus[resource_type] = surplus_quantity
			if cell_key.x == 50 and cell_key.y == 50:
				print("[SURPLUS SAVED 50,50] %s: %.3f accantonato" % [
					GameTypes.WorldObjectType.keys()[resource_type], surplus_quantity
				])


func _collect_pending_migration_surplus(world: World) -> Dictionary:
	var leftover_surplus: Dictionary = {}
	for state in world.cell_states:
		if state.pending_migration_surplus.is_empty():
			continue
		if state.x == 50 and state.y == 50:
			for resource_type in state.pending_migration_surplus.keys():
				print("[SURPLUS APPLIED 50,50] %s: %.3f applicato" % [
					GameTypes.WorldObjectType.keys()[resource_type], state.pending_migration_surplus[resource_type]
				])
		leftover_surplus[Vector2i(state.x, state.y)] = state.pending_migration_surplus.duplicate()
	return leftover_surplus


func _clear_pending_migration_surplus(world: World) -> void:
	for state in world.cell_states:
		state.pending_migration_surplus.clear()
