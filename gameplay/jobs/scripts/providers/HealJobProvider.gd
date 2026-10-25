class_name HealJobProvider
extends RefCounted

# Fornitore "cura" della lista dei lavori (2026-10-25, cura somministrata): un lavoro per malato allettato ("heal:<id>",
# un lavoratore) finché è a letto (HumanIndividual.is_sick), ha un rimedio utile non ancora preso oggi
# (HealthConditionService.useful_remedies) e quel rimedio c'è in un edificio (magazzino o Prodotti finiti, es. la capanna
# del guaritore — WarehouseSelectionService.has_retrieval_source). Sparisce da solo quando è trattato oggi, guarisce o
# muore; il giorno dopo ricompare. Prima chi ha la salute più bassa. Chi lo prende (solo adulti fertili, maturi e anziani,
# mai un allettato né il malato stesso) preleva il rimedio e glielo porta (TaskBuilderService.build_heal_task,
# RemedyAction TAKE/GIVE). Assegnazione e Rimetti in coda restano alla scena.

const TASK_NAME := "task_heal_name"


static func collect(ctx: GameContext, provider: Dictionary, _assigned: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for patient in ctx.individuals:
		if patient == null or patient.health_conditions.is_empty() or not patient.is_sick():
			continue
		var job := {"id": patient.id}
		var is_assigned := not workers(ctx, job).is_empty()
		var remedy_name := _available_remedy(ctx, patient)
		if remedy_name.is_empty() and not is_assigned:
			continue
		var macro := patient.home_macro_coords
		var microcell := Vector2i(floori(patient.position.x), floori(patient.position.y))
		jobs.append({
			"key": "heal:%d" % patient.id, "kind": "heal", "name": GameContext.tr_text("task_heal_job_name").format({"name": patient.name}),
			"text": GameContext.tr_text("task_heal_job_tooltip").format({"name": patient.name, "health": roundi(patient.current_health)}),
			"log_name": "cura di #%d %s" % [patient.id, patient.name],
			"icon": {"text": IconRegistry.get_command_icon("heal")}, "macro": macro, "microcell": microcell,
			"reach_target": {"macro_x": macro.x, "macro_y": macro.y, "micro_x": microcell.x, "micro_y": microcell.y},
			"entry_kind": "individual", "id": patient.id, "sort": patient.current_health,
			"assigned": is_assigned, "hidden": false, "blocked_reason": "",
			"target": patient, "remedy_name": remedy_name, "provider": provider,
		})
	return jobs


# Motivo per cui `worker` non potrebbe ricevere la cura (HumanIndividual.ASSIGN_OK se può): mai il malato stesso; età e
# malattia di chi cura le controlla la task (heal.tres, get_assign_rejection_reason).
static func rejection(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> String:
	var patient: HumanIndividual = job["target"]
	if worker == patient:
		return "è il malato"
	var task := build_task(ctx, worker, job)
	if task == null:
		return "nessun rimedio raggiungibile"
	return worker.get_assign_rejection_reason(task, ctx.age_band_of(worker))


# La task della cura per `worker`: rimedio dall'edificio più vicino a lui. null se non ce n'è.
static func build_task(ctx: GameContext, worker: HumanIndividual, job: Dictionary) -> Task:
	var remedy_name := String(job.get("remedy_name", ""))
	if remedy_name.is_empty():
		return null
	var source := WarehouseSelectionService.find_source_for_retrieval(
		ctx.world, worker.position, worker.home_macro_coords, remedy_name, [], 1, worker.id, Callable(), true
	)
	if source == null:
		return null
	return TaskBuilderService.build_heal_task(worker, job["target"], source, remedy_name)


# Lavoratore: chi ha (in corso o in coda) la task della cura di questo malato.
static func workers(ctx: GameContext, job: Dictionary) -> Array[HumanIndividual]:
	var result: Array[HumanIndividual] = []
	var patient_id := int(job["id"])
	for member in ctx.individuals:
		for task in JobWorkScanService.open_tasks(member):
			if task.task_name == TASK_NAME and int(task.context.get(RemedyAction.CONTEXT_PATIENT_ID, -1)) == patient_id:
				result.append(member)
				break
	return result


# Primo rimedio utile al malato che c'è in un edificio; "" se nessuno.
static func _available_remedy(ctx: GameContext, patient: HumanIndividual) -> String:
	for remedy_name in HealthConditionService.useful_remedies(patient):
		if WarehouseSelectionService.has_retrieval_source(ctx.world, remedy_name):
			return remedy_name
	return ""
