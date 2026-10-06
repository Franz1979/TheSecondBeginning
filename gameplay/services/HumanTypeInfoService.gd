class_name HumanTypeInfoService
extends RefCounted

# Scheda del tipo di un pipottino (2026-10-05, richiesta utente — la "i" del pannello dell'abitante, come quella degli
# edifici): fascia d'età e sesso, non il singolo pipottino. Righe per InfoCardBlock ({"text", "indent", "wrap"}), tutte
# lette dai dati — HumanRules (via HumanCalculator, le stesse formule del gioco), durate delle fasce dell'era corrente
# (GameData), fasce fertili (HumanTypes.FERTILE_AGE_BANDS), fasce escluse dai lavori (Action.disallowed_age_bands delle
# azioni di lavoro). Moltiplicatori neutri (1,0) e voci senza dati non compaiono. Cache per fascia, sesso e regole: le
# righe non cambiano finché non cambiano dati o lingua.

static var _cache: Dictionary = {}


# Titolo "Adulto fertile, maschio" (nome della fascia concordato col sesso).
static func get_title(age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> String:
	return TranslationServer.translate("human_type_title").format({
		"band": _band_name(age_band, sex),
		"sex": TranslationServer.translate("sex_female" if sex == HumanTypes.Sex.FEMALE else "sex_male").to_lower(),
	})


static func build_rows(
	human_rules: HumanRules, durations_male: Array[float], durations_female: Array[float],
	age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if human_rules == null:
		return rows
	var key := "%d|%d|%d|%s|%s|%s" % [
		human_rules.get_instance_id(), int(age_band), int(sex), str(durations_male), str(durations_female), TranslationServer.get_locale()
	]
	if _cache.has(key):
		return _cache[key]
	var add_row := func(text: String, indent: bool, wrap: bool) -> void:
		rows.append({"text": text, "indent": indent, "wrap": wrap})
	var tr_ := func(key_name: String) -> String: return TranslationServer.translate(key_name)

	add_row.call(get_title(age_band, sex), false, false)
	# Età: dalle durate delle fasce dell'era corrente (stesse di HumanCalculator.get_age_band).
	var durations: Array[float] = durations_female if sex == HumanTypes.Sex.FEMALE else durations_male
	if durations.size() > int(age_band):
		var start := HumanCalculator.get_age_band_start_age(durations, age_band)
		if int(age_band) == durations.size() - 1:
			add_row.call(tr_.call("human_type_age_from").format({"from": _number(start)}), false, false)
		else:
			add_row.call(tr_.call("human_type_age_range").format({"from": _number(start), "to": _number(start + durations[int(age_band)])}), false, false)
	add_row.call(tr_.call("human_type_desc_%s" % _band_key(age_band)), false, true)

	# Trasporto: base × taglia (fascia) × taglia (sesso), più il bonus per posto attrezzo vuoto.
	var size_age: float = human_rules.size_multiplier_by_age[age_band]
	var size_sex: float = human_rules.size_multiplier_by_sex[sex]
	add_row.call(tr_.call("human_type_carry").format({
		"value": _number(HumanCalculator.get_max_carry_capacity(human_rules, age_band, sex, human_rules.tool_slot_count)),
	}), false, false)
	add_row.call(tr_.call("human_type_size_factors").format({"age": _factor(size_age), "sex": _factor(size_sex)}), true, false)
	if human_rules.carry_bonus_per_empty_tool_slot > 0.0:
		add_row.call(tr_.call("human_type_tool_slot_bonus").format({
			"bonus": _number(human_rules.carry_bonus_per_empty_tool_slot), "slots": human_rules.tool_slot_count,
		}), true, false)
	add_row.call(tr_.call("human_type_food_space").format({"value": _number(HumanCalculator.get_max_food_space(human_rules, age_band, sex))}), false, false)
	add_row.call(tr_.call("human_type_calories").format({
		"value": _number(HumanCalculator.get_daily_calorie_consumption(human_rules, age_band, sex)),
	}), false, false)
	add_row.call(tr_.call("human_type_stamina").format({"value": _number(HumanCalculator.get_max_stamina(human_rules, age_band, sex))}), false, false)
	# Altri moltiplicatori per fascia o sesso: solo quelli diversi da 1,0.
	for entry in [
		["human_type_thirst", human_rules.thirst_multiplier_by_age, human_rules.thirst_multiplier_by_sex],
		["human_type_health", human_rules.health_multiplier_by_age, human_rules.health_multiplier_by_sex],
		["human_type_happiness", human_rules.happiness_multiplier_by_age, human_rules.happiness_multiplier_by_sex],
		["human_type_loyalty", human_rules.loyalty_multiplier_by_age, human_rules.loyalty_multiplier_by_sex],
		["human_type_faith", human_rules.faith_multiplier_by_age, human_rules.faith_multiplier_by_sex],
	]:
		var multiplier: float = float(entry[1][age_band]) * float(entry[2][sex])
		if not is_equal_approx(multiplier, 1.0):
			add_row.call(tr_.call(String(entry[0])).format({"value": _factor(multiplier)}), false, false)

	# Figli: fasce fertili del gioco.
	add_row.call(tr_.call("human_type_can_have_children" if HumanTypes.FERTILE_AGE_BANDS.has(age_band) else "human_type_cannot_have_children"), false, false)

	# Lavori: fasce escluse dalle azioni di lavoro.
	var allowed: PackedStringArray = []
	var forbidden: PackedStringArray = []
	for job in _job_probes():
		var action: Action = job["action"]
		var name: String = tr_.call(String(job["key"]))
		if action.disallowed_age_bands.has(age_band):
			forbidden.append(name)
		else:
			allowed.append(name)
	if not allowed.is_empty():
		add_row.call(tr_.call("human_type_jobs_allowed").format({"jobs": ", ".join(allowed)}), false, true)
	if not forbidden.is_empty():
		add_row.call(tr_.call("human_type_jobs_forbidden").format({"jobs": ", ".join(forbidden)}), false, true)
	_cache[key] = rows
	return rows


# Lavori ordinabili dal giocatore e l'azione di lavoro di ciascuno (costruita coi valori di base: serve solo
# disallowed_age_bands, fissato dal costruttore). Nome = chiave tr() dell'attività già usata nei messaggi di rifiuto.
static func _job_probes() -> Array[Dictionary]:
	return [
		{"key": "task_activity_pickup", "action": PickUpAction.new(Vector2i.ZERO, null)},
		{"key": "task_activity_cut", "action": CutAction.new()},
		{"key": "task_activity_quarry", "action": QuarryAction.new()},
		{"key": "task_activity_hunt", "action": ApproachPreyAction.new()},
		{"key": "task_activity_butcher", "action": ButcherAction.new()},
		{"key": "task_activity_build", "action": BuildAction.new()},
		{"key": "task_activity_demolish", "action": DemolishAction.new()},
		{"key": "task_activity_produce", "action": ProduceAction.new()},
		{"key": "task_activity_rite", "action": RiteAction.new()},
	]


static func _band_key(age_band: HumanTypes.AgeBand) -> String:
	return String(HumanTypes.AgeBand.keys()[age_band]).to_lower()


static func _band_name(age_band: HumanTypes.AgeBand, sex: HumanTypes.Sex) -> String:
	return TranslationServer.translate("age_band_%s_%s" % [_band_key(age_band), "female" if sex == HumanTypes.Sex.FEMALE else "male"])


# Numero con al più una cifra decimale, virgola in italiano.
static func _number(value: float) -> String:
	var text := str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
	return text.replace(".", ",") if TranslationServer.get_locale().begins_with("it") else text


static func _factor(value: float) -> String:
	var text := "%.2f" % value
	return "×" + (text.replace(".", ",") if TranslationServer.get_locale().begins_with("it") else text)
