class_name SocialRiteService
extends RefCounted

# Riti sociali (2026-10-14, richiesta utente — da BanquetService, generalizzato: base + specializzazione, vedi
# docs/design/socialita_teaching.md). Servizio senza stato: il raduno è generico (SocialRiteRules), falò e cibo valgono
# solo per il banchetto (BanquetRiteRules, dal 2026-10-17 sullo Spiazzo delle feste, docs/design/feast_ground.md). Lo
# stato di un rito in corso vive in GameData.active_social_rites (salvato), un record per edificio:
#   {"building_id", "rite_id", "uid" (numero del rito, 2026-10-24), "organizer_id", "phase": PHASE_PREPARING/PHASE_WAITING/PHASE_FEASTING, "elapsed" (giorni
#    della fase), "participants": {"<id>": {"counts"}}, "convoked": [id],
#    solo banchetto: "pot_calories", "pot_space", "calorie_threshold", in preparazione "material_quota"}
# Svolgimento:
#   1. start: verifiche, record e convocazione di tutto il villaggio come per il corteo funebre (tranne neonati, bisogni
#      di sopravvivenza, chi porta un corpo): ognuno riceve la task del rito (build_attend_task), che interrompe qualunque
#      altra cosa e si fa anche con lo zaino carico (HumanIndividual.assign_task, come il corteo).
#   2. on_arrival (SocialRiteAttendAction.activate): con min_participants arrivati da ragazzo in su comincia il raduno
#      (PHASE_FEASTING); banchetto: il falò brucia il suo combustibile e tutto il cibo dello spiazzo va nel piatto comune.
#   3. advance (una volta per fotogramma, da una qualunque SocialRiteAttendAction): attesa scaduta = rito saltato; a fine
#      durata _finish.
#   4. _finish: ai presenti felicità e socialità, coesione al villaggio; banchetto: le calorie del piatto comune divise tra
#      i presenti nelle provviste (eccedenza persa) e coesione in più per le calorie servite. L'ordine
#      dell'edificio (Building.requested_rite_id) è evaso.
# Presenza: la task corrente è ancora il rito su quell'edificio (is_attending). Chi se ne va perde effetti e cibo.
# Banchetto annullato o saltato: niente si consuma prima dell'inizio, cibo e combustibile restano nello spiazzo per il
# prossimo (intanto il cibo deperisce).

const TASK_NAME := "task_social_rite_name"
# Preparazione (2026-10-16, banchetto come la Produce): solo l'organizzatore, che porta prima il combustibile e poi il
# cibo nello spiazzo (MaterialSupplyService, get_preparation_missing); a soglia raggiunta la convocazione (on_prepared).
const PHASE_PREPARING := "preparing"
const PHASE_WAITING := "waiting"
const PHASE_FEASTING := "feasting"
# Nel context della task: id dell'edificio e organizzatore.
const CONTEXT_BUILDING_ID := "social_rite_building_id"
const CONTEXT_ORGANIZER := "social_rite_organizer"
# Nel record del banchetto in preparazione (2026-10-17): quanto lo spiazzo accetta ancora {risorsa: pezzi}, più il
# combustibile mancante sotto MaterialSupplyService.FUEL_KEY (in unità di fuel_value, vale per qualunque combustibile).
const MATERIAL_QUOTA_KEY := "material_quota"
# Nel record del banchetto (2026-10-17): soglia di calorie fissata all'avvio.
const CALORIE_THRESHOLD_KEY := "calorie_threshold"


static func log_event(text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_SOCIAL_RITE_LOGS:
		print("[RITO SOCIALE] %s" % text)


static func find_rite(game_data: GameData, building_id: int) -> Dictionary:
	if game_data == null:
		return {}
	for record in game_data.active_social_rites:
		if int(record.get("building_id", -1)) == building_id:
			return record
	return {}


# Motivo (testo già tradotto) per cui il rito non si può organizzare a `building` adesso; "" = si può.
static func get_start_rejection(building: Building, rules: SocialRiteRules, individuals: Array, game_data: GameData) -> String:
	if building == null or rules == null or game_data == null:
		return TranslationServer.translate("rite_reject_none_available_panel")
	# Solo negli edifici del rito (2026-10-17): un vecchio ordine rimasto su un altro tipo (il banchetto sul focolare) non
	# riparte là.
	if not rules.building_types.is_empty() and not rules.building_types.has(building.building_type_name):
		return TranslationServer.translate("social_rite_reject_wrong_building")
	if not find_rite(game_data, building.id).is_empty():
		return TranslationServer.translate("rite_reject_building_busy")
	var adults := 0
	for member in _village_members(building, individuals):
		if _counts_as_adult(member, game_data):
			adults += 1
	if adults < rules.min_village_adults:
		return TranslationServer.translate("social_rite_reject_adults").format({"n": rules.min_village_adults})
	# Convocati solo di alcune età (2026-10-16, lezione: i bambini): senza nessuno di loro nel villaggio non si fa.
	if not rules.convoked_age_bands.is_empty():
		var any_convocable := false
		for member in _village_members(building, individuals):
			if rules.convoked_age_bands.has(_age_band(member, game_data)):
				any_convocable = true
				break
		if not any_convocable:
			return TranslationServer.translate("social_rite_reject_no_convocable")
	# Cibo e combustibile non bloccano l'ordine (2026-10-16): li porta l'organizzatore in preparazione.
	return ""


# Avvia il rito con `organizer`: record e convocazione. Ritorna "" o il motivo del rifiuto (già tradotto).
# `calorie_threshold` (2026-10-17, banchetto spontaneo): soglia del banchetto se > 0, altrimenti quella dello spiazzo.
static func start(
	organizer: HumanIndividual, building: Building, rules: SocialRiteRules, individuals: Array, game_data: GameData,
	world: World, calorie_threshold: int = -1
) -> String:
	var rejection := get_start_rejection(building, rules, individuals, game_data)
	if rejection != "":
		return rejection
	# Numero del rito (2026-10-24): lo portano anche gli step delle task, che valgono solo per questo rito.
	var rite_uid := game_data.next_social_rite_uid
	game_data.next_social_rite_uid += 1
	var record := {
		"building_id": building.id, "rite_id": rules.id, "uid": rite_uid, "organizer_id": organizer.id, "phase": PHASE_PREPARING,
		"elapsed": 0.0, "participants": {}, "convoked": [],
		"pot_calories": 0.0, "pot_space": 0.0,
	}
	# Lezione (2026-10-16): la materia si fissa adesso — dal 2026-10-17 a caso tra le skill insegnabili migliori
	# dell'insegnante (TeachingRiteService.pick_subject), non più sempre la migliore.
	if rules is TeachingRiteRules:
		var subject := TeachingRiteService.pick_subject(rules as TeachingRiteRules, organizer)
		record[TeachingRiteService.RECORD_SUBJECT_KEY] = subject
		log_event("lezione di #%d %s all'edificio #%d: materia %s (%d)." % [
			organizer.id, organizer.name, building.id, subject, int(organizer.get(subject)) if subject != "" else 0
		])
	# Banchetto (2026-10-17): la soglia di calorie si fissa adesso, cambiarla nel pannello vale per il prossimo.
	if rules is BanquetRiteRules:
		record[CALORIE_THRESHOLD_KEY] = calorie_threshold if calorie_threshold > 0 \
			else get_calorie_threshold(building, rules as BanquetRiteRules)
	game_data.active_social_rites.append(record)
	# Prima solo l'organizzatore (2026-10-16): se manca materiale lo porta lui (preparazione), poi la convocazione.
	var task := build_attend_task(organizer, building, true, rules.task_label_key, rite_uid)
	var age_band := _age_band(organizer, game_data)
	if organizer.get_assign_rejection_reason(task, age_band as HumanTypes.AgeBand) == HumanIndividual.ASSIGN_OK:
		organizer.assign_task(task, age_band as HumanTypes.AgeBand)
	if organizer.current_task != task:
		cancel(building, individuals, game_data, false)
		return TranslationServer.translate("rite_reject_none_available_panel")
	(record["convoked"] as Array).append(organizer.id)
	if get_preparation_missing(building).is_empty():
		_convoke(record, building, rules, organizer, individuals, game_data)
	else:
		log_event("'%s' organizzato da #%d %s all'edificio #%d: in preparazione, manca %s." % [
			rules.id, organizer.id, organizer.name, building.id, str(get_preparation_missing(building))
		])
	return ""


# Fabbisogno della preparazione di un rito sociale in corso a `building` (2026-10-16): {} se non è in preparazione o non
# manca nulla. Banchetto sullo spiazzo (2026-10-17), un fabbisogno alla volta:
#   1. il combustibile del falò (BanquetRiteRules.bonfire_fuel) per primo, perché non deperisce: voce FUEL_KEY;
#   2. poi il cibo fino alla soglia di calorie dello spiazzo (get_calorie_threshold): dalle calorie mancanti si sceglie il
#      cibo più deperibile che ha una fonte (_food_to_fetch) e se ne chiedono i pezzi che le coprono.
# Ricalcolato a ogni richiesta. Quello che si porta va in record["material_quota"]: lo spiazzo, che ha il deposito
# riservato agli eventi, lo accetta solo fino a lì (BuildingStorageService._production_quota). Letto da
# MaterialSupplyService.get_missing_materials.
static func get_preparation_missing(building: Building) -> Dictionary:
	var missing: Dictionary = {}
	var record := find_rite(GameSettings.active_game_data, building.id) if building != null else {}
	if record.is_empty() or String(record.get("phase", "")) != PHASE_PREPARING:
		return missing
	var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as BanquetRiteRules
	if rules == null:
		return missing
	var quota: Dictionary = {}
	record[MATERIAL_QUOTA_KEY] = quota
	var missing_fuel := rules.bonfire_fuel - _stored_fuel(building)
	if missing_fuel > ProductionService.FUEL_EPSILON:
		missing[MaterialSupplyService.FUEL_KEY] = missing_fuel
		quota[MaterialSupplyService.FUEL_KEY] = missing_fuel
		return missing
	var missing_calories := float(_rite_calorie_threshold(record, building, rules)) - _stored_food_calories(building)
	if missing_calories <= 0.0:
		return missing
	var food_name := _food_to_fetch(building)
	var food_rules := CaloricCalculator.get_caloric_source_rules(food_name)
	if food_rules == null or food_rules.calories_per_unit <= 0.0:
		return missing
	var units := int(ceil(missing_calories / food_rules.calories_per_unit - 0.0001))
	missing[food_name] = units
	quota[food_name] = units
	return missing


# Soglia di calorie del banchetto a `building`: quella scelta nel pannello (Building.feast_calorie_threshold) o il valore
# di partenza dei dati, mai sotto il minimo.
static func get_calorie_threshold(building: Building, rules: BanquetRiteRules) -> int:
	if rules == null:
		return 0
	var threshold := building.feast_calorie_threshold if building != null and building.feast_calorie_threshold > 0 \
		else rules.default_calorie_threshold
	return maxi(threshold, rules.min_calorie_threshold)


# Soglia del banchetto in corso: quella fissata all'avvio (salvataggi senza: quella dello spiazzo).
static func _rite_calorie_threshold(record: Dictionary, building: Building, rules: BanquetRiteRules) -> int:
	return int(record.get(CALORIE_THRESHOLD_KEY, get_calorie_threshold(building, rules)))


# Riepilogo del deposito per il pannello (2026-10-17, richiesta utente): {} se l'edificio non ospita un banchetto;
# altrimenti {"calories", "threshold", "fuel", "fuel_needed"} — calorie e combustibile nel deposito, soglia del banchetto
# in corso (o quella dello spiazzo) e combustibile del falò.
static func get_banquet_storage_summary(building: Building) -> Dictionary:
	if building == null:
		return {}
	for type_rules in RiteService.get_type_rites(building):
		if type_rules is BanquetRiteRules:
			var rules := type_rules as BanquetRiteRules
			var record := find_rite(GameSettings.active_game_data, building.id)
			return {
				"calories": _stored_food_calories(building), "threshold": _rite_calorie_threshold(record, building, rules),
				"fuel": _stored_fuel(building), "fuel_needed": rules.bonfire_fuel,
			}
	return {}


# Combustibile nel deposito di `building` (somma di quantità × fuel_value).
static func _stored_fuel(building: Building) -> float:
	var total := 0.0
	for resource_name in building.stored_resources.keys():
		total += float(_stored_quantity(building, String(resource_name))) * ProductionService.get_fuel_value(String(resource_name))
	return total


# Calorie del cibo (categoria FOOD) nel deposito di `building`.
static func _stored_food_calories(building: Building) -> float:
	var total := 0.0
	for resource_name in building.stored_resources.keys():
		var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
		if resource_rules != null and resource_rules.category == SecondaryResourceTypes.Category.FOOD:
			total += float(_stored_quantity(building, String(resource_name))) * resource_rules.calories_per_unit
	return total


# Cibi in ordine di deperibilità (day_durability crescente; -1 = non deperisce, in fondo), calcolato una volta.
static var _foods_by_perishability: Array[String] = []


static func _get_foods_by_perishability() -> Array[String]:
	if not _foods_by_perishability.is_empty():
		return _foods_by_perishability
	var foods: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if resource_rules != null and resource_rules.category == SecondaryResourceTypes.Category.FOOD and resource_rules.calories_per_unit > 0.0:
			foods.append(resource_name)
	var durability := func(resource_name: String) -> int:
		var days := CaloricCalculator.get_caloric_source_rules(resource_name).day_durability
		return days if days > 0 else 1 << 30
	foods.sort_custom(func(a: String, b: String) -> bool:
		var days_a: int = durability.call(a)
		var days_b: int = durability.call(b)
		return days_a < days_b if days_a != days_b else a < b
	)
	_foods_by_perishability = foods
	return foods


# Cibo da portare per il banchetto di `building`: il più deperibile che un altro edificio può dare (stesse fonti dei
# rifornimenti, WarehouseSelectionService.has_retrieval_source); se nessuno ne ha, il più deperibile in assoluto (il
# rifornimento resta in attesa di materiale).
static func _food_to_fetch(building: Building) -> String:
	var world := GameSettings.active_world
	var excluded: Array[int] = [building.id]
	var foods := _get_foods_by_perishability()
	for food_name in foods:
		if WarehouseSelectionService.has_retrieval_source(world, food_name, excluded):
			return food_name
	return foods[0] if not foods.is_empty() else ""


# Quanto di `resource_name` lo spiazzo di un banchetto in preparazione accetta ancora (record["material_quota"]): il cibo
# per nome, qualunque combustibile per i pezzi che coprono il combustibile mancante; 0 altrimenti.
static func get_material_quota(game_data: GameData, building_id: int, resource_name: String) -> int:
	var record := find_rite(game_data, building_id)
	if record.is_empty() or String(record.get("phase", "")) != PHASE_PREPARING:
		return 0
	var quota: Dictionary = record.get(MATERIAL_QUOTA_KEY, {})
	if quota.has(resource_name):
		return int(quota[resource_name])
	if quota.has(MaterialSupplyService.FUEL_KEY):
		var fuel_value := ProductionService.get_fuel_value(resource_name)
		if fuel_value > 0.0:
			return int(ceil(float(quota[MaterialSupplyService.FUEL_KEY]) / fuel_value - ProductionService.FUEL_EPSILON))
	return 0


# true se a `building` c'è un banchetto nella festa vera (falò acceso, FeastFireNode — 2026-10-17).
static func has_lit_bonfire(building: Building) -> bool:
	var record := find_rite(GameSettings.active_game_data, building.id) if building != null else {}
	return not record.is_empty() and String(record.get("phase", "")) == PHASE_FEASTING 		and RiteService.get_rules(String(record.get("rite_id", ""))) is BanquetRiteRules


# true se a `building` c'è un rito sociale in preparazione.
static func is_preparing(building: Building) -> bool:
	var record := find_rite(GameSettings.active_game_data, building.id) if building != null else {}
	return not record.is_empty() and String(record.get("phase", "")) == PHASE_PREPARING


# --- riti spontanei (attività idle) ---

# Edificio per un rito sociale spontaneo di `individual` (2026-10-17, generalizzato dalla lezione al ceppo): il più vicino
# raggiungibile che ammette il rito, senza riti in corso né ordini in attesa, che get_start_rejection lascia partire e con
# l'attesa SocialRiteRules.idle_cooldown_days dall'ultimo rito sociale lì trascorsa. Banchetto: anche il freno sulle scorte
# (_has_idle_food_stock). null se l'individuo non può celebrarlo o nessun edificio va bene.
static func find_idle_target(
	rules: SocialRiteRules, individual: HumanIndividual, age_band: int, world: World, individuals: Array, game_data: GameData
) -> Building:
	if rules == null or individual == null or world == null or game_data == null:
		return null
	if not RiteService.can_celebrate(rules, individual, age_band):
		return null
	var busy := RiteService.get_active_rite_buildings(individuals)
	var today := game_data.get_absolute_day()
	var last_end: Dictionary = game_data.building_runtime.last_social_rite_end_day
	var predicate := func(candidate: Variant) -> bool:
		var building := candidate as Building
		if building == null or busy.has(building.id) or building.requested_rite_id != "":
			return false
		if not RiteService.get_rites_for_building(building).has(rules):
			return false
		if last_end.has(building.id) and float(today - int(last_end[building.id])) < rules.idle_cooldown_days:
			return false
		if rules is BanquetRiteRules and not _has_idle_food_stock(building, rules as BanquetRiteRules, world):
			return false
		return get_start_rejection(building, rules, individuals, game_data) == ""
	return SpatialSelectionService.find_nearest(
		world.buildings, individual.position, individual.home_macro_coords, predicate, [],
		PathfindingService.reachability_for(individual)
	) as Building


# Soglia di calorie di un banchetto spontaneo: dal 2026-10-18 (richiesta utente) la stessa "Soglia calorie" dello spiazzo
# (get_calorie_threshold), con o senza gestore scorte; prima era un valore a parte (dati del rito o cassetto).
static func get_idle_calorie_threshold(building: Building, rules: BanquetRiteRules) -> int:
	return get_calorie_threshold(building, rules)


# Gestore scorte sbloccato: la stessa idea che apre il cassetto Gestione scorte (WarehousePanel.REQUIRED_IDEA_ID).
static func _is_stock_manager_unlocked() -> bool:
	var folk := GameSettings.active_human_folk
	return GameSettings.active_game_data != null and folk != null and folk.completed_ideas.has(WarehousePanel.REQUIRED_IDEA_ID)


# Freno del banchetto spontaneo: cibo nei magazzini del villaggio (VillageStockService, lo spiazzo non conta) almeno
# idle_min_stock_ratio × la soglia dello spiazzo. Col gestore scorte sbloccato vale solo se la casella "solo se consumano meno
# di un terzo delle scorte" è accesa (GameData.stock_banquet_safe_only). Oggi le scorte sono di tutto il mondo
# (VillageStockService non distingue i villaggi).
static func _has_idle_food_stock(building: Building, rules: BanquetRiteRules, world: World) -> bool:
	if _is_stock_manager_unlocked() and not GameSettings.active_game_data.stock_banquet_safe_only:
		return true
	var food_calories := VillageStockService.get_food_calories(VillageStockService.get_village_stock(world))
	return food_calories >= rules.idle_min_stock_ratio * float(get_idle_calorie_threshold(building, rules))


# Preparazione finita (SocialRiteAttendAction dell'organizzatore, 2026-10-16): materiale minimo nell'edificio, si convoca
# il villaggio e comincia l'attesa dei partecipanti.
static func on_prepared(building: Building, organizer: HumanIndividual, individuals: Array, game_data: GameData) -> void:
	var record := find_rite(game_data, building.id)
	var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as SocialRiteRules
	if record.is_empty() or rules == null or String(record["phase"]) != PHASE_PREPARING:
		return
	building.is_awaiting_material = false
	_convoke(record, building, rules, organizer, individuals, game_data)


# Convocazione del villaggio (prima in start): tutti tranne neonati, chi porta un corpo, i bisogni urgenti e
# l'organizzatore, che ha già la sua task. Il rito passa all'attesa dei partecipanti.
static func _convoke(
	record: Dictionary, building: Building, rules: SocialRiteRules, organizer: HumanIndividual, individuals: Array,
	game_data: GameData
) -> void:
	record["phase"] = PHASE_WAITING
	record["elapsed"] = 0.0
	var called: Array[String] = [organizer.name]
	for member in _village_members(building, individuals):
		if member == organizer:
			continue
		# Età convocate e posti (2026-10-16, SocialRiteRules.convoked_age_bands / max_participants).
		if not rules.convoked_age_bands.is_empty() and not rules.convoked_age_bands.has(_age_band(member, game_data)):
			continue
		if rules.max_participants > 0 and called.size() - 1 >= rules.max_participants:
			break
		var skip := _skip_reason(member, game_data)
		if skip != "":
			log_event("  #%d %s non convocato: %s." % [member.id, member.name, skip])
			continue
		var task := build_attend_task(member, building, false, rules.task_label_key, int(record.get("uid", -1)))
		var age_band := _age_band(member, game_data)
		if member.get_assign_rejection_reason(task, age_band as HumanTypes.AgeBand) != HumanIndividual.ASSIGN_OK:
			continue
		member.assign_task(task, age_band as HumanTypes.AgeBand)
		if member.current_task == task:
			called.append(member.name)
			(record["convoked"] as Array).append(member.id)
	log_event("'%s' di #%d %s all'edificio #%d: convocati %d (%s)." % [
		rules.id, organizer.id, organizer.name, building.id, called.size(), ", ".join(called)
	])
	# Chi era già arrivato (l'organizzatore) può bastare a far cominciare un rito con pochi partecipanti.
	if _count_counting(record) >= rules.min_participants:
		_begin(record, building, rules)


# Inizio del raduno (prima dentro on_arrival).
static func _begin(record: Dictionary, building: Building, rules: SocialRiteRules) -> void:
	record["phase"] = PHASE_FEASTING
	record["elapsed"] = 0.0
	if rules is BanquetRiteRules:
		record.erase(MATERIAL_QUOTA_KEY)
		_banquet_light_bonfire(building, rules as BanquetRiteRules)
		_banquet_serve_food(record, building)
	log_event("all'edificio #%d comincia '%s' (%d partecipanti che contano)." % [building.id, rules.id, _count_counting(record)])


# Task del rito per `member`: [cammina all'edificio, al rito]. `rite_uid`: numero del rito (record "uid"), -1 = qualunque.
static func build_attend_task(member: HumanIndividual, building: Building, is_organizer: bool, label_key: String = "", rite_uid: int = -1) -> Task:
	var steps: Array[Action] = []
	var descriptions: Array[String] = []
	steps.append(WalkAction.new(MaterialSupplyService.building_point(member, building)))
	descriptions.append("task_social_rite_step_walk")
	steps.append(SocialRiteAttendAction.new(building, rite_uid))
	descriptions.append("task_social_rite_step_attend")
	var task := Task.new(steps)
	task.task_name = TASK_NAME
	task.step_descriptions = descriptions
	# Sospendibile (2026-10-14): un bisogno di sopravvivenza mette il rito in coda invece di cancellarlo; finito il bisogno
	# il pipottino torna. Se nel frattempo il rito non c'è più, la task in coda viene scartata (SocialRiteAttendAction.
	# is_target_valid, HumanIndividualActionService.is_task_valid).
	task.is_suspendable = true
	task.context[CONTEXT_BUILDING_ID] = building.id
	if label_key != "":
		task.context[Task.ACTIVITY_LABEL_KEY] = label_key
	if is_organizer:
		task.context[CONTEXT_ORGANIZER] = true
		task.context[RiteService.CONTEXT_ORDERED] = true
	return task


# Arrivo di `individual` all'edificio (SocialRiteAttendAction.activate). Ritorna true se con questo arrivo il raduno
# comincia (per icona e suono d'inizio).
static func on_arrival(building: Building, individual: HumanIndividual, game_data: GameData) -> bool:
	var record := find_rite(game_data, building.id)
	var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as SocialRiteRules
	if record.is_empty() or rules == null:
		return false
	var participants: Dictionary = record["participants"]
	var key := str(individual.id)
	if participants.has(key):
		return false
	# Contano i partecipanti da ragazzo in su (o le età di counted_age_bands, 2026-10-16) e sempre l'organizzatore; gli
	# altri partecipano ma non contano.
	var age_band := _age_band(individual, game_data)
	var counts := individual.id == int(record["organizer_id"])
	if not counts:
		counts = rules.counted_age_bands.has(age_band) if not rules.counted_age_bands.is_empty() else age_band != HumanTypes.AgeBand.CHILD
	participants[key] = {"counts": counts}
	log_event("#%d %s arriva all'edificio #%d%s." % [individual.id, individual.name, building.id, "" if counts else " (non conta)"])
	if String(record["phase"]) != PHASE_WAITING or _count_counting(record) < rules.min_participants:
		return false
	# Senza l'organizzatore non si comincia (2026-10-17, bugfix: la lezione partiva con due bambini e l'insegnante per strada).
	if not participants.has(str(int(record["organizer_id"]))):
		return false
	_begin(record, building, rules)
	return true


# Avanzamento del rito di `building` di `delta` giorni, una sola volta per fotogramma qualunque sia la
# SocialRiteAttendAction che lo chiama.
static func advance(building: Building, delta: float, individuals: Array, game_data: GameData) -> void:
	var record := find_rite(game_data, building.id)
	var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as SocialRiteRules
	if record.is_empty() or rules == null:
		return
	var frame := Engine.get_process_frames()
	if int(record.get("_frame", -1)) == frame:
		return
	record["_frame"] = frame
	# In preparazione nessuna scadenza (2026-10-16): l'organizzatore porta il materiale, si annulla con la X.
	if String(record["phase"]) == PHASE_PREPARING:
		return
	record["elapsed"] = float(record["elapsed"]) + delta
	if String(record["phase"]) == PHASE_WAITING:
		if float(record["elapsed"]) >= rules.wait_days:
			log_event("all'edificio #%d '%s' salta: solo %d partecipanti in %.1f giorni." % [
				building.id, rules.id, _count_counting(record), rules.wait_days
			])
			_log_missing(record, individuals)
			cancel(building, individuals, game_data, false)
		return
	if float(record["elapsed"]) >= rules.feast_days:
		_finish(record, building, rules, individuals, game_data)


# Annulla il rito di `building` (X del rito, attesa scaduta, organizzatore non convocabile): banchetto, cibo e
# combustibile già portati restano nello spiazzo per il prossimo. `stop_tasks` (X del giocatore): le task si chiudono subito
# e i pipottini fermati vengono restituiti, da rimettere in attività; false (attesa scaduta, chiamato da dentro un'azione
# del rito): le task finiscono da sole, perché SocialRiteAttendAction vede il rito sparito.
static func cancel(building: Building, individuals: Array, game_data: GameData, stop_tasks: bool = true) -> Array[HumanIndividual]:
	var freed: Array[HumanIndividual] = []
	var record := find_rite(game_data, building.id)
	if record.is_empty():
		return freed
	game_data.active_social_rites.erase(record)
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		# In coda si tolgono sempre (2026-10-16, bugfix: anche con l'attesa scaduta), quelle in corso solo con stop_tasks.
		for queued in individual.task_queue.duplicate():
			if is_rite_task_at(queued, building.id):
				individual.task_queue.erase(queued)
		if stop_tasks and is_rite_task_at(individual.current_task, building.id):
			individual.stop(false)
			freed.append(individual)
	if building.requested_rite_id == String(record.get("rite_id", "")):
		building.requested_rite_id = ""
	log_event("rito all'edificio #%d annullato." % building.id)
	return freed


static func is_rite_task_at(task: Task, building_id: int) -> bool:
	return task != null and task.task_name == TASK_NAME and int(task.context.get(CONTEXT_BUILDING_ID, -1)) == building_id


# true se `individual` è al rito di `building_id` adesso (task corrente, azione del rito in corso).
static func is_attending(individual: HumanIndividual, building_id: int) -> bool:
	if individual == null or not is_rite_task_at(individual.current_task, building_id) or individual.current_task.is_finished():
		return false
	# Lo step deve essere di questo rito (2026-10-24): la task di un rito chiuso non rende presenti al successivo.
	var step := individual.current_task.get_current_action()
	return step is SocialRiteAttendAction and step.is_target_valid()


# Convocati non ancora arrivati e cosa stanno facendo (log alla scadenza dell'attesa).
static func _log_missing(record: Dictionary, individuals: Array) -> void:
	var participants: Dictionary = record["participants"]
	for raw_id in record.get("convoked", []):
		if participants.has(str(int(raw_id))):
			continue
		var individual := _find(individuals, int(raw_id))
		if individual == null:
			log_event("  #%d non arrivato: non c'è più." % int(raw_id))
			continue
		var task := individual.current_task
		var doing := "nessuna task"
		if task != null and not task.is_finished():
			doing = "%s, passo %d/%d (%s)" % [
				task.task_name, task.current_step_index + 1, task.steps.size(),
				task.step_descriptions[task.current_step_index] if task.current_step_index < task.step_descriptions.size() else "?"
			]
		log_event("  #%d %s non arrivato: %s, zaino %s." % [individual.id, individual.name, doing, str(individual.carried_resources.keys())])


# --- fine del rito ---

static func _finish(record: Dictionary, building: Building, rules: SocialRiteRules, individuals: Array, game_data: GameData) -> void:
	game_data.active_social_rites.erase(record)
	var participants: Dictionary = record["participants"]
	var present: Array[HumanIndividual] = []
	var pot_calories := float(record.get("pot_calories", 0.0))
	var pot_space := float(record.get("pot_space", 0.0))
	for key in participants.keys():
		var individual := _find(individuals, int(key))
		if individual != null and is_attending(individual, building.id):
			present.append(individual)
	# Contagio (2026-10-25, ContagionService): ogni presente tira per ogni contagioso presente.
	ContagionService.expose_group(present, game_data, "rito '%s' all'edificio #%d" % [rules.id, building.id])
	var share := float(present.size())
	var banquet := rules as BanquetRiteRules
	for individual in present:
		var is_organizer := individual.id == int(record["organizer_id"])
		if banquet != null:
			# Calorie del piatto comune divise tra i presenti (eccedenza oltre la capienza persa).
			individual.food_calories_held += pot_calories / share if share > 0.0 else 0.0
			individual.food_space_used += pot_space / share if share > 0.0 else 0.0
			HumanFoodPouchService.clamp_to_capacity(individual)
		individual.current_happiness = clampf(individual.current_happiness + rules.happiness_gain, 0.0, maxf(individual.max_happiness, individual.current_happiness))
		var social_gain := rules.social_gain_organizer if is_organizer else rules.social_gain_participant
		individual.skill_social = minf(individual.skill_social + social_gain, HumanIndividual.SKILL_MAX)
	# Lezione (2026-10-16): materia e cognizione agli allievi presenti, punti culturali all'edificio.
	if rules is TeachingRiteRules:
		var teacher: HumanIndividual = null
		var students: Array[HumanIndividual] = []
		for individual in present:
			if individual.id == int(record["organizer_id"]):
				teacher = individual
			else:
				students.append(individual)
		TeachingRiteService.apply_lesson(record, building, rules as TeachingRiteRules, teacher, students, game_data)
	# Fine per l'attesa dei riti spontanei sullo stesso edificio (2026-10-17, ogni rito sociale).
	game_data.building_runtime.last_social_rite_end_day[building.id] = game_data.get_absolute_day()
	# Coesione (2026-10-14): fissa per il rito, più — per il banchetto — una quota per le calorie servite (2026-10-17).
	var village := _village_of(building)
	var cohesion_gain := rules.cohesion_gain
	if banquet != null:
		cohesion_gain += banquet.cohesion_gain_per_1000_calories * pot_calories / 1000.0
	var cohesion_before := village.cohesion if village != null else 0.0
	VillageCohesionService.add(village, cohesion_gain, "rito sociale '%s'" % rules.id)
	if building.requested_rite_id == rules.id:
		building.requested_rite_id = ""
	log_event("all'edificio #%d '%s' finisce: %d presenti%s; coesione %s." % [
		building.id, rules.id, present.size(),
		", %d calorie divise" % roundi(pot_calories) \
			if banquet != null else "",
		"%.2f -> %.2f (+%.2f)" % [cohesion_before, village.cohesion, cohesion_gain] if village != null else "nessun villaggio",
	])


# --- banchetto: falò e piatto comune ---

# Falò (2026-10-17): brucia dal deposito dell'edificio combustibile fino a coprire bonfire_fuel (risorse in ordine di
# nome, come ProductionService._consume_fuel); il resto resta.
static func _banquet_light_bonfire(building: Building, rules: BanquetRiteRules) -> void:
	var remaining := rules.bonfire_fuel
	var names: Array = building.stored_resources.keys()
	names.sort()
	for raw_name in names:
		if remaining <= ProductionService.FUEL_EPSILON:
			break
		var resource_name := String(raw_name)
		var fuel_value := ProductionService.get_fuel_value(resource_name)
		if fuel_value <= 0.0:
			continue
		var wanted := mini(int(ceil(remaining / fuel_value - ProductionService.FUEL_EPSILON)), _stored_quantity(building, resource_name))
		var burned := BuildingStorageService.withdraw_stored(building, resource_name, wanted)
		remaining -= float(burned) * fuel_value
		log_event("all'edificio #%d il falò brucia %d %s." % [building.id, burned, resource_name])


# Piatto comune (2026-10-17): tutto il cibo del deposito dell'edificio.
static func _banquet_serve_food(record: Dictionary, building: Building) -> void:
	for raw_name in building.stored_resources.keys().duplicate():
		var resource_name := String(raw_name)
		var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if resource_rules == null or resource_rules.category != SecondaryResourceTypes.Category.FOOD:
			continue
		var taken := BuildingStorageService.withdraw_stored(building, resource_name, _stored_quantity(building, resource_name))
		if taken <= 0:
			continue
		record["pot_calories"] = float(record["pot_calories"]) + float(taken) * resource_rules.calories_per_unit
		record["pot_space"] = float(record["pot_space"]) + float(taken) * resource_rules.space_per_unit
		log_event("all'edificio #%d nel piatto comune %d %s." % [building.id, taken, resource_name])


# --- interni ---

static func _village_members(building: Building, individuals: Array) -> Array[HumanIndividual]:
	var members: Array[HumanIndividual] = []
	var village := _village_of(building)
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null:
			continue
		if village == null or individual.village_ref == village:
			members.append(individual)
	return members


# Villaggio dell'edificio (Building.village_id); null senza villaggio (allora conta tutta la popolazione).
static func _village_of(building: Building) -> Village:
	var folk := GameSettings.active_human_folk
	return folk.find_village(building.village_id) if folk != null else null


# Come il corteo funebre (ProcessionService._skip_reason): esclusi neonati, chi porta un corpo e i bisogni di
# sopravvivenza in corso.
static func _skip_reason(individual: HumanIndividual, game_data: GameData) -> String:
	if _age_band(individual, game_data) == HumanTypes.AgeBand.INFANT:
		return "neonato"
	if individual.carried_body_id != -1:
		return "porta un corpo"
	# Malato (2026-10-24, HumanIndividual.is_sick): non va ai riti.
	if individual.is_sick():
		return "malato"
	var task := individual.current_task
	if task != null and not task.is_finished() and task.interrupt_priority != -1:
		return "bisogno urgente"
	# Già chiamato a un altro rito sociale ancora in corso (2026-10-17, bugfix: la seconda lezione rubava i bambini alla
	# prima). Una task di un rito già sparito non conta: verrà scartata.
	var tasks: Array[Task] = []
	if task != null and not task.is_finished():
		tasks.append(task)
	tasks.append_array(individual.task_queue)
	for other in tasks:
		if other.task_name == TASK_NAME and not find_rite(game_data, int(other.context.get(CONTEXT_BUILDING_ID, -1))).is_empty():
			return "a un altro rito"
	return ""


static func _counts_as_adult(individual: HumanIndividual, game_data: GameData) -> bool:
	# Malato (2026-10-24): non conta per gli adulti minimi del villaggio, al rito non verrebbe.
	if individual.is_sick():
		return false
	var age_band := _age_band(individual, game_data)
	return age_band != HumanTypes.AgeBand.INFANT and age_band != HumanTypes.AgeBand.CHILD


static func _age_band(individual: HumanIndividual, game_data: GameData) -> int:
	if game_data == null:
		return HumanTypes.AgeBand.FERTILE_ADULT
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, float(game_data.year - individual.birth_year_virtual)
	)


static func _count_counting(record: Dictionary) -> int:
	var count := 0
	for entry in (record["participants"] as Dictionary).values():
		if bool(entry.get("counts", false)):
			count += 1
	return count


static func _stored_quantity(building: Building, resource_name: String) -> int:
	return int((building.stored_resources.get(resource_name, {}) as Dictionary).get("quantity", 0))


static func _find(individuals: Array, individual_id: int) -> HumanIndividual:
	for member in individuals:
		var individual := member as HumanIndividual
		if individual != null and individual.id == individual_id:
			return individual
	return null
