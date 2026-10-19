class_name SiteCutJobProvider
extends RefCounted

# Fornitore "taglio per il cantiere" della lista dei lavori (2026-10-18, richiesta utente — cantiere nel bosco, vedi
# SiteCutService): per ogni cantiere con alberi o cespugli vivi sul suo ingombro, un lavoro per microcella
# ("site_cut:<id>:<x>:<y>"), il "taglia tutto" di quella cella per chiunque abbia l'ascia (addosso o da prendere in
# deposito). Assegnato = qualcuno ha una serie di cella su quella microcella. Solo celle vive (le piante disegnate sono
# quelle tagliabili). Assegnazione, X e Rimetti in coda restano alla scena.

const SORT_OFFSET: float = 4400000.0


static func job_key(site: Building, cell: Vector2i) -> String:
	return "site_cut:%d:%d:%d" % [site.id, cell.x, cell.y]


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.world == null:
		return jobs
	var tool_blocked := ToolFetchService.blocked_reason(ctx, SiteCutService.TOOL_CATEGORIES, SiteCutService.AGE_KIND)
	for site in ctx.world.buildings:
		if site.is_complete or site.is_demolished or site.rules == null:
			continue
		var macro := Vector2i(site.macro_x, site.macro_y)
		if not ctx.live_cells.has(macro):
			continue
		var cells := SiteCutService.cells_with_plants(ctx.world, site)
		var total := BuildingFootprint.cells_of(site).size()
		var site_name := GameContext.tr_text(site.rules.building_name)
		for i in range(cells.size()):
			var cell := cells[i]
			var claimers := SiteCutService.cell_claimers(ctx.individuals, macro, cell)
			var name := GameContext.tr_text("job_site_cut").format({"building": site_name})
			if total > 1:
				name = GameContext.tr_text("job_site_cut_cell").format({"building": site_name, "index": i + 1, "count": cells.size()})
			jobs.append({
				"key": job_key(site, cell), "kind": "site_cut", "name": name, "text": name,
				"log_name": "taglio del cantiere #%d, cella %s" % [site.id, str(cell)],
				"icon": {"command": "cut"}, "macro": macro, "microcell": cell,
				"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": cell.x, "micro_y": cell.y},
				"entry_kind": "building", "id": site.id, "sort": float(site.id) + SORT_OFFSET + float(i) * 0.01,
				"assigned": not claimers.is_empty(), "hidden": false,
				"blocked_reason": "" if not claimers.is_empty() else tool_blocked,
				"target": site, "cell": cell, "provider": provider, "claimers": claimers,
			})
	return jobs


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): età e ascia (addosso o in un
# deposito raggiungibile), una pianta raggiungibile sulla cella, il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var tool_rejection := ToolFetchService.rejection(ctx, worker, SiteCutService.TOOL_CATEGORIES, SiteCutService.AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var site: Building = job["target"]
	var plant := SiteCutService.pick_plant(ctx, worker, site, job["cell"])
	if plant.is_empty():
		return "nessuna pianta raggiungibile"
	var probe := TaskBuilderService.build_cut_task(worker, plant, -1, {})
	if probe == null:
		return "nessuna pianta raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result
