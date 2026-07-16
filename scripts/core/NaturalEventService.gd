class_name NaturalEventService
extends RefCounted

const REGISTERED_EVENT_TYPES := [
	GameTypes.NaturalEventType.FIRE,
	GameTypes.NaturalEventType.DROUGHT,
	GameTypes.NaturalEventType.SEA_FLOOD,
	# in futuro: RIVER_FLOOD, EARTHQUAKE, ecc.
]

# TEMPORANEO PER TEST: forza il centro di ogni evento su questa cella invece di
# estrarlo a caso su tutto il mondo, utile finché le risorse sono seminate solo
# in (50,50). Rimettere DEBUG_FORCE_CENTER a false quando si torna al random.
const DEBUG_FORCE_CENTER: bool = false
const DEBUG_FORCE_CENTER_CELL := Vector2i(50, 50)


func trigger_events(world: World, year: int) -> Array:
	for state in world.cell_states:
		state.tick_growth_bonuses()

	var triggered_events: Array = []
	for event_type in REGISTERED_EVENT_TYPES:
		var rules := NaturalEventCalculator.get_event_rules(event_type)
		if rules == null:
			continue

		var event_count := _roll_event_count(rules.base_probability_per_year)
		if event_count <= 0:
			print("[%s] anno=%d: nessun evento" % [GameTypes.NaturalEventType.keys()[event_type], year])

		for i in range(event_count):
			var event := _create_event_instance(world, event_type, rules, year)
			_apply_event_effects(world, event, rules)
			triggered_events.append(event)

	return triggered_events


# base_probability_per_year is treated as an expected event count per year (Poisson-like):
# floor(rate) events are guaranteed, plus one more with probability equal to the fractional part.
func _roll_event_count(rate: float) -> int:
	var count := int(floor(rate))
	if randf() < rate - float(count):
		count += 1
	return count


func _create_event_instance(
	world: World,
	event_type: GameTypes.NaturalEventType,
	rules: NaturalEventRules,
	year: int
) -> NaturalEventInstance:
	var center := Vector2i(randi_range(0, World.WIDTH - 1), randi_range(0, World.HEIGHT - 1))
	if rules.requires_coastal_center:
		center = _pick_random_coastal_cell(world, center)
	if DEBUG_FORCE_CENTER:
		center = DEBUG_FORCE_CENTER_CELL

	var center_x := center.x
	var center_y := center.y

	var intensity_index := _roll_intensity(rules.intensity_probability_weights)

	var radius := 0
	if intensity_index < rules.radius_by_intensity.size():
		radius = rules.radius_by_intensity[intensity_index]

	return NaturalEventInstance.new(event_type, year, center_x, center_y, intensity_index, radius)


# Sceglie a caso tra le celle costiere (coast_type != NONE, cioè adiacenti al mare).
# fallback_center viene restituito se la mappa non ha nessuna cella costiera.
func _pick_random_coastal_cell(world: World, fallback_center: Vector2i) -> Vector2i:
	var coastal_cells: Array[Vector2i] = []
	for cell in world.cells:
		if cell.coast_type != GameTypes.CoastType.NONE:
			coastal_cells.append(Vector2i(cell.x, cell.y))

	if coastal_cells.is_empty():
		return fallback_center

	return coastal_cells[randi_range(0, coastal_cells.size() - 1)]


func _roll_intensity(weights: Array[float]) -> int:
	if weights.is_empty():
		return 0

	var total_weight := 0.0
	for weight in weights:
		total_weight += weight
	if total_weight <= 0.0:
		return 0

	var roll := randf() * total_weight
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return i

	return weights.size() - 1


func _apply_event_effects(world: World, event: NaturalEventInstance, rules: NaturalEventRules) -> void:
	match event.event_type:
		GameTypes.NaturalEventType.FIRE:
			var fire_service := FireEventEffectService.new()
			fire_service.apply(world, event, rules as FireEventRules)
		GameTypes.NaturalEventType.DROUGHT:
			var drought_service := DroughtEventEffectService.new()
			drought_service.apply(world, event, rules as DroughtEventRules)
		GameTypes.NaturalEventType.SEA_FLOOD:
			var sea_flood_service := SeaFloodEventEffectService.new()
			sea_flood_service.apply(world, event, rules as SeaFloodEventRules)
		_:
			pass
