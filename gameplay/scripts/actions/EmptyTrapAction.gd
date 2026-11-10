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
#
# Coltello (2026-11-09, richiesta utente): gli attrezzi della trappola (SecondaryResourceRules.trap_empty_tool_categories,
# rete: coltello) si controllano a ogni tick con il gate di sempre: senza resta fermo e riparte quando arrivano. Svuotata una
# trappola con prede, un uso. Se mancano a metà giro (coltello rotto) e qualcosa è già nello zaino, il giro finisce lì:
# niente altre tappe, consegna di quanto raccolto.
#
# Lacci (2026-11-09): ogni preda si macella sul posto (tempo in più col ritmo di ButcherAction, TrapService.butcher_days) e
# nello zaino vanno carne, pelle, tendini e ossa; un uso del coltello per preda (la rete: uno per rete).
# Giro a tappe decise strada facendo (2026-11-09): finita una tappa, la prossima è la trappola della zona più vicina con
# prede, non nel giro di un altro, la cui resa entra nello zaino (TrapJobProvider.next_round_trap); nessuna = consegna.

const STAMINA_DRAIN_PER_DAY: float = 150.0

var _elapsed: float = 0.0
var trap_id: int = 0
# Giro chiuso in anticipo per mancanza di attrezzi: non svuota questa trappola, consegna e basta.
var _round_cut_short: bool = false


func _init(p_trap_id: int = 0) -> void:
	trap_id = p_trap_id
	target = null
	skill_effect_key = TrapService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Skill della trappola che si svuota (2026-11-08: pesca per la nassa).
func get_skill_effect_key(_individual: Variant, context: Dictionary) -> String:
	var trap := TrapService.find_trap(GameSettings.active_game_data, resolve_trap_id(context))
	var rules := TrapService.get_rules(trap.trap_name) if trap != null else null
	return rules.trap_skill_effect_key if rules != null else skill_effect_key


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _round_cut_short:
		return 0.0
	refresh_required_tools(context)
	if not ensure_required_tools(individual):
		var catch_so_far: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
		if not catch_so_far.is_empty():
			_cut_round_short(individual)
		return 0.0
	_elapsed += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return -STAMINA_DRAIN_PER_DAY * delta


# Attrezzi richiesti dalla trappola di questa tappa (non salvati: si ricavano dalle regole).
func refresh_required_tools(context: Dictionary) -> void:
	var trap := TrapService.find_trap(GameSettings.active_game_data, resolve_trap_id(context))
	required_tool_categories = TrapService.empty_tool_categories(trap.trap_name) if trap != null else []


# Attrezzi spariti a metà giro: via le tappe che restano, questa tappa diventa la consegna.
func _cut_round_short(individual: Variant) -> void:
	_round_cut_short = true
	var task: Task = individual.current_task if individual != null else null
	if task != null:
		var index := task.steps.find(self)
		if index >= 0:
			task.remove_steps(index + 1, task.steps.size())
	TrapService.log_line("#%d %s: attrezzi per svuotare finiti, il giro si chiude e consegna" % [individual.id, individual.name])


func resolve_trap_id(context: Dictionary) -> int:
	return trap_id if trap_id > 0 else int(context.get(TrapService.CONTEXT_TRAP_ID, 0))


func is_complete(_individual: Variant, context: Dictionary) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	if _round_cut_short:
		return true
	var trap := TrapService.find_trap(game_data, resolve_trap_id(context))
	if trap == null:
		return true
	var rules := TrapService.get_rules(trap.trap_name)
	return _elapsed >= (rules.trap_empty_days if rules != null else 0.0) + TrapService.butcher_days(trap)


func on_complete(individual: Variant, context: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var current_id := resolve_trap_id(context)
	var trap := TrapService.find_trap(game_data, current_id)
	var is_last := not _has_later_stop(individual) and not _plan_next_stop(individual, context, current_id)
	if _round_cut_short:
		_queue_delivery(context)
		return
	if trap == null:
		var catch_so_far: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
		if is_last and catch_so_far.is_empty():
			context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = GameContext.tr_text("trap_fail_gone").format({"name": individual.name})
			return
		TrapService.log_line("#%d %s: trappola #%d non c'è più, saltata" % [individual.id, individual.name, current_id])
		if is_last:
			_queue_delivery(context)
		return
	var rules := TrapService.get_rules(trap.trap_name)
	var result := TrapService.empty(game_data, trap)
	var preys := int(result["preys"])
	# Coltello: un uso per preda macellata (lacci) o uno per trappola svuotata (rete).
	var uses := preys if rules != null and rules.trap_quarry == TrapService.QUARRY_SMALL_GAME else mini(preys, 1)
	for i in range(uses):
		var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, null)
		if not broken.is_empty():
			report_broken_tools(individual, broken)
			break
	if int(result["quantity"]) <= 0:
		TrapService.log_line("#%d %s svuota %s #%d: vuota (prede già marcite)" % [individual.id, individual.name, trap.trap_name, current_id])
	var catch: Dictionary = context.get(TrapService.CONTEXT_ROUND_CATCH, {})
	for product in result["products"]:
		var resource_name := String(product["resource"])
		var quantity := int(product["quantity"])
		if quantity <= 0 or resource_name == "":
			continue
		var added: int = individual.add_carried_resource(resource_name, quantity, float(product["decay_fraction"]))
		TrapService.log_line("#%d %s svuota %s #%d: %d %s (deperimento %.2f), usi rimasti %d%s" % [
			individual.id, individual.name, trap.trap_name, current_id, quantity, resource_name, float(product["decay_fraction"]),
			trap.get_remaining_uses(), "" if added == quantity else " — non c'era posto nello zaino, perse %d" % (quantity - added)
		])
		if added > 0:
			catch[resource_name] = int(catch.get(resource_name, 0)) + added
	if not catch.is_empty():
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


# Giro: aggiunge dopo questa tappa il cammino e lo svuotamento della prossima trappola (TrapJobProvider.next_round_trap).
# true se l'ha aggiunta. Solo nei giri e solo se gli attrezzi ci sono ancora.
func _plan_next_stop(individual: Variant, context: Dictionary, current_id: int) -> bool:
	if _round_cut_short or individual == null or not context.get(TrapService.CONTEXT_ROUND, false):
		return false
	var task: Task = individual.current_task
	if task == null or task.steps.find(self) != task.current_step_index:
		return false
	var game_data: GameData = GameSettings.active_game_data
	var current := TrapService.find_trap(game_data, current_id)
	var from: Vector2 = individual.position
	var exclude: Array[int] = [current_id]
	# Spazio dopo aver messo nello zaino la resa di questa tappa (non ancora svuotata).
	var free_space: float = individual.max_carry_capacity - individual.get_carried_space() \
		- (TrapJobProvider.catch_space(current) if current != null else 0.0)
	var next := TrapJobProvider.next_round_trap(game_data, GameSettings.active_human_individuals, individual,
		int(context.get(TrapService.CONTEXT_AREA_ID, 0)), String(context.get(TrapService.CONTEXT_ROUND_JOB, "hunt")), from, free_space, exclude)
	if next == null:
		return false
	var stop := EmptyTrapAction.new(next.id)
	stop.refresh_required_tools(context)
	var steps: Array[Action] = [WalkAction.new(TrapJobProvider.site_point(individual, next)), stop]
	var descriptions: Array[String] = ["task_empty_trap_step_walk", "task_empty_trap_step_empty"]
	task.insert_steps_after_current(steps, descriptions)
	TrapService.log_line("#%d %s: prossima tappa del giro %s #%d" % [individual.id, individual.name, next.trap_name, next.id])
	return true


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
	return {"elapsed": _elapsed, "trap_id": trap_id, "round_cut_short": _round_cut_short}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	trap_id = int(data.get("trap_id", 0))
	_round_cut_short = bool(data.get("round_cut_short", false))
