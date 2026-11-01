class_name CarcassJobProvider
extends RefCounted

# Fornitore "macellazione" della lista dei lavori (2026-11-01, richiesta utente — cacciatore col solo arco, carcassa
# rimasta a terra): un lavoro per carcassa ("butcher:<id>") per chiunque abbia una lama (addosso o da prendere in deposito),
# come il taglio per i cantieri con l'ascia. La task è quella di sempre (TaskBuilderService.build_butcher_task): macella e
# porta via. Assegnato = qualcuno ha una macellazione di quella carcassa. Solo celle vive. Assegnazione e Rimetti in coda
# restano alla scena.

const SORT_OFFSET: float = 4450000.0
const TOOL_CATEGORIES: Array = [TaskTypes.ToolCategory.BUTCHERING]
# Non è l'età della caccia: niente neonati né bambini (ToolFetchService.age_ok); il resto lo dice il compito di prova.
const AGE_KIND := DrawerOrderService.TYPE_CUT


static func job_key(carcass_id: int) -> String:
	return "butcher:%d" % carcass_id


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null:
		return jobs
	var tool_blocked := ToolFetchService.blocked_reason(ctx, TOOL_CATEGORIES, AGE_KIND)
	var claimers_by_carcass: Dictionary = {}
	var kept_by_hunter: Dictionary = {}
	_scan_tasks(ctx, claimers_by_carcass, kept_by_hunter)
	for pile in ctx.game_data.ground_piles:
		if pile.carcasses.is_empty() or not ctx.live_cells.has(pile.macro_coords):
			continue
		for carcass in pile.carcasses:
			var carcass_id := int(carcass.get("id", -1))
			if kept_by_hunter.has(carcass_id):
				continue
			var claimers: Array[HumanIndividual] = []
			claimers.assign(claimers_by_carcass.get(carcass_id, []))
			var name := GameContext.tr_text("job_butcher").format({
				"species": GameContext.tr_text("animal_species_%s" % String(carcass.get("species", ""))),
			})
			jobs.append({
				"key": job_key(carcass_id), "kind": "butcher", "name": name, "text": name,
				"log_name": "macellazione della carcassa #%d" % carcass_id,
				"icon": {"command": "butcher"}, "macro": pile.macro_coords, "microcell": pile.microcell,
				"reach_target": {
					"macro_x": pile.macro_coords.x, "macro_y": pile.macro_coords.y, "micro_x": pile.microcell.x, "micro_y": pile.microcell.y,
				},
				"entry_kind": "ground_pile", "id": pile.id, "sort": float(carcass_id) + SORT_OFFSET,
				"assigned": not claimers.is_empty(), "hidden": false,
				"blocked_reason": "" if not claimers.is_empty() else tool_blocked,
				"target": pile, "carcass_id": carcass_id, "provider": provider, "claimers": claimers,
			})
	return jobs


# Un giro sulle task aperte: chi ha già una macellazione, per carcassa; e le carcasse che il cacciatore macellerà appena
# recuperata l'arma (ha la lama in cintura, WorkFollowUpService.butcher_after_hunt): niente riga, nessuno gliele toglie.
# Il cacciatore senza lama non le trattiene: la riga c'è subito.
static func _scan_tasks(ctx: GameContext, claimers_by_carcass: Dictionary, kept_by_hunter: Dictionary) -> void:
	for member in ctx.individuals:
		var has_blade := ToolGateService.find_belt_slot_for(member, TaskTypes.ToolCategory.BUTCHERING) != -1
		for task in JobWorkScanService.open_tasks(member):
			for step in task.steps:
				if step is ButcherAction:
					var carcass_id: int = (step as ButcherAction).carcass_id
					if not claimers_by_carcass.has(carcass_id):
						claimers_by_carcass[carcass_id] = []
					if not (claimers_by_carcass[carcass_id] as Array).has(member):
						(claimers_by_carcass[carcass_id] as Array).append(member)
			if has_blade and task.context.has(HuntService.CONTEXT_KILL_CARCASS):
				kept_by_hunter[int((task.context[HuntService.CONTEXT_KILL_CARCASS] as Dictionary).get("id", -1))] = true
	for carcass_id in claimers_by_carcass:
		kept_by_hunter.erase(carcass_id)


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): lama (addosso o in un deposito
# raggiungibile), carcassa ancora a terra, il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var tool_rejection := ToolFetchService.rejection(ctx, worker, TOOL_CATEGORIES, AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var pile: GroundPile = job["target"]
	var carcass_id := int(job["carcass_id"])
	if GroundPileService.find_carcass(ctx.game_data, pile.macro_coords, pile.microcell, carcass_id).is_empty():
		return "carcassa non più a terra"
	var cell: LiveMacroCell = ctx.live_cells.get(pile.macro_coords)
	if cell == null or cell.macro_state == null:
		return "cella della carcassa non disponibile"
	var probe := TaskBuilderService.build_butcher_task(worker, pile, carcass_id, cell.macro_state)
	if probe == null:
		return "carcassa non raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result


# true se `task` deve ancora macellare una carcassa a terra: è la riga di questo lavoro, non un comando diretto.
static func is_butchering_task(task: Task) -> bool:
	for step in task.steps:
		if step is ButcherAction and (step as ButcherAction).is_target_valid():
			return true
	return false
