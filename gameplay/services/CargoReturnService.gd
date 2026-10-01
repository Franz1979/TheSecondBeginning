class_name CargoReturnService
extends RefCounted

# Regola unica del carico nello zaino (2026-09-29, richiesta utente — consolidamento, primo passo): quando la Task
# PROPRIETARIA del carico viene chiusa, per qualunque motivo (tasto H, annullo del cantiere, cantiere completato o
# demolito da altri), il carico torna al magazzino più vicino con una Task di ritorno [Walk → Unload]; a terra solo se
# nessun magazzino lo accetta. Vale anche per il carico rimasto senza proprietario quando il pipottino resta libero
# (release_orphan_cargo, da resolve_idle_individual). Service stateless, stesso pattern degli altri *Service.
#
# Fuori da questa regola, con la loro logica: le sospensioni (interrupt da bisogno, "zaino occupato", ordine a metà
# giro di rifornimento), l'avanzo di un giro reinserito nella stessa Task, lo scarto quando la ricerca del magazzino
# fallisce, la pulizia delle consegne vuote in coda e i comandi di debug.

# Esito di release_cargo.
enum Outcome {
	EMPTY,      # zaino vuoto: nulla da fare
	NOT_OWNER,  # la Task chiusa non possiede il carico: lo zaino resta com'è (appartiene a un'altra Task)
	RETURNING,  # ritorno al magazzino creato: sostituisce la Task chiusa (corrente o in coda)
	DISCARDED,  # nessun magazzino, o era già una Task di ritorno: carico a terra
}

# Marca nel context delle Task di ritorno (salvata con il context). Chiudere una Task di ritorno scarta a terra invece
# di crearne un'altra: il secondo H "ferma davvero" e non c'è mai un ciclo infinito di ritorni.
const CONTEXT_CARGO_RETURN := "cargo_return"

# Collegamento dei segnali degli Unload della Task di ritorno (refresh della griglia di stoccaggio e simili), registrato
# da GameScene in _ready — stesso schema di IdleTaskAssignmentService.daydream_step_appended_connector: questo service
# non conosce GameScene. Callable(unload: UnloadAction, owner: HumanIndividual).
static var unload_signal_connector: Callable = Callable()


static func is_cargo_return_task(task: Task) -> bool:
	return task != null and bool(task.context.get(CONTEXT_CARGO_RETURN, false))


# Da chiamare PRIMA di chiudere `closed_task`, mentre è ancora la current_task dell'individuo o ancora in coda: il
# proprietario del carico (TaskQueueService.get_cargo_owner) si legge qui, prima di qualunque chiusura.
#   - RETURNING: se `closed_task` era corrente, è già stata chiusa (stop senza scarto) e sostituita dal ritorno, attivo;
#     se era in coda, il ritorno ha preso il suo posto nella coda. Il chiamante non deve né scartare né rimettere in
#     moto l'individuo per una Task corrente sostituita.
#   - DISCARDED / NOT_OWNER / EMPTY: il chiamante chiude `closed_task` come al solito, SENZA scartare lo zaino
#     (stop(false), o rimozione dalla coda) — lo scarto, se dovuto, è già avvenuto qui.
# La preferenza della macellazione (context CONTEXT_PREFER_RECIPE_WORKSTATION della Task chiusa) passa al ritorno:
# ingredienti di una ricetta prima alla postazione, come la ricerca del magazzino dopo la macellazione.
static func release_cargo(individual: HumanIndividual, closed_task: Task, world: World) -> Outcome:
	if individual == null or individual.carried_resources.is_empty():
		return Outcome.EMPTY
	if closed_task == null or TaskQueueService.get_cargo_owner(individual) != closed_task:
		return Outcome.NOT_OWNER
	var return_task: Task = null
	if not is_cargo_return_task(closed_task):
		var prefer_workstation := bool(closed_task.context.get(HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION, false))
		return_task = build_cargo_return_task(individual, world, prefer_workstation)
	if return_task == null:
		_log(individual, "carico %s a terra (%s)." % [
			str(individual.carried_resources.keys()),
			"Task di ritorno fermata" if is_cargo_return_task(closed_task) else "nessun magazzino lo accetta"
		])
		individual.discard_carried_resource()
		return Outcome.DISCARDED
	if individual.current_task == closed_task:
		individual.stop(false)
		_assign_as_current(individual, return_task)
	else:
		connect_unload_signals(individual, return_task)
		var queue_index := individual.task_queue.find(closed_task)
		if queue_index >= 0:
			individual.task_queue[queue_index] = return_task
		else:
			TaskQueueService.push_suspended_task(individual, return_task)
	_log(individual, "'%s' chiusa con il carico %s — lo riporta al magazzino%s." % [
		closed_task.task_name, str(individual.carried_resources.keys()),
		"" if individual.current_task == return_task else " (in coda)"
	])
	return Outcome.RETURNING


# Carico senza proprietario su un individuo rimasto libero (resolve_idle_individual, prima del fallback perditempo —
# che assegnandosi con assign_task lo scarterebbe a terra): ritorno al magazzino come Task corrente. true = ritorno
# assegnato; false = zaino vuoto, individuo ancora occupato, o nessun magazzino (carico a terra).
static func release_orphan_cargo(individual: HumanIndividual, world: World) -> bool:
	if individual == null or individual.carried_resources.is_empty():
		return false
	if individual.current_task != null and not individual.current_task.is_finished():
		return false
	var return_task := build_cargo_return_task(individual, world, false)
	if return_task == null:
		_log(individual, "libero con il carico %s e nessun magazzino lo accetta — a terra." % str(individual.carried_resources.keys()))
		individual.discard_carried_resource()
		return false
	TaskDebugRegistry.on_task_closed(individual.current_task)
	individual.current_task = null
	_assign_as_current(individual, return_task)
	_log(individual, "libero con il carico %s — lo riporta al magazzino." % str(individual.carried_resources.keys()))
	return true


# Task [Walk → Unload] verso la destinazione del carico, SENZA assegnarla. Destinazione:
#   - con `prefer_recipe_workstation` (macellazione): la prima varietà dello zaino che è ingrediente di una ricetta va
#     alla postazione più vicina che la accetta (WarehouseSelectionService.find_nearest_recipe_workstation);
#   - altrimenti, o se nessuna postazione va bene: il magazzino più vicino (find_best) per la prima varietà che un
#     magazzino accetta.
# L'Unload deposita tutto ciò che la destinazione accetta; il resto segue il re-routing normale di UnloadAction, che
# con la preferenza nel context del ritorno la rispetta anche lui. null = zaino vuoto o nessuna destinazione.
static func build_cargo_return_task(individual: HumanIndividual, world: World, prefer_recipe_workstation: bool = false) -> Task:
	if individual == null or world == null or individual.carried_resources.is_empty():
		return null
	var reachable := PathfindingService.reachability_for(individual)
	var destination: Building = null
	if prefer_recipe_workstation:
		for raw_name in individual.carried_resources.keys():
			destination = WarehouseSelectionService.find_nearest_recipe_workstation(
				world, individual.position, individual.home_macro_coords, String(raw_name), 1, [], reachable
			)
			if destination != null:
				break
	if destination == null:
		for raw_name in individual.carried_resources.keys():
			var carried_name := String(raw_name)
			destination = WarehouseSelectionService.find_best(
				world, individual.position, individual.home_macro_coords, carried_name,
				individual.get_carried_quantity(carried_name), [], reachable
			)
			if destination != null:
				break
	if destination == null:
		return null
	var steps: Array[Action] = [
		WalkAction.new(MaterialSupplyService.building_point(individual, destination)),
		UnloadAction.new(destination, UnloadAction.DepositKind.RESOURCE),
	]
	var task := Task.new(steps)
	task.task_name = "task_unload_resource_name"
	task.step_descriptions = ["task_unload_resource_step_walk", "task_unload_resource_step_unload"]
	task.is_suspendable = true
	task.context[CONTEXT_CARGO_RETURN] = true
	if prefer_recipe_workstation:
		task.context[HumanIndividualActionService.CONTEXT_PREFER_RECIPE_WORKSTATION] = true
	return task


# Assegnazione diretta come Task corrente, senza assign_task (che con lo zaino carico riprenderebbe dalla coda la Task
# "proprietaria del carico" al posto del ritorno). current_task deve essere già null.
static func _assign_as_current(individual: HumanIndividual, return_task: Task) -> void:
	connect_unload_signals(individual, return_task)
	individual.current_task = return_task
	TaskDebugRegistry.on_task_assigned(individual, return_task)
	return_task.get_current_action().activate(individual, return_task.context)


static func connect_unload_signals(individual: HumanIndividual, return_task: Task) -> void:
	if not unload_signal_connector.is_valid():
		return
	for step in return_task.steps:
		if step is UnloadAction:
			unload_signal_connector.call(step as UnloadAction, individual)


static func _log(individual: HumanIndividual, message: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[CARGO RETURN] #%d %s: %s" % [individual.id, individual.name, message])
