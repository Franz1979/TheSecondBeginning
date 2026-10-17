class_name RepairJobProvider
extends RefCounted

# Fornitore "riparazioni" della lista dei lavori (2026-10-10; spostato da GameScene il 2026-10-17, refactoring GameScene
# blocco 2b): edifici con la riparazione richiesta (Building.repair_requested, "repair:<id>"). La task è la Repair
# esistente (TaskBuilderService.build_repair_task), un solo riparatore per edificio. Assegnazione, X e Rimetti in coda
# restano alla scena.


static func collect(ctx: GameContext, provider: Dictionary, assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for building in ctx.world.buildings:
		if not building.repair_requested or not RepairAction.is_building_repairable(building):
			continue
		if building.current_durability >= float(building.rules.max_durability):
			continue
		var building_name := GameContext.tr_text(building.rules.building_name)
		var text := GameContext.tr_text("pending_repair").format({"building": building_name})
		jobs.append({
			"key": "repair:%d" % building.id, "kind": "repair", "name": text, "text": text, "log_name": building_name,
			"icon": {"building_command": BuildingCommandIcon.KIND_REPAIR},
			"macro": Vector2i(building.macro_x, building.macro_y), "microcell": Vector2i(building.micro_x, building.micro_y),
			"reach_target": building, "entry_kind": "building", "id": building.id, "sort": float(building.id),
			"assigned": assigned["repair"].has(building.id), "hidden": false,
			"target": building, "provider": provider,
		})
		# Rimandata per materiale (2026-10-17): resta assegnata, riga in "In coda" col motivo.
		if assigned["postponed_repair"].has(building.id) and not assigned["repair_active"].has(building.id):
			jobs[jobs.size() - 1]["postponed_by"] = assigned["postponed_repair"][building.id]
	return jobs


static func job_keys(building: Building) -> Array[String]:
	var keys: Array[String] = ["repair:%d" % building.id]
	return keys


# Motivo per cui `worker` non potrebbe ricevere la Repair Task (HumanIndividual.ASSIGN_OK se può), su una task di prova.
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var probe := TaskBuilderService.build_repair_task(worker, job["target"])
	if probe == null:
		return "definizione mancante"
	return worker.get_assign_rejection_reason(probe, ctx.age_band_of(worker))


static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	return JobWorkScanService.workers_on_building(ctx.individuals, job["target"], JobWorkScanService.REPAIR_TASK_NAMES)
