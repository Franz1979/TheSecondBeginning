class_name CultivationJobProvider
extends RefCounted

# Lavori di coltivazione della lista (2026-11-15, orto delle prove e campi — tipo "cultivate"), uno per LOTTO (CropLot,
# passo 2 dei campi), un lavoratore per lotto: in un campo ne lavorano insieme quanti sono i lotti.
# - Semina ("cultivate:sow:<id>:<lotto>", CultivationService.needs_sowing): senza semi già sul terreno chi lo prende passa dal
#   magazzino o granaio più vicino con i semi (sow.tres), altrimenti va diretto a lavorare (sow_resume.tres). Bastone da
#   scavo obbligatorio. Campo (2026-11-15, passo 3c): i semi del capanno passano sul lotto senza viaggio
#   (FieldSeedStoreService.take_for_lot); dal magazzino (mai da un altro capanno) solo quelli che il capanno non ha.
# - Mietitura ("cultivate:reap:<id>:<lotto>", CultivationService.needs_reaping): va sul terreno e miete (reap.tres). Falcetto
#   obbligatorio.
# Senza semi in nessun deposito o senza l'attrezzo raggiungibile il lavoro si vede bloccato.

const KIND := "cultivate"
const AGE_KIND := DrawerOrderService.TYPE_PRODUCE
const JOB_SOW := "sow"
const JOB_REAP := "reap"
# Rizollatura (2026-11-15, Cura del campo passo 2 — FieldFertilityService): lotto per lotto, col piccone, prima della Semina.
const JOB_RETILL := "retill"


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null or ctx.world == null:
		return jobs
	var taken := _taken(ctx)
	for building in ctx.world.buildings:
		if not CultivationService.is_cultivated(building):
			continue
		for lot in CultivationService.lots(building):
			var job_type := job_type_of(ctx.game_data, building, lot)
			if job_type == "":
				continue
			var lot_key := CropLot.key_of(lot.microcell)
			var is_assigned := taken.has(Vector2i(building.id, lot_key))
			var blocked := ""
			if not is_assigned:
				var seed_name := CultivationService.seed_resource(building)
				if job_type == JOB_SOW and CultivationService.harvest_pile(ctx.game_data, building, lot) != null:
					blocked = GameContext.tr_text("sow_blocked_harvest_pile")
				elif job_type == JOB_SOW and lot.seeds <= 0 and FieldSeedStoreService.stored(building) <= 0 \
						and not WarehouseSelectionService.has_retrieval_source(ctx.world, seed_name, FieldSeedStoreService.store_ids(ctx.world)):
					blocked = GameContext.tr_text("sow_blocked_no_seeds").format({"seeds": IconRegistry.get_resource_display_name(seed_name)})
				elif not shed_covers(ctx, building, job_type, null):
					blocked = ToolFetchService.blocked_reason(ctx, job_tools(job_type), AGE_KIND)
			var species_name := CultivationService.species_display_name(ctx.game_data, building.crop_species, building)
			var building_name := GameContext.tr_text(building.rules.building_name) if building.rules != null else building.building_type_name
			var text_format := {"species": species_name, "building": building_name}
			jobs.append({
				"key": "cultivate:%s:%d:%d" % [job_type, building.id, lot_key], "kind": KIND,
				"name": GameContext.tr_text("task_%s_job_name" % job_type).format(text_format),
				"text": GameContext.tr_text("task_%s_job_tooltip" % job_type).format(text_format),
				"log_name": "%s %s in %s #%d lotto %s" % [job_type, building.crop_species, building.building_type_name, building.id, lot.microcell],
				"icon": {"text": IconRegistry.get_command_icon(job_type)}, "map_icon_key": job_type,
				"macro": Vector2i(building.macro_x, building.macro_y), "microcell": lot.microcell,
				"reach_target": building, "entry_kind": "building", "id": building.id, "lot": lot_key,
				"sort": float(building.id) + float(lot_key) / float(World.WIDTH * World.HEIGHT),
				"assigned": is_assigned, "hidden": false, "blocked_reason": blocked,
				"target": building, "provider": provider, "job_type": job_type,
			})
	return jobs


# Lavoro che il lotto chiede adesso alla lista: JOB_SOW, JOB_REAP o "" (anche con "Coltiva in automatico" spenta).
static func job_type_of(game_data: GameData, building: Building, lot: CropLot) -> String:
	if not CultivationService.is_auto(game_data, building):
		return ""
	if FieldFertilityService.needs_retill(game_data, building, lot):
		return JOB_RETILL
	if CultivationService.needs_sowing(game_data, building, lot):
		return JOB_SOW
	if CultivationService.needs_reaping(game_data, building, lot):
		return JOB_REAP
	return ""


static func job_tools(job_type: String) -> Array[TaskTypes.ToolCategory]:
	if job_type == JOB_RETILL:
		return FieldFertilityService.RETILL_TOOLS
	return CultivationService.REAPING_TOOLS if job_type == JOB_REAP else CultivationService.SOWING_TOOLS


# Attrezzi del capanno (2026-11-15, passo 2c): true se l'Attrezzeria del terreno copre gli attrezzi del lavoro e ha
# ancora un pezzo libero per `worker` (pezzi dell'attrezzo meno chi lavora già qui coi pezzi del capanno, `worker` escluso).
static func shed_covers(ctx: GameContext, building: Building, job_type: String, worker: HumanIndividual) -> bool:
	var pieces := 1 << 30
	for category in job_tools(job_type):
		var shed_tool := BuildingToolkitService.find_tool_for(building, category)
		if shed_tool == "":
			return false
		pieces = mini(pieces, BuildingToolkitService.get_quantity(building, shed_tool))
	var in_use := 0
	for member in ctx.individuals:
		if member == worker:
			continue
		for task in JobWorkScanService.open_tasks(member):
			if is_cultivation_task(task) and int(task.context[CultivationService.CONTEXT_BUILDING_ID]) == building.id \
					and bool(task.context.get(CultivationService.CONTEXT_SHED_TOOLS, false)):
				in_use += 1
				break
	return in_use < pieces


# Attrezzi che `worker` deve avere suoi per questo lavoro: nessuno se il capanno ha un pezzo per lui.
static func worker_tools(ctx: GameContext, building: Building, job_type: String, worker: HumanIndividual) -> Array[TaskTypes.ToolCategory]:
	var none: Array[TaskTypes.ToolCategory] = []
	return none if shed_covers(ctx, building, job_type, worker) else job_tools(job_type)


# Attrezzi da prendere in deposito per un compito già fatto (build_task): nessuno se usa quelli del capanno.
static func task_tools(task: Task, job_type: String) -> Array[TaskTypes.ToolCategory]:
	var none: Array[TaskTypes.ToolCategory] = []
	if task != null and bool(task.context.get(CultivationService.CONTEXT_SHED_TOOLS, false)):
		return none
	return job_tools(job_type)


static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var building: Building = job.get("target")
	var lot := job_lot(job)
	if building == null or lot == null:
		return "nessun terreno"
	var job_type := String(job.get("job_type", JOB_SOW))
	if job_type == JOB_SOW and CultivationService.harvest_pile(ctx.game_data, building, lot) != null:
		return GameContext.tr_text("sow_blocked_harvest_pile")
	# Semi da portare: come cava e taglio, chi col bastone in cintura non porta nemmeno un'oncia non prende la Semina.
	if job_type == JOB_SOW and lot.seeds <= 0 and shed_seeds_free(ctx, building, worker) < CultivationService.seeds_wanted(building, lot):
		var carry_rejection := ToolFetchService.carry_rejection(worker, worker_tools(ctx, building, job_type, worker), CultivationService.seed_resource(building))
		if carry_rejection != "":
			return carry_rejection
	var tool_rejection := ToolFetchService.rejection(ctx, worker, worker_tools(ctx, building, job_type, worker), AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var task := build_task(ctx, worker, building, lot)
	if task == null:
		return "nessun seme raggiungibile"
	return worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))


# Lotto di un lavoro della lista, o null.
static func job_lot(job: Dictionary) -> CropLot:
	var building: Building = job.get("target")
	if building == null or not job.has("lot"):
		return null
	return CultivationService.find_lot(building, CropLot.cell_of_key(int(job["lot"])))


# Task per `worker` sul lotto `lot` di `building`, secondo quello che il lotto chiede (semina con o senza presa dei semi,
# mietitura). null se non chiede niente o mancano i semi.
static func build_task(ctx: GameContext, worker: HumanIndividual, building: Building, lot: CropLot) -> Task:
	if building == null or lot == null:
		return null
	var job_type := job_type_of(ctx.game_data, building, lot)
	if job_type == "":
		return null
	var macro := Vector2i(building.macro_x, building.macro_y)
	# Sul lotto stesso (la terra coltivata si calpesta, a caro prezzo: PathfindingService).
	var site := Vector2(lot.microcell) + Vector2(randf_range(0.15, 0.85), randf_range(0.15, 0.85)) \
		+ TaskBuilderService.macro_offset(worker, macro)
	var context := {
		CultivationService.CONTEXT_BUILDING_ID: building.id,
		CultivationService.CONTEXT_LOT_CELL: CropLot.key_of(lot.microcell),
		"sow_garden": building,
		"sow_site_position": site,
		CultivationService.CONTEXT_SHED_TOOLS: shed_covers(ctx, building, job_type, worker),
	}
	if job_type == JOB_REAP:
		var reap := TaskDefinitionCache.get_definition(CultivationService.REAP_TASK_DEFINITION_PATH)
		return TaskFactory.build_task(reap, context) if reap != null else null
	if job_type == JOB_RETILL:
		var retill := TaskDefinitionCache.get_definition(FieldFertilityService.RETILL_TASK_DEFINITION_PATH)
		return TaskFactory.build_task(retill, context) if retill != null else null
	# Raccolto ancora sul terreno: niente semina finché non si porta via.
	if CultivationService.harvest_pile(ctx.game_data, building, lot) != null:
		return null
	if lot.seeds > 0:
		var resume := TaskDefinitionCache.get_definition(CultivationService.RESUME_TASK_DEFINITION_PATH)
		return TaskFactory.build_task(resume, context) if resume != null else null
	# Semi dal capanno (2026-11-15, passo 3c): se il capanno ha tutto il lotto, si va diretti a seminare; altrimenti il resto
	# dal magazzino più vicino (mai da un capanno); senza magazzino, si semina con quelli del capanno.
	var seed_name := CultivationService.seed_resource(building)
	var from_shed := mini(shed_seeds_free(ctx, building, worker), CultivationService.seeds_wanted(building, lot))
	context[CultivationService.CONTEXT_SHED_SEEDS] = from_shed
	if from_shed > 0 and from_shed >= CultivationService.seeds_wanted(building, lot):
		var direct := TaskDefinitionCache.get_definition(CultivationService.RESUME_TASK_DEFINITION_PATH)
		return TaskFactory.build_task(direct, context) if direct != null else null
	var garden_point := Vector2(lot.microcell) + Vector2(0.5, 0.5)
	var source := WarehouseSelectionService.find_source_for_retrieval(ctx.world, garden_point, macro, seed_name,
		FieldSeedStoreService.store_ids(ctx.world), 1, worker.id)
	if source == null and from_shed > 0:
		var shed_only := TaskDefinitionCache.get_definition(CultivationService.RESUME_TASK_DEFINITION_PATH)
		return TaskFactory.build_task(shed_only, context) if shed_only != null else null
	var definition := TaskDefinitionCache.get_definition(CultivationService.TASK_DEFINITION_PATH)
	if source == null or definition == null:
		return null
	context["sow_source_building"] = source
	context["sow_source_position"] = TaskBuilderService.building_arrival_point(worker, source)
	return TaskFactory.build_task(definition, context)


# Once del capanno del campo ancora libere per `worker`: quelle tenute meno quelle che contano di trovarci gli altri
# seminatori non ancora arrivati sul lotto (CONTEXT_SHED_SEEDS, finché il loro lotto è senza semi). 0 se non è un campo.
static func shed_seeds_free(ctx: GameContext, building: Building, worker: HumanIndividual) -> int:
	if not FieldSeedStoreService.is_seed_store(building):
		return 0
	var free := FieldSeedStoreService.stored(building)
	for member in ctx.individuals:
		if member == worker:
			continue
		for task in JobWorkScanService.open_tasks(member):
			if not is_cultivation_task(task) or int(task.context[CultivationService.CONTEXT_BUILDING_ID]) != building.id:
				continue
			var planned := int(task.context.get(CultivationService.CONTEXT_SHED_SEEDS, 0))
			var other_lot := CultivationService.lot_from_context(building, task.context)
			if planned > 0 and other_lot != null and other_lot.seeds <= 0:
				free -= planned
			break
	return maxi(free, 0)


static func is_cultivation_task(task: Task) -> bool:
	return task != null and task.context.has(CultivationService.CONTEXT_BUILDING_ID)


static func _taken(ctx: GameContext) -> Dictionary:
	var taken: Dictionary = {}
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if is_cultivation_task(task):
				taken[_task_lot_id(task)] = true
	return taken


static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	var lot_id := Vector2i(int(job.get("id", -1)), int(job.get("lot", -1)))
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if is_cultivation_task(task) and _task_lot_id(task) == lot_id:
				result.append(member)
				break
	return result


# (id dell'edificio, chiave del lotto) di un compito di coltivazione; compiti salvati prima dei lotti: il lotto
# dell'unica microcella dell'orto.
static func _task_lot_id(task: Task) -> Vector2i:
	var building_id := int(task.context[CultivationService.CONTEXT_BUILDING_ID])
	if task.context.has(CultivationService.CONTEXT_LOT_CELL):
		return Vector2i(building_id, int(task.context[CultivationService.CONTEXT_LOT_CELL]))
	var garden: Building = task.context.get("sow_garden")
	if garden != null:
		var all := CultivationService.lots(garden)
		if not all.is_empty():
			return Vector2i(building_id, CropLot.key_of(all[0].microcell))
	return Vector2i(building_id, -1)
