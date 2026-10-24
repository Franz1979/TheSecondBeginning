class_name ProductionCommandService
extends RefCounted

# Comando di produzione: ordine sull'edificio e Produce Task [Walk → Produce] (2026-10-24, refactoring GameScene 5B.5 —
# prima GameScene._assign_produce_task, _has_max_concurrent_orders, _report_production_orders_full,
# _works_on_production_at). Senza stato: avvisi, icone e pannelli passano dagli effetti. In scena restano griglia delle
# ricette, mirino del lavoratore e coda degli ordini del pannello.


# Costruisce e assegna la Produce Task a `worker` (2026-09-23). Stesso esito visivo della Build: icona di comando se
# assegnata (o accodata), X se rifiutata.
# `existing_order_key` (2026-10-04, riassegnazione): ordine già sull'edificio rimasto senza lavoratore — niente controllo
# dei posti né nuovo ordine; la produzione si lega a quell'ordine, con i pezzi che gli mancano. Dal 2026-10-09 (ordini in
# coda) la riassegnazione usa la consegna salvata nell'ordine e, con l'edificio al completo, viene rifiutata come un
# ordine nuovo. `silent` (presa dalla lista dei lavori): nessun avviso, popup né X; i controlli li ha già fatti
# ProduceJobProvider.rejection.
# `wire_before_assign` (Callable(Task, HumanIndividual)): collegamento dei segnali del rifornimento automatico
# (MaterialSupplyService), chiamato subito prima di assign_task, che può già attivare il primo step — per questo non
# passa dagli effetti, che la scena applica dopo.
static func assign_produce(
	ctx: GameContext, worker: HumanIndividual, building: Building, resource_name: String, quantity: int,
	deliver_to_warehouse: bool, existing_order_key: String, keep_for_building: bool, silent: bool,
	wire_before_assign: Callable, effects: GameEffects
) -> void:
	if existing_order_key != "":
		deliver_to_warehouse = ProductionService.get_order_deliver_to_warehouse(building, existing_order_key)
	# "Tieni per l'edificio" vale solo se il prodotto è un attrezzo e l'Attrezzeria ha posto per lui (2026-10-08,
	# BuildingToolkitService.can_add); altrimenti si ignora e "Consegna al magazzino" resta com'è. Le due si escludono
	# (2026-10-04, Attrezzeria). Riassegnazione di un ordine esistente: vale la scelta già salvata nell'ordine.
	if keep_for_building and existing_order_key == "" and not BuildingToolkitService.can_add(building, resource_name):
		keep_for_building = false
	if keep_for_building:
		deliver_to_warehouse = false
	if worker == null or building == null or not ProductionService.can_produce_at(building, resource_name):
		return
	var is_reassignment := existing_order_key != ""
	if is_reassignment and not ProductionService.has_order(building, existing_order_key):
		return
	if has_max_concurrent_orders(ctx.individuals, building):
		if not silent:
			report_orders_full(worker, building, effects)
			effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	if not is_reassignment and not ProductionService.has_output_room(building, resource_name):
		return
	quantity = clampi(quantity, 1, ProductionService.get_max_order_quantity(building))
	var task := TaskBuilderService.build_produce_task(worker, building, resource_name, quantity, deliver_to_warehouse)
	if task == null:
		return

	var age_band := ctx.age_band_of(worker)
	# Idoneità PRIMA del gate degli attrezzi (2026-09-26): il gate sposta davvero gli attrezzi dallo zaino alla cintura,
	# quindi un individuo non idoneo va rifiutato prima, senza toccare zaino né cintura. Icona sull'edificio, riuscita =
	# Task in corso o in coda.
	var request := AssignRequest.create(worker, task, "task_activity_produce", silent).at_microcell(
		Vector2i(building.macro_x, building.macro_y), Vector2i(building.micro_x, building.micro_y), "produce"
	)
	request.strict = true
	if not AssignService.check(request, age_band, effects):
		if not silent:
			effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	# Controllo attrezzi (2026-09-25): ToolGateService sposta in cintura gli attrezzi necessari presi dallo zaino.
	#   - MISSING_TOOLS: la Task viene ASSEGNATA comunque e resta in attesa all'edificio, come la Build senza materiale —
	#     ProduceAction ricontrolla a ogni tick e parte da sola quando gli attrezzi arrivano. Popup con QUALI attrezzi.
	#   - BELT_FULL/CANNOT_EQUIP: l'attrezzo c'è ma non entra in cintura — la Task NON viene assegnata: avviso, popup e X.
	# Attrezzeria (2026-10-04): l'attrezzo richiesto è soddisfatto se c'è nell'Attrezzeria dell'edificio oppure sul
	# pipottino; al pipottino si chiedono solo le categorie che l'Attrezzeria non copre.
	var tool_gate := ToolGateService.try_satisfy(
		worker, BuildingToolkitService.filter_uncovered(building, ToolGateService.get_required_categories(task)), ctx.game_data
	)
	if tool_gate["result"] == ToolGateService.Result.MISSING_TOOLS:
		if not silent:
			effects.notify(NotificationTypes.NotificationPopupType.TOOL_REQUIRED, GameContext.tr_text("tool_gate_assigned_waiting").format({
				"name": worker.name,
				"tools": ToolFetchService.describe_missing_categories(tool_gate["missing_categories"]),
			}))
	elif tool_gate["result"] != ToolGateService.Result.OK:
		if silent:
			return
		CommandFeedback.tool_gate_failure(worker, tool_gate, effects)
		AssignService.reject_icon(request, effects)
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	worker.tool_gate_warning = ""
	if not tool_gate["equipped"].is_empty():
		# Attrezzi appena spostati dallo zaino alla cintura: il pannello individuo deve mostrarli.
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)

	if wire_before_assign.is_valid():
		wire_before_assign.call(task, worker)
	# ORDINI SEPARATI (2026-10-04): l'ordine nasce qui e occupa subito il posto (liberati prima quelli senza lavoratore);
	# la ProduceAction lavora solo su di lui.
	var order_key := existing_order_key
	var board_enabled := JobBoardService.is_enabled(ctx.folk)
	if is_reassignment:
		ProductionService.set_order_worker_id(building, order_key, worker.id)
	elif board_enabled:
		# Ordini in coda (2026-10-09): con l'idea gli ordini senza lavoratore non vengono mai cancellati per fare posto;
		# il limite vale per gli ordini con un lavoratore, già controllato sopra.
		order_key = ProductionService.create_order(building, resource_name, quantity, worker.id, keep_for_building, deliver_to_warehouse, true)
	else:
		ProductionService.free_slot_from_unclaimed(building, JobWorkScanService.production_order_workers(ctx.individuals, building))
		order_key = ProductionService.create_order(building, resource_name, quantity, worker.id, keep_for_building, deliver_to_warehouse)
	if order_key == "":
		# Con l'idea il limite toccato è quello degli ordini in tutto (coda dell'edificio piena, 2026-10-09).
		if board_enabled:
			CommandFeedback.reject(worker, GameContext.tr_text("produce_reject_queue_full").format({
				"building": building.get_display_name(), "max": ProductionService.get_max_orders(building),
			}), effects)
		else:
			report_orders_full(worker, building, effects)
		AssignService.reject_icon(request, effects)
		effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
		return
	for step in task.steps:
		if step is ProduceAction:
			(step as ProduceAction).order_key = order_key
	# Stesso pipottino già al lavoro su un ordine di questo edificio: il nuovo ordine aspetta nella sua coda.
	var assigned := false
	if works_on_production_at(worker.current_task, building):
		TaskQueueService.push_suspended_task(worker, task)
		assigned = AssignService.finish(request, true, age_band, effects)
	else:
		assigned = AssignService.commit(request, age_band, effects)
	if not assigned:
		# Una riassegnazione fallita lascia l'ordine com'era, senza lavoratore.
		if not is_reassignment:
			ProductionService.cancel_order(building, order_key)
	else:
		# Lavoro assegnato (2026-10-09): esce dalla lista; se ci tornerà, l'attesa per l'assegnazione a mano riparte.
		var job_keys: Array[String] = ["produce:%d:%s" % [building.id, order_key]]
		CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
	JobWorkScanService.reconcile_production_units(ctx.individuals, building)
	# Pulsanti ricetta spenti subito (edificio ora impegnato), senza aspettare il refresh giornaliero.
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_BUILDING)
	if assigned and DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[PRODUCE] Task di produzione '%s' x%d assegnata a #%d %s presso l'edificio #%d." % [resource_name, quantity, worker.id, worker.name, building.id])


# true se l'edificio ha già tante Produce Task assegnate quante ne ammette (BuildingRules.production_concurrent_orders,
# 2026-09-24): stessa regola usata dal pannello per spegnere le ricette. Contano gli ordini con un lavoratore.
static func has_max_concurrent_orders(individuals: Array, building: Building) -> bool:
	return ProductionService.has_max_concurrent_orders(building, JobWorkScanService.production_order_workers(individuals, building).size())


# Avviso di ordine in più rifiutato (2026-10-04): l'edificio ha già tutti gli ordini che può tenere.
static func report_orders_full(worker: HumanIndividual, building: Building, effects: GameEffects) -> void:
	CommandFeedback.reject(worker, GameContext.tr_text("produce_reject_orders_full").format({
		"building": building.get_display_name(), "max": ProductionService.get_max_concurrent_orders(building),
	}), effects)


# true se `task` è una Produce Task non conclusa con un passo di produzione su `building`.
static func works_on_production_at(task: Task, building: Building) -> bool:
	if task == null or task.is_finished() or not JobWorkScanService.PRODUCE_TASK_NAMES.has(task.task_name):
		return false
	for step_index in range(task.current_step_index, task.steps.size()):
		if task.steps[step_index] is ProduceAction and (task.steps[step_index] as ProduceAction).target_building == building:
			return true
	return false
