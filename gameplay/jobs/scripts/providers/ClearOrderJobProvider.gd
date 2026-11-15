class_name ClearOrderJobProvider
extends RefCounted

# Fornitore "sgombero della microcella" della lista dei lavori (2026-11-15, richiesta utente — vedi ClearOrderService):
# per ogni microcella segnata con piante, ClearOrderService.jobs_for lavori ("clear_cut:<mx>:<my>:<x>:<y>:<n>"),
# ciascuno una serie "taglia tutto qui" da ClearOrderService.CHUNK piante per chiunque abbia l'ascia (addosso o da
# prendere in deposito). Chi ha una serie di cella su quella microcella (SiteCutService.all_cell_claimers) tiene uno dei
# lavori: il primo al primo, il secondo al secondo. Microcella viva senza più piante: il segno si toglie qui.
# Tipo "clear_cut": nelle priorità conta come il Taglio (JobBoardService.PRIORITY_KIND_BY_KIND). Assegnazione, X e
# Rimetti in coda restano alla scena.
# Roccia (collect_rock, tipo "clear_quarry", conta come la Cava): un lavoro ogni CHUNK estrazioni rimaste, ciascuno una
# serie da CHUNK estrazioni sulla roccia per chiunque abbia il piccone; chi ha già un'estrazione su quella roccia
# (ClearOrderService.rock_claimers) tiene uno dei lavori. Roccia esaurita: il segno si toglie qui. Lo stesso per l'argilla
# (KIND_CLAY, scavi sul giacimento, stesso tipo di lavoro).

const KIND := "clear_cut"
const ROCK_KIND := "clear_quarry"
const SORT_OFFSET: float = 4500000.0


static func job_key(macro_coords: Vector2i, lot: Vector2i, index: int, kind: String = KIND) -> String:
	return "%s:%d:%d:%d:%d:%d" % [kind, macro_coords.x, macro_coords.y, lot.x, lot.y, index]


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null or ctx.game_data.clear_orders.is_empty():
		return jobs
	var tool_blocked := ToolFetchService.blocked_reason(ctx, ClearOrderService.TOOL_CATEGORIES, ClearOrderService.AGE_KIND)
	var claimers_by_cell := SiteCutService.all_cell_claimers(ctx.individuals)
	var emptied: Array[Dictionary] = []
	var order_index := 0
	for order in ctx.game_data.clear_orders.values():
		order_index += 1
		if String(order.get("kind", "")) != ClearOrderService.KIND_PLANTS:
			continue
		var macro := ClearOrderService.order_macro(order)
		var lot := ClearOrderService.order_lot(order)
		if not ctx.live_cells.has(macro):
			continue
		var plant_count := ClearOrderService.count_plants(ctx.live_cells, macro, lot)
		var claimers: Array = claimers_by_cell.get(Vector4i(macro.x, macro.y, lot.x, lot.y), [])
		if plant_count <= 0 and claimers.is_empty():
			emptied.append(order)
			continue
		var job_count := maxi(ClearOrderService.jobs_for(plant_count), claimers.size())
		var name := GameContext.tr_text("job_clear_plants").format({"count": plant_count})
		for i in range(job_count):
			var job_claimers: Array[HumanIndividual] = []
			if i < claimers.size():
				job_claimers.append(claimers[i] as HumanIndividual)
			jobs.append({
				"key": job_key(macro, lot, i), "kind": KIND, "name": name, "text": name,
				"log_name": "sgombero della microcella %s in %s, lavoro %d" % [str(lot), str(macro), i + 1],
				"icon": {"command": "cut"}, "macro": macro, "microcell": lot,
				"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": lot.x, "micro_y": lot.y},
				"entry_kind": "clear_order", "id": order_index, "sort": SORT_OFFSET + float(order_index) + float(i) * 0.01,
				"assigned": not job_claimers.is_empty(), "hidden": false,
				# Più lavori che piante libere (le altre le stanno già tagliando): niente da prendere per ora.
				"blocked_reason": "" if not job_claimers.is_empty() else tool_blocked,
				"target": order, "cell": lot, "provider": provider, "claimers": job_claimers,
			})
	for order in emptied:
		ClearOrderService.unmark(ctx.game_data, ClearOrderService.order_macro(order), ClearOrderService.order_lot(order))
	return jobs


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): età e ascia (addosso o in un
# deposito raggiungibile), una pianta libera e raggiungibile sulla microcella, il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var tool_rejection := ToolFetchService.rejection(ctx, worker, ClearOrderService.TOOL_CATEGORIES, ClearOrderService.AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var plant := ClearOrderService.pick_plant(ctx, worker, job["macro"], job["cell"])
	if plant.is_empty():
		return "nessuna pianta libera e raggiungibile"
	var probe := TaskBuilderService.build_cut_task(worker, plant, -1, {})
	if probe == null:
		return "nessuna pianta libera e raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func collect_rock(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null or ctx.game_data.clear_orders.is_empty():
		return jobs
	var tool_blocked := ToolFetchService.blocked_reason(ctx, ClearOrderService.ROCK_TOOL_CATEGORIES, ClearOrderService.ROCK_AGE_KIND)
	var emptied: Array[Dictionary] = []
	var order_index := 0
	for order in ctx.game_data.clear_orders.values():
		order_index += 1
		var kind := String(order.get("kind", ""))
		if kind != ClearOrderService.KIND_ROCK and kind != ClearOrderService.KIND_CLAY:
			continue
		var source := ClearOrderService.source_of(kind)
		var macro := ClearOrderService.order_macro(order)
		var lot := ClearOrderService.order_lot(order)
		if not ctx.live_cells.has(macro):
			continue
		var extractions := ClearOrderService.count_extractions(ctx.live_cells, macro, lot, source)
		var claimers := ClearOrderService.rock_claimers(ctx.individuals, macro, lot, source)
		if extractions <= 0 and claimers.is_empty():
			emptied.append(order)
			continue
		var job_count := maxi(ClearOrderService.jobs_for(extractions), claimers.size())
		var name := GameContext.tr_text("job_clear_clay" if kind == ClearOrderService.KIND_CLAY else "job_clear_rock").format({"count": extractions})
		for i in range(job_count):
			var job_claimers: Array[HumanIndividual] = []
			if i < claimers.size():
				job_claimers.append(claimers[i])
			jobs.append({
				"key": job_key(macro, lot, i, ROCK_KIND), "kind": ROCK_KIND, "name": name, "text": name,
				"log_name": "sgombero (%s) %s in %s, lavoro %d" % [kind, str(lot), str(macro), i + 1], "source": source,
				"icon": {"command": "quarry"}, "macro": macro, "microcell": lot,
				"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": lot.x, "micro_y": lot.y},
				"entry_kind": "clear_order", "id": order_index, "sort": SORT_OFFSET + float(order_index) + float(i) * 0.01,
				"assigned": not job_claimers.is_empty(), "hidden": false,
				"blocked_reason": "" if not job_claimers.is_empty() else tool_blocked,
				"target": order, "cell": lot, "provider": provider, "claimers": job_claimers,
			})
	for order in emptied:
		ClearOrderService.unmark(ctx.game_data, ClearOrderService.order_macro(order), ClearOrderService.order_lot(order))
	return jobs


# Come rejection, per la roccia: età e piccone, roccia ancora in piedi e raggiungibile, il compito di prova.
static func rejection_rock(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var tool_rejection := ToolFetchService.rejection(ctx, worker, ClearOrderService.ROCK_TOOL_CATEGORIES, ClearOrderService.ROCK_AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var macro: Vector2i = job["macro"]
	var lot: Vector2i = job["cell"]
	var source := String(job.get("source", ExtractionSourceService.SOURCE_ROCK))
	if ClearOrderService.count_extractions(ctx.live_cells, macro, lot, source) <= 0:
		return "roccia o argilla esaurita"
	if not HaulZoneService.is_cell_reachable(worker, macro, lot):
		return "roccia non raggiungibile"
	var probe := TaskBuilderService.build_quarry_task(worker, macro, lot, -1, {}, source)
	if probe == null:
		return "roccia non raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result
