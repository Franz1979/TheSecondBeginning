class_name ZoneOrderCommandService
extends RefCounted

# Ordini di zona della coda: Taglia, Estrai, Raccogli, Caccia (2026-10-24, refactoring GameScene 5B.6 — prima
# GameScene._assign_drawer_cut_job, _release_drawer_zone_order, _start_zone_order_tool_fetch e _start_towed_fetch). Senza
# stato: avvisi, icone, collegamenti dei segnali e pannelli passano dagli effetti. In scena restano lo strato
# dell'ordine nel cassetto (valori ricordati, scelta della zona) e la creazione dell'ordine.


# Presa: la serie del comando di oggi, in silenzio, con l'id dell'ordine nella serie; solo se il pipottino ha davvero la
# task l'ordine diventa "preso". Attrezzi da prendere in deposito decisi prima, partono dopo l'assegnazione.
static func assign_drawer_zone_job(ctx: GameContext, worker: HumanIndividual, job: Dictionary, effects: GameEffects) -> void:
	var order: Dictionary = job["order"]
	var order_type := String(order.get("type", DrawerOrderService.TYPE_CUT))
	var order_id := int(order["id"])
	if DrawerOrderService.find(ctx.game_data, order_id).is_empty() or bool(order.get("taken", false)):
		return
	# Taglio/estrazione (2026-10-23), raccolta e caccia (2026-10-24): il bersaglio scelto dall'ordine
	# (DrawerOrderTargetService).
	var pick: Dictionary = {}
	if DrawerOrderTargetService.uses_order_target(order_type):
		if DrawerOrderTargetService.ensure_target(ctx, order):
			pick = DrawerOrderTargetService.get_pick(ctx, order)
	else:
		pick = DrawerOrderJobProvider.pick_zone_target(ctx, worker, job)
	if pick.is_empty():
		return
	var area: WorkArea = pick["area"]
	var fetch_plan := ToolFetchService.plan_fetch(ctx.world, worker, DrawerOrderService.tool_categories(order_type))
	var series: Dictionary = {}
	if order_type == DrawerOrderService.TYPE_GATHER:
		var trips := maxi(int(order.get("count", 1)), 1)
		TransportCommandService.assign_work_area_gather(ctx, worker, area, {
			"kind": int(order.get("criterion_kind", PickUpAction.CriterionKind.ALL)),
			"category": int(order.get("criterion_category", -1)), "resource_name": String(order.get("resource_name", "")),
			"repeat": trips > 1, "trips": trips, "stock_fill": order.has(StockRequestService.ORDER_KEY),
		}, true, order_id, effects)
	elif order_type == DrawerOrderService.TYPE_HUNT:
		# Cacce del gestore scorte (2026-10-19): la coppia della regola, letta adesso (anche per gli ordini nati prima).
		var hunt_destination := String(order.get("butcher_destination", ""))
		if order.has(StockRequestService.ORDER_KEY):
			hunt_destination = WarehouseManagerService.stock_hunt_destination(ctx)
		series = HuntZoneService.make_meat_series(
			area.id, maxi(int(order.get("count", 1)), 1), hunt_destination,
			int(order.get("zone_id", -1)) < 0
		)
		series[DrawerOrderService.SERIES_KEY] = order_id
		HuntCommandService.assign_work_area_hunt(ctx, worker, area, series, true, not fetch_plan.is_empty(), effects)
	elif order_type == DrawerOrderService.TYPE_QUARRY:
		series = QuarryZoneService.make_series(area.id, maxi(int(order.get("count", 1)), 1))
		series[DrawerOrderService.SERIES_KEY] = order_id
		ExtractionCommandService.assign_quarry(ctx, worker, pick["rock"], area.id, series, true, effects)
	else:
		series = CutZoneService.make_series(area.id, maxi(int(order.get("count", 1)), 1))
		series[DrawerOrderService.SERIES_KEY] = order_id
		if DrawerOrderService.order_cut_yield(order) != "":
			series[CutZoneService.SERIES_YIELD_KEY] = DrawerOrderService.order_cut_yield(order)
		ExtractionCommandService.assign_cut(ctx, worker, pick["plant"], area.id, series, true, effects)
	for task in JobWorkScanService.open_tasks(worker):
		if DrawerOrderService.order_of_task(task) == order_id:
			order["taken"] = true
			order["started"] = true
			order["done_seen"] = 0
			# Da qui il bersaglio lo prenota la CutAction/QuarryAction del pipottino (2026-10-23).
			DrawerOrderTargetService.clear_target(order)
			# L'avviso "nessuna preda" sparisce quando l'ordine riprende.
			order.erase(HuntOrderService.NO_PREY_KEY)
			var job_keys: Array[String] = [String(job["key"])]
			CommandFeedback.forget_job_board_waits(ctx.game_data, job_keys, effects)
			start_tool_fetch(ctx, worker, fetch_plan, order_id, effects)
			# Travois (2026-10-23): serie di più viaggi -> lo prende prima, se ce n'è uno libero. Caccia esclusa (si
			# insegue la preda). Serie di raccolta: "stessi viaggi, più roba" (ogni viaggio porta di più, il numero non
			# cambia). Ipotesi b, per il futuro: un viaggio col travois conta come più viaggi in proporzione al carico,
			# così la serie finisce prima.
			if order_type != DrawerOrderService.TYPE_HUNT and int(order.get("count", 1)) > 1:
				start_towed_fetch(ctx, worker, order_id, effects)
			return


# Toglie un ordine di zona preso a chi lo porta (Rimetti in coda, Blocca, X, H): la Task in corso con l'effetto di H
# (regola del carico, "salta la lista una volta", ripresa con resolve_idle_individual), quelle in coda tolte (o
# sostituite dal ritorno del carico, se lo possiedono); l'ordine torna in coda con quello che resta, la stessa scelta e
# la stessa zona. I ritorni del carico nati qui sono marcati (DrawerOrderService.CARGO_KEY): niente riga "Diretto".
static func release_drawer_zone_order(ctx: GameContext, order: Dictionary, effects: GameEffects) -> void:
	var order_id := int(order["id"])
	var claim: Dictionary = DrawerOrderService.collect_zone_claims(ctx.individuals).get(order_id, {})
	order["done_seen"] = maxi(int(order.get("done_seen", 0)), int(claim.get("done", 0)))
	DrawerOrderService.return_order(ctx, order)
	for member in ctx.individuals:
		var current_closed := false
		var current := member.current_task
		if current != null and not current.is_finished() and DrawerOrderService.order_of_task(current) == order_id:
			member.skip_job_board_once = true
			if CargoReturnService.release_cargo(member, current, ctx.world) != CargoReturnService.Outcome.RETURNING:
				member.stop(false)
				current_closed = true
			elif member.current_task != null:
				member.current_task.context[DrawerOrderService.CARGO_KEY] = true
		for queued in member.task_queue.duplicate():
			var queued_task := queued as Task
			if queued_task != null and DrawerOrderService.order_of_task(queued_task) == order_id:
				var queue_index := member.task_queue.find(queued)
				if CargoReturnService.release_cargo(member, queued_task, ctx.world) != CargoReturnService.Outcome.RETURNING:
					member.task_queue.erase(queued)
				elif queue_index >= 0 and queue_index < member.task_queue.size() and member.task_queue[queue_index] != null:
					(member.task_queue[queue_index] as Task).context[DrawerOrderService.CARGO_KEY] = true
		if current_closed:
			HumanIndividualActionService.resolve_idle_individual(member, ctx.age_band_of(member), ctx.world)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Prelievi in deposito prima del lavoro appena assegnato (ToolFetchService.start_fetch): segnali delle task di prelievo
# (griglia del magazzino) e pannello.
static func start_tool_fetch(ctx: GameContext, worker: HumanIndividual, plan: Array[Dictionary], work_label: Variant, effects: GameEffects) -> void:
	for task in ToolFetchService.start_fetch(ctx, worker, plan, work_label):
		effects.wire_storage_task(task, worker)
	effects.refresh_panel(GameEffects.PanelKind.SELECTED_INDIVIDUAL)


# Presa del travois prima di un lavoro a più viaggi (ToolFetchService.start_towed_fetch): segnali della task.
static func start_towed_fetch(ctx: GameContext, worker: HumanIndividual, work_label: Variant, effects: GameEffects) -> void:
	var task := ToolFetchService.start_towed_fetch(ctx, worker, work_label)
	if task != null:
		effects.wire_storage_task(task, worker)
