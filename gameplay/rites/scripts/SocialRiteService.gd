class_name SocialRiteService
extends RefCounted

# Riti sociali (2026-10-14, richiesta utente — da BanquetService, generalizzato: base + specializzazione, vedi
# docs/design/socialita_teaching.md). Servizio senza stato: il raduno è generico (SocialRiteRules), la cottura vale solo
# per il banchetto (BanquetRiteRules). Lo stato di un rito in corso vive in GameData.active_social_rites (salvato), un
# record per edificio:
#   {"building_id", "rite_id", "organizer_id", "phase": PHASE_WAITING/PHASE_FEASTING, "elapsed" (giorni della fase),
#    "participants": {"<id>": {"counts"}}, "convoked": [id],
#    solo banchetto: "order_key" (ordine di cottura), "meat_units", "pot_calories", "pot_space", "cooked"}
# Svolgimento:
#   1. start: verifiche, record e convocazione di tutto il villaggio come per il corteo funebre (tranne neonati, bisogni
#      di sopravvivenza, chi porta un corpo): ognuno riceve la task del rito (build_attend_task), che interrompe qualunque
#      altra cosa e si fa anche con lo zaino carico (HumanIndividual.assign_task, come il corteo).
#   2. on_arrival (SocialRiteAttendAction.activate): con min_participants arrivati da ragazzo in su comincia il raduno
#      (PHASE_FEASTING); banchetto: si apre l'ordine di cottura di tutta la carne cruda del focolare.
#   3. advance (una volta per fotogramma, da una qualunque SocialRiteAttendAction): attesa scaduta = rito saltato;
#      banchetto: l'organizzatore, se presente, cuoce tutta la carne entro la durata; a fine durata _finish.
#   4. _finish: ai presenti felicità e socialità, coesione al villaggio; banchetto: le calorie della carne cotta divise tra
#      i presenti nelle provviste (eccedenza persa) e il bonus della Produce all'organizzatore. L'ordine dell'edificio
#      (Building.requested_rite_id) è evaso.
# Presenza: la task corrente è ancora il rito su quell'edificio (is_attending). Chi se ne va perde effetti e carne.
# Dal 2026-10-14 (richiesta utente) il banchetto non chiede più cibo portato dai partecipanti: solo la carne del focolare.

const TASK_NAME := "task_social_rite_name"
# Preparazione (2026-10-16, banchetto come la Produce): solo l'organizzatore, che porta prima il combustibile e poi la
# carne nel focolare (MaterialSupplyService, get_preparation_missing); a minimo raggiunto la convocazione (on_prepared).
const PHASE_PREPARING := "preparing"
const PHASE_WAITING := "waiting"
const PHASE_FEASTING := "feasting"
# Nel context della task: id dell'edificio e organizzatore.
const CONTEXT_BUILDING_ID := "social_rite_building_id"
const CONTEXT_ORGANIZER := "social_rite_organizer"
const PRODUCE_SKILL_KEY := "produce"


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
	if not find_rite(game_data, building.id).is_empty():
		return TranslationServer.translate("rite_reject_building_busy")
	var adults := 0
	for member in _village_members(building, individuals):
		if _counts_as_adult(member, game_data):
			adults += 1
	if adults < rules.min_village_adults:
		return TranslationServer.translate("social_rite_reject_adults").format({"n": rules.min_village_adults})
	# Carne e combustibile non bloccano più l'ordine (2026-10-16): li porta l'organizzatore in preparazione.
	return ""


# Avvia il rito con `organizer`: record e convocazione. Ritorna "" o il motivo del rifiuto (già tradotto).
static func start(
	organizer: HumanIndividual, building: Building, rules: SocialRiteRules, individuals: Array, game_data: GameData,
	world: World
) -> String:
	var rejection := get_start_rejection(building, rules, individuals, game_data)
	if rejection != "":
		return rejection
	var record := {
		"building_id": building.id, "rite_id": rules.id, "organizer_id": organizer.id, "phase": PHASE_PREPARING,
		"elapsed": 0.0, "participants": {}, "convoked": [],
		"order_key": "", "meat_units": 0, "pot_calories": 0.0, "pot_space": 0.0, "cooked": 0,
	}
	game_data.active_social_rites.append(record)
	# Prima solo l'organizzatore (2026-10-16): se manca materiale lo porta lui (preparazione), poi la convocazione.
	var task := build_attend_task(organizer, building, true)
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
# manca nulla. Banchetto: prima SOLO il combustibile per i pezzi minimi (MaterialSupplyService.FUEL_KEY), poi la carne
# cruda mancante — la carne arriva per ultima e non aspetta deperendo. Letto da MaterialSupplyService.get_missing_materials.
static func get_preparation_missing(building: Building) -> Dictionary:
	var missing: Dictionary = {}
	var record := find_rite(GameSettings.active_game_data, building.id) if building != null else {}
	if record.is_empty() or String(record.get("phase", "")) != PHASE_PREPARING:
		return missing
	var rules := RiteService.get_rules(String(record.get("rite_id", ""))) as BanquetRiteRules
	if rules == null:
		return missing
	var raw_meat := _stored_quantity(building, rules.raw_meat_resource)
	var fuel_per_piece := ProductionService.get_required_fuel(building, rules.cooked_resource)
	var reserved := {rules.raw_meat_resource: raw_meat}
	var missing_fuel := fuel_per_piece * float(rules.min_raw_meat) - ProductionService.get_available_fuel(building, reserved)
	if missing_fuel > ProductionService.FUEL_EPSILON:
		missing[MaterialSupplyService.FUEL_KEY] = missing_fuel
		return missing
	if raw_meat < rules.min_raw_meat:
		missing[rules.raw_meat_resource] = rules.min_raw_meat - raw_meat
	return missing


# true se a `building` c'è un rito sociale in preparazione.
static func is_preparing(building: Building) -> bool:
	var record := find_rite(GameSettings.active_game_data, building.id) if building != null else {}
	return not record.is_empty() and String(record.get("phase", "")) == PHASE_PREPARING


# Preparazione finita (SocialRiteAttendAction dell'organizzatore, 2026-10-16): materiale minimo nel focolare, si convoca
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
		var skip := _skip_reason(member, game_data)
		if skip != "":
			log_event("  #%d %s non convocato: %s." % [member.id, member.name, skip])
			continue
		var task := build_attend_task(member, building, false)
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
		_banquet_open_cooking(record, building, rules as BanquetRiteRules)
	log_event("all'edificio #%d comincia '%s' (%d partecipanti che contano)." % [building.id, rules.id, _count_counting(record)])


# Task del rito per `member`: [cammina all'edificio, al rito].
static func build_attend_task(member: HumanIndividual, building: Building, is_organizer: bool) -> Task:
	var steps: Array[Action] = []
	var descriptions: Array[String] = []
	steps.append(WalkAction.new(MaterialSupplyService.building_point(member, building)))
	descriptions.append("task_social_rite_step_walk")
	steps.append(SocialRiteAttendAction.new(building))
	descriptions.append("task_social_rite_step_attend")
	var task := Task.new(steps)
	task.task_name = TASK_NAME
	task.step_descriptions = descriptions
	# Sospendibile (2026-10-14): un bisogno di sopravvivenza mette il rito in coda invece di cancellarlo; finito il bisogno
	# il pipottino torna. Se nel frattempo il rito non c'è più, la task in coda viene scartata (SocialRiteAttendAction.
	# is_target_valid, HumanIndividualActionService.is_task_valid).
	task.is_suspendable = true
	task.context[CONTEXT_BUILDING_ID] = building.id
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
	# Contano i partecipanti da ragazzo in su; i bambini partecipano ma non contano.
	var counts := _age_band(individual, game_data) != HumanTypes.AgeBand.CHILD
	participants[key] = {"counts": counts}
	log_event("#%d %s arriva all'edificio #%d%s." % [individual.id, individual.name, building.id, "" if counts else " (bambino, non conta)"])
	if String(record["phase"]) != PHASE_WAITING or _count_counting(record) < rules.min_participants:
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
	if rules is BanquetRiteRules:
		_banquet_cook(record, building, rules as BanquetRiteRules, delta, individuals)
	if float(record["elapsed"]) >= rules.feast_days:
		_finish(record, building, rules, individuals, game_data)


# Annulla il rito di `building` (X del rito, attesa scaduta, organizzatore non convocabile): l'ordine di cottura si
# annulla, la carne cruda non cotta resta nel focolare. `stop_tasks` (X del giocatore): le task si chiudono subito
# e i pipottini fermati vengono restituiti, da rimettere in attività; false (attesa scaduta, chiamato da dentro un'azione
# del rito): le task finiscono da sole, perché SocialRiteAttendAction vede il rito sparito.
static func cancel(building: Building, individuals: Array, game_data: GameData, stop_tasks: bool = true) -> Array[HumanIndividual]:
	var freed: Array[HumanIndividual] = []
	var record := find_rite(game_data, building.id)
	if record.is_empty():
		return freed
	game_data.active_social_rites.erase(record)
	if String(record.get("order_key", "")) != "":
		ProductionService.cancel_order(building, String(record["order_key"]))
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
	return individual.current_task.get_current_action() is SocialRiteAttendAction


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
	if String(record.get("order_key", "")) != "":
		ProductionService.cancel_order(building, String(record["order_key"]))
	var participants: Dictionary = record["participants"]
	var present: Array[HumanIndividual] = []
	var pot_calories := float(record.get("pot_calories", 0.0))
	var pot_space := float(record.get("pot_space", 0.0))
	for key in participants.keys():
		var individual := _find(individuals, int(key))
		if individual != null and is_attending(individual, building.id):
			present.append(individual)
	var share := float(present.size())
	var banquet := rules as BanquetRiteRules
	for individual in present:
		var is_organizer := individual.id == int(record["organizer_id"])
		if banquet != null:
			# Calorie della carne cotta divise tra i presenti (eccedenza oltre la capienza persa).
			individual.food_calories_held += pot_calories / share if share > 0.0 else 0.0
			individual.food_space_used += pot_space / share if share > 0.0 else 0.0
			HumanFoodPouchService.clamp_to_capacity(individual)
			if is_organizer and int(record.get("cooked", 0)) > 0:
				individual.skill_crafting = minf(individual.skill_crafting + banquet.crafting_gain_organizer, HumanIndividual.SKILL_MAX)
		individual.current_happiness = clampf(individual.current_happiness + rules.happiness_gain, 0.0, maxf(individual.max_happiness, individual.current_happiness))
		var social_gain := rules.social_gain_organizer if is_organizer else rules.social_gain_participant
		individual.skill_social = minf(individual.skill_social + social_gain, HumanIndividual.SKILL_MAX)
	# Coesione (2026-10-14): fissa per il rito, più — per il banchetto — una quota per ogni carne cotta (quanto si festeggia).
	var village := _village_of(building)
	var cohesion_gain := rules.cohesion_gain
	if banquet != null:
		cohesion_gain += banquet.cohesion_gain_per_meat * float(int(record.get("cooked", 0)))
	var cohesion_before := village.cohesion if village != null else 0.0
	VillageCohesionService.add(village, cohesion_gain, "rito sociale '%s'" % rules.id)
	if building.requested_rite_id == rules.id:
		building.requested_rite_id = ""
	log_event("all'edificio #%d '%s' finisce: %d presenti%s; coesione %s." % [
		building.id, rules.id, present.size(),
		", %d carni cotte, %d calorie divise" % [int(record.get("cooked", 0)), roundi(pot_calories)] if banquet != null else "",
		"%.2f -> %.2f (+%.2f)" % [cohesion_before, village.cohesion, cohesion_gain] if village != null else "nessun villaggio",
	])


# --- banchetto: cottura ---

# Pezzi che si possono cuocere adesso (2026-10-15): il minimo tra la carne cruda nel focolare e i pezzi che il
# combustibile copre (combustibile disponibile senza contare la carne / combustibile di un pezzo).
static func _banquet_cookable_units(building: Building, rules: BanquetRiteRules) -> int:
	var raw_meat := _stored_quantity(building, rules.raw_meat_resource)
	var fuel_per_piece := ProductionService.get_required_fuel(building, rules.cooked_resource)
	if fuel_per_piece <= 0.0:
		return raw_meat
	var recipe := CaloricCalculator.get_caloric_source_rules(rules.cooked_resource)
	var reserved: Dictionary = {}
	if recipe != null:
		for input_name in recipe.recipe_inputs.keys():
			reserved[input_name] = int(recipe.recipe_inputs[input_name]) * raw_meat
	var fuel_units := floori((ProductionService.get_available_fuel(building, reserved) + ProductionService.FUEL_EPSILON) / fuel_per_piece)
	return mini(raw_meat, fuel_units)


static func _banquet_open_cooking(record: Dictionary, building: Building, rules: BanquetRiteRules) -> void:
	# Tanti pezzi quanti ne coprono insieme carne e combustibile (2026-10-15): il resto della carne resta cruda.
	var units := _banquet_cookable_units(building, rules)
	record["meat_units"] = units
	record["order_key"] = ProductionService.create_order(
		building, rules.cooked_resource, units, int(record["organizer_id"]), false, false, true
	)
	# Riservato al rito: niente coda dei lavori né riga "Assegna" nel pannello (2026-10-14).
	ProductionService.mark_order_reserved(building, String(record["order_key"]), rules.id)
	log_event("all'edificio #%d si cuociono %d %s entro %.1f giorni." % [building.id, units, rules.raw_meat_resource, rules.feast_days])


# Cottura dell'organizzatore presente: tutta la carne entro la durata della festa (lavoro di tutti i pezzi / durata),
# più in fretta con la skill della Produce (fattore minimo 1). Ogni pezzo pronto va subito nel piatto comune.
static func _banquet_cook(record: Dictionary, building: Building, rules: BanquetRiteRules, delta: float, individuals: Array) -> void:
	var order_key := String(record.get("order_key", ""))
	if order_key == "" or not ProductionService.has_order(building, order_key):
		return
	var organizer := _find(individuals, int(record["organizer_id"]))
	if organizer == null or not is_attending(organizer, building.id):
		return
	var unit_labor := ProductionService.get_required_labor(building, rules.cooked_resource)
	var labor_per_day := float(int(record.get("meat_units", 0))) * unit_labor / maxf(rules.feast_days, 0.001)
	ProductionService.add_labor(building, order_key, labor_per_day * delta * maxf(SkillEffectService.get_factor(PRODUCE_SKILL_KEY, organizer), 1.0))
	var cooked_rules := CaloricCalculator.get_caloric_source_rules(rules.cooked_resource)
	while ProductionService.has_order(building, order_key) and ProductionService.get_labor_accumulated(building, order_key) >= unit_labor:
		var leftover := ProductionService.get_labor_accumulated(building, order_key) - unit_labor
		var produced := ProductionService.complete_production(building, order_key)
		if produced <= 0:
			return
		# complete_production azzera il lavoro dell'ordine: il lavoro in più di questo fotogramma resta per il pezzo dopo.
		ProductionService.add_labor(building, order_key, leftover)
		var taken := ProductionService.withdraw_output(building, rules.cooked_resource, produced)
		if cooked_rules != null:
			record["pot_calories"] = float(record["pot_calories"]) + float(taken) * cooked_rules.calories_per_unit
			record["pot_space"] = float(record["pot_space"]) + float(taken) * cooked_rules.space_per_unit
		record["cooked"] = int(record["cooked"]) + taken
		log_event("#%d %s cuoce %d %s all'edificio #%d (%d/%d)." % [
			organizer.id, organizer.name, taken, rules.cooked_resource, building.id, int(record["cooked"]), int(record["meat_units"])
		])


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
	var task := individual.current_task
	if task != null and not task.is_finished() and task.interrupt_priority != -1:
		return "bisogno urgente"
	return ""


static func _counts_as_adult(individual: HumanIndividual, game_data: GameData) -> bool:
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
