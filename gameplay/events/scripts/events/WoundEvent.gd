class_name WoundEvent
extends RandomEvent

# Ferita (2026-10-25, richiesta utente — ferita di debug): un pipottino vivo a caso che può prenderla
# (HealthConditionService.can_get: non già lacerato, fascia d'età ammessa) riceve una lacerazione. Stesso schema di
# IllnessEvent: da subito è a letto, la sua coda torna agli altri (SicknessService). annual_probability 0: si lancia dal
# menu eventi della barra di debug.

const WOUND_ID := "laceration"

var _victim: HumanIndividual = null


func apply(context: RandomEventContext) -> bool:
	var candidates: Array[HumanIndividual] = []
	for individual in context.human_individuals:
		if HealthConditionService.can_get(individual, WOUND_ID, context.game_data):
			candidates.append(individual)
	if candidates.is_empty():
		return false
	_victim = candidates.pick_random()
	if not HealthConditionService.add_condition(_victim, WOUND_ID, context.game_data):
		_victim = null
		return false
	SicknessService.release_queued_tasks(_victim, context.human_individuals)
	if DebugLogging.ENABLED:
		print("[WOUND] #%d %s si ferisce: %s (salute %.1f/%.1f)." % [
			_victim.id, _victim.name, HealthConditionService.debug_text(_victim), _victim.current_health, _victim.max_health
		])
	return true


func get_popup_text(_context: RandomEventContext) -> String:
	if _victim == null:
		return ""
	return tr("random_event_wound_popup").format({"name": _victim.name, "wound": tr(HealthConditionService.get_rules(WOUND_ID).display_name)})
