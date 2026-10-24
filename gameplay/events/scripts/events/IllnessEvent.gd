class_name IllnessEvent
extends RandomEvent

# Malattia (2026-10-24, richiesta utente): un pipottino vivo a caso, non già malato di qualcosa, si ammala di febbre
# (IllnessService). Da subito è malato (HumanIndividual.is_sick): finisce il compito in corso, la sua coda torna agli
# altri (SicknessService). Per ora nessun tiro: annual_probability 0, si lancia dal menu eventi della barra di debug.

const ILLNESS_ID := "fever"

var _victim: HumanIndividual = null


func apply(context: RandomEventContext) -> bool:
	var candidates: Array[HumanIndividual] = []
	for individual in context.human_individuals:
		if individual.illness_id == "":
			candidates.append(individual)
	if candidates.is_empty():
		return false
	_victim = candidates.pick_random()
	if not IllnessService.infect(_victim, ILLNESS_ID):
		_victim = null
		return false
	SicknessService.release_queued_tasks(_victim, context.human_individuals)
	if DebugLogging.ENABLED:
		print("[ILLNESS] #%d %s si ammala: %s per %d giorni (salute %.1f/%.1f)." % [
			_victim.id, _victim.name, ILLNESS_ID, _victim.illness_days_remaining, _victim.current_health, _victim.max_health
		])
	return true


func get_popup_text(_context: RandomEventContext) -> String:
	if _victim == null:
		return ""
	return tr("random_event_illness_popup").format({"name": _victim.name, "illness": IllnessService.display_name(_victim)})
