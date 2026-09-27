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
# AUTO_ROLL_ENABLED = false: per ora il sorteggio automatico è spento, gli eventi si scatenano solo a mano.

const DATA_DIR := "res://gameplay/events/data/"
const ROLL_DAY_OF_YEAR: int = 5
const AUTO_ROLL_ENABLED: bool = false

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


# Sorteggio annuale: aggiunge a game_data.scheduled_random_events gli eventi che accadranno nei 365 giorni
# successivi a oggi. Ritorna le voci aggiunte (per il log).
static func roll_year(game_data: GameData, context: RandomEventContext) -> Array[Dictionary]:
	var scheduled: Array[Dictionary] = []
	if game_data == null:
		return scheduled
	var today := game_data.get_absolute_day()
	for rules in list_rules():
		if not _is_eligible(rules, context):
			continue
		if randf() >= rules.annual_probability:
			continue
		var candidate_days: Array[int] = []
		for offset in range(1, GameData.DAYS_PER_YEAR + 1):
			var absolute_day := today + offset
			if rules.allowed_seasons.is_empty() or rules.allowed_seasons.has(SeasonCalculator.get_season_for_day(absolute_day % GameData.DAYS_PER_YEAR)):
				candidate_days.append(absolute_day)
		if candidate_days.is_empty():
			continue
		var entry := {"id": rules.id, "absolute_day": candidate_days[randi() % candidate_days.size()], "params": {}}
		game_data.scheduled_random_events.append(entry)
		scheduled.append(entry)
	return scheduled


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
	event.apply(context)
	return event.get_popup_text(context)


# Vincoli del sorteggio automatico (RandomEventRules gruppo Constraints).
static func _is_eligible(rules: RandomEventRules, context: RandomEventContext) -> bool:
	if rules.annual_probability <= 0.0 or context == null or context.game_data == null:
		return false
	if context.game_data.year < rules.min_year:
		return false
	if rules.min_population > 0 and context.human_individuals.size() < rules.min_population:
		return false
	if rules.required_idea_id != "" and (context.human_folk == null or not context.human_folk.completed_ideas.has(rules.required_idea_id)):
		return false
	return true
