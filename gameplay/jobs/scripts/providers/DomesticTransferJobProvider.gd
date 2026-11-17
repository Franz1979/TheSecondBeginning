class_name DomesticTransferJobProvider
extends RefCounted

# Fornitore "Trasferisci animali" della lista dei lavori (2026-11-16, riga Allevamento, tipo "husbandry"): un lavoro per
# tettoia delle gabbie con piccoli domestici in attesa (DomesticTransferService.transferable) e un solo lavoratore. Chi lo
# prende va alla tettoia (cammino + TakeAnimalsAction); gli animali li sceglie all'arrivo. Solo celle vive. Assegnazione e
# Rimetti in coda restano alla scena.

const KIND := "husbandry"
const SORT_OFFSET: float = 4470000.0
const CONTEXT_SHELTER_ID := "transfer_shelter_id"
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/transfer_animals.tres"


static func job_key(shelter_id: int) -> String:
	return "%s:transfer:%d" % [KIND, shelter_id]


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null or ctx.world == null:
		return jobs
	var reserved := KeptAnimalService.reservations(ctx.individuals)
	for building in ctx.world.buildings:
		if KeptAnimalService.capacity(building) <= 0 or DomesticTransferService.is_breeding_building(building):
			continue
		var macro := Vector2i(building.macro_x, building.macro_y)
		if not ctx.live_cells.has(macro):
			continue
		var claimers := _workers_of(ctx, building.id)
		var animals := DomesticTransferService.transferable(ctx.game_data, ctx.world, building, reserved)
		if animals.is_empty() and claimers.is_empty():
			continue
		var species := animals[0].species if not animals.is_empty() else ""
		var name := GameContext.tr_text("job_transfer_animals").format({
			"species": KeptAnimalService.species_display_name(species, false) if species != "" else "",
			"count": animals.size(),
		})
		var microcell := Vector2i(building.micro_x, building.micro_y)
		jobs.append({
			"key": job_key(building.id), "kind": KIND, "name": name, "text": name,
			"log_name": "trasferimento di %d animali dalla tettoia %d" % [animals.size(), building.id],
			"icon": {"command": "transport"}, "macro": macro, "microcell": microcell,
			"reach_target": {
				"macro_x": macro.x, "macro_y": macro.y, "micro_x": microcell.x, "micro_y": microcell.y,
			},
			"entry_kind": "building", "id": building.id, "sort": float(building.id) + SORT_OFFSET,
			"assigned": not claimers.is_empty(), "hidden": false, "blocked_reason": "",
			"target": building, "provider": provider, "claimers": claimers,
		})
	return jobs


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): animali da portare, posto nello
# zaino per almeno uno, il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var shelter: Building = job["target"]
	var animals := DomesticTransferService.transferable(ctx.game_data, ctx.world, shelter,
		KeptAnimalService.reservations(ctx.individuals))
	if animals.is_empty():
		return "nessun animale da trasferire"
	var lightest := INF
	var today := ctx.game_data.get_absolute_day()
	for animal in animals:
		lightest = minf(lightest, KeptAnimalService.live_space(animal.species, DomesticTransferService.age_band_of(animal, today)))
	if DomesticTransferService.free_space(worker) < lightest:
		return "zaino pieno"
	var probe := build_task(worker, shelter)
	if probe == null:
		return "tettoia non raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func build_task(worker: HumanIndividual, shelter: Building) -> Task:
	if shelter == null:
		return null
	var definition := TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH)
	if definition == null:
		return null
	var task := TaskFactory.build_task(definition, {
		"transfer_shelter_position": KeepAnimalAction.walk_point(worker, shelter),
		"transfer_shelter": shelter,
	})
	if task == null:
		return null
	# L'edificio serviva solo a costruire lo step: nel context resta l'id (salvabile).
	task.context.erase("transfer_shelter")
	task.context[CONTEXT_SHELTER_ID] = shelter.id
	return task


static func is_transfer_task(task: Task) -> bool:
	return task != null and task.context.has(CONTEXT_SHELTER_ID)


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result


static func _workers_of(ctx: GameContext, shelter_id: int) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if is_transfer_task(task) and int(task.context[CONTEXT_SHELTER_ID]) == shelter_id:
				result.append(member)
				break
	return result
