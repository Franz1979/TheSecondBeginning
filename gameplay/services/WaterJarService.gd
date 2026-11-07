class_name WaterJarService
extends RefCounted

# Giare d'acqua (2026-11-06, richiesta utente — Vasellame, giare: passo 1, comando diretto). Una sola risorsa, la Giara
# ("clay_jar"): ogni giara è un'istanza (ToolInstance) con i suoi usi e la sua acqua (0..water_capacity, 400). Pesa 50 più
# un decimo dell'acqua che contiene (HumanIndividual.get_carried_space). In magazzino entra sempre vuota
# (BuildingStorageService.store_tool_instance versa l'acqua); con l'acqua sta solo nelle Tettoie dell'acqua.
#
# La tettoia (water_shelter, deposito chiuso: BuildingRules.storage_event_only) ha un posto per giara (storage_slot_count)
# e la gestisce solo questo servizio: nessuno ci deposita né ci preleva per conto suo, e non conta nelle scorte. Le giare
# restano nella tettoia anche quando si svuotano. "Piena" vuol dire due cose separate: posti (giare presenti) e acqua.
#
# Riempire (fill_jar.tres, un compito con un viaggio alla volta): [Walk alla sorgente, TakeJar, Walk alla riva, FillJar,
# Walk alla tettoia, PutJar]. Sorgente: una giara VUOTA della tettoia (2026-11-07, richiesta utente: una giara con un po'
# d'acqua resta nella tettoia, la gente ci beve finché si svuota; si porta via e si riporta sempre piena), altrimenti, con
# un posto libero,
# una giara vuota dal magazzino. Il posto di una giara in viaggio resta riservato. Finito un viaggio, se ne mancano altri,
# il compito si allunga col viaggio successivo (append_next_trip, da HumanIndividualActionService). Il travois è
# obbligatorio: una giara piena (90) non si porta a mano. Ogni riempimento consuma un uso: a zero la giara si rompe.
# Bere (2026-11-07, passo 4): la tettoia con acqua è un punto d'acqua per il bere normale e d'emergenza (find_drink_shelter,
# scelta da ThirstService.assign_drink_task contro la riva più vicina); la bevuta toglie dalle giare quello che manca al
# corpo, più l'otre (drink_at_shelter). Chi porta una giara con acqua beve da quella sul posto, senza fermarsi
# (drink_from_carried_jars, da ThirstService.apply_drain dopo l'otre). Bere non consuma gli usi della giara.
# Regola del WM "Acqua per tettoia" (2026-11-07, passo 3: WaterShelterStockService): trips_to_reach dice quanti viaggi
# in più servono per tenere la tettoia al livello voluto.
# Prossimi passi (non qui): valore per singola tettoia, giare mancanti, consumo.
# Senza stato.

const JAR := "clay_jar"
const SHELTER_TYPE := "water_shelter"
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/fill_jar.tres"

# Context della Task. Chiavi consumate dagli step (posizioni ed edifici) e chiavi che restano (id, contatori, stato).
const CONTEXT_SOURCE_POSITION := "fill_jar_source_position"
const CONTEXT_SOURCE_BUILDING := "fill_jar_source_building"
const CONTEXT_WATER_POSITION := "fill_jar_water_position"
const CONTEXT_SHELTER_POSITION := "fill_jar_shelter_position"
const CONTEXT_SHELTER_BUILDING := "fill_jar_shelter_building"
const CONTEXT_SHELTER_ID := "fill_jar_shelter_id"
const CONTEXT_SOURCE_ID := "fill_jar_source_id"
# Giare ancora da riempire, compresa quella del viaggio in corso.
const CONTEXT_REMAINING := "fill_jar_remaining"
# true tra TakeJar e PutJar: la giara è in viaggio e il suo posto nella tettoia è riservato.
const CONTEXT_CARRYING := "fill_jar_carrying"
# Scritta da PutJarAction se mancano altri viaggi; HumanIndividualActionService aggiunge il viaggio successivo.
const CONTEXT_PENDING_NEXT_TRIP := "fill_jar_pending_next_trip"
# Riempimento fallito alla riva (niente posto per la giara piena): la giara torna vuota nella tettoia e la serie finisce lì.
const CONTEXT_STOP_AFTER_TRIP := "fill_jar_stop_after_trip"


static func is_shelter(building: Building) -> bool:
	return building != null and building.building_type_name == SHELTER_TYPE


static func is_fill_task(task: Task) -> bool:
	return task != null and task.context.has(CONTEXT_SHELTER_ID)


static func jar_water_capacity() -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(JAR)
	return int(rules.water_capacity) if rules != null else 0


# Dove ci si ferma alla tettoia (2026-11-07, WaterShelterShape ridisegnata): sullo spiazzo davanti al tetto, dal lato della
# rotazione, con un po' di sparpaglio come TaskBuilderService.building_arrival_point. Nel riferimento di `worker`.
static func shelter_point(worker: HumanIndividual, shelter: Building) -> Vector2:
	var forward := TentShapes.direction_vector(shelter.rotation)
	var side := Vector2(forward.y, -forward.x)
	var local := Vector2(0.5, 0.5) + side * randf_range(-0.3, 0.3) + forward * randf_range(0.22, 0.4)
	return Vector2(shelter.micro_x, shelter.micro_y) + local + TaskBuilderService.macro_offset(worker, Vector2i(shelter.macro_x, shelter.macro_y))


static func shelter_capacity(shelter: Building) -> int:
	return shelter.rules.storage_slot_count if shelter != null and shelter.rules != null else 0


# --- Contenuto della tettoia ---

# Acqua di ogni giara nella tettoia (i pezzi nuovi sono vuoti), nell'ordine in cui sono disegnate.
static func shelter_jar_waters(shelter: Building) -> Array[int]:
	if shelter == null:
		var none: Array[int] = []
		return none
	return entry_jar_waters(shelter.stored_resources.get(JAR, {}))


# Acqua di ogni giara di una voce (deposito o zaino): prima i pezzi nuovi (vuoti), poi le istanze.
static func entry_jar_waters(entry: Dictionary) -> Array[int]:
	var waters: Array[int] = []
	for i in range(ToolInstance.get_new_quantity(entry)):
		waters.append(0)
	for instance in ToolInstance.get_used_instances(entry):
		waters.append(ToolInstance.get_water(instance))
	return waters


# Riquadro di una giara (zaino dell'individuo, posto della tettoia): icona con l'acqua se almeno una ha dell'acqua, e
# nel tooltip l'acqua di ciascuna (2026-11-06, richiesta utente: si deve vedere se la giara è piena o vuota).
static func decorate_jar_box(box: Control, waters: Array[int]) -> void:
	var any_water := false
	var lines: Array[String] = []
	for water in waters:
		any_water = any_water or water > 0
		lines.append(GameContext.tr_text("jar_water_tooltip").format({"water": water, "capacity": jar_water_capacity()}))
	for child in box.get_children():
		if child is ClayJarIcon:
			(child as ClayJarIcon).full = any_water
			child.queue_redraw()
	if not lines.is_empty():
		box.tooltip_text += "\n" + TooltipText.wrap("\n".join(lines))


static func shelter_water(shelter: Building) -> int:
	var total := 0
	for water in shelter_jar_waters(shelter):
		total += water
	return total


# Giare in viaggio per `shelter` nei compiti di riempimento aperti (in corso o in coda): quante sono già in mano
# (`carrying`), quante sono attese dalla tettoia stessa e quante da un magazzino (CONTEXT_SOURCE_ID: viaggio con la giara
# ancora da prendere; tolta da take_jar). Un compito tra un viaggio e il successivo non conta.
static func _trips_for(shelter: Building) -> Dictionary:
	var counts := {"carrying": 0, "from_shelter": 0, "from_storage": 0}
	for member in GameSettings.active_human_individuals:
		for task in JobWorkScanService.open_tasks(member):
			if not is_fill_task(task) or int(task.context[CONTEXT_SHELTER_ID]) != shelter.id:
				continue
			if bool(task.context.get(CONTEXT_CARRYING, false)):
				counts["carrying"] += 1
			elif not task.context.has(CONTEXT_SOURCE_ID):
				continue
			elif int(task.context[CONTEXT_SOURCE_ID]) == shelter.id:
				counts["from_shelter"] += 1
			else:
				counts["from_storage"] += 1
	return counts


# Giare della tettoia vuote (senza acqua) e non già prenotate da un altro viaggio.
static func _free_empty_jars(shelter: Building, trips: Dictionary) -> int:
	var empty := 0
	for water in shelter_jar_waters(shelter):
		if water <= 0:
			empty += 1
	return maxi(empty - int(trips["from_shelter"]), 0)


# Giare vuote della tettoia ancora libere per un viaggio (2026-11-07, giare mancanti: WaterShelterStockService).
static func free_empty_jars(shelter: Building) -> int:
	return _free_empty_jars(shelter, _trips_for(shelter))


# Viaggi già decisi che prenderanno una giara da un magazzino e non l'hanno ancora presa.
static func pending_storage_trips(shelter: Building) -> int:
	return int(_trips_for(shelter)["from_storage"])


# Posti della tettoia senza giara e non riservati (giare in viaggio o attese da un magazzino).
static func _free_places(shelter: Building, trips: Dictionary) -> int:
	return maxi(shelter_capacity(shelter) - shelter_jar_waters(shelter).size() - int(trips["carrying"]) - int(trips["from_storage"]), 0)


# Quanti riempimenti si possono ancora chiedere alla tettoia: giare vuote più posti liberi. 0 = tettoia piena
# d'acqua, o non utilizzabile (non completa, fuori servizio, demolita).
static func fillable_count(shelter: Building) -> int:
	if not is_shelter(shelter) or not shelter.is_complete or shelter.is_demolished or shelter.is_out_of_service():
		return 0
	var trips := _trips_for(shelter)
	return _free_empty_jars(shelter, trips) + _free_places(shelter, trips)


# Viaggi già decisi per `shelter`: i riempimenti che restano ai compiti aperti (viaggio in corso compreso).
static func planned_trips(shelter: Building) -> int:
	var total := 0
	for member in GameSettings.active_human_individuals:
		for task in JobWorkScanService.open_tasks(member):
			if is_fill_task(task) and int(task.context[CONTEXT_SHELTER_ID]) == shelter.id:
				total += maxi(int(task.context.get(CONTEXT_REMAINING, 0)), 0)
	return total


# Viaggi in più (oltre a quelli già decisi, planned_trips) perché l'acqua della tettoia arrivi ad almeno `target`. Ogni
# viaggio porta una giara piena (400): una vuota della tettoia o una nuova in un posto libero; i viaggi già decisi contano
# già come pieni. Si può superare `target` (giare sempre piene); il limite è solo la tettoia: giare vuote e posti liberi
# non ancora presi dai viaggi già decisi. 0 = coi viaggi già decisi arriva al livello, o nessun viaggio possibile.
static func trips_to_reach(shelter: Building, target: int) -> int:
	if not is_shelter(shelter) or target <= 0:
		return 0
	var capacity := jar_water_capacity()
	if capacity <= 0:
		return 0
	var trips := _trips_for(shelter)
	var planned := planned_trips(shelter)
	var missing := target - shelter_water(shelter) - planned * capacity
	if missing <= 0:
		return 0
	# Viaggi decisi oltre quello in corso: non hanno ancora preso il loro posto (fillable_count non li vede).
	var reserved_now := int(trips["carrying"]) + int(trips["from_shelter"]) + int(trips["from_storage"])
	var available := maxi(fillable_count(shelter) - maxi(planned - reserved_now, 0), 0)
	return mini(int(ceil(float(missing) / float(capacity))), available)


# Magazzino più vicino a `worker` con almeno una giara, raggiungibile; null se nessuno (le tettoie non sono sorgenti).
# Con `worker` null (riga dell'ordine del WM in coda): un magazzino qualsiasi con una giara.
static func find_jar_storage(world: World, worker: HumanIndividual) -> Building:
	if worker == null:
		return WarehouseSelectionService.find_source_for_retrieval(world, Vector2.ZERO, Vector2i.ZERO, JAR, [], 1, -1, Callable())
	return WarehouseSelectionService.find_source_for_retrieval(
		world, worker.position, worker.home_macro_coords, JAR, [], 1, worker.id, PathfindingService.reachability_for(worker)
	)


# Sorgente del prossimo viaggio verso `shelter`: la tettoia stessa se ha una giara vuota libera, altrimenti un
# magazzino con una giara se nella tettoia c'è un posto libero. {"source": Building} oppure {"error": chiave del motivo}.
static func pick_source(world: World, worker: HumanIndividual, shelter: Building) -> Dictionary:
	var trips := _trips_for(shelter)
	if _free_empty_jars(shelter, trips) > 0:
		return {"source": shelter}
	if _free_places(shelter, trips) <= 0:
		return {"error": "fill_jar_reject_shelter_full"}
	var storage := find_jar_storage(world, worker)
	if storage == null:
		return {"error": "fill_jar_reject_no_empty_jar"}
	return {"source": storage}


# --- Compito ---

# Compito con il primo viaggio da `source` (pick_source) a `shelter`; `count` riempimenti in tutto. null se nessuna riva
# è raggiungibile.
static func build_fill_task(worker: HumanIndividual, source: Building, shelter: Building, count: int) -> Task:
	var context := _trip_context(worker, source, shelter)
	if context.is_empty():
		return null
	context[CONTEXT_SHELTER_ID] = shelter.id
	context[CONTEXT_REMAINING] = count
	return TaskFactory.build_task(TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH), context)


static func _trip_context(worker: HumanIndividual, source: Building, shelter: Building) -> Dictionary:
	var source_point := shelter_point(worker, source) if is_shelter(source) else TaskBuilderService.building_arrival_point(worker, source)
	var arrival := shelter_point(worker, shelter)
	var water_point: Variant = pick_fill_point(worker, source_point, arrival)
	if water_point == null:
		return {}
	return {
		CONTEXT_SOURCE_POSITION: source_point,
		CONTEXT_SOURCE_BUILDING: source,
		CONTEXT_WATER_POSITION: water_point,
		CONTEXT_SHELTER_POSITION: arrival,
		CONTEXT_SHELTER_BUILDING: shelter,
		CONTEXT_SOURCE_ID: source.id,
	}


# Viaggio successivo (HumanIndividualActionService, dopo PutJarAction con CONTEXT_PENDING_NEXT_TRIP): gli step di un
# nuovo viaggio aggiunti in coda allo stesso compito. Niente viaggio (tettoia piena d'acqua, nessuna giara, nessuna riva):
# il compito finisce lì, con un messaggio se il motivo è un problema da sistemare.
static func append_next_trip(individual: HumanIndividual, task: Task, world: World) -> void:
	var shelter := _find_building(world, int(task.context.get(CONTEXT_SHELTER_ID, -1)))
	if shelter == null or fillable_count(shelter) <= 0:
		return
	var pick := pick_source(world, individual, shelter)
	if pick.has("error"):
		if String(pick["error"]) == "fill_jar_reject_no_empty_jar":
			task.context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = \
				GameContext.tr_text("fill_jar_stop_no_jar").format({"name": individual.name})
		return
	var trip_context := _trip_context(individual, pick["source"], shelter)
	if trip_context.is_empty():
		return
	var trip := TaskFactory.build_task(TaskDefinitionCache.get_definition(TASK_DEFINITION_PATH), trip_context)
	if trip == null:
		return
	task.context[CONTEXT_SOURCE_ID] = int(trip_context[CONTEXT_SOURCE_ID])
	var first_index := task.steps.size()
	task.append_steps(trip.steps)
	for i in range(trip.step_descriptions.size()):
		if first_index + i < task.step_descriptions.size():
			task.step_descriptions[first_index + i] = trip.step_descriptions[i]
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[FILL JAR] #%d %s: viaggio successivo da %s #%d, ne mancano %d." % [
			individual.id, individual.name, pick["source"].building_type_name, pick["source"].id,
			int(task.context.get(CONTEXT_REMAINING, 0))
		])


# Riva dove fermarsi a riempire: tra le rive (LiveMacroCell.drink_spots, fuori dal ruscello, libere) quella con il giro più
# corto sorgente -> riva -> tettoia, in linea d'aria. Prima nella cella dell'individuo (raggiungibile dalla sorgente), poi
# nelle altre celle vive (come ThirstService._find_drink_target, senza controllo di raggiungibilità). Punto nel riferimento
# dell'individuo, al centro della microcella; null se nessuna.
static func pick_fill_point(worker: HumanIndividual, source_point: Vector2, shelter_point: Vector2) -> Variant:
	var home := worker.home_macro_coords
	var from := Vector2i(floori(source_point.x), floori(source_point.y))
	var best: Variant = null
	var best_length := INF
	var own_cell := PathfindingService.get_live_cell(home)
	if own_cell != null:
		for spot in own_cell.drink_spots:
			if own_cell.stream_positions.has(spot):
				continue
			var point := Vector2(spot) + Vector2(0.5, 0.5)
			var length := source_point.distance_to(point) + point.distance_to(shelter_point)
			if length >= best_length:
				continue
			if PathfindingService.is_blocked(own_cell, spot) or not PathfindingService.is_reachable(own_cell, from, spot):
				continue
			best_length = length
			best = point
	if best != null:
		return best
	var live_cells := PathfindingService.get_live_cells()
	for macro in live_cells:
		if macro == home:
			continue
		var cell: LiveMacroCell = live_cells[macro]
		var offset := (Vector2i(macro) - home) * World.WIDTH
		for spot in cell.drink_spots:
			if cell.stream_positions.has(spot) or PathfindingService.is_blocked(cell, spot):
				continue
			var point := Vector2(spot + offset) + Vector2(0.5, 0.5)
			var length := source_point.distance_to(point) + point.distance_to(shelter_point)
			if length < best_length:
				best_length = length
				best = point
	return best


# --- Le tre azioni del viaggio ---

# TakeJarAction: dalla tettoia una giara vuota, da un magazzino una giara (la più consumata), nello
# zaino se ci sta. "" se riuscito, altrimenti il motivo già tradotto.
static func take_jar(individual: HumanIndividual, source: Building, context: Dictionary) -> String:
	if source == null or source.is_demolished:
		return GameContext.tr_text("fill_jar_fail_no_jar").format({"name": individual.name})
	var jar: Dictionary = _take_from_shelter(source) if is_shelter(source) else _take_from_storage(source)
	if jar.is_empty():
		return GameContext.tr_text("fill_jar_fail_no_jar").format({"name": individual.name})
	# Correzione 2026-11-07 (richiesta utente): si controlla già qui che ci starà da piena (il travois può essere sparito
	# dopo l'assegnazione); senza posto la giara resta dov'era e il compito si chiude prima di partire.
	if not _fits(individual, _filled_copy(jar)) or not individual.add_carried_tool_instance(JAR, jar):
		_give_back(source, jar)
		return GameContext.tr_text("fill_jar_fail_no_travois").format({"name": individual.name})
	# Da qui la giara è in viaggio: il posto resta riservato come "in mano", non più come "da prendere".
	context.erase(CONTEXT_SOURCE_ID)
	context[CONTEXT_CARRYING] = true
	return ""


static func _take_from_storage(source: Building) -> Dictionary:
	var units: Array = BuildingStorageService.withdraw_tool_units(source, JAR, 1)
	return units[0] if not units.is_empty() else {}


# Giara vuota (prima i pezzi nuovi); {} se nessuna è vuota.
static func _take_from_shelter(shelter: Building) -> Dictionary:
	if not shelter.stored_resources.has(JAR):
		return {}
	var entry: Dictionary = (shelter.stored_resources[JAR] as Dictionary).duplicate(true)
	var max_uses := ToolInstance.get_max_uses(JAR)
	var jar: Dictionary = {}
	if ToolInstance.get_new_quantity(entry) > 0:
		jar = ToolInstance.create(max_uses, float(entry.get("decay_fraction", 0.0)))
	else:
		var instances: Array = ToolInstance.get_used_instances(entry).duplicate()
		var best_index := -1
		for i in range(instances.size()):
			var water := ToolInstance.get_water(instances[i])
			if water <= 0:
				best_index = i
				break
		if best_index == -1:
			return {}
		jar = instances[best_index]
		instances.remove_at(best_index)
		ToolInstance.set_used_instances(entry, instances)
	entry["quantity"] = int(entry.get("quantity", 0)) - 1
	_write_shelter_entry(shelter, entry)
	return jar


# Giara rimessa dove era stata presa (zaino senza posto).
static func _give_back(source: Building, jar: Dictionary) -> void:
	if is_shelter(source):
		_add_to_shelter(source, jar)
	else:
		BuildingStorageService.store_tool_instance(source, JAR, jar)


# FillJarAction: la giara dello zaino con meno acqua si riempie fino a water_capacity, con un uso in meno (a zero si
# rompe). "" se riuscito, altrimenti il motivo già tradotto (la giara resta nello zaino, tranne quando si rompe).
static func fill_carried_jar(individual: HumanIndividual) -> String:
	var jar := _take_carried_jar(individual, false)
	if jar.is_empty():
		return GameContext.tr_text("fill_jar_fail_no_jar").format({"name": individual.name})
	var uses_left := ToolInstance.get_remaining_uses(jar) - 1
	if uses_left <= 0:
		return GameContext.tr_text("fill_jar_fail_broken").format({"name": individual.name})
	var full := _filled_copy(jar)
	full[ToolInstance.KEY_REMAINING_USES] = uses_left
	if not _fits(individual, full) or not individual.add_carried_tool_instance(JAR, full):
		individual.add_carried_tool_instance(JAR, jar)
		return GameContext.tr_text("fill_jar_fail_no_room").format({"name": individual.name})
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[FILL JAR] #%d %s: giara riempita (%d -> %d), usi rimasti %d." % [
			individual.id, individual.name, ToolInstance.get_water(jar), ToolInstance.get_water(full), uses_left
		])
	return ""


# PutJarAction: la giara dello zaino con più acqua va nella tettoia (il suo posto era riservato). Se mancano altri
# viaggi lo segna nel context (CONTEXT_PENDING_NEXT_TRIP). "" se riuscito, altrimenti il motivo già tradotto (la giara
# resta nello zaino: alla prima pausa finisce in magazzino, vuota).
static func put_jar(individual: HumanIndividual, shelter: Building, context: Dictionary) -> String:
	context.erase(CONTEXT_CARRYING)
	if not is_shelter(shelter) or shelter.is_demolished or shelter.is_out_of_service() \
			or shelter_jar_waters(shelter).size() >= shelter_capacity(shelter):
		return GameContext.tr_text("fill_jar_fail_shelter").format({"name": individual.name})
	var jar := _take_carried_jar(individual, true)
	if jar.is_empty():
		return GameContext.tr_text("fill_jar_fail_no_jar").format({"name": individual.name})
	_add_to_shelter(shelter, jar)
	var remaining := int(context.get(CONTEXT_REMAINING, 1)) - 1
	context[CONTEXT_REMAINING] = remaining
	if context.has(CONTEXT_STOP_AFTER_TRIP):
		context.erase(CONTEXT_STOP_AFTER_TRIP)
		context[CONTEXT_REMAINING] = 0
	elif remaining > 0:
		context[CONTEXT_PENDING_NEXT_TRIP] = true
	return ""


# Toglie dallo zaino la giara con meno acqua (`most_water` false) o con più acqua (true); {} se non ne ha. Le altre
# giare restano nello zaino.
static func _take_carried_jar(individual: HumanIndividual, most_water: bool) -> Dictionary:
	var quantity := individual.get_carried_quantity(JAR)
	if quantity <= 0:
		return {}
	var units: Array = individual.take_carried_tool_units(JAR, quantity)
	var best_index := -1
	for i in range(units.size()):
		if best_index == -1:
			best_index = i
			continue
		var water := ToolInstance.get_water(units[i])
		var best_water := ToolInstance.get_water(units[best_index])
		if (most_water and water > best_water) or (not most_water and water < best_water):
			best_index = i
	var jar: Dictionary = units[best_index]
	for i in range(units.size()):
		if i != best_index:
			individual.add_carried_tool_instance(JAR, units[i])
	return jar


# Copia di `jar` con l'acqua al massimo (usi invariati).
static func _filled_copy(jar: Dictionary) -> Dictionary:
	var full := jar.duplicate(true)
	ToolInstance.set_water(full, jar_water_capacity())
	return full


# true se `jar` entra nello zaino adesso (ingombro della giara più un decimo della sua acqua).
static func _fits(individual: HumanIndividual, jar: Dictionary) -> bool:
	var rules := CaloricCalculator.get_caloric_source_rules(JAR)
	if rules == null:
		return false
	var weight := rules.space_per_unit + float(ToolInstance.get_water(jar)) * ToolInstance.WATER_SPACE_PER_UNIT
	return individual.max_carry_capacity - individual.get_carried_space() + FoodSelectionService.UNIT_FIT_EPSILON >= weight


# Una giara nella tettoia, con la sua acqua: posto controllato dal chiamante.
static func _add_to_shelter(shelter: Building, jar: Dictionary) -> void:
	var entry: Dictionary = (shelter.stored_resources.get(JAR, {}) as Dictionary).duplicate(true)
	if not entry.has("decay_fraction"):
		entry["decay_fraction"] = 0.0
	if ToolInstance.is_full(jar, ToolInstance.get_max_uses(JAR)):
		entry["quantity"] = int(entry.get("quantity", 0)) + 1
	else:
		ToolInstance.add_instance_to_entry(entry, jar)
	_write_shelter_entry(shelter, entry)


static func _write_shelter_entry(shelter: Building, entry: Dictionary) -> void:
	if int(entry.get("quantity", 0)) <= 0:
		shelter.stored_resources.erase(JAR)
	else:
		shelter.stored_resources[JAR] = entry


# --- Bere (passo 4) ---

# Context del bere alla tettoia (drink.tres / emergency_drink.tres): id della tettoia scelta.
const CONTEXT_DRINK_SHELTER_ID := "drink_shelter_id"


# Tettoia più vicina a `individual` (in linea d'aria) con almeno `need` d'acqua, completa, in servizio e raggiungibile.
# {"shelter", "point" (arrivo nel riferimento dell'individuo), "distance_squared"}; {} se nessuna.
static func find_drink_shelter(individual: HumanIndividual, need: float) -> Dictionary:
	var world: World = GameSettings.active_world
	if world == null:
		return {}
	var reachable := PathfindingService.reachability_for(individual)
	var best: Dictionary = {}
	for building in world.buildings:
		if not is_shelter(building) or not building.is_complete or building.is_demolished or building.is_out_of_service():
			continue
		if not PathfindingService.get_live_cells().has(Vector2i(building.macro_x, building.macro_y)):
			continue
		if float(shelter_water(building)) < maxf(need, 1.0) or not bool(reachable.call(building)):
			continue
		var point := shelter_point(individual, building)
		var distance := individual.position.distance_squared_to(point)
		if best.is_empty() or distance < float(best["distance_squared"]):
			best = {"shelter": building, "point": point, "distance_squared": distance}
	return best


# Bevuta alla tettoia (DrinkAction): il corpo torna pieno con l'acqua delle giare (prima la giara con meno acqua), poi
# l'otre in cintura, come alla riva (un uso dell'otre per riempimento). Se non basta, beve quello che c'è. Ritorna la
# tettoia (per ridisegnarla), null se non c'è più.
static func drink_at_shelter(individual: HumanIndividual, shelter_id: int) -> Building:
	var shelter := _find_building(GameSettings.active_world, shelter_id)
	if not is_shelter(shelter) or shelter.is_demolished:
		return null
	var body_need := maxf(individual.max_thirst - individual.current_thirst, 0.0)
	var drunk := _take_shelter_water(shelter, body_need)
	individual.current_thirst = minf(individual.current_thirst + drunk, individual.max_thirst)
	individual.thirst_retry_below = INF
	if individual.current_thirst > 0.0:
		individual.dehydration_elapsed = 0.0
		individual.thirst_zero_alerted = false
	var slot_index := ThirstService.waterskin_slot(individual)
	if slot_index != -1:
		var skin_need := ThirstService.waterskin_capacity(individual) - individual.waterskin_water
		if skin_need > 0.0:
			var poured := _take_shelter_water(shelter, skin_need)
			if poured > 0.0:
				individual.waterskin_water += poured
				if individual.consume_equipped_tool_use(slot_index, GameSettings.active_game_data):
					individual.waterskin_water = 0.0
	if DebugLogging.ENABLED and DebugLogging.SHOW_THIRST_LOGS:
		print("[THIRST] #%d %s: beve %.1f alla tettoia #%d (resta %d)." % [individual.id, individual.name, drunk, shelter.id, shelter_water(shelter)])
	return shelter


# Toglie fino a `amount` d'acqua dalle giare della tettoia, dalla giara con meno acqua (le giare si svuotano una alla
# volta). Ritorna quanta ne ha tolta. L'acqua delle giare è intera: si arrotonda per eccesso, al massimo quella che c'è.
static func _take_shelter_water(shelter: Building, amount: float) -> float:
	if amount <= 0.0 or not shelter.stored_resources.has(JAR):
		return 0.0
	var entry: Dictionary = (shelter.stored_resources[JAR] as Dictionary).duplicate(true)
	var instances: Array = ToolInstance.get_used_instances(entry).duplicate(true)
	var taken := _drain_instances(instances, int(ceil(amount)))
	ToolInstance.set_used_instances(entry, instances)
	_write_shelter_entry(shelter, entry)
	return float(taken)


# Chi porta giare con acqua beve da quelle quando ha sete (ThirstService.apply_drain, dopo l'otre): quanto manca al corpo,
# dalla giara con meno acqua. Ritorna quanta ne ha bevuta.
static func drink_from_carried_jars(individual: HumanIndividual) -> float:
	if individual.get_carried_quantity(JAR) <= 0:
		return 0.0
	var need := int(ceil(individual.max_thirst - individual.current_thirst))
	if need <= 0 or ToolInstance.get_entry_water(individual.carried_resources[JAR]) <= 0:
		return 0.0
	var units: Array = individual.take_carried_tool_units(JAR, individual.get_carried_quantity(JAR))
	var drunk := _drain_instances(units, need)
	for unit in units:
		individual.add_carried_tool_instance(JAR, unit)
	individual.current_thirst = minf(individual.current_thirst + float(drunk), individual.max_thirst)
	individual.thirst_retry_below = INF
	return float(drunk)


# Toglie fino a `amount` d'acqua dalle istanze (modificate sul posto), prima da quella con meno acqua.
static func _drain_instances(instances: Array, amount: int) -> int:
	var order: Array[int] = []
	for i in range(instances.size()):
		if ToolInstance.get_water(instances[i]) > 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return ToolInstance.get_water(instances[a]) < ToolInstance.get_water(instances[b])
	)
	var taken := 0
	for index in order:
		if taken >= amount:
			break
		var water := ToolInstance.get_water(instances[index])
		var part := mini(water, amount - taken)
		ToolInstance.set_water(instances[index], water - part)
		taken += part
	return taken


static func _find_building(world: World, building_id: int) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null
