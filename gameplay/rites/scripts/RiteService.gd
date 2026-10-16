class_name RiteService
extends RefCounted

# Catalogo dei riti (2026-10-02, richiesta utente — task Rite): RiteRules caricati dalla cartella dati (stesso schema
# di RandomEventService.list_rules), e quali riti un edificio ammette e un pipottino può celebrare. Statico, la sola
# cache è l'elenco dei file letto una volta per sessione.

const DATA_DIR := "res://gameplay/rites/data/"
# Nel context della Task di un rito ordinato dal pannello (2026-10-14): al completamento evade Building.requested_rite_id.
const CONTEXT_ORDERED := "rite_ordered"

static var _rules_cache: Array[RiteRules] = []
static var _rules_loaded: bool = false


# Tutti i riti definiti, ordinati per id.
static func list_rules() -> Array[RiteRules]:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	_rules_cache.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("RiteService: cartella %s non trovata." % DATA_DIR)
		return _rules_cache
	for file_name in dir.get_files():
		# Nei progetti esportati le risorse testuali possono comparire come "*.tres.remap".
		var resource_file := String(file_name).trim_suffix(".remap")
		if resource_file.get_extension() != "tres":
			continue
		var rules := load(DATA_DIR + resource_file) as RiteRules
		if rules == null or rules.id == "":
			push_error("RiteService: %s non è un RiteRules valido." % resource_file)
			continue
		_rules_cache.append(rules)
	_rules_cache.sort_custom(func(a: RiteRules, b: RiteRules) -> bool: return a.id < b.id)
	return _rules_cache


static func get_rules(rite_id: String) -> RiteRules:
	for rules in list_rules():
		if rules.id == rite_id:
			return rules
	return null


# true se `building` può ospitare un rito ADESSO: completo, non demolito né da demolire.
static func is_building_usable(building: Building) -> bool:
	return building != null and building.rules != null and building.is_complete and not building.is_demolished \
		and not building.is_out_of_service()


# Riti ammessi da `building` (il suo tipo è in RiteRules.building_types); vuoto se l'edificio non è utilizzabile. Senza
# i riti riservati alla task Seppellisci (RiteRules.bury_task_only, 2026-10-04 — il funerale): questo elenco alimenta
# task Rito, popup e riti spontanei.
static func get_rites_for_building(building: Building) -> Array[RiteRules]:
	var rites: Array[RiteRules] = []
	if not is_building_usable(building):
		return rites
	for rules in list_rules():
		# min_buried (2026-10-04): il ricordo dei defunti richiede almeno un sepolto.
		if rules.building_types.has(building.building_type_name) and not rules.bury_task_only \
				and building.buried.size() >= rules.min_buried:
			rites.append(rules)
	return rites


# Riti che il TIPO di `building` ammette per il comando manuale (2026-10-04): in building_types e non riservati alla task
# Seppellisci, senza guardare lo stato dell'edificio né i sepolti. Serve a distinguere "nessun rito per questo tipo"
# (il click destro prosegue come un comando qualunque) da "riti ammessi ma nessuno celebrabile ora" (comando rifiutato).
static func get_type_rites(building: Building) -> Array[RiteRules]:
	var rites: Array[RiteRules] = []
	if building == null:
		return rites
	for rules in list_rules():
		if rules.building_types.has(building.building_type_name) and not rules.bury_task_only:
			rites.append(rules)
	return rites


# Motivo per cui il pannello di `building` non può ordinare `rite_id` adesso (2026-10-14, avvio dal pannello), chiave
# tr(); "" = si può. `busy_building_ids` = get_active_rite_buildings dei vivi.
static func get_order_rejection_key(building: Building, rite_id: String, busy_building_ids: Dictionary) -> String:
	var rules := get_rules(rite_id)
	if rules == null or not is_building_usable(building) or not rules.building_types.has(building.building_type_name) 			or rules.bury_task_only:
		return "rite_reject_none_available_panel"
	if building.buried.size() < rules.min_buried:
		return "rite_reject_no_buried"
	if building.requested_rite_id != "" or busy_building_ids.has(building.id):
		return "rite_reject_building_busy"
	# Nessuno che possa celebrarlo (2026-10-14, richiesta utente): pulsante spento invece di un mirino a vuoto.
	if not has_possible_celebrant(building, rules, GameSettings.active_human_individuals, GameSettings.active_game_data):
		return "rite_reject_no_celebrant"
	# Riti sociali (2026-10-14): le loro condizioni (abitanti adulti, rito già in corso) — testo già tradotto. Carne e combustibile
	# del banchetto non bloccano più l'ordine (2026-10-16): li porta l'organizzatore.
	if rules is SocialRiteRules:
		return SocialRiteService.get_start_rejection(building, rules as SocialRiteRules, GameSettings.active_human_individuals, GameSettings.active_game_data)
	return ""


# true se nel villaggio di `building` (senza villaggio: tra tutti) c'è almeno un vivo che può celebrare `rules`: età
# del rito e della task rite.tres, skill minima del tipo (can_celebrate).
const RITE_TASK_AGE_BANDS: Array[int] = [3, 4, 5]


static func has_possible_celebrant(building: Building, rules: RiteRules, individuals: Array, game_data: GameData) -> bool:
	if game_data == null:
		return true
	var folk := GameSettings.active_human_folk
	var village: Village = folk.find_village(building.village_id) if folk != null else null
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null or (village != null and individual.village_ref != village):
			continue
		var age_band := HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			individual.sex, float(game_data.year - individual.birth_year_virtual)
		)
		# I riti religiosi passano dalla task rite.tres (età propria); gli altri solo dall'età del rito.
		if rules is ReligiousRiteRules and not RITE_TASK_AGE_BANDS.has(age_band):
			continue
		if can_celebrate(rules, individual, age_band):
			return true
	return false


# Chi ha la Task del rito ORDINATO su `building` (context CONTEXT_ORDERED), in corso o in coda, con il RiteAction ancora
# da fare (2026-10-14): riga del rito nel pannello e lavoro "rite:" della coda.
static func get_ordered_rite_workers(building: Building, individuals: Array) -> Array[HumanIndividual]:
	var workers: Array[HumanIndividual] = []
	if building == null:
		return workers
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var tasks: Array[Task] = []
		if individual.current_task != null and not individual.current_task.is_finished():
			tasks.append(individual.current_task)
		tasks.append_array(individual.task_queue)
		for task in tasks:
			if is_ordered_rite_on(task, building):
				workers.append(individual)
				break
	return workers


# true se `task` è un rito ordinato (CONTEXT_ORDERED) su `building` con il RiteAction ancora da fare.
static func is_ordered_rite_on(task: Task, building: Building) -> bool:
	if task == null or task.is_finished() or not bool(task.context.get(CONTEXT_ORDERED, false)):
		return false
	for step_index in range(task.current_step_index, task.steps.size()):
		var step: Action = task.steps[step_index]
		if step is RiteAction and (step as RiteAction).target_building == building:
			return true
		# Banchetto (2026-10-14): l'organizzatore (la sua task ha CONTEXT_ORDERED).
		# Solo con il rito ancora in corso (2026-10-16, bugfix: dopo l'attesa scaduta il focolare restava occupato).
		if step is SocialRiteAttendAction and (step as SocialRiteAttendAction).target_building == building and step.is_target_valid():
			return true
	return false


# Edifici con un rito assegnato o in corso (2026-10-02 — un rito alla volta per edificio, manuale o idle): id ->
# Building, dalle Task correnti e in coda di `individuals` che contengono un RiteAction.
static func get_active_rite_buildings(individuals: Array) -> Dictionary:
	var result: Dictionary = {}
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		var tasks: Array[Task] = []
		if individual.current_task != null and not individual.current_task.is_finished():
			tasks.append(individual.current_task)
		tasks.append_array(individual.task_queue)
		for task in tasks:
			for step in task.steps:
				if step is RiteAction and (step as RiteAction).target_building != null:
					result[(step as RiteAction).target_building.id] = (step as RiteAction).target_building
				# Banchetto (2026-10-14): il focolare è occupato finché qualcuno è al banchetto o ci sta andando.
				# Solo con il rito ancora in corso (2026-10-16, bugfix): le task rimaste di un rito annullato non lo occupano.
				elif step is SocialRiteAttendAction and (step as SocialRiteAttendAction).target_building != null and step.is_target_valid():
					result[(step as SocialRiteAttendAction).target_building.id] = (step as SocialRiteAttendAction).target_building
	return result


# Riti SPONTANEI ammessi da `building` e celebrabili da `individual` (2026-10-02, rito idle).
static func get_spontaneous_rites_for(building: Building, individual: HumanIndividual, age_band: int) -> Array[RiteRules]:
	var rites: Array[RiteRules] = []
	for rules in get_rites_for_building(building):
		if rules.spontaneous and can_celebrate(rules, individual, age_band):
			rites.append(rules)
	return rites


# Bersaglio di un rito spontaneo per `individual` (2026-10-02, leisure_rite): l'edificio valido più vicino
# (SpatialSelectionService.find_nearest) — completo, non demolito, senza un rito già assegnato o in corso, con almeno
# un rito spontaneo celebrabile — e un rito a caso tra quelli. {"building": Building, "rite": RiteRules}, {} se nessuno.
static func find_spontaneous_rite_target(individual: HumanIndividual, world: World, age_band: int, individuals: Array) -> Dictionary:
	if individual == null or world == null:
		return {}
	var busy := get_active_rite_buildings(individuals)
	var predicate := func(candidate: Variant) -> bool:
		var candidate_building := candidate as Building
		# Un rito ordinato in attesa (2026-10-14, Building.requested_rite_id) tiene l'edificio libero per chi lo celebrerà.
		return candidate_building != null and not busy.has(candidate_building.id) and candidate_building.requested_rite_id == "" \
			and not get_spontaneous_rites_for(candidate_building, individual, age_band).is_empty()
	var reachable := PathfindingService.reachability_for(individual)
	# Scelta a caso (2026-10-04, richiesta utente): tra gli edifici ammessi e raggiungibili entro
	# HumanRules.spontaneous_rite_max_distance microcelle in linea d'aria, uno a caso con probabilità uguali; se non ce
	# n'è nessuno, il più vicino tra i raggiungibili, come prima.
	var nearby: Array[Building] = []
	var max_distance := _spontaneous_rite_max_distance(individual)
	for candidate in world.buildings:
		if not predicate.call(candidate):
			continue
		var macro_offset := Vector2(Vector2i(candidate.macro_x, candidate.macro_y) - individual.home_macro_coords) * World.WIDTH
		var candidate_position := Vector2(candidate.micro_x, candidate.micro_y) + macro_offset
		if individual.position.distance_to(candidate_position) > max_distance:
			continue
		if reachable.is_valid() and not reachable.call(candidate):
			continue
		nearby.append(candidate)
	if not nearby.is_empty():
		var chosen: Building = nearby.pick_random()
		return {"building": chosen, "rite": get_spontaneous_rites_for(chosen, individual, age_band).pick_random()}
	var building := SpatialSelectionService.find_nearest(
		world.buildings, individual.position, individual.home_macro_coords, predicate, [], reachable
	) as Building
	if building == null:
		return {}
	return {"building": building, "rite": get_spontaneous_rites_for(building, individual, age_band).pick_random()}


# HumanRules.spontaneous_rite_max_distance del popolo dell'individuo; il valore predefinito di HumanRules se le regole non
# sono risolvibili.
static func _spontaneous_rite_max_distance(individual: HumanIndividual) -> float:
	var folk := individual.folk_ref
	if folk == null or folk.human_rules_ref == null:
		return HumanRules.new().spontaneous_rite_max_distance
	return folk.human_rules_ref.spontaneous_rite_max_distance


# true se `individual` (nella fascia `age_band`) può celebrare `rules`: eventuale restrizione di età del rito
# (allowed_age_bands vuoto = nessuna) e skill_ritual sufficiente. La restrizione di età della task la controlla
# l'assegnazione (HumanIndividual.get_assign_rejection_reason, Task.allowed_age_bands).
static func can_celebrate(rules: RiteRules, individual: HumanIndividual, age_band: int) -> bool:
	if rules == null or individual == null:
		return false
	if not rules.allowed_age_bands.is_empty() and not rules.allowed_age_bands.has(age_band):
		return false
	# Skill del tipo del rito (2026-10-14, richiesta utente): religioso → ritualità, sociale → socialità, politico →
	# leadership, culturale → cognizione (per ora).
	return float(individual.get(get_skill_property(rules))) >= rules.min_skill


# Skill (property di HumanIndividual) che misura chi celebra un rito di questo tipo.
static func get_skill_property(rules: RiteRules) -> String:
	match rules.rite_type:
		RiteRules.RiteType.SOCIAL:
			return "skill_social"
		RiteRules.RiteType.POLITICAL:
			return "skill_leadership"
		RiteRules.RiteType.CULTURAL:
			return "skill_cognition"
	return "skill_ritual"
