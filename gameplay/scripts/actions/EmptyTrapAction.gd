class_name EmptyTrapAction
extends Action

# Svuotamento della trappola sul posto (2026-11-07, lavoro "Svuota trappola", empty_trap.tres): il Walk prima porta alla
# trappola (context TrapService.CONTEXT_TRAP_ID). Lavoro di trap_empty_days giorni, più svelto con la Caccia
# (SkillEffectService "trap"). Alla fine prende tutte le prede ancora dentro, anche quelle cadute dopo la partenza
# (TrapService.empty: un uso in meno, a zero la trappola sparisce) e le mette nello zaino come trap_catch_resource, vecchie
# quanto le prede; la consegna la accoda "pending_warehouse_search" verso la destinazione nel context. Trappola sparita o
# vuota: la Task si chiude.

#
# Giro delle reti (2026-11-07): ogni EmptyTrapAction ha la sua trappola (trap_id; 0 = quella del context, Task di una
# rete). Le prede si sommano nel context (TrapService.CONTEXT_ROUND_CATCH) e la consegna parte solo dall'ultima tappa;
# una trappola sparita o vuota a metà giro si salta.

const STAMINA_DRAIN_PER_DAY: float = 150.0

var _elapsed: float = 0.0
var trap_id: int = 0


func _init(p_trap_id: int = 0) -> void:
	trap_id = p_trap_id
	target = null
	skill_effect_key = TrapService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return -STAMINA_DRAIN_PER_DAY * delta


func resolve_trap_id(context: Dictionary) -> int:
	return trap_id if trap_id > 0 else int(context.get(TrapService.CONTEXT_TRAP_ID, 0))


func is_complete(_individual: Variant, context: Dictionary) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	var trap := TrapService.find_trap(game_data, resolve_trap_id(context))
	if trap == null:
		return true
	var rules := TrapService.get_rules(trap.trap_name)
	return _elapsed >= (rules.trap_empty_days if rules != null else 0.0)


func on_complete(individual: Variant, context: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var current_id := resolve_trap_id(context)
	var trap := TrapService.find_trap(game_data, current_id)
	var is_last := not _has_later_stop(individual)
	if trap == null:
		var catch_so_far: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
		if is_last and catch_so_far.is_empty():
			context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = GameContext.tr_text("trap_fail_gone").format({"name": individual.name})
			return
		TrapService.log_line("#%d %s: trappola #%d non c'è più, saltata" % [individual.id, individual.name, current_id])
		if is_last:
			_queue_delivery(context)
		return
	var result := TrapService.empty(game_data, trap)
	var resource_name := String(result["resource"])
	var quantity := int(result["quantity"])
	if quantity <= 0 or resource_name == "":
		TrapService.log_line("#%d %s svuota %s #%d: vuota (prede già marcite)" % [individual.id, individual.name, trap.trap_name, current_id])
	else:
		var added: int = individual.add_carried_resource(resource_name, quantity, float(result["decay_fraction"]))
		TrapService.log_line("#%d %s svuota %s #%d: %d %s (deperimento %.2f), usi rimasti %d%s" % [
			individual.id, individual.name, trap.trap_name, current_id, quantity, resource_name, float(result["decay_fraction"]),
			trap.get_remaining_uses(), "" if added == quantity else " — non c'era posto nello zaino, perse %d" % (quantity - added)
		])
		if added > 0:
			var catch: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
			catch[resource_name] = int(catch.get(resource_name, 0)) + added
			context[TrapService.CONTEXT_ROUND_CATCH] = catch
	if is_last:
		_queue_delivery(context)


# Consegna di tutte le prede raccolte nel giro (una ricerca per risorsa), dopo l'ultima tappa.
func _queue_delivery(context: Dictionary) -> void:
	var catch: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
	context.erase(TrapService.CONTEXT_ROUND_CATCH)
	var searches: Array = []
	for resource_name in catch.keys():
		if int(catch[resource_name]) > 0:
			searches.append({"resource_name": String(resource_name), "quantity": int(catch[resource_name])})
	if not searches.is_empty():
		context["pending_warehouse_search"] = {"searches": searches, "excluded_building_ids": []}


# true se dopo questo passo la Task ha un'altra tappa di svuotamento.
func _has_later_stop(individual: Variant) -> bool:
	var task: Task = individual.current_task if individual != null else null
	if task == null:
		return false
	var index := task.steps.find(self)
	if index < 0:
		return false
	for i in range(index + 1, task.steps.size()):
		if task.steps[i] is EmptyTrapAction:
			return true
	return false


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "trap_id": trap_id}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	trap_id = int(data.get("trap_id", 0))
