class_name TakeTrapAction
extends Action

# Presa della trappola da montare (2026-11-07, capanna del trappoliere — lavoro "Piazza trappola", place_trap.tres): dall'
# edificio raggiunto (Prodotti finiti della capanna o un magazzino) un pezzo di TrapService.CONTEXT_TRAP_NAME nello zaino,
# con i suoi usi (ToolInstance). Breve sosta sul posto (il Walk prima porta all'edificio). Niente trappola o niente posto
# nello zaino: la Task si chiude con il motivo.

const DURATION_DAYS: float = 0.005

var source_building: Building = null
var _elapsed: float = 0.0


func _init(p_source_building: Building) -> void:
	target = null
	source_building = p_source_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(_individual: Variant, _context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var trap_name := String(context.get(TrapService.CONTEXT_TRAP_NAME, ""))
	var failure := ""
	if source_building == null or source_building.is_demolished or trap_name == "":
		failure = "trap_fail_no_source"
	else:
		var units: Array = BuildingStorageService.withdraw_tool_units_auto(source_building, trap_name, 1)
		if units.is_empty():
			failure = "trap_fail_no_trap"
		elif not individual.add_carried_tool_instance(trap_name, units[0]):
			BuildingStorageService.store_tool_instance(source_building, trap_name, units[0])
			failure = "trap_fail_no_room"
	if failure == "":
		TrapService.log_line("#%d %s prende %s da %s #%d" % [individual.id, individual.name, trap_name, source_building.building_type_name, source_building.id])
	else:
		TrapService.log_line("#%d %s non prende %s: %s" % [individual.id, individual.name, trap_name, failure])
	if failure != "":
		var message := GameContext.tr_text(failure).format({"name": individual.name})
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = message
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = message


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "trap_building_id": source_building.id if source_building != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
