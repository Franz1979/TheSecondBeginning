class_name FamilyArrivalEvent
extends RandomEvent

# Arrivo di una famiglia (2026-09-27, richiesta utente): una coppia di adulti fertili con i loro figli entra nella
# macrocella del villaggio come gruppo di migranti (VisitorService.spawn_party) e cammina fino al centro del
# villaggio; da lì proseguono i meccanismi dei visitatori già esistenti (popup di decisione in GameScene,
# accoglienza o rifiuto). Nessun popup all'applicazione: la domanda al giocatore arriva all'arrivo del gruppo.
#
# Il sorteggio richiede il centro del villaggio (requires_village_center nel .tres); l'attivazione manuale dal
# menu di debug salta i vincoli, quindi qui l'assenza del centro è ricontrollata e segnalata.
#
# Età e figli sorteggiati a ogni arrivo (2026-10-07, richiesta utente — prima fissi: padre 25, madre 24, figli di 4 e
# 3 anni), con le stesse regole del seed iniziale (HumanSeedingService) e le durate delle fasce dell'era corrente
# (GameData.era_effective_age_band_durations_male/female):
#   - padre: età a caso nella fascia fertile, lasciando FERTILE_EDGE_MARGIN_YEARS dall'inizio e
#     FERTILE_EDGE_MARGIN_MAX_YEARS dalla fine (stessi margini del seed);
#   - madre: nella sua fascia fertile con gli stessi margini, mai più vecchia del padre;
#   - figli: da 0 a 3 (CHILDREN_COUNT_WEIGHTS, più probabili 1 e 2), sesso a caso, età intere tutte diverse e distanti
#     almeno EraRules.min_birth_spacing_years; il più grande ha al massimo CHILD_MAX_AGE_YEARS anni e al massimo l'età
#     della madre meno l'età d'inizio della fertilità (sempre una madre plausibile). Un neonato è ammesso: VisitorService
#     lo affida alla madre all'accoglienza.

const CHILDREN_COUNT_WEIGHTS: Array[float] = [0.15, 0.35, 0.35, 0.15]
const CHILD_MAX_AGE_YEARS: int = 10
# Moltiplicatore della probabilità annua quando le abitazioni del villaggio hanno posti liberi per almeno tutti
# i membri della famiglia (2026-09-27, richiesta utente): un villaggio con spazio attira chi cerca casa.
const HOUSING_AVAILABLE_MULTIPLIER: float = 1.5

# Famiglia sorteggiata dal calcolo della probabilità (get_probability_multiplier, che la usa per contare i posti) e
# salvata nell'appuntamento se l'evento viene estratto (get_schedule_params -> GameData.scheduled_random_events
# "params"["family"], salvato con la partita): all'arrivo apply usa quella (context.params), anche dopo un
# caricamento. Senza (attivazione manuale dal menu di debug, appuntamenti salvati prima): apply ne sorteggia una.
const PARAMS_FAMILY_KEY := "family"
var _rolled_family: Dictionary = {}


# Membri di `family` (padre, madre e figli).
static func get_group_size(family: Dictionary) -> int:
	return 2 + (family.get("children", []) as Array).size()


# Sorteggia la famiglia e conta i posti liberi per lei (AssignHouseService: max_residents meno residenti assegnati):
# posti >= membri -> x1.5.
func get_probability_multiplier(context: RandomEventContext) -> float:
	_rolled_family = roll_family(context.game_data)
	if AssignHouseService.count_free_slots(context.world, context.human_individuals) >= get_group_size(_rolled_family):
		return HOUSING_AVAILABLE_MULTIPLIER
	return 1.0


func get_schedule_params() -> Dictionary:
	if _rolled_family.is_empty():
		return {}
	return {PARAMS_FAMILY_KEY: _rolled_family.duplicate(true)}


# Riuscito (true) solo se il gruppo compare davvero: senza centro del villaggio o senza un bordo raggiungibile
# ritorna false, e il raffreddamento dei visitatori non riparte.
func apply(context: RandomEventContext) -> bool:
	var center := VisitorService.find_village_center(context.world)
	if center == null:
		push_warning("FamilyArrivalEvent: nessun centro del villaggio completo (Pebble Circle), la famiglia non arriva.")
		return false
	var family := _family_from_params(context.params)
	if family.is_empty():
		family = roll_family(context.game_data)
	var children: Array[Dictionary] = []
	for child in family.get("children", []):
		children.append(child)
	var members := VisitorService.build_family_members(int(family["father_age"]), int(family["mother_age"]), children)
	var party := VisitorService.spawn_party(context.game_data, context.world, center, VisitorTypes.PartyType.MIGRANTS, members)
	if party == null:
		push_warning("FamilyArrivalEvent: nessuna microcella di bordo raggiungibile (tutta acqua), la famiglia non arriva.")
		return false
	if DebugLogging.ENABLED:
		print("[VISITORS] Famiglia in arrivo: gruppo #%d (%d membri: padre %d, madre %d, figli %s) entra da %s verso %s nella macrocella %s." % [
			party.id, party.members.size(), int(family["father_age"]), int(family["mother_age"]), str(family.get("children", [])),
			str(party.entry_point), str(party.target_point), str(party.macro_coords)
		])
	return true


# Famiglia salvata nell'appuntamento, con i numeri riportati a int (JSON non distingue int/float); {} se manca o non
# è valida.
static func _family_from_params(params: Dictionary) -> Dictionary:
	var raw: Variant = params.get(PARAMS_FAMILY_KEY, {})
	if not (raw is Dictionary) or not (raw as Dictionary).has("father_age") or not (raw as Dictionary).has("mother_age"):
		return {}
	var children: Array = []
	for raw_child in (raw as Dictionary).get("children", []):
		if raw_child is Dictionary:
			children.append({"age": int(raw_child.get("age", 0)), "sex": int(raw_child.get("sex", HumanTypes.Sex.MALE))})
	return {"father_age": int(raw["father_age"]), "mother_age": int(raw["mother_age"]), "children": children}


# {"father_age": int, "mother_age": int, "children": [{"age": int, "sex": HumanTypes.Sex}, ...]} — vedi le regole in
# testa al file. Durate delle fasce da `game_data` (quelle dell'era corrente).
static func roll_family(game_data: GameData) -> Dictionary:
	var durations_male: Array[float] = game_data.era_effective_age_band_durations_male if game_data != null else ([] as Array[float])
	var durations_female: Array[float] = game_data.era_effective_age_band_durations_female if game_data != null else ([] as Array[float])
	var father_range := _fertile_age_range(durations_male)
	var father_age := randi_range(father_range.x, father_range.y)
	var mother_range := _fertile_age_range(durations_female)
	var mother_age := randi_range(mother_range.x, maxi(mother_range.x, mini(father_age, mother_range.y)))
	var fertile_start := int(HumanCalculator.get_age_band_start_age(durations_female, HumanTypes.AgeBand.FERTILE_ADULT)) \
		if durations_female.size() > int(HumanTypes.AgeBand.FERTILE_ADULT) else 15
	var max_child_age := mini(CHILD_MAX_AGE_YEARS, mother_age - fertile_start)
	var children: Array[Dictionary] = []
	for child_age in _roll_child_ages(_roll_children_count(), max_child_age, _min_birth_spacing_years(game_data)):
		children.append({"age": child_age, "sex": HumanTypes.Sex.MALE if randf() < 0.5 else HumanTypes.Sex.FEMALE})
	return {"father_age": father_age, "mother_age": mother_age, "children": children}


# Età intere ammesse per un adulto della famiglia: fascia fertile con i margini del seed; senza durate valide, 20-25.
static func _fertile_age_range(durations: Array[float]) -> Vector2i:
	if durations.size() <= int(HumanTypes.AgeBand.FERTILE_ADULT):
		return Vector2i(20, 25)
	var start := HumanCalculator.get_age_band_start_age(durations, HumanTypes.AgeBand.FERTILE_ADULT)
	var end := start + durations[HumanTypes.AgeBand.FERTILE_ADULT]
	var min_age := ceili(start + HumanSeedingService.FERTILE_EDGE_MARGIN_YEARS)
	var max_age := floori(end - HumanSeedingService.FERTILE_EDGE_MARGIN_MAX_YEARS)
	if max_age < min_age:
		return Vector2i(ceili(start), ceili(start))
	return Vector2i(min_age, max_age)


static func _roll_children_count() -> int:
	var roll := randf()
	var cumulative := 0.0
	for count in range(CHILDREN_COUNT_WEIGHTS.size()):
		cumulative += CHILDREN_COUNT_WEIGHTS[count]
		if roll < cumulative:
			return count
	return CHILDREN_COUNT_WEIGHTS.size() - 1


# Fino a `count` età intere distinte in 0..max_age, distanti almeno `spacing` anni l'una dall'altra; meno figli se
# non ci stanno. Dalla più grande alla più piccola.
static func _roll_child_ages(count: int, max_age: int, spacing: int) -> Array[int]:
	var ages: Array[int] = []
	if count <= 0 or max_age < 0:
		return ages
	var pool: Array[int] = []
	for age in range(max_age + 1):
		pool.append(age)
	pool.shuffle()
	for candidate in pool:
		if ages.size() >= count:
			break
		var fits := true
		for age in ages:
			if absi(age - candidate) < spacing:
				fits = false
				break
		if fits:
			ages.append(candidate)
	ages.sort()
	ages.reverse()
	return ages


static func _min_birth_spacing_years(game_data: GameData) -> int:
	var era_rules := EraCalculator.get_era_rules(game_data.current_era_name) if game_data != null else null
	return maxi(1, era_rules.min_birth_spacing_years if era_rules != null else 1)
