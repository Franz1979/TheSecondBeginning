class_name SelfRemedyService
extends RefCounted

# Autocura (2026-10-25, richiesta utente): regola "appena libero" (HumanIndividualActionService.resolve_idle_individual,
# prima di riprendere la coda). Finché un pipottino è malato o convalescente, in piedi (non allettato: HumanIndividual.
# is_sick falso) e non infante, se esiste un rimedio per una sua condizione non ancora trattata oggi
# (HealthConditionService.useful_remedies) va a prenderlo e lo consuma: dallo zaino sul posto, altrimenti dall'edificio
# più vicino che lo può dare (magazzino o Prodotti finiti di una postazione, es. la capanna del guaritore — stessa regola
# dei rifornimenti automatici, WarehouseSelectionService.find_source_for_retrieval). Senza rimedio non succede nulla.
# Massimo uno al giorno per condizione (HealthConditionService.KEY_REMEDY). Gli allettati lo riceveranno da altri.

const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/take_remedy.tres"
const BACKPACK_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/take_remedy_backpack.tres"


# true se ha dato a `individual` la task "Prendi il rimedio".
static func try_take_remedy(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	if age_band == HumanTypes.AgeBand.INFANT or individual.health_conditions.is_empty() or individual.is_sick():
		return false
	for remedy_name in HealthConditionService.useful_remedies(individual):
		var task := _build_task(individual, world, remedy_name)
		if task == null or not individual.can_assign_task(task, age_band):
			continue
		if individual.assign_task(task, age_band):
			if DebugLogging.ENABLED:
				print("[REMEDY] #%d %s va a prendere %s (%s)." % [
					individual.id, individual.name, remedy_name, HealthConditionService.debug_text(individual)
				])
			return true
	return false


static func _build_task(individual: HumanIndividual, world: World, remedy_name: String) -> Task:
	if individual.get_carried_quantity(remedy_name) > 0:
		return TaskFactory.build_task(TaskDefinitionCache.get_definition(BACKPACK_TASK_DEFINITION_PATH), {
			RemedyAction.CONTEXT_REMEDY_NAME: remedy_name,
			"remedy_target_building": null,
			"remedy_source_kind": RemedyAction.SourceKind.BACKPACK,
		})
	var source := WarehouseSelectionService.find_source_for_retrieval(
		world, individual.position, individual.home_macro_coords, remedy_name, [], 1, individual.id, Callable(), true
	)
	if source == null:
		return null
	return TaskFactory.build_task(TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH), {
		RemedyAction.CONTEXT_REMEDY_NAME: remedy_name,
		"remedy_target_position": TaskBuilderService.building_arrival_point(individual, source),
		"remedy_target_building": source,
		"remedy_source_kind": RemedyAction.SourceKind.BUILDING,
	})
