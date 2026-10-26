class_name InjuryRollService
extends RefCounted

# Ferite da lavoro (2026-10-25, richiesta utente): a fine di ogni azione completata un tiro indipendente sul rischio
# della sua chiave d'azione (Action.get_skill_effect_key, le stesse di SkillEffectService). I dati sono in
# res://gameplay/data/injury_risks/action_injury_risks.tres (vedi ActionInjuryRisks per il formato). Un solo tiro per
# azione, al massimo una ferita: le probabilità delle ferite della chiave si sommano in ordine, ciascuna scalata dalla
# skill (rischio × (1 − skill_reduction × livello della skill)). La ferita estratta che il pipottino non può prendere
# (HealthConditionService.can_get: già presente, età) non dà niente. Chiamato da
# HumanIndividualActionService.finish_current_step, che poi manda a letto (SicknessService.on_bedridden).
# Stateless (RefCounted, static), stesso pattern di SkillEffectService.

const RISKS_PATH := "res://gameplay/data/injury_risks/action_injury_risks.tres"

# Cache del file dati (i .tres non cambiano a runtime): stesso principio delle altre cache static.
static var _risks: ActionInjuryRisks = null
static var _risks_loaded: bool = false


# Tiro per `action` appena completata da `individual`. Ferita presa: già applicata (HealthConditionService.add_condition)
# e restituita come {"condition_id", "activity" (chiave di traduzione dell'attività)}; altrimenti {}.
static func roll_after_action(individual: HumanIndividual, action: Action, context: Dictionary, game_data: GameData) -> Dictionary:
	if individual == null or action == null:
		return {}
	var action_key := action.get_skill_effect_key(individual, context)
	if action_key == "":
		return {}
	var risks := _get_risks()
	if risks == null or not risks.risks_by_action_key.has(action_key):
		return {}
	var entry: Dictionary = risks.risks_by_action_key[action_key]
	var skill_ratio := SkillEffectService.get_skill_ratio(action_key, individual, _skill_override(action))
	var risk_factor := maxf(1.0 - float(entry.get("skill_reduction", 0.0)) * skill_ratio, 0.0)
	var wounds: Dictionary = entry.get("wounds", {})
	var roll := randf()
	var cumulative := 0.0
	for condition_id in wounds.keys():
		cumulative += float(wounds[condition_id]) * risk_factor
		if roll >= cumulative:
			continue
		if not HealthConditionService.add_condition(individual, String(condition_id), game_data):
			return {}
		if DebugLogging.ENABLED:
			print("[INJURY] #%d %s si ferisce (azione '%s', tiro %.4f, rischio totale %.4f, skill %.2f): %s (salute %.1f/%.1f)." % [
				individual.id, individual.name, action_key, roll, _total_risk(wounds) * risk_factor, skill_ratio,
				HealthConditionService.debug_text(individual), individual.current_health, individual.max_health
			])
		return {"condition_id": String(condition_id), "activity": String(entry.get("activity", ""))}
	return {}


# Produce in un edificio con BuildingRules.production_skill (es. Medicina alla capanna del guaritore): la stessa skill che
# ne migliora il rendimento (ProduceAction, SkillEffectService.get_factor_for_action con l'override).
static func _skill_override(action: Action) -> String:
	var produce := action as ProduceAction
	if produce == null or produce.target_building == null or produce.target_building.rules == null:
		return ""
	return produce.target_building.rules.production_skill


static func _total_risk(wounds: Dictionary) -> float:
	var total := 0.0
	for condition_id in wounds.keys():
		total += float(wounds[condition_id])
	return total


static func _get_risks() -> ActionInjuryRisks:
	if _risks_loaded:
		return _risks
	_risks_loaded = true
	if not ResourceLoader.exists(RISKS_PATH):
		push_warning("InjuryRollService: file dati non trovato: %s" % RISKS_PATH)
		return null
	_risks = load(RISKS_PATH) as ActionInjuryRisks
	return _risks
