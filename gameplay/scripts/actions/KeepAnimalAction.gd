class_name KeepAnimalAction
extends Action

# Animali vivi dei cesti sistemati nella tettoia delle gabbie (2026-11-12, addomesticazione per cattura viva, passo B2):
# tappa a fine giro delle trappole (EmptyTrapAction._queue_live_delivery), prima della consegna della carne. All'arrivo,
# per ogni animale in braccio (entries, voci KeptAnimalService.make_entry): posto ancora libero → nasce l'individuo
# (KeptAnimalService.keep_animal); tettoia sparita o piena (posto non più valido) → un'altra tettoia con posto (tappa nuova
# subito dopo); nessuna → si macella qui (ritmo di ButcherAction, coltello come al cesto) e la resa va a destinazione con
# la consegna della carne ("pending_warehouse_search").

const HANDOVER_DAYS: float = 0.01

var building: Building = null
var entries: Array = []
var _elapsed: float = 0.0
var _resolved: bool = false
var _to_butcher: Array = []


func _init(p_building: Building = null, p_entries: Array = []) -> void:
	target = null
	building = p_building
	entries = p_entries
	skill_effect_key = TrapService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if not _resolved:
		_resolve(individual, context)
	if not _to_butcher.is_empty() and not ensure_required_tools(individual):
		return 0.0
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if not _resolved:
		_resolve(individual, context)
	return _elapsed >= HANDOVER_DAYS + _butcher_days()


# All'arrivo: chi ha posto entra, chi no va a un'altra tettoia o si macella. Una volta sola (_resolved, salvato).
func _resolve(individual: Variant, context: Dictionary) -> void:
	_resolved = true
	var game_data: GameData = GameSettings.active_game_data
	var world: World = GameSettings.active_world
	var reserved := KeptAnimalService.reservations(GameSettings.active_human_individuals, self)
	var rerouted := {}
	for entry in entries:
		var species := String(entry.get("species", ""))
		if KeptAnimalService.has_room_for(game_data, building, species, reserved):
			var animal := KeptAnimalService.keep_animal(game_data, building, entry)
			# Punti addomesticazione all'arrivo (2026-11-12): li assegna la scena a fine tappa
			# (HumanIndividualActionService.CONTEXT_PENDING_DOMESTICATION_POINTS), con l'eventuale scoperta.
			# Anche a 0 punti (anziano): il primo arrivo scopre la specie (passo C).
			var pending: Dictionary = context.get(HumanIndividualActionService.CONTEXT_PENDING_DOMESTICATION_POINTS, {})
			pending[species] = int(pending.get(species, 0)) + KeptAnimalService.capture_points(entry)
			context[HumanIndividualActionService.CONTEXT_PENDING_DOMESTICATION_POINTS] = pending
			TrapService.log_line("#%d %s: %s nella %s #%d (animale #%d)" % [individual.id, individual.name,
				entry.get("wild_species", "?"), building.building_type_name, building.id, animal.id if animal != null else -1])
			continue
		var macro: Vector2i = Vector2i(building.macro_x, building.macro_y) if building != null else individual.home_macro_coords
		var other := KeptAnimalService.find_building_with_room(game_data, world, species, macro, reserved)
		if other != null:
			entry["building_id"] = other.id
			reserved.append(entry)
			if not rerouted.has(other.id):
				rerouted[other.id] = {"building": other, "entries": []}
			rerouted[other.id]["entries"].append(entry)
			TrapService.log_line("#%d %s: %s non entra nella %s #%d (%s), va alla %s #%d" % [individual.id, individual.name,
				entry.get("wild_species", "?"), building.building_type_name if building != null else "tettoia",
				building.id if building != null else -1, _no_room_reason(game_data, building, species),
				other.building_type_name, other.id])
			continue
		_to_butcher.append(entry)
		TrapService.log_line("#%d %s: nessun posto per %s, si macella" % [individual.id, individual.name, entry.get("wild_species", "?")])
	entries = []
	if not _to_butcher.is_empty():
		required_tool_categories = TrapService.empty_tool_categories(String(_to_butcher[0].get("trap_name", "")))
	_insert_reroutes(individual, rerouted)


# Perché la tettoia prevista non va più bene, per il log.
static func _no_room_reason(game_data: GameData, shelter: Building, species: String) -> String:
	if shelter == null:
		return "non c'è più"
	if not shelter.is_complete or shelter.is_out_of_service():
		return "fuori servizio"
	var current := KeptAnimalService.current_species(game_data, shelter)
	if current != "" and current != species:
		return "tiene %s" % current
	return "piena"


func _insert_reroutes(individual: Variant, rerouted: Dictionary) -> void:
	var task: Task = individual.current_task if individual != null else null
	if task == null or rerouted.is_empty():
		return
	var steps: Array[Action] = []
	var descriptions: Array[String] = []
	for group in rerouted.values():
		steps.append(WalkAction.new(walk_point(individual, group["building"])))
		steps.append(KeepAnimalAction.new(group["building"], group["entries"]))
		descriptions.append("task_empty_trap_step_walk_shelter")
		descriptions.append("task_empty_trap_step_keep_animal")
	task.insert_steps_after_current(steps, descriptions)


func _butcher_days() -> float:
	var days := 0.0
	for entry in _to_butcher:
		var meat := float(ButcherAction.compute_yields(String(entry.get("wild_species", "")), int(entry.get("age_band", 0)))["meat"])
		days += maxf(meat / ButcherAction.MEAT_UNITS_PER_DAY, ButcherAction.MIN_DURATION_DAYS)
	return days


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _to_butcher.is_empty():
		return
	var searches: Array = []
	for entry in _to_butcher:
		var yields := ButcherAction.compute_yields(String(entry.get("wild_species", "")), int(entry.get("age_band", 0)))
		for resource_name in yields:
			var quantity := int(yields[resource_name])
			if quantity <= 0:
				continue
			var added: int = individual.add_carried_resource(String(resource_name), quantity, 0.0)
			if added > 0:
				searches.append({"resource_name": String(resource_name), "quantity": added})
		var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, null)
		if not broken.is_empty():
			report_broken_tools(individual, broken)
	_to_butcher = []
	if searches.is_empty():
		return
	var pending: Dictionary = context.get("pending_warehouse_search", {"searches": [], "excluded_building_ids": []})
	pending["searches"].append_array(searches)
	context["pending_warehouse_search"] = pending


# Punto d'arrivo alla tettoia, nelle coordinate di `individual` (come gli scarichi ai magazzini).
static func walk_point(individual: HumanIndividual, shelter: Building) -> Vector2:
	var macro_offset := Vector2(Vector2i(shelter.macro_x, shelter.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(shelter.micro_x, shelter.micro_y) + macro_offset + Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85))


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "resolved": _resolved, "to_butcher": _to_butcher,
		"keep_building_id": building.id if building != null else -1, "keep_entries": entries}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_resolved = bool(data.get("resolved", false))
	_to_butcher = data.get("to_butcher", [])
	if not _to_butcher.is_empty():
		required_tool_categories = TrapService.empty_tool_categories(String(_to_butcher[0].get("trap_name", "")))
