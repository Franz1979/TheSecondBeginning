class_name SlaughterJobProvider
extends RefCounted

# Fornitore "Macella" della lista dei lavori (cane, passo 7, 2026-11-04): un lavoro per animale domestico con l'ordine del
# giocatore (DomesticAnimal.slaughter_requested). Tipo "butcher": stessa riga dei permessi e stessa skill della macellazione
# (chiave "butcher:animal:<id>", JobBoardService.get_kind). Solo celle vive. Assegnazione e Rimetti in coda restano alla scena.

const SORT_OFFSET: float = 4460000.0


static func job_key(animal_id: int) -> String:
	return "butcher:animal:%d" % animal_id


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if ctx.game_data == null:
		return jobs
	var tool_blocked := ToolFetchService.blocked_reason(ctx, CarcassJobProvider.TOOL_CATEGORIES, CarcassJobProvider.AGE_KIND)
	for animal in ctx.game_data.domestic_animals:
		if not animal.slaughter_requested or not ctx.live_cells.has(animal.macro_coords):
			continue
		var claimers := _workers_of(ctx, animal.id)
		var name := GameContext.tr_text("job_butcher").format({"species": GameContext.tr_text("animal_species_%s" % animal.species)})
		var microcell := Vector2i(animal.position.floor())
		jobs.append({
			"key": job_key(animal.id), "kind": "butcher", "name": name, "text": name,
			"log_name": "macellazione di %s %d" % [animal.species, animal.id],
			"icon": {"command": "butcher"}, "macro": animal.macro_coords, "microcell": microcell,
			"reach_target": {
				"macro_x": animal.macro_coords.x, "macro_y": animal.macro_coords.y, "micro_x": microcell.x, "micro_y": microcell.y,
			},
			"entry_kind": "domestic_animal", "id": animal.id, "sort": float(animal.id) + SORT_OFFSET,
			"assigned": not claimers.is_empty(), "hidden": false,
			"blocked_reason": "" if not claimers.is_empty() else tool_blocked,
			"target": animal, "provider": provider, "claimers": claimers,
		})
	return jobs


# Motivo per cui `worker` non può prendere il lavoro (HumanIndividual.ASSIGN_OK se può): lama (addosso o in un deposito
# raggiungibile), animale ancora vivo, il compito di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var tool_rejection := ToolFetchService.rejection(ctx, worker, CarcassJobProvider.TOOL_CATEGORIES, CarcassJobProvider.AGE_KIND)
	if tool_rejection != "":
		return tool_rejection
	var animal: DomesticAnimal = job["target"]
	if DomesticAnimalService.find_animal(ctx.game_data, animal.id) == null:
		return "animale non più vivo"
	var probe := TaskBuilderService.build_slaughter_task(worker, animal)
	if probe == null:
		return "animale non raggiungibile"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func workers(_ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in job.get("claimers", []):
		result.append(member as HumanIndividual)
	return result


# true se `task` macella un animale con l'ordine in lista: è la riga di questo lavoro, non un comando diretto.
static func is_listed_task(task: Task, game_data: GameData) -> bool:
	for step in task.steps:
		if step is SlaughterAction:
			var animal := DomesticAnimalService.find_animal(game_data, (step as SlaughterAction).animal_id)
			return animal != null and animal.slaughter_requested
	return false


static func _workers_of(ctx: GameContext, animal_id: int) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if DomesticAnimalSlaughterService.task_slaughters(task, animal_id):
				result.append(member)
				break
	return result
