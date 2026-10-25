class_name ProduceJobProvider
extends RefCounted

# Fornitore "ordini di produzione" della lista dei lavori (2026-10-09; spostato da GameScene il 2026-10-17, refactoring
# GameScene blocco 2d): un lavoro per ogni ordine di una workstation (produce:<id edificio>:<chiave ordine>), "In coda"
# se nessuno lo lavora, "In corso" altrimenti. Escluse le ricette ad avanzamento automatico (come la scheda "In sospeso").
# Con l'edificio al completo (ordini con un lavoratore = production_concurrent_orders) gli ordini senza lavoratore restano
# visibili ma non prendibili ("Edificio occupato"), finché un ordine dell'edificio non finisce. Attrezzi controllati
# prima e in sola lettura (rejection); il materiale mancante no (c'è già l'avviso nella campanella). Assegnazione (la
# riassegnazione del bottone "Assegna" del pannello), X e Rimetti in coda restano alla scena.

# Ordini di produzione dopo corpi, edifici, mucchi e uscite piene nelle righe del cassetto.
const SORT_OFFSET: float = 3000000.0


static func collect(ctx: GameContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	# Ordini con un lavoratore per edificio (id -> quanti), dalle chiavi "id:ordine" di JobWorkScanService.collect_assignments.
	var busy_counts: Dictionary = {}
	for claimed_key in assigned["produce"].keys():
		var building_id := int(String(claimed_key).get_slice(":", 0))
		busy_counts[building_id] = int(busy_counts.get(building_id, 0)) + 1
	for building in ctx.world.buildings:
		if building.is_demolished or building.rules == null or building.is_out_of_service():
			continue
		if not building.is_complete or not building.rules.is_workstation or building.production_progress.is_empty():
			continue
		var building_name := GameContext.tr_text(building.rules.building_name)
		var is_full := ProductionService.has_max_concurrent_orders(building, int(busy_counts.get(building.id, 0)))
		var order_index := 0
		for order_key in ProductionService.get_order_keys(building):
			order_index += 1
			# Cottura di un rito sociale (2026-10-14): la fa il rito, non è un lavoro della coda.
			if ProductionService.is_order_reserved(building, order_key):
				continue
			var recipe := ProductionService.get_order_recipe(building, order_key)
			var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe)
			if recipe_rules != null and recipe_rules.recipe_auto_progress_days > 0:
				continue
			var units := maxi(ProductionService.get_order_units(building, order_key), 1)
			var is_assigned: bool = assigned["produce"].has("%d:%s" % [building.id, order_key])
			var recipe_name := IconRegistry.get_resource_display_name(recipe)
			var blocked_reason := ""
			if not is_assigned:
				if is_full:
					blocked_reason = GameContext.tr_text("task_assignment_produce_building_busy")
				else:
					# Attrezzo che l'Attrezzeria non copre (2026-10-11, stessa regola degli ordini di zona): addosso a qualcuno o
					# da prendere in deposito; altrimenti visibile ma non prendibile.
					blocked_reason = ToolFetchService.blocked_reason(
						ctx, BuildingToolkitService.filter_uncovered(building, ToolFetchService.recipe_tool_categories(recipe)), DrawerOrderService.TYPE_PRODUCE
					)
			jobs.append({
				"key": "produce:%d:%s" % [building.id, order_key], "kind": "produce",
				"name": GameContext.tr_text("task_assignment_produce_row").format({"recipe": recipe_name, "quantity": units, "building": building_name}),
				"text": GameContext.tr_text("pending_produce").format({"building": building_name, "product": recipe_name}),
				"log_name": "%s ×%d @ %s #%d" % [recipe, units, building.building_type_name, building.id],
				"icon": {"resource": recipe}, "macro": Vector2i(building.macro_x, building.macro_y),
				"microcell": Vector2i(building.micro_x, building.micro_y), "reach_target": building,
				"entry_kind": "building", "id": building.id, "sort": float(building.id) + SORT_OFFSET + order_index * 0.001,
				"assigned": is_assigned, "hidden": false,
				"blocked_reason": blocked_reason,
				"target": building, "provider": provider, "order_key": order_key, "recipe": recipe,
			})
			# Rimandato per materiale (2026-10-17): resta assegnato, riga in "In coda" col motivo.
			var produce_key := "%d:%s" % [building.id, order_key]
			if assigned["postponed_produce"].has(produce_key) and not assigned["produce_active"].has(produce_key):
				jobs[jobs.size() - 1]["postponed_by"] = assigned["postponed_produce"][produce_key]
	return jobs


# Idoneità alla presa, in silenzio: la stessa Produce Task dell'assegnazione (mai assegnata) passa il controllo di
# idoneità, e ogni categoria di attrezzo che l'Attrezzeria dell'edificio non copre il pipottino ce l'ha già o può
# prenderla in deposito (ToolFetchService.rejection). Senza l'attrezzo il lavoro resta in coda per un altro pipottino.
# Ricetta che l'edificio non sa più fare (2026-10-25, bugfix — ordine di un salvataggio fatto prima che la ricetta
# cambiasse edifici): scartata qui, altrimenti vinceva la scelta e assign_produce la rifiutava, mandando tutti in svago.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var building: Building = job["target"]
	var order_key := String(job["order_key"])
	if not ProductionService.can_produce_at(building, String(job["recipe"])):
		return "ricetta non producibile in questo edificio"
	var task := TaskBuilderService.build_produce_task(
		worker, building, String(job["recipe"]), maxi(ProductionService.get_order_units(building, order_key), 1),
		ProductionService.get_order_deliver_to_warehouse(building, order_key)
	)
	if task == null:
		return "definizione mancante"
	var assign_rejection := worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))
	if assign_rejection != HumanIndividual.ASSIGN_OK:
		return assign_rejection
	var tool_rejection := ToolFetchService.rejection(
		ctx, worker, BuildingToolkitService.filter_uncovered(building, ToolGateService.get_required_categories(task)), DrawerOrderService.TYPE_PRODUCE
	)
	return tool_rejection if tool_rejection != "" else HumanIndividual.ASSIGN_OK


static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	var worker: Variant = JobWorkScanService.production_order_workers(ctx.individuals, job["target"]).get(String(job["order_key"]))
	if worker != null:
		result.append(worker as HumanIndividual)
	return result
