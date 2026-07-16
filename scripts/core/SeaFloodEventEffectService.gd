class_name SeaFloodEventEffectService
extends RefCounted


func apply(world: World, event: NaturalEventInstance, rules: SeaFloodEventRules) -> void:
	var center := Vector2i(event.center_x, event.center_y)
	var affected_cells: Array[Vector2i] = []

	for dy in range(-event.radius, event.radius + 1):
		for dx in range(-event.radius, event.radius + 1):
			if abs(dx) + abs(dy) > event.radius:
				continue

			var pos := center + Vector2i(dx, dy)
			var cell := world.get_cell_at(pos.x, pos.y)
			if cell == null or cell.terrain_base == GameTypes.TerrainBase.WATER:
				continue

			affected_cells.append(pos)

	event.affected_cells = affected_cells

	if affected_cells.is_empty():
		print("[INONDAZIONE MARINA] anno=%d centro=(%d,%d) nessuna cella di terra colpita" % [
			event.year, event.center_x, event.center_y
		])
		return

	var total_budget := 0
	if event.intensity_index < rules.cells_destroyed_by_intensity.size():
		total_budget = rules.cells_destroyed_by_intensity[event.intensity_index]

	var destruction_service := VegetationDestructionService.new()
	destruction_service.destroy_in_cells(
		world, affected_cells, total_budget, rules.fragility_weight_by_succession_level
	)

	var duration := 0
	if event.intensity_index < rules.post_event_growth_duration_by_intensity.size():
		duration = rules.post_event_growth_duration_by_intensity[event.intensity_index]

	for pos in affected_cells:
		var state := world.get_cell_state_at(pos.x, pos.y)
		if state == null:
			continue
		state.register_growth_bonus(GameTypes.NaturalEventType.SEA_FLOOD, rules.post_event_growth_multiplier, duration)

	print("[INONDAZIONE MARINA] anno=%d centro=(%d,%d) intensita=%d raggio=%d celle_colpite=%d moltiplicatore_crescita=%.2f durata=%d" % [
		event.year, event.center_x, event.center_y, event.intensity_index, event.radius, affected_cells.size(),
		rules.post_event_growth_multiplier, duration
	])
