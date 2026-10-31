class_name SicknessService
extends RefCounted

# Malato (2026-10-24, richiesta utente — HumanIndividual.is_sick): sotto la soglia di salute, o con una condizione che
# manda a letto, il pipottino fa solo i bisogni (vedi HumanIndividual.get_assign_rejection_reason e
# resolve_idle_individual). Va a letto (on_bedridden, 2026-10-25, richiesta utente — malattia e ferita come H): il
# compito in corso, se non è un bisogno, si chiude subito come con H (TaskCancelService), non va in coda; i lavori nella
# sua coda personale li prendono gli altri: tolti dalla coda, i lavori della lista che li leggevano dalle task tornano
# liberi da soli (gli ordini di zona del cassetto con DrawerOrderService.settle_zone_orders, i lavori di produzione con la
# riconciliazione delle unità qui sotto). Lo zaino e il travois cadono a terra in un mucchio.
# Stateless, stesso pattern degli altri *Service.


# Una volta al giorno per l'intera popolazione (GameTimeService, dopo l'interazione dei vitali che cambia la salute): chi
# è malato e ha ancora un lavoro in corso o in coda (appena sceso sotto la soglia) va a letto.
static func release_sick_queues(ctx: GameContext) -> void:
	for individual in ctx.individuals.duplicate():
		if individual.is_sick() and (_has_unshelter_queue(individual) or _has_work_in_progress(individual)):
			on_bedridden(ctx, individual, GameEffects.new())


# Va a letto (2026-10-25): chiamata appena una condizione rende `individual` malato (IllnessEvent, WoundEvent, giro
# giornaliero). Il compito in corso si chiude come con H se non è un bisogno; prima: il rito sociale che organizza si
# annulla, travois e zaino cadono a terra in un mucchio, le carcasse che doveva macellare finiscono negli avvisi
# "In sospeso" e la coda si libera.
static func on_bedridden(ctx: GameContext, individual: HumanIndividual, effects: GameEffects) -> void:
	if individual == null or not individual.is_sick():
		return
	var closing_current := _has_work_in_progress(individual)
	var dropped_tasks: Array = individual.task_queue.duplicate()
	if closing_current:
		dropped_tasks.append(individual.current_task)
	_note_unbutchered_carcasses(ctx.game_data, dropped_tasks)
	_cancel_organized_social_rites(ctx, individual)
	_drop_towed(ctx, individual)
	# Zaino a terra in ogni caso (2026-10-25, richiesta utente): mucchio dov'è, lo riporta la lista dei mucchi. Con lo zaino
	# vuoto la chiusura di H non avvia ritorni del carico.
	individual.discard_carried_resource()
	release_queued_tasks(individual, ctx.individuals)
	if closing_current:
		TaskCancelService.stop_current_task(ctx, individual, effects, "%s va a letto" % individual.name)


# Task che un malato può avere in corso (2026-10-25): le stesse che può ricevere (HumanIndividual.get_assign_rejection_reason:
# bisogni di stamina e provviste, riposo lungo, provviste del tasto F) più il ritorno del carico rimasto senza proprietario.
static func is_bed_compatible(task: Task) -> bool:
	return task != null and ([
		HumanIndividualActionService.INTERRUPT_PRIORITY_EMERGENCY_REST,
		HumanIndividualActionService.INTERRUPT_PRIORITY_EMERGENCY_RESTOCK,
		HumanIndividualActionService.INTERRUPT_PRIORITY_REST,
	].has(task.interrupt_priority) or HumanIndividual.SICK_ALLOWED_TASK_NAMES.has(task.task_name) \
		or CargoReturnService.is_cargo_return_task(task))


static func _has_work_in_progress(individual: HumanIndividual) -> bool:
	var task := individual.current_task
	return task != null and not task.is_finished() and not is_bed_compatible(task) 		and not (individual.may_build_own_shelter() and HumanIndividual.is_shelter_task(task))


# Coda con qualcosa che non sia il riparo per sé (2026-10-31, HumanIndividual.may_build_own_shelter).
static func _has_unshelter_queue(individual: HumanIndividual) -> bool:
	if not individual.may_build_own_shelter():
		return not individual.task_queue.is_empty()
	for task in individual.task_queue:
		if not HumanIndividual.is_shelter_task(task):
			return true
	return false


# Riparo per sé (2026-10-31): c'è un cantiere residenziale nuovo prendibile adesso nella lista (open_job_keys, letta
# dall'ultimo giro, mai ricalcolata). Solo allora il malato senza casa va al punto di assegnazione.
static func has_open_shelter_job(game_data: GameData, world: World) -> bool:
	if game_data == null or world == null:
		return false
	for key in game_data.job_board_runtime.open_job_keys.keys():
		var parts := String(key).split(":")
		if parts.size() != 2 or parts[0] != "build":
			continue
		var building_id := int(parts[1])
		for building in world.buildings:
			if building.id == building_id:
				if building.rules != null and building.rules.max_residents > 0:
					return true
				break
	return false


# Macellazioni tolte con la carcassa ancora intera: avviso "In sospeso", il giocatore la riassegna a mano.
static func _note_unbutchered_carcasses(game_data: GameData, tasks: Array) -> void:
	for raw_task in tasks:
		var task := raw_task as Task
		if task == null:
			continue
		for step in task.steps:
			var butcher := step as ButcherAction
			if butcher != null and not GroundPileService.find_carcass(game_data, butcher.pile_macro_coords, butcher.pile_microcell, butcher.carcass_id).is_empty():
				WorkFollowUpService.note_unbutchered_carcass(game_data, butcher.pile_macro_coords, butcher.pile_microcell, butcher.carcass_id)


# Rito sociale organizzato da `individual`: annullato come allo scadere dell'attesa (stop_tasks false — le task dei
# partecipanti finiscono da sole e il falò si spegne, SocialRiteAttendAction.rite_ended).
static func _cancel_organized_social_rites(ctx: GameContext, individual: HumanIndividual) -> void:
	for record in ctx.game_data.active_social_rites.duplicate():
		if int(record.get("organizer_id", -1)) != individual.id:
			continue
		var building := _find_building(ctx.world, int(record.get("building_id", -1)))
		if building != null:
			SocialRiteService.log_event("organizzatore #%d %s a letto." % [individual.id, individual.name])
			SocialRiteService.cancel(building, ctx.individuals, ctx.game_data, false)


# Travois: cade a terra in un mucchio dov'è il pipottino (come gli attrezzi del morto), lo riporta la lista dei mucchi.
static func _drop_towed(ctx: GameContext, individual: HumanIndividual) -> void:
	if not individual.is_towing():
		return
	var tool_name := individual.towed_resource
	var instance := individual.detach_towed(ctx.game_data)
	var max_uses := ToolInstance.get_max_uses(tool_name)
	if max_uses > 0 and not ToolInstance.is_usable(instance):
		return
	var entry: Dictionary = {"quantity": 0, "decay_fraction": 0.0}
	if ToolInstance.is_full(instance, max_uses):
		entry["quantity"] = 1
	else:
		ToolInstance.add_instance_to_entry(entry, instance)
	GroundPileService.drop_entries(ctx.game_data, individual.home_macro_coords, individual.position, {tool_name: entry}, ctx.world)


static func _find_building(world: World, building_id: int) -> Building:
	if world == null or building_id == -1:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


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
