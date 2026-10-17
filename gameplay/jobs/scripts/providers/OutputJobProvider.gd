class_name OutputJobProvider
extends RefCounted

# Fornitore "uscite piene" della lista dei lavori (2026-10-08; spostato da GameScene il 2026-10-17, refactoring GameScene
# blocco 2b): consegna dei Prodotti finiti a magazzino (output:<id edificio>). In coda quando una workstation con Prodotti
# finiti (posti > 0) ha un ordine fermo perché non c'è posto per il prossimo pezzo (ProductionService.is_output_blocking,
# lo stesso blocco dell'avviso "Prodotti finiti pieni"), oppure (2026-10-17) senza ordini attivi quando l'uscita è così
# piena che almeno una ricetta non ci starebbe (ProductionService.blocks_new_orders: altrimenti non si potrebbe ordinare
# niente e nessuno la svuoterebbe); esce appena l'uscita ha di nuovo posto o l'ordine può ripartire. Tutta la lista si
# spegne con la regola "Svuota le uscite piene" (UserOptions.job_board_empty_full_outputs). Chi lo prende (un pipottino
# libero qualunque) fa la task deliver_output.tres (TaskBuilderService.build_output_job_task): cammino all'edificio e lo
# stesso step di consegna di "Porta al deposito", poi la ricerca del magazzino di sempre accoda cammino e scarico. Se dopo
# il viaggio l'ordine è ancora fermo, il lavoro rientra in coda da solo (ricalcolo a ogni giro). Assegnato = una task, in
# corso o in coda, con TaskBuilderService.CONTEXT_OUTPUT_JOB_BUILDING_ID di quell'edificio. Nascosto mentre il pipottino
# dell'ordine fa già la sua consegna a metà ordine (ProduceAction.CONTEXT_OUTPUT_DELIVERY_ROUND). Nessun magazzino che
# accetta il prodotto (cercato dalla posizione dell'edificio): visibile ma non prendibile, come i mucchi. Assegnazione, X e
# Rimetti in coda restano alla scena.

# Uscite piene dopo corpi, edifici e mucchi nelle righe del cassetto.
const SORT_OFFSET: float = 2000000.0


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if not UserOptions.job_board_empty_full_outputs or ctx.world == null:
		return jobs
	var claims := _collect_claims(ctx.individuals)
	var self_delivering := _collect_delivery_rounds(ctx.individuals)
	for building in ctx.world.buildings:
		if not is_job_needed(building):
			continue
		var is_assigned := claims.has(building.id)
		var resource_name := job_resource(building)
		var building_name := GameContext.tr_text(building.rules.building_name)
		var job_name := GameContext.tr_text("pending_output_delivery").format({
			"building": building_name,
			"used": ProductionService.get_output_used(building), "capacity": ProductionService.get_output_capacity(building),
		})
		if ProductionService.get_output_capacity(building) <= 0:
			job_name = GameContext.tr_text("pending_output_delivery_rack").format({"building": building_name})
		jobs.append({
			"key": "output:%d" % building.id, "kind": "output", "name": job_name, "text": job_name,
			"log_name": "uscita di %s #%d" % [building.building_type_name, building.id],
			"icon": {"command": "transport"}, "macro": Vector2i(building.macro_x, building.macro_y),
			"microcell": Vector2i(building.micro_x, building.micro_y), "reach_target": building,
			"entry_kind": "building", "id": building.id, "sort": float(building.id) + SORT_OFFSET,
			"assigned": is_assigned, "hidden": not is_assigned and self_delivering.has(building.id),
			"blocked_reason": "" if is_assigned or _has_storage(ctx.world, building, resource_name) else GameContext.tr_text("task_assignment_pile_no_storage"),
			"target": building, "provider": provider, "claimers": claims.get(building.id, []), "resource_name": resource_name,
		})
	return jobs


# Workstation completa con Prodotti finiti (posti > 0) e uscita che blocca: un ordine in corso senza posto per il prossimo
# pezzo, oppure (2026-10-17) nessun ordine e almeno una ricetta che non ci starebbe. Dal 2026-10-11 anche una postazione
# senza uscita (l'essiccatoio) piena: nessun posto per i suoi ingredienti e prodotti pronti nel suo magazzino
# (_rack_full_with_products).
static func is_job_needed(building: Building) -> bool:
	if building == null or building.rules == null or building.is_demolished or building.is_out_of_service():
		return false
	if not building.is_complete or not building.rules.is_workstation:
		return false
	if ProductionService.get_output_capacity(building) <= 0:
		return _rack_full_with_products(building)
	if ProductionService.has_active_production(building):
		return ProductionService.is_output_blocking(building)
	return ProductionService.blocks_new_orders(building)


# Postazione senza uscita piena: almeno un ingrediente delle sue ricette ad avanzamento automatico non ha più posto (ogni
# tipo occupa un posto suo: un prodotto pronto può togliere il posto alla pelle mentre la carne ha ancora il suo), e
# almeno un prodotto pronto (risorsa del suo magazzino che non è suo ingrediente né combustibile) da portare via.
static func _rack_full_with_products(building: Building) -> bool:
	if _rack_ready_product(building) == "":
		return false
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if rules == null or rules.recipe_auto_progress_days <= 0 or not rules.recipe_workstation_types.has(building.building_type_name):
			continue
		for input_name in rules.recipe_inputs.keys():
			if BuildingStorageService.get_max_depositable(building, String(input_name)) <= 0:
				return true
	return false


# Prodotto pronto più numeroso nel magazzino di una postazione senza uscita (non ingrediente né combustibile), "" se nessuno.
static func _rack_ready_product(building: Building) -> String:
	var best_name := ""
	var best_count := 0
	for raw_name in building.stored_resources.keys():
		var name := String(raw_name)
		if ProductionService.is_workstation_ingredient(building, name):
			continue
		var count := int((building.stored_resources[raw_name] as Dictionary).get("quantity", 0))
		if count > best_count or (count == best_count and count > 0 and name < best_name):
			best_count = count
			best_name = name
	return best_name


# Risorsa da portare via: quella con più pezzi nei Prodotti finiti (a parità, in ordine di nome); per una postazione senza
# uscita, il prodotto pronto più numeroso nel suo magazzino.
static func job_resource(building: Building) -> String:
	if ProductionService.get_output_capacity(building) <= 0:
		return _rack_ready_product(building)
	var best_name := ""
	var best_count := 0
	for raw_name in building.production_output.keys():
		var count := int(building.production_output[raw_name])
		if count > best_count or (count == best_count and count > 0 and String(raw_name) < best_name):
			best_count = count
			best_name = String(raw_name)
	return best_name


# Un magazzino (diverso dall'edificio) accetta almeno un pezzo della risorsa, cercato dalla posizione dell'edificio
# (nessun pipottino né raggiungibilità: quelli si rifanno alla presa, rejection).
static func _has_storage(world: World, building: Building, resource_name: String) -> bool:
	if resource_name == "":
		return false
	var excluded_ids: Array[int] = [building.id]
	return WarehouseSelectionService.find_best(
		world, Vector2(building.micro_x, building.micro_y) + Vector2(0.5, 0.5), Vector2i(building.macro_x, building.macro_y),
		resource_name, 1, excluded_ids
	) != null


# Chi ha in carico quale uscita: id edificio -> Array[HumanIndividual], dalle task (in corso o in coda, non concluse)
# con TaskBuilderService.CONTEXT_OUTPUT_JOB_BUILDING_ID.
static func _collect_claims(individuals: Array[HumanIndividual]) -> Dictionary:
	var claims: Dictionary = {}
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			if not task.context.has(TaskBuilderService.CONTEXT_OUTPUT_JOB_BUILDING_ID):
				continue
			var building_id := int(task.context[TaskBuilderService.CONTEXT_OUTPUT_JOB_BUILDING_ID])
			if not claims.has(building_id):
				claims[building_id] = []
			if not (claims[building_id] as Array).has(member):
				(claims[building_id] as Array).append(member)
	return claims


# Edifici la cui uscita sta già venendo svuotata dal pipottino dell'ordine (consegna a metà ordine): id -> true.
static func _collect_delivery_rounds(individuals: Array[HumanIndividual]) -> Dictionary:
	var rounds: Dictionary = {}
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			if task.context.has(ProduceAction.CONTEXT_OUTPUT_DELIVERY_ROUND):
				rounds[int(task.context[ProduceAction.CONTEXT_OUTPUT_DELIVERY_ROUND])] = true
	return rounds


# Idoneità alla presa: edificio in una macrocella viva, la consegna di prova passa il controllo di idoneità, e dal
# pipottino un magazzino raggiungibile accetta la risorsa (lo stesso controllo dello step di consegna).
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var building: Building = job["target"]
	var resource_name := String(job.get("resource_name", ""))
	var task: Task = null
	if ctx.live_cells.has(Vector2i(building.macro_x, building.macro_y)):
		task = TaskBuilderService.build_output_job_task(worker, building, resource_name)
	if task == null:
		return "edificio non in una macrocella attiva"
	var assign_rejection := worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))
	if assign_rejection != HumanIndividual.ASSIGN_OK:
		return assign_rejection
	var excluded_ids: Array[int] = [building.id]
	if not worker.can_carry_one_unit_when_empty(resource_name) or WarehouseSelectionService.find_best(
		ctx.world, worker.position, worker.home_macro_coords, resource_name, 1, excluded_ids, PathfindingService.reachability_for(worker)
	) == null:
		return "nessun magazzino raggiungibile"
	return HumanIndividual.ASSIGN_OK


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result
