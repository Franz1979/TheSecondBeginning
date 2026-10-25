class_name IllnessEvent
extends RandomEvent

# Malattia (2026-10-24, richiesta utente): un pipottino vivo a caso, non già malato di qualcosa e che può prenderla
# (HealthConditionService.can_get, fascia d'età ammessa), si ammala di febbre
# (HealthConditionService). Da subito è malato (HumanIndividual.is_sick): finisce il compito in corso, la sua coda torna agli
# altri (SicknessService). Per ora nessun tiro: annual_probability 0, si lancia dal menu eventi della barra di debug.

const ILLNESS_ID := "fever"

var _victim: HumanIndividual = null


func apply(context: RandomEventContext) -> bool:
	var candidates: Array[HumanIndividual] = []
	for individual in context.human_individuals:
		if not HealthConditionService.has_category(individual, HealthConditionRules.Category.ILLNESS) \
				and HealthConditionService.can_get(individual, ILLNESS_ID, context.game_data):
			candidates.append(individual)
	if candidates.is_empty():
		return false
	_victim = candidates.pick_random()
	if not HealthConditionService.add_condition(_victim, ILLNESS_ID, context.game_data):
		_victim = null
		return false
	SicknessService.release_queued_tasks(_victim, context.human_individuals)
	if DebugLogging.ENABLED:
		print("[ILLNESS] #%d %s si ammala: %s (salute %.1f/%.1f)." % [
			_victim.id, _victim.name, HealthConditionService.debug_text(_victim), _victim.current_health, _victim.max_health
		])
	return true


func get_popup_text(_context: RandomEventContext) -> String:
	if _victim == null:
		return ""
	return tr("random_event_illness_popup").format({"name": _victim.name, "illness": tr(HealthConditionService.get_rules(ILLNESS_ID).display_name)})
