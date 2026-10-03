class_name RiteService
extends RefCounted

# Catalogo dei riti (2026-10-02, richiesta utente — task Rite): RiteRules caricati dalla cartella dati (stesso schema
# di RandomEventService.list_rules), e quali riti un edificio ammette e un pipottino può celebrare. Statico, la sola
# cache è l'elenco dei file letto una volta per sessione.

const DATA_DIR := "res://gameplay/rites/data/"

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
		and not building.is_marked_for_demolition


# Riti ammessi da `building` (il suo tipo è in RiteRules.building_types); vuoto se l'edificio non è utilizzabile.
static func get_rites_for_building(building: Building) -> Array[RiteRules]:
	var rites: Array[RiteRules] = []
	if not is_building_usable(building):
		return rites
	for rules in list_rules():
		if rules.building_types.has(building.building_type_name):
			rites.append(rules)
	return rites


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
		return candidate_building != null and not busy.has(candidate_building.id) \
			and not get_spontaneous_rites_for(candidate_building, individual, age_band).is_empty()
	var building := SpatialSelectionService.find_nearest(
		world.buildings, individual.position, individual.home_macro_coords, predicate, [],
		PathfindingService.reachability_for(individual)
	) as Building
	if building == null:
		return {}
	return {"building": building, "rite": get_spontaneous_rites_for(building, individual, age_band).pick_random()}


# true se `individual` (nella fascia `age_band`) può celebrare `rules`: eventuale restrizione di età del rito
# (allowed_age_bands vuoto = nessuna) e skill_ritual sufficiente. La restrizione di età della task la controlla
# l'assegnazione (HumanIndividual.get_assign_rejection_reason, Task.allowed_age_bands).
static func can_celebrate(rules: RiteRules, individual: HumanIndividual, age_band: int) -> bool:
	if rules == null or individual == null:
		return false
	if not rules.allowed_age_bands.is_empty() and not rules.allowed_age_bands.has(age_band):
		return false
	return individual.skill_ritual >= rules.min_skill
