class_name SicknessService
extends RefCounted

# Malato (2026-10-24, richiesta utente — HumanIndividual.is_sick): sotto la soglia di salute il pipottino fa solo i
# bisogni (vedi HumanIndividual.get_assign_rejection_reason e resolve_idle_individual). Il compito in corso lo finisce;
# i lavori sospesi nella sua coda personale li prendono gli altri: tolti dalla coda, i lavori della lista che li
# leggevano dalle task tornano liberi da soli (gli ordini di zona del cassetto con DrawerOrderService.settle_zone_orders,
# i lavori di produzione con la riconciliazione delle unità qui sotto). Il carico nello zaino resta senza proprietario:
# il malato lo riporta al magazzino (CargoReturnService.release_orphan_cargo, da resolve_idle_individual).
# Stateless, stesso pattern degli altri *Service.


# Una volta al giorno per l'intera popolazione (GameTimeService, dopo l'interazione dei vitali che cambia la salute).
static func release_sick_queues(individuals: Array[HumanIndividual]) -> void:
	for individual in individuals:
		if individual.is_sick() and not individual.task_queue.is_empty():
			release_queued_tasks(individual, individuals)


# Toglie tutte le task in coda di `individual` e rimette in pari le unità degli edifici di produzione che ci lavoravano.
static func release_queued_tasks(individual: HumanIndividual, individuals: Array[HumanIndividual]) -> void:
	var produce_buildings: Array[Building] = []
	var released: Array[String] = []
	for queued in individual.task_queue:
		var task := queued as Task
		if task == null:
			continue
		released.append(task.task_name)
		if HuntService.is_hunt_task(task):
			HuntService.log_event(individual, "caccia tolta dalla coda: %s è malato." % individual.name)
		for step in task.steps:
			if step is ProduceAction and (step as ProduceAction).target_building != null \
					and not produce_buildings.has((step as ProduceAction).target_building):
				produce_buildings.append((step as ProduceAction).target_building)
	individual.task_queue.clear()
	for building in produce_buildings:
		JobWorkScanService.reconcile_production_units(individuals, building)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[SICK] #%d %s: malato (salute %.1f) — coda liberata: %s." % [
			individual.id, individual.name, individual.current_health, str(released)
		])
