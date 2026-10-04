class_name BodyBurialService
extends RefCounted

# Trasporto dei corpi verso il cumulo sepolcrale (2026-10-04, richiesta utente — cumulo sepolcrale, passo 2). Stateless,
# come gli altri *Service: legge la partita attiva da GameSettings (active_game_data, active_world,
# active_human_individuals), così le Action della task Seppellisci (PickUpBodyAction, CarryBodyAction,
# PutDownBodyAction) non devono portarsi dietro riferimenti non salvabili.
#
# Il corpo è un record DEAD_BODY di game_data.expired_objects, identificato dal suo "individual_id". In spalla:
# "carried_by_id" = id del pipottino (HumanIndividual.carried_body_id = id del corpo, i due lati sempre insieme, solo da
# pick_up/put_down_carried_body), "carried_since_absolute_day" = giorno della presa; i giorni in spalla non contano per
# la scadenza (ExpiredObjectCalculator.get_elapsed_days, accumulati in "carried_days_total" alla posa). Posato al cumulo
# a fine task (disteso sulla lastra-altare dal 2026-10-04, passo 3a): "mound_id" = id del cumulo, e il corpo occupa uno dei suoi posti finché resta a terra (in attesa
# del funerale, passo successivo). "view_dirty" (transitorio, mai salvato): la vista del corpo va rifatta — la legge
# GameScene._sync_body_burial.
#
# Posti di un cumulo: BuildingRules.max_buried − Building.buried − i corpi che lo hanno come destinazione (task
# Seppellisci in corso o in coda, CarryBodyAction.target_building_id) o che vi sono già posati accanto ("mound_id").

const BURY_TASK_NAME := "task_bury_name"
const BURY_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/bury.tres"
# Chiavi del context della task (bury.tres): id del corpo e cumulo scelto all'assegnazione (consumate dagli step),
# nome del defunto (resta nel context, per la descrizione dell'attività).
const CONTEXT_BODY_ID := "bury_body_id"
const CONTEXT_MOUND_ID := "bury_mound_id"
const CONTEXT_BODY_NAME := "bury_body_name"
# Funerale (2026-10-04, passo 3b): rito dell'ultimo step di bury.tres e chiavi del suo context (edificio risolto dal
# record quando il corpo è sulla lastra, quindi null all'assegnazione).
const FUNERAL_RITE_ID := "funeral_rite"
const CONTEXT_RITE_BUILDING := "bury_rite_building"
const CONTEXT_RITE_ID := "bury_rite_id"


static func find_body_record(body_id: int) -> Dictionary:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or body_id == -1:
		return {}
	for record in game_data.expired_objects:
		if record["object_type"] == ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY and int(record["individual_id"]) == body_id:
			return record
	return {}


# true se il record è scaduto (in spalla non scade mai, vedi ExpiredObjectCalculator.is_expired).
static func is_expired(record: Dictionary) -> bool:
	var game_data: GameData = GameSettings.active_game_data
	var rules := ExpiredObjectCalculator.get_object_rules(ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY)
	if game_data == null or rules == null:
		return false
	return ExpiredObjectCalculator.is_expired(record, rules, game_data.year, game_data.current_day)


static func get_body_name(record: Dictionary) -> String:
	var data: Dictionary = record.get("type_specific_data", {})
	return String(data.get("name", ""))


# Posizione del corpo nel riferimento della macrocella `origin_macro_coords` (stessa convenzione degli edifici).
static func get_body_position_relative_to(record: Dictionary, origin_macro_coords: Vector2i) -> Vector2:
	var macro_offset := Vector2(Vector2i(record["home_macro_coords"]) - origin_macro_coords) * World.WIDTH
	return Vector2(record["position"]) + macro_offset


# Il pipottino prende il corpo in spalla: il corpo lascia il suolo (e un eventuale posto accanto a un cumulo).
static func pick_up(individual: HumanIndividual, record: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	record["carried_by_id"] = individual.id
	record["carried_since_absolute_day"] = game_data.get_absolute_day() if game_data != null else 0
	record["mound_id"] = -1
	record["view_dirty"] = true
	individual.carried_body_id = int(record["individual_id"])
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[BURY] #%d %s prende in spalla il corpo di %s." % [individual.id, individual.name, get_body_name(record)])


# Il pipottino posa il corpo che ha in spalla dove si trova (nessun effetto se non ne ha). Il record prende la posizione
# del pipottino, normalizzata nella macrocella in cui cade davvero (anche diversa da quella di partenza); la scadenza
# riprende da dove si era fermata. `mound_id` != -1: posato accanto a quel cumulo, di cui occupa un posto.
static func put_down_carried_body(individual: HumanIndividual, mound_id: int = -1) -> void:
	if individual == null or individual.carried_body_id == -1:
		return
	var record := find_body_record(individual.carried_body_id)
	individual.carried_body_id = -1
	if record.is_empty():
		return
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null and ExpiredObjectCalculator.is_carried(record):
		var carried_since := int(record.get("carried_since_absolute_day", game_data.get_absolute_day()))
		record["carried_days_total"] = int(record.get("carried_days_total", 0)) + maxi(0, game_data.get_absolute_day() - carried_since)
	record["carried_by_id"] = -1
	var macro_shift := Vector2i(floori(individual.position.x / World.WIDTH), floori(individual.position.y / World.HEIGHT))
	record["home_macro_coords"] = individual.home_macro_coords + macro_shift
	record["position"] = individual.position - Vector2(macro_shift.x * World.WIDTH, macro_shift.y * World.HEIGHT)
	# Posato al cumulo (2026-10-04, passo 3a): disteso sulla lastra-altare, dentro la microcella del cumulo (il pipottino
	# resta nella microcella accanto). Cumulo non più trovato: resta dove si trova il pipottino.
	var mound := find_building(mound_id)
	if mound != null:
		record["home_macro_coords"] = Vector2i(mound.macro_x, mound.macro_y)
		record["position"] = Vector2(mound.micro_x, mound.micro_y) + PlaceholderBuildingShapes.burial_slab_center_microcell()
	record["mound_id"] = mound_id
	record["view_dirty"] = true
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[BURY] #%d %s posa il corpo di %s in %s (macrocella %s)%s." % [
			individual.id, individual.name, get_body_name(record), str(record["position"]), str(record["home_macro_coords"]),
			" accanto al cumulo #%d" % mound_id if mound_id != -1 else ""
		])


# true se il corpo è disteso sulla lastra di un cumulo (posato a fine task Seppellisci, "mound_id").
static func is_on_slab(record: Dictionary) -> bool:
	return not ExpiredObjectCalculator.is_carried(record) and int(record.get("mound_id", -1)) != -1


static func is_bury_task(task: Task) -> bool:
	return task != null and task.task_name == BURY_TASK_NAME


# Id del corpo di una task Seppellisci, -1 se non ne ha.
static func get_task_body_id(task: Task) -> int:
	if task == null:
		return -1
	for step in task.steps:
		if step is PickUpBodyAction:
			return (step as PickUpBodyAction).body_id
		if step is CarryBodyAction:
			return (step as CarryBodyAction).body_id
		if step is PutDownBodyAction:
			return (step as PutDownBodyAction).body_id
	return -1


# Cumulo di destinazione di una task Seppellisci, -1 se nessuno.
static func get_task_mound_id(task: Task) -> int:
	if task == null:
		return -1
	for step in task.steps:
		if step is CarryBodyAction:
			return (step as CarryBodyAction).target_building_id
	return -1


# Task Seppellisci in corso o in coda di `individuals`.
static func get_active_bury_tasks(individuals: Array) -> Array[Task]:
	var tasks: Array[Task] = []
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		if is_bury_task(individual.current_task) and not individual.current_task.is_finished():
			tasks.append(individual.current_task)
		for queued in individual.task_queue:
			if is_bury_task(queued) and not queued.is_finished():
				tasks.append(queued)
	return tasks


# Pipottino con la task Seppellisci del corpo `body_id` (in corso o in coda), null se nessuno.
static func get_bury_assignee(body_id: int, individuals: Array) -> HumanIndividual:
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var tasks: Array[Task] = []
		if individual.current_task != null and not individual.current_task.is_finished():
			tasks.append(individual.current_task)
		tasks.append_array(individual.task_queue)
		for task in tasks:
			if is_bury_task(task) and get_task_body_id(task) == body_id:
				return individual
	return null


static func is_mound(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.max_buried > 0


# Posti già presi del cumulo da corpi diversi da `excluding_body_id`: destinazione di una task Seppellisci attiva, o già
# posati accanto (a terra, non scaduti).
static func count_reserved_places(building: Building, excluding_body_id: int, individuals: Array) -> int:
	var bodies: Dictionary = {}
	for task in get_active_bury_tasks(individuals):
		var body_id := get_task_body_id(task)
		if body_id != excluding_body_id and get_task_mound_id(task) == building.id:
			bodies[body_id] = true
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null:
		for record in game_data.expired_objects:
			if record["object_type"] != ExpiredObjectTypes.ExpiredObjectType.DEAD_BODY:
				continue
			var body_id := int(record["individual_id"])
			if body_id == excluding_body_id or int(record.get("mound_id", -1)) != building.id:
				continue
			if ExpiredObjectCalculator.is_carried(record) or is_expired(record):
				continue
			bodies[body_id] = true
	return bodies.size()


# true se il cumulo può accogliere il corpo `body_id`: completo, non demolito né da demolire, con un posto libero
# (il posto eventualmente già preso da questo stesso corpo conta come suo).
static func is_mound_usable(building: Building, body_id: int, individuals: Array) -> bool:
	if not is_mound(building) or not building.is_complete or building.is_demolished or building.is_marked_for_demolition:
		return false
	return building.buried.size() + count_reserved_places(building, body_id, individuals) < building.rules.max_buried


# Cumulo utilizzabile più vicino a `origin_position` (nel riferimento di `origin_macro_coords`), null se nessuno.
static func find_nearest_mound(
	origin_position: Vector2, origin_macro_coords: Vector2i, body_id: int, individuals: Array, reachable: Callable = Callable()
) -> Building:
	var world: World = GameSettings.active_world
	if world == null:
		return null
	var predicate := func(candidate: Variant) -> bool:
		return is_mound_usable(candidate as Building, body_id, individuals)
	return SpatialSelectionService.find_nearest(
		world.buildings, origin_position, origin_macro_coords, predicate, [], reachable
	) as Building


static func find_building(building_id: int) -> Building:
	var world: World = GameSettings.active_world
	if world == null or building_id == -1:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


# Punto "accanto al cumulo" nel riferimento di `individual`: la microcella vicina (8 direzioni) non bloccata più vicina
# al pipottino; la microcella del cumulo stessa se nessuna vicina è libera.
static func get_put_down_point(building: Building, individual: HumanIndividual) -> Vector2:
	var mound_macro := Vector2i(building.macro_x, building.macro_y)
	var macro_offset := Vector2(mound_macro - individual.home_macro_coords) * World.WIDTH
	var cell: LiveMacroCell = PathfindingService.get_live_cell(mound_macro)
	var has_grid := cell != null and cell.path_grid != null
	var best := Vector2i(building.micro_x, building.micro_y)
	var best_distance := INF
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(building.micro_x + dx, building.micro_y + dy)
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= World.WIDTH or neighbor.y >= World.HEIGHT:
				continue
			if has_grid and PathfindingService.is_blocked(cell, neighbor):
				continue
			var distance := (Vector2(neighbor) + Vector2(0.5, 0.5) + macro_offset).distance_to(individual.position)
			if distance < best_distance:
				best_distance = distance
				best = neighbor
	return PathfindingService.random_point_in_microcell(Vector2(best) + macro_offset)


# Invariante del corpo in spalla, controllata ogni frame da GameScene per ogni pipottino: il corpo resta in spalla solo
# mentre la task Seppellisci che lo porta è quella in corso, al passo "cammina al cumulo" o "posa il corpo". In ogni
# altro caso (task interrotta da un bisogno o da un altro ordine, annullata, scartata) il pipottino posa il corpo dove si
# trova; se la task è in coda, alla ripresa ricomincia da "prendi il corpo" (che riporta il pipottino al corpo, vedi
# PickUpBodyAction.get_required_position).
static func enforce_carrier(individual: HumanIndividual) -> void:
	if individual == null or individual.carried_body_id == -1:
		return
	var body_id := individual.carried_body_id
	var task := individual.current_task
	if is_bury_task(task) and not task.is_finished():
		var action := task.get_current_action()
		if (action is CarryBodyAction and (action as CarryBodyAction).body_id == body_id) \
				or (action is PutDownBodyAction and (action as PutDownBodyAction).body_id == body_id):
			return
	put_down_carried_body(individual)
	for queued in individual.task_queue:
		if is_bury_task(queued) and get_task_body_id(queued) == body_id:
			rewind_to_pick_up(queued)


# Parenti del defunto del record (2026-10-04, funerale): partner, genitori (dal record, -1 = nessuno; i record precedenti
# a questi campi non ne hanno) e figli (pipottini con mother_id/father_id = il defunto). id -> "partner"/"parent"/
# "child" (il tipo serve al log [RITE]; chi legge l'appartenenza usa has()).
static func get_relative_ids(record: Dictionary, individuals: Array) -> Dictionary:
	var relatives: Dictionary = {}
	if record.is_empty():
		return relatives
	var data: Dictionary = record.get("type_specific_data", {})
	for key in ["partner_id", "mother_id", "father_id"]:
		var relative_id := int(data.get(key, -1))
		if relative_id != -1:
			relatives[relative_id] = "partner" if key == "partner_id" else "parent"
	var deceased_id := int(record["individual_id"])
	for member in individuals:
		var individual := member as HumanIndividual
		if individual != null and (individual.mother_id == deceased_id or individual.father_id == deceased_id):
			relatives[individual.id] = "child"
	return relatives


# Corteo funebre (2026-10-04, richiesta utente): quando `carrier` prende il corpo (PickUpBodyAction, anche a una ripresa
# dalla coda), partner, genitori e figli vivi del morto vengono convocati a seguirlo fino al cumulo di destinazione della
# sua task Seppellisci e a restarvi accanto fino alla fine del rito (ProcessionService). Distanza massima: RiteRules.
# procession_max_distance del rito funebre (0 = nessun corteo). Log [RITE]: una riga per parente, convocato o perché no.
static func convoke_funeral_procession(carrier: HumanIndividual, record: Dictionary) -> void:
	if carrier == null or record.is_empty() or not is_bury_task(carrier.current_task):
		return
	var rules := RiteService.get_rules(FUNERAL_RITE_ID)
	if rules == null or rules.procession_max_distance <= 0.0:
		return
	var mound := find_building(get_task_mound_id(carrier.current_task))
	if mound == null:
		return
	var individuals: Array = GameSettings.active_human_individuals
	var relative_ids := get_relative_ids(record, individuals)
	var participants: Array = []
	for member in individuals:
		var individual := member as HumanIndividual
		if individual != null and relative_ids.has(individual.id):
			participants.append(individual)
	var body_name := get_body_name(record)
	var keeper_task := carrier.current_task
	var procession_text := TranslationServer.translate("procession_funeral_text").format({"name": body_name})
	var results := ProcessionService.convoke(
		carrier, keeper_task, participants, mound, procession_text, rules.procession_max_distance
	)
	var log_enabled := DebugLogging.ENABLED and DebugLogging.SHOW_RITE_LOGS
	# Richiamo dei parenti saltati (2026-10-04): solo i parenti, ogni procession_recall_interval_days giorni finché il
	# corteo è in corso (ProcessionService.tick). Gli abitanti della leadership sono scelti solo qui sotto, una volta.
	var relative_id_list: Array = []
	for participant in participants:
		relative_id_list.append((participant as HumanIndividual).id)
	ProcessionService.set_recall(carrier, relative_id_list, rules.procession_recall_interval_days, "[RITE]" if log_enabled else "")
	if log_enabled:
		print("[RITE] corteo funebre di %s: guida #%d %s, cumulo #%d, %d parenti vivi." % [
			body_name, carrier.id, carrier.name, mound.id, participants.size()
		])
		for result in results:
			var relative: HumanIndividual = result["individual"]
			print("[RITE]   #%d %s (%s): %s." % [
				relative.id, relative.name, RiteEffectService._relative_kind_text(relative_ids[relative.id]), result["outcome"]
			])
	# Corteo esteso dalla leadership del morto (2026-10-04): dopo i parenti, in fila dietro di loro, una quota degli
	# abitanti candidati — candidati × leadership ÷ procession_full_leadership, arrotondato, mai oltre i candidati — i
	# più vicini alla guida. Candidati: vivi, della stessa popolazione (stesso criterio della fede del rito a tutta la
	# popolazione: source_group_ref di chi celebra, qui il portatore), non parenti, da adolescenti in su, convocabili.
	if rules.procession_full_leadership <= 0.0 or carrier.source_group_ref == null:
		return
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	var leadership := float((record.get("type_specific_data", {}) as Dictionary).get("skill_leadership", 0.0))
	var candidates: Array = []
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null or individual.source_group_ref != carrier.source_group_ref or relative_ids.has(individual.id):
			continue
		if HumanIndividualActionService._resolve_age_band(individual, game_data) < HumanTypes.AgeBand.TEENAGER:
			continue
		if ProcessionService.get_skip_reason(individual, carrier, rules.procession_max_distance) != "":
			continue
		candidates.append(individual)
	var count := mini(roundi(float(candidates.size()) * leadership / rules.procession_full_leadership), candidates.size())
	candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
		return ProcessionService.distance_between(a as HumanIndividual, carrier) < ProcessionService.distance_between(b as HumanIndividual, carrier)
	)
	var chosen: Array = candidates.slice(0, maxi(count, 0))
	var extended_results: Array[Dictionary] = []
	if not chosen.is_empty():
		extended_results = ProcessionService.convoke(
			carrier, keeper_task, chosen, mound, procession_text, rules.procession_max_distance, false
		)
	if log_enabled:
		var convoked := 0
		for result in extended_results:
			if result["outcome"] == ProcessionService.OUTCOME_CONVOKED:
				convoked += 1
		print("[RITE] corteo esteso: leadership del defunto %.1f (valore pieno %.0f), %d candidati, %d scelti, %d convocati." % [
			leadership, rules.procession_full_leadership, candidates.size(), chosen.size(), convoked
		])
		for result in extended_results:
			var inhabitant: HumanIndividual = result["individual"]
			print("[RITE]   #%d %s (abitante, %.1f microcelle): %s." % [
				inhabitant.id, inhabitant.name, ProcessionService.distance_between(inhabitant, carrier), result["outcome"]
			])


# Parenti vivi dei sepolti in `building` (2026-10-04, ricordo dei defunti — rito senza defunto): partner, genitori (dai
# dati salvati alla sepoltura) e figli (pipottini con mother_id/father_id = il sepolto) di ciascun sepolto. id ->
# {"kind": "partner"/"parent"/"child", "of": nome del sepolto}; un pipottino parente di più sepolti compare una volta
# (il primo trovato). I sepolti senza dati di parentela (save precedenti) contano solo per i figli.
static func get_buried_relative_ids(building: Building, individuals: Array) -> Dictionary:
	var relatives: Dictionary = {}
	if building == null or building.buried.is_empty():
		return relatives
	for entry in building.buried:
		var buried_entry: Dictionary = entry if entry is Dictionary else {}
		var deceased_id := int(buried_entry.get("individual_id", -1))
		var deceased_name := String(buried_entry.get("name", "?"))
		for key in ["partner_id", "mother_id", "father_id"]:
			var relative_id := int(buried_entry.get(key, -1))
			if relative_id != -1 and not relatives.has(relative_id):
				relatives[relative_id] = {"kind": "partner" if key == "partner_id" else "parent", "of": deceased_name}
		if deceased_id == -1:
			continue
		for member in individuals:
			var individual := member as HumanIndividual
			if individual != null and not relatives.has(individual.id) \
					and (individual.mother_id == deceased_id or individual.father_id == deceased_id):
				relatives[individual.id] = {"kind": "child", "of": deceased_name}
	return relatives


# Funerale concluso (2026-10-04): il corpo viene consumato — il record sparisce da game_data.expired_objects (la vista la
# toglie GameScene._sync_body_burial) e il defunto entra in Building.buried del cumulo, con nome e anno di sepoltura.
static func bury_body(record: Dictionary, building: Building) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if record.is_empty() or building == null or game_data == null:
		return
	game_data.expired_objects.erase(record)
	# Parentela del sepolto (2026-10-04, ricordo dei defunti): genitori e partner dal record (-1 se mancanti), per
	# riconoscerne i parenti nei riti successivi (get_buried_relative_ids). I sepolti dei save precedenti non li hanno.
	var data: Dictionary = record.get("type_specific_data", {})
	building.buried.append({
		"individual_id": int(record["individual_id"]),
		"name": get_body_name(record),
		"year": game_data.year,
		"mother_id": int(data.get("mother_id", -1)),
		"father_id": int(data.get("father_id", -1)),
		"partner_id": int(data.get("partner_id", -1)),
	})
	if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
		print("[BURY] %s sepolto nel cumulo #%d (anno %d, sepolti %d/%d)." % [
			get_body_name(record), building.id, game_data.year, building.buried.size(),
			building.rules.max_buried if building.rules != null else 0
		])


# Corpo già sulla lastra (2026-10-04, funerale): la task Seppellisci salta il trasporto e passa direttamente al rito —
# a un nuovo comando su un corpo già posato e alla ripresa dalla coda. `walker` != null: inserisce anche il cammino fino
# accanto al cumulo (assegnazione nuova; alla ripresa ci pensa il ritorno automatico al punto richiesto dallo step).
static func skip_transport_if_on_slab(task: Task, walker: HumanIndividual = null) -> void:
	if not is_bury_task(task):
		return
	var record := find_body_record(get_task_body_id(task))
	if record.is_empty() or not is_on_slab(record):
		return
	for i in range(task.steps.size()):
		if not (task.steps[i] is RiteAction):
			continue
		if task.current_step_index >= i:
			return
		task.current_step_index = i
		var rite := task.steps[i] as RiteAction
		if walker != null and rite.is_target_valid():
			var required: Variant = rite.get_required_position(walker, task.context)
			if required != null:
				task.insert_step_before_current(WalkAction.new(required))
		return


# Riporta la task Seppellisci al passo "prendi il corpo" (se l'ha già superato).
static func rewind_to_pick_up(task: Task) -> void:
	for i in range(task.steps.size()):
		if task.steps[i] is PickUpBodyAction:
			if task.current_step_index > i:
				task.current_step_index = i
			return
