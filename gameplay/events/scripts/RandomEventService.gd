class_name RandomEventService
extends RefCounted

# Sistema di eventi casuali (2026-09-26, richiesta utente). Stateless, funzioni statiche, stesso pattern degli
# altri *Service. Dati per evento in gameplay/events/data/*.tres (RandomEventRules), comportamento negli script
# degli eventi (RandomEvent).
#
# Ciclo:
#   - SORTEGGIO una volta all'anno, al giorno dell'anno ROLL_DAY_OF_YEAR (GameTimeService._on_day_advanced): per
#     ogni evento idoneo si tira se accadrà nei 365 giorni successivi (annual_probability) e, se sì, in quale
#     giorno ASSOLUTO (GameData.get_absolute_day), rispettando le stagioni ammesse. Il risultato va in
#     GameData.scheduled_random_events ({"id", "absolute_day", "params"}), salvato e ricaricato. Nessun sorteggio
#     all'avvio di una partita nuova: il primo anno resta senza eventi fino al primo giorno ROLL_DAY_OF_YEAR.
#   - APPLICAZIONE ogni giorno: take_due_events toglie dalla lista gli eventi del giorno (o di giorni già passati,
#     es. dopo un salto d'anno di debug) e GameTimeService li applica, come le morti programmate.
#   - ATTIVAZIONE MANUALE dalla barra di debug (GameTimeService.trigger_random_event_now): stesso percorso di
#     applicazione, nessun vincolo di sorteggio.
# AUTO_ROLL_ENABLED = true dal 2026-09-27 (richiesta utente): sorteggio automatico attivo; l'attivazione manuale di
# debug resta disponibile. Il resoconto del sorteggio va nel log [RANDOM EVENT ROLL] (DebugLogging.SHOW_RANDOM_EVENT_ROLL_LOGS).

const DATA_DIR := "res://gameplay/events/data/"
const ROLL_DAY_OF_YEAR: int = 5
const AUTO_ROLL_ENABLED: bool = true

static var _rules_cache: Array[RandomEventRules] = []
static var _rules_loaded: bool = false


# Tutti gli eventi definiti, ordinati per id (una sola scansione della cartella per sessione).
static func list_rules() -> Array[RandomEventRules]:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	_rules_cache.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("RandomEventService: cartella %s non trovata." % DATA_DIR)
		return _rules_cache
	for file_name in dir.get_files():
		# Nei progetti esportati le risorse testuali possono comparire come "*.tres.remap".
		var resource_file := String(file_name).trim_suffix(".remap")
		if resource_file.get_extension() != "tres":
			continue
		var rules := load(DATA_DIR + resource_file) as RandomEventRules
		if rules == null or rules.id == "":
			push_error("RandomEventService: %s non è un RandomEventRules valido." % resource_file)
			continue
		_rules_cache.append(rules)
	_rules_cache.sort_custom(func(a: RandomEventRules, b: RandomEventRules) -> bool: return a.id < b.id)
	return _rules_cache


static func get_rules(event_id: String) -> RandomEventRules:
	for rules in list_rules():
		if rules.id == event_id:
			return rules
	return null


# Categorie di eventi (2026-09-27, raffreddamento condiviso): {CATEGORY_DIR}{id}.tres, sottocartella di DATA_DIR
# (list_rules legge solo i file della cartella principale, quindi non le confonde con gli eventi).
const CATEGORY_DIR := DATA_DIR + "categories/"
static var _category_cache: Dictionary = {}


# Regole della categoria `category_id`, o null (con avviso, una volta) se il file manca.
static func get_category_rules(category_id: String) -> RandomEventCategoryRules:
	if category_id == "":
		return null
	if _category_cache.has(category_id):
		return _category_cache[category_id]
	var path := CATEGORY_DIR + category_id + ".tres"
	var category_rules: RandomEventCategoryRules = null
	if ResourceLoader.exists(path):
		category_rules = load(path) as RandomEventCategoryRules
	if category_rules == null:
		push_warning("RandomEventService: categoria di eventi '%s' senza %s valido: nessun raffreddamento." % [category_id, path])
	_category_cache[category_id] = category_rules
	return category_rules


# Raffreddamento della categoria dell'evento: moltiplicatore della sua RandomEventCategoryRules per gli anni
# trascorsi dall'ultimo evento della stessa categoria (GameData.random_event_category_last_year). 1.0 senza
# categoria, senza file della categoria o se nessun evento della categoria è ancora avvenuto.
static func _get_cooldown_multiplier(rules: RandomEventRules, context: RandomEventContext) -> float:
	if rules.category == "" or context == null or context.game_data == null:
		return 1.0
	if not context.game_data.random_event_category_last_year.has(rules.category):
		return 1.0
	var category_rules := get_category_rules(rules.category)
	if category_rules == null:
		return 1.0
	var years_elapsed: int = context.game_data.year - int(context.game_data.random_event_category_last_year[rules.category])
	return category_rules.get_cooldown_multiplier(years_elapsed)


# Sorteggio annuale: aggiunge a game_data.scheduled_random_events gli eventi che accadranno nei 365 giorni
# successivi a oggi.
#
# Per categoria (2026-09-27, richiesta utente): al massimo UN evento per categoria (RandomEventRules.category)
# all'anno. Per ogni categoria si tira una volta sola con la probabilità più alta tra gli eventi idonei della
# categoria (moltiplicatori e raffreddamento già applicati); se il tiro riesce, l'evento si sceglie tra quei
# candidati in proporzione alle loro probabilità. Gli eventi senza categoria sono tirati singolarmente, come prima.
# Il giorno si sorteggia sempre nelle stagioni ammesse dell'evento estratto.
#
# Ritorna il resoconto per il log [RANDOM EVENT ROLL]: {"events": Array[Dictionary], "categories": Array[Dictionary]}.
#   events, una voce per OGNI evento definito: {"id", "category", "ineligible_reason": String ("" = idoneo),
#     "population", "base_probability", "village_multiplier", "event_multiplier", "cooldown_multiplier",
#     "probability", "roll": float (-1 = non tirato singolarmente: evento di categoria o probabilità nulla),
#     "drawn": bool, "absolute_day": int (-1 = nessun giorno), "no_valid_day": bool (estratto ma nessun giorno nelle
#     stagioni ammesse)}. Le probabilità restano 0 per un evento non idoneo (non calcolate).
#   categories, una voce per categoria con almeno un candidato (idoneo, probabilità > 0): {"category",
#     "candidates": Array[Dictionary] ({"id", "probability"}), "probability" (la massima), "roll", "succeeded",
#     "choice_roll" (-1 = nessuna scelta), "chosen_id" ("" = nessuno)}.
static func roll_year(game_data: GameData, context: RandomEventContext) -> Dictionary:
	var event_report: Array[Dictionary] = []
	var category_report: Array[Dictionary] = []
	var report := {"events": event_report, "categories": category_report}
	if game_data == null:
		return report
	var today := game_data.get_absolute_day()
	# Passo 1: idoneità e probabilità di ogni evento; i candidati di categoria sono raccolti per il passo 2, in
	# ordine di comparsa (list_rules è ordinata per id: esito deterministico a parità di tiri).
	var category_candidates: Dictionary = {}  # categoria -> Array di [RandomEventRules, voce del resoconto]
	var category_order: Array[String] = []
	for rules in list_rules():
		var entry := {
			"id": rules.id, "category": rules.category, "ineligible_reason": _get_ineligibility_reason(rules, context), "population": 0,
			"base_probability": 0.0, "village_multiplier": 1.0, "event_multiplier": 1.0, "cooldown_multiplier": 1.0,
			"probability": 0.0,
			"roll": -1.0, "drawn": false, "absolute_day": -1, "no_valid_day": false,
		}
		event_report.append(entry)
		if entry["ineligible_reason"] != "":
			continue
		entry.merge(get_probability_breakdown(rules, context), true)
		var probability: float = entry["probability"]
		if probability <= 0.0:
			continue
		if rules.category != "":
			if not category_candidates.has(rules.category):
				category_candidates[rules.category] = []
				category_order.append(rules.category)
			category_candidates[rules.category].append([rules, entry])
			continue
		# Evento senza categoria: tiro singolo, come prima.
		entry["roll"] = randf()
		if float(entry["roll"]) < probability:
			_schedule_drawn_event(game_data, rules, entry, today)
	# Passo 2: un tiro per categoria.
	for category in category_order:
		category_report.append(_roll_category(game_data, category, category_candidates[category], today))
	return report


# Tiro di una categoria: probabilità = la massima tra i candidati; se riesce, scelta pesata per probabilità (un
# secondo numero casuale su [0, somma)) e sorteggio del giorno per l'evento scelto. Ritorna la voce del resoconto.
static func _roll_category(game_data: GameData, category: String, candidates: Array, today: int) -> Dictionary:
	var candidate_summary: Array[Dictionary] = []
	var max_probability := 0.0
	var probability_sum := 0.0
	for candidate in candidates:
		var candidate_probability: float = (candidate[1] as Dictionary)["probability"]
		candidate_summary.append({"id": (candidate[0] as RandomEventRules).id, "probability": candidate_probability})
		max_probability = maxf(max_probability, candidate_probability)
		probability_sum += candidate_probability
	var category_entry := {
		"category": category, "candidates": candidate_summary, "probability": max_probability,
		"roll": randf(), "succeeded": false, "choice_roll": -1.0, "chosen_id": "",
	}
	if float(category_entry["roll"]) >= max_probability:
		return category_entry
	category_entry["succeeded"] = true
	var choice_roll := randf() * probability_sum
	category_entry["choice_roll"] = choice_roll
	# Ultimo candidato come ripiego: arrotondamenti float non possono lasciare la scelta vuota.
	var chosen: Array = candidates[candidates.size() - 1]
	var cumulative := 0.0
	for candidate in candidates:
		cumulative += float((candidate[1] as Dictionary)["probability"])
		if choice_roll < cumulative:
			chosen = candidate
			break
	var chosen_rules: RandomEventRules = chosen[0]
	category_entry["chosen_id"] = chosen_rules.id
	_schedule_drawn_event(game_data, chosen_rules, chosen[1], today)
	return category_entry


# Evento estratto: giorno a caso tra i 365 successivi a oggi, nelle stagioni ammesse; lo programma in
# game_data.scheduled_random_events e aggiorna la sua voce del resoconto (drawn/absolute_day, o no_valid_day).
static func _schedule_drawn_event(game_data: GameData, rules: RandomEventRules, entry: Dictionary, today: int) -> void:
	var candidate_days: Array[int] = []
	for offset in range(1, GameData.DAYS_PER_YEAR + 1):
		var absolute_day := today + offset
		if rules.allowed_seasons.is_empty() or rules.allowed_seasons.has(SeasonCalculator.get_season_for_day(absolute_day % GameData.DAYS_PER_YEAR)):
			candidate_days.append(absolute_day)
	if candidate_days.is_empty():
		entry["no_valid_day"] = true
		return
	entry["drawn"] = true
	entry["absolute_day"] = candidate_days[randi() % candidate_days.size()]
	var params: Variant = entry.get("schedule_params", {})
	game_data.scheduled_random_events.append({
		"id": rules.id, "absolute_day": entry["absolute_day"],
		"params": (params as Dictionary).duplicate(true) if params is Dictionary else {},
	})


# Toglie dalla lista e restituisce gli eventi programmati per oggi o per giorni già passati.
static func take_due_events(game_data: GameData) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if game_data == null or game_data.scheduled_random_events.is_empty():
		return due
	var today := game_data.get_absolute_day()
	var kept: Array[Dictionary] = []
	for entry in game_data.scheduled_random_events:
		if int(entry.get("absolute_day", 0)) <= today:
			due.append(entry)
		else:
			kept.append(entry)
	game_data.scheduled_random_events = kept
	return due


# Applica l'evento: istanza nuova del suo script, effetti, poi il testo del popup ("" = nessun popup).
static func apply_event(context: RandomEventContext) -> String:
	if context == null or context.rules == null or context.rules.event_script == null:
		return ""
	var event := context.rules.event_script.new() as RandomEvent
	if event == null:
		push_error("RandomEventService: lo script dell'evento '%s' non estende RandomEvent." % context.rules.id)
		return ""
	var succeeded := event.apply(context)
	# Raffreddamento condiviso (2026-09-27): solo un evento RIUSCITO (RandomEvent.apply -> true) — sorteggiato o lanciato
	# dal debug — fa ripartire il contatore della sua categoria dall'anno corrente.
	if succeeded and context.rules.category != "" and context.game_data != null:
		context.game_data.random_event_category_last_year[context.rules.category] = context.game_data.year
	return event.get_popup_text(context)


# Probabilità annua effettiva dell'evento (0..1), vedi get_probability_breakdown.
static func get_annual_probability(rules: RandomEventRules, context: RandomEventContext) -> float:
	return float(get_probability_breakdown(rules, context)["probability"])


# Scomposizione della probabilità annua: base di RandomEventRules (fasce di popolazione o valore unico) x
# moltiplicatori generali del villaggio x moltiplicatore proprio dell'evento (RandomEvent.get_probability_
# multiplier) x raffreddamento della categoria (_get_cooldown_multiplier), limitata a 0..1. {"population",
# "base_probability", "village_multiplier", "event_multiplier", "cooldown_multiplier", "probability"}.
static func get_probability_breakdown(rules: RandomEventRules, context: RandomEventContext) -> Dictionary:
	var population := context.human_individuals.size() if context != null else 0
	var base_probability := rules.get_base_annual_probability(population)
	var village_multiplier := _get_probability_multiplier(rules, context)
	var event_data := _get_event_probability_data(rules, context)
	var event_multiplier: float = event_data["multiplier"]
	var cooldown_multiplier := _get_cooldown_multiplier(rules, context)
	return {
		"population": population,
		"base_probability": base_probability,
		"village_multiplier": village_multiplier,
		"event_multiplier": event_multiplier,
		"cooldown_multiplier": cooldown_multiplier,
		"probability": clampf(base_probability * village_multiplier * event_multiplier * cooldown_multiplier, 0.0, 1.0),
		# Parametri dell'appuntamento se l'evento viene estratto (RandomEvent.get_schedule_params, 2026-10-07).
		"schedule_params": event_data["params"],
	}


# Moltiplicatore proprio dell'evento: istanza temporanea del suo script (come apply_event) che risponde
# get_probability_multiplier, poi (stessa istanza, 2026-10-07) get_schedule_params. {"multiplier": float, "params":
# Dictionary}; 1.0 e {} se lo script manca o non estende RandomEvent.
static func _get_event_probability_data(rules: RandomEventRules, context: RandomEventContext) -> Dictionary:
	if rules.event_script == null or context == null:
		return {"multiplier": 1.0, "params": {}}
	var event := rules.event_script.new() as RandomEvent
	if event == null:
		return {"multiplier": 1.0, "params": {}}
	var multiplier := event.get_probability_multiplier(context)
	return {"multiplier": multiplier, "params": event.get_schedule_params()}


# Punto di applicazione dei moltiplicatori futuri della probabilità (2026-09-27, richiesta utente): benessere,
# cultura, attrattiva del villaggio. Oggi tutti inattivi (1.0): quando arriveranno, ciascuno sarà un fattore
# qui, eventualmente pesato per evento da nuovi campi di RandomEventRules.
static func _get_probability_multiplier(_rules: RandomEventRules, _context: RandomEventContext) -> float:
	var wellbeing_multiplier := 1.0
	var culture_multiplier := 1.0
	var attractiveness_multiplier := 1.0
	return wellbeing_multiplier * culture_multiplier * attractiveness_multiplier


# Vincoli del sorteggio automatico (RandomEventRules gruppo Constraints): "" se l'evento è idoneo, altrimenti il
# motivo (per il log). La probabilità nulla è gestita dal sorteggio (get_probability_breakdown), non qui.
static func _get_ineligibility_reason(rules: RandomEventRules, context: RandomEventContext) -> String:
	if context == null or context.game_data == null:
		return "nessun contesto"
	if rules.requires_village_center and VisitorService.find_village_center(context.world) == null:
		return "manca il centro del villaggio"
	if context.game_data.year < rules.min_year:
		return "anno < %d" % rules.min_year
	if rules.min_population > 0 and context.human_individuals.size() < rules.min_population:
		return "popolazione < %d" % rules.min_population
	if rules.required_idea_id != "" and (context.human_folk == null or not context.human_folk.completed_ideas.has(rules.required_idea_id)):
		return "idea '%s' non completata" % rules.required_idea_id
	return ""

