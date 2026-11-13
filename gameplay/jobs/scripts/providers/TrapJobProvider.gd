class_name TrapJobProvider
extends RefCounted

# Fornitore "Piazza trappola" della lista dei lavori (2026-11-07, capanna del trappoliere — TrapService). Un lavoro per zona
# e tipo di trappola ("trap:<id zona>:<trappola>", un lavoratore) quando la zona ha meno trappole del numero voluto
# (TrapService.target_for, montate più in viaggio), un edificio ne ha una pronta (Prodotti finiti della capanna o magazzino)
# e nella zona c'è un posto che vale (TrapService.choose_site). Finita una, se ne mancano ancora ricompare. Chi lo prende va
# all'edificio più vicino al posto, prende la trappola e la monta (place_trap.tres). Assegnazione alla scena.
# Svuotamento (2026-11-07): nello stesso tipo di lavoro "trap", un lavoro per trappola montata che va svuotata
# (TrapService.needs_emptying), "trap:empty:<id>" (il tipo è il prefisso della chiave: JobBoardService.get_kind), un lavoratore: va alla trappola, la svuota (EmptyTrapAction) e porta le
# prede dove va la carne delle cacce del gestore scorte (GameData.stock_excess_meat_destination). Le voci hanno
# "job_type" = JOB_PLACE o JOB_EMPTY.

const JOB_PLACE := "place"
const JOB_EMPTY := "empty"
# Giro delle reti di una zona (2026-11-07): "trap:round:<id zona>", un lavoratore, quando una trappola della zona va
# svuotata; chi lo prende passa da tutte quelle della zona con prede (le più vicine prima, finché la resa sta nello zaino)
# e consegna una volta sola. Le trappole fuori zona (piazzate a mano) restano col lavoro di una sola (JOB_EMPTY).
const JOB_ROUND := "round"
# Età per lo svuotamento col coltello (2026-11-09): come la macellazione, niente neonati né bambini.
const EMPTY_AGE_KIND := DrawerOrderService.TYPE_CUT
const ROUND_ZONE_JOBS: Array[String] = ["hunt", "fish"]
# Nome e descrizione del giro per lavoro di zona.
const ROUND_TEXT_KEYS := {
	"hunt": ["task_empty_trap_round_job_name", "task_empty_trap_round_job_tooltip"],
	"fish": ["task_empty_fish_trap_round_job_name", "task_empty_fish_trap_round_job_tooltip"],
}


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null:
		return jobs
	for trap_name in TrapService.list_trap_names():
		var has_source := WarehouseSelectionService.has_retrieval_source(ctx.world, trap_name)
		# Vincolo di piazzamento (2026-11-12, cesto a caduta senza tettoia delle gabbie): il lavoro si vede, con la X rossa.
		var placement_blocked := TrapService.placement_blocked_reason(ctx.world, trap_name)
		for area in ctx.game_data.work_areas:
			var job := {"area_id": area.id, "trap_name": trap_name}
			var is_assigned := not workers(ctx, job).is_empty()
			if not is_assigned:
				var target := TrapService.target_for(ctx.game_data, area, trap_name)
				if target <= 0 or not has_source:
					continue
				if TrapService.count_for_area(ctx.game_data, ctx.individuals, area, trap_name) >= target:
					continue
			var site := TrapService.choose_site(ctx.game_data, ctx.world, ctx.individuals, area, trap_name)
			if site == TrapService.NO_SITE and not is_assigned:
				continue
			var display_name := IconRegistry.get_resource_display_name(trap_name)
			var microcell := site if site != TrapService.NO_SITE else area.rect.get_center()
			# Attrezzi per montarla (2026-11-11, fossa col piccone): come lo svuotamento, presi in deposito.
			var setup_tools := TrapService.setup_tool_categories(trap_name)
			var place_blocked := "" if is_assigned or setup_tools.is_empty() else ToolFetchService.blocked_reason(ctx, setup_tools, EMPTY_AGE_KIND)
			if not is_assigned and placement_blocked != "":
				place_blocked = placement_blocked
			jobs.append({
				"key": "trap:%d:%s" % [area.id, trap_name], "kind": "trap",
				"name": GameContext.tr_text("task_place_trap_job_name").format({"trap": display_name, "area": area.name}),
				"text": GameContext.tr_text("task_place_trap_job_tooltip").format({"trap": display_name, "area": area.name}),
				"log_name": "piazza %s in zona #%d" % [trap_name, area.id],
				"icon": {"text": IconRegistry.get_command_icon("trap")}, "macro": area.macro_coords, "microcell": microcell,
				"reach_target": {"macro_x": area.macro_coords.x, "macro_y": area.macro_coords.y, "micro_x": microcell.x, "micro_y": microcell.y},
				"entry_kind": "work_area", "id": area.id, "sort": 0.0,
				"assigned": is_assigned, "hidden": false, "blocked_reason": place_blocked,
				"area_id": area.id, "trap_name": trap_name, "site": site, "provider": provider, "job_type": JOB_PLACE,
			})
	var busy := TrapService.trap_ids_being_emptied(ctx.individuals)
	for area in ctx.game_data.work_areas:
		# Un giro per lavoro di zona (2026-11-08): reti con la caccia, nasse con la pesca.
		for zone_job in ROUND_ZONE_JOBS:
			var round_job := {"job_type": JOB_ROUND, "area_id": area.id, "zone_job": zone_job}
			var round_assigned := not workers(ctx, round_job).is_empty()
			var due := 0
			var with_catch := 0
			var with_live := 0
			var first_lot := TrapService.NO_SITE
			var round_macro := area.macro_coords
			for trap in ctx.game_data.placed_traps:
				if trap.work_area_id != area.id or trap.get_caught() <= 0 or busy.has(trap.id) or _zone_job_of(trap) != zone_job:
					continue
				with_catch += 1
				if _has_live_catch(trap):
					with_live += 1
				if TrapService.needs_emptying(ctx.game_data, trap):
					due += 1
					if first_lot == TrapService.NO_SITE:
						first_lot = trap.lot
						round_macro = trap.macro_coords
			if not round_assigned and due == 0:
				continue
			var microcell := first_lot if first_lot != TrapService.NO_SITE else area.rect.get_center()
			var text_keys: Array = ROUND_TEXT_KEYS[zone_job]
			var round_tools := TrapService.round_tool_categories(zone_job)
			var round_blocked := "" if round_assigned or round_tools.is_empty() else ToolFetchService.blocked_reason(ctx, round_tools, EMPTY_AGE_KIND)
			jobs.append({
				"key": "trap:round:%d:%s" % [area.id, zone_job], "kind": "trap",
				"name": GameContext.tr_text(text_keys[0]).format({"area": area.name, "count": with_catch}),
				"text": GameContext.tr_text(text_keys[1]).format({"area": area.name, "count": with_catch}),
				"log_name": "giro delle trappole (%s) in zona #%d" % [zone_job, area.id],
				"icon": {"text": IconRegistry.get_command_icon("trap")}, "macro": round_macro, "microcell": microcell,
				"reach_target": {"macro_x": round_macro.x, "macro_y": round_macro.y, "micro_x": microcell.x, "micro_y": microcell.y},
				"entry_kind": "work_area", "id": area.id, "sort": 0.0,
				"assigned": round_assigned, "hidden": false, "blocked_reason": round_blocked,
				"area_id": area.id, "zone_job": zone_job, "provider": provider, "job_type": JOB_ROUND,
				# Animale vivo in un cesto (2026-11-12, passo B2): dentro le Trappole questo giro passa prima.
				"priority_first": with_live > 0,
			})
	for trap in ctx.game_data.placed_traps:
		if WorkAreaService.find_by_id(ctx.game_data, trap.work_area_id) != null:
			continue
		var job := {"job_type": JOB_EMPTY, "trap_id": trap.id}
		var is_assigned := not workers(ctx, job).is_empty()
		if not is_assigned and not TrapService.needs_emptying(ctx.game_data, trap):
			continue
		var display_name := IconRegistry.get_resource_display_name(trap.trap_name)
		var rules := TrapService.get_rules(trap.trap_name)
		var capacity := rules.trap_capacity if rules != null else 0
		var empty_tools := TrapService.empty_tool_categories(trap.trap_name)
		var empty_blocked := "" if is_assigned or empty_tools.is_empty() else ToolFetchService.blocked_reason(ctx, empty_tools, EMPTY_AGE_KIND)
		jobs.append({
			"key": "trap:empty:%d" % trap.id, "kind": "trap",
			"name": GameContext.tr_text("task_empty_trap_job_name").format({"trap": display_name, "caught": trap.get_caught(), "capacity": capacity}),
			"text": GameContext.tr_text("task_empty_trap_job_tooltip").format({"trap": display_name, "caught": trap.get_caught(), "capacity": capacity}),
			"log_name": "svuota %s #%d" % [trap.trap_name, trap.id],
			"icon": {"text": IconRegistry.get_command_icon("trap")}, "macro": trap.macro_coords, "microcell": trap.lot,
			"reach_target": {"macro_x": trap.macro_coords.x, "macro_y": trap.macro_coords.y, "micro_x": trap.lot.x, "micro_y": trap.lot.y},
			"entry_kind": "work_area", "id": trap.work_area_id, "sort": 0.0,
			"assigned": is_assigned, "hidden": false, "blocked_reason": empty_blocked,
			"trap_id": trap.id, "trap_name": trap.trap_name, "provider": provider, "job_type": JOB_EMPTY,
		})
	return jobs


# Motivo per cui `worker` non potrebbe prendere il lavoro (HumanIndividual.ASSIGN_OK se può).
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	# Spazio (2026-11-07, come i materiali dei cantieri): chi non porta la trappola a zaino vuoto non prende il piazzamento.
	var trap_name := String(job.get("trap_name", ""))
	if String(job.get("job_type", JOB_PLACE)) == JOB_PLACE and not worker.can_carry_one_unit_when_empty(trap_name):
		return HumanIndividualActionService.no_room_message(worker, [trap_name] as Array[String])
	if String(job.get("job_type", JOB_PLACE)) == JOB_PLACE:
		var placement_blocked := TrapService.placement_blocked_reason(ctx.world, trap_name)
		if placement_blocked != "":
			return placement_blocked
	# Svuotamento (2026-11-09): gli attrezzi addosso o da prendere in deposito, come la macellazione.
	var tools := job_tool_categories(job)
	if not tools.is_empty():
		var tool_rejection := ToolFetchService.rejection(ctx, worker, tools, EMPTY_AGE_KIND)
		if tool_rejection != "":
			return tool_rejection
	var task := build_task(ctx, worker, job)
	if task == null:
		return "nessuna trappola raggiungibile o nessun posto"
	return worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))


# Attrezzi che il lavoro chiede: giro = tutti i tipi del suo lavoro di zona, svuotamento di una trappola = i suoi,
# piazzamento = quelli per montarla (2026-11-11, vuoto salvo la fossa).
static func job_tool_categories(job: Dictionary) -> Array[TaskTypes.ToolCategory]:
	match String(job.get("job_type", JOB_PLACE)):
		JOB_ROUND:
			return TrapService.round_tool_categories(String(job.get("zone_job", "hunt")))
		JOB_EMPTY:
			return TrapService.empty_tool_categories(String(job.get("trap_name", "")))
	return TrapService.setup_tool_categories(String(job.get("trap_name", "")))


# La Task per `worker`: trappola dall'edificio più vicino al posto. null se manca la trappola, la zona o il posto.
static func build_task(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> Task:
	if String(job.get("job_type", JOB_PLACE)) == JOB_EMPTY:
		return _build_empty_task(ctx, worker, job)
	if String(job.get("job_type", JOB_PLACE)) == JOB_ROUND:
		return build_round_task(ctx, worker, int(job.get("area_id", 0)), String(job.get("zone_job", "hunt")))
	var area := WorkAreaService.find_by_id(ctx.game_data, int(job.get("area_id", 0)))
	var site: Vector2i = job.get("site", TrapService.NO_SITE)
	if area == null or site == TrapService.NO_SITE:
		return null
	return build_place_task(ctx, worker, String(job.get("trap_name", "")), area.macro_coords, site, area.id)


# Task "Piazza trappola" di `trap_name` sulla microcella `lot` di `macro_coords`, con la trappola dall'edificio più vicino
# al posto. Usata dal lavoro di zona e dal clic destro (`manual`, 2026-11-07). null se manca la trappola o la definizione.
static func build_place_task(ctx: GameContext, worker: HumanIndividual, trap_name: String, macro_coords: Vector2i, lot: Vector2i, area_id: int, manual: bool = false) -> Task:
	if trap_name == "":
		return null
	var site_point := Vector2(lot) + Vector2(0.5, 0.5)
	var source := WarehouseSelectionService.find_source_for_retrieval(
		ctx.world, site_point, macro_coords, trap_name, [], 1, worker.id, Callable(), true
	)
	if source == null:
		return null
	var definition := TaskDefinitionCache.get_definition(TrapService.TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var context := {
		TrapService.CONTEXT_TRAP_NAME: trap_name,
		TrapService.CONTEXT_AREA_ID: area_id,
		TrapService.CONTEXT_MACRO_X: macro_coords.x,
		TrapService.CONTEXT_MACRO_Y: macro_coords.y,
		TrapService.CONTEXT_LOT_X: lot.x,
		TrapService.CONTEXT_LOT_Y: lot.y,
		"trap_source_position": TaskBuilderService.building_arrival_point(worker, source),
		"trap_source_building": source,
		"trap_site_position": site_point + TaskBuilderService.macro_offset(worker, macro_coords),
	}
	if manual:
		context[TrapService.CONTEXT_MANUAL] = true
	var task := TaskFactory.build_task(definition, context)
	var rules := TrapService.get_rules(trap_name)
	if task != null and rules != null and rules.trap_quarry == TrapService.QUARRY_FISH:
		task.task_name = TrapService.FISH_TASK_NAME
	return task


# Svuotamento: cammino fino alla trappola e EmptyTrapAction; destinazione delle prede nel context. null se la trappola
# non c'è più.
static func _build_empty_task(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> Task:
	return build_empty_task(ctx, worker, int(job.get("trap_id", 0)))


# Giro delle trappole della zona `area_id` (2026-11-07): tutte quelle con prede e non già nella Task di un altro, in ordine
# di vicinanza (dal pipottino, poi dalla tappa precedente), finché la resa prevista sta nello zaino (la prima sempre).
# Task di svuotamento della prima più un cammino + EmptyTrapAction per ognuna delle altre. null se non ce n'è nessuna.
# Dal 2026-11-09 la Task ha solo la prima tappa (la più vicina, anche se la sua resa non entra tutta nello zaino): le altre
# le aggiunge EmptyTrapAction a fine tappa (next_round_trap), così entrano anche le trappole riempite strada facendo.
static func build_round_task(ctx: GameContext, worker: HumanIndividual, area_id: int, zone_job: String) -> Task:
	var exclude: Array[int] = []
	var first := next_round_trap(ctx.game_data, ctx.individuals, worker, area_id, zone_job, worker.position, INF, exclude)
	if first == null:
		return null
	var task := build_empty_task(ctx, worker, first.id)
	if task == null:
		return null
	task.context[TrapService.CONTEXT_ROUND] = true
	task.context[TrapService.CONTEXT_ROUND_JOB] = zone_job
	task.context[TrapService.CONTEXT_AREA_ID] = area_id
	return task


# Prossima tappa del giro della zona `area_id` per `worker`: la trappola del lavoro di zona `zone_job` più vicina a `from`
# con prede, non già nella Task di svuotamento di un altro né in `exclude`, la cui resa entra in `free_space`. null se nessuna.
static func next_round_trap(game_data: GameData, individuals: Array[HumanIndividual], worker: HumanIndividual, area_id: int,
		zone_job: String, from: Vector2, free_space: float, exclude: Array[int]) -> PlacedTrap:
	if game_data == null:
		return null
	var busy := TrapService.trap_ids_being_emptied(individuals, worker)
	var best: PlacedTrap = null
	var best_distance := INF
	for trap in game_data.placed_traps:
		if trap.work_area_id != area_id or trap.get_caught() <= 0 or busy.has(trap.id) or exclude.has(trap.id) \
				or _zone_job_of(trap) != zone_job or catch_space(trap) > free_space:
			continue
		var distance := site_point(worker, trap).distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = trap
	return best


# true se nel cesto c'è un animale ancora vivo (cattura viva).
static func _has_live_catch(trap: PlacedTrap) -> bool:
	if not TrapService.is_live_catch(TrapService.get_rules(trap.trap_name)):
		return false
	for i in range(trap.get_caught()):
		if trap.is_catch_alive(i):
			return true
	return false


static func _zone_job_of(trap: PlacedTrap) -> String:
	var rules := TrapService.get_rules(trap.trap_name)
	return rules.trap_zone_job if rules != null else ""


# Punto d'arrivo alla trappola, nelle coordinate di `worker`.
static func site_point(worker: HumanIndividual, trap: PlacedTrap) -> Vector2:
	return Vector2(trap.lot) + Vector2(0.5, 0.5) + TaskBuilderService.macro_offset(worker, trap.macro_coords)


# Spazio nello zaino della resa attuale della trappola (prede × trap_catch_yield × space_per_unit della risorsa; lacci:
# i prodotti della macellazione delle prede).
static func catch_space(trap: PlacedTrap) -> float:
	var rules := TrapService.get_rules(trap.trap_name)
	if rules == null:
		return 0.0
	if TrapService.is_herd_quarry(rules):
		var space := 0.0
		for product in TrapService.catch_products(trap, 0):
			var product_rules := CaloricCalculator.get_caloric_source_rules(String(product["resource"]))
			space += float(product["quantity"]) * (product_rules.space_per_unit if product_rules != null else 0.0)
		return space
	var resource_rules := CaloricCalculator.get_caloric_source_rules(rules.trap_catch_resource)
	var unit_space := resource_rules.space_per_unit if resource_rules != null else 0.0
	return float(trap.get_caught() * maxi(rules.trap_catch_yield, 0)) * unit_space


# Task "Svuota trappola" di `trap_id` (lavoro di zona e clic destro, 2026-11-07). null se la trappola non c'è più.
static func build_empty_task(ctx: GameContext, worker: HumanIndividual, trap_id: int) -> Task:
	var trap := TrapService.find_trap(ctx.game_data, trap_id)
	if trap == null:
		return null
	var definition := TaskDefinitionCache.get_definition(TrapService.EMPTY_TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var site_point := Vector2(trap.lot) + Vector2(0.5, 0.5)
	var task := TaskFactory.build_task(definition, {
		TrapService.CONTEXT_TRAP_ID: trap.id,
		TrapService.CONTEXT_TRAP_NAME: trap.trap_name,
		"trap_site_position": site_point + TaskBuilderService.macro_offset(worker, trap.macro_coords),
		ButcherDestinationService.CONTEXT_KEY: ButcherDestinationService.resolve_stock(ctx.game_data.stock_excess_meat_destination, ctx.world, ctx.folk),
	})
	var rules := TrapService.get_rules(trap.trap_name)
	if task != null and rules != null and rules.trap_quarry == TrapService.QUARRY_FISH:
		task.task_name = TrapService.EMPTY_FISH_TASK_NAME
	if task != null:
		for step in task.steps:
			if step is EmptyTrapAction:
				(step as EmptyTrapAction).refresh_required_tools(task.context)
	return task


# Lavoratore: chi ha (in corso o in coda) la Task di questa zona e trappola (o, per lo svuotamento, di questa trappola).
# I piazzamenti ordinati col clic destro non contano: non sono il lavoro della lista (contano solo nel numero della zona).
# Avvisi della campanella (2026-11-07, come "nessuno può trasportare" dei cantieri): una voce per zona e tipo di trappola
# quando la zona ne vuole ancora, una è pronta in un edificio e nessuno del gruppo la porta a zaino vuoto.
static func collect_nobody_can_carry_entries(ctx: GameContext) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ctx.game_data == null or ctx.individuals.is_empty():
		return entries
	for trap_name in TrapService.list_trap_names():
		var someone_can := false
		for member in ctx.individuals:
			if member.can_carry_one_unit_when_empty(trap_name):
				someone_can = true
				break
		if someone_can or not WarehouseSelectionService.has_retrieval_source(ctx.world, trap_name):
			continue
		for area in ctx.game_data.work_areas:
			var target := TrapService.target_for(ctx.game_data, area, trap_name)
			if target <= 0 or TrapService.count_for_area(ctx.game_data, ctx.individuals, area, trap_name) >= target:
				continue
			var text := GameContext.tr_text("pending_material_nobody_can_carry").format({
				"building": area.name, "resource": IconRegistry.get_resource_display_name(trap_name),
			})
			entries.append(PendingEntryService.make_entry("trap_too_heavy:%d:%s" % [area.id, trap_name], text, {
				"kind": "work_area", "id": area.id, "macro": area.macro_coords, "sort": float(area.id), "name": text,
			}, true))
	return entries


# Avvisi della campanella (2026-11-09, tutte le trappole): una voce per zona e tipo quando la zona ne vuole ancora, una è
# pronta in un edificio, nessuno la sta già portando lì e nella zona non resta un posto adatto (TrapService.choose_site).
static func collect_no_site_entries(ctx: GameContext) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ctx.game_data == null or ctx.world == null:
		return entries
	for trap_name in TrapService.list_trap_names():
		if not WarehouseSelectionService.has_retrieval_source(ctx.world, trap_name):
			continue
		for area in ctx.game_data.work_areas:
			var target := TrapService.target_for(ctx.game_data, area, trap_name)
			if target <= 0 or TrapService.count_for_area(ctx.game_data, ctx.individuals, area, trap_name) >= target:
				continue
			if TrapService.choose_site(ctx.game_data, ctx.world, ctx.individuals, area, trap_name) != TrapService.NO_SITE:
				continue
			var text := GameContext.tr_text("pending_trap_no_site").format({
				"area": area.name, "trap": IconRegistry.get_resource_display_name(trap_name),
			})
			entries.append(PendingEntryService.make_entry("trap_no_site:%d:%s" % [area.id, trap_name], text, {
				"kind": "work_area", "id": area.id, "macro": area.macro_coords, "sort": float(area.id), "name": text,
			}, true))
	return entries


static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	if String(job.get("job_type", JOB_PLACE)) == JOB_EMPTY:
		var trap_id := int(job.get("trap_id", 0))
		for member in ctx.individuals:
			for task in JobWorkScanService.open_tasks(member):
				if TrapService.is_empty_task(task) and TrapService.task_trap_ids(task).has(trap_id):
					result.append(member)
					break
		return result
	if String(job.get("job_type", JOB_PLACE)) == JOB_ROUND:
		var round_area_id := int(job.get("area_id", 0))
		var round_zone_job := String(job.get("zone_job", "hunt"))
		for member in ctx.individuals:
			for task in JobWorkScanService.open_tasks(member):
				if TrapService.is_empty_task(task) and task.context.get(TrapService.CONTEXT_ROUND, false) \
						and int(task.context.get(TrapService.CONTEXT_AREA_ID, 0)) == round_area_id \
						and String(task.context.get(TrapService.CONTEXT_ROUND_JOB, "hunt")) == round_zone_job:
					result.append(member)
					break
		return result
	var area_id := int(job.get("area_id", 0))
	var trap_name := String(job.get("trap_name", ""))
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if TrapService.is_place_task(task) and not task.context.get(TrapService.CONTEXT_MANUAL, false) 					and int(task.context.get(TrapService.CONTEXT_AREA_ID, 0)) == area_id \
					and String(task.context[TrapService.CONTEXT_TRAP_NAME]) == trap_name:
				result.append(member)
				break
	return result
