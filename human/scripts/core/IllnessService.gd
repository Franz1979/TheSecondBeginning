class_name IllnessService
extends RefCounted

# Malattie (2026-10-24, richiesta utente — evento malattia): chi si ammala ha HumanIndividual.illness_id e
# illness_days_remaining (salvati con la partita). Ogni giorno, dentro l'interazione dei vitali
# (HumanVitalsInteractionService.apply_daily_interaction), perde IllnessRules.daily_health_loss e scala un giorno; a
# fine durata guarisce (con la salute almeno a recovery_health_threshold, per le malattie gravi future). Stateless,
# stesso pattern degli altri *Service; le regole lette una volta e tenute in memoria.

const DATA_DIR := "res://human/data/illnesses/"

static var _rules_cache: Dictionary = {}  # id -> IllnessRules


static func get_rules(illness_id: String) -> IllnessRules:
	if illness_id == "":
		return null
	if not _rules_cache.has(illness_id):
		var path := DATA_DIR + illness_id + ".tres"
		_rules_cache[illness_id] = load(path) as IllnessRules if ResourceLoader.exists(path) else null
	return _rules_cache[illness_id]


# Fa ammalare `individual` di `illness_id` (durata estratta ora). false = malattia sconosciuta o già malato di qualcosa.
static func infect(individual: HumanIndividual, illness_id: String) -> bool:
	var rules := get_rules(illness_id)
	if rules == null or individual == null or individual.illness_id != "":
		return false
	individual.illness_id = illness_id
	individual.illness_days_remaining = randi_range(rules.min_duration_days, maxi(rules.min_duration_days, rules.max_duration_days))
	return true


# Un giorno di malattia: toglie la salute del giorno e scala la durata; a fine durata guarisce. Ritorna la salute tolta.
static func advance_daily(individual: HumanIndividual) -> float:
	var rules := get_rules(individual.illness_id)
	if rules == null:
		individual.illness_id = ""
		individual.illness_days_remaining = 0
		return 0.0
	var health_before := individual.current_health
	individual.current_health = maxf(individual.current_health - rules.daily_health_loss, 0.0)
	individual.illness_days_remaining -= 1
	if individual.illness_days_remaining <= 0 and individual.current_health >= rules.recovery_health_threshold:
		individual.illness_id = ""
		individual.illness_days_remaining = 0
	return health_before - individual.current_health


# Nome tradotto della malattia in corso ("" = nessuna).
static func display_name(individual: HumanIndividual) -> String:
	var rules := get_rules(individual.illness_id)
	return GameContext.tr_text(rules.display_name) if rules != null else ""
