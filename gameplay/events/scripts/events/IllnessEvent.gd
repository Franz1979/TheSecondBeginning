class_name IllnessEvent
extends RandomEvent

# Malattia (2026-10-24, richiesta utente): un pipottino vivo, non già malato di qualcosa e che può prenderla
# (ContagionService.can_catch: fascia d'età ammessa, non in incubazione, non immune), si ammala di febbre.
# Paziente zero (2026-10-25, richiesta utente — febbre negli eventi casuali): sorteggiato ogni anno (illness.tres, fasce di
# popolazione, autunno/inverno, categoria "illnesses" col suo raffreddamento) parte IN INCUBAZIONE (ContagionService.
# start_incubation): gira e contagia senza che nessuno lo sappia, nessun popup; l'avviso arriva con i sintomi. Dal menu
# eventi della barra di debug (nessun parametro dell'appuntamento) parte invece subito acuta, a letto, con popup.
# Scelta pesata per cause concrete (mai un moltiplicatore di probabilità): peso 1, +2 senza casa o in casa non riscaldata
# nella stagione fredda (Building.heated_today, HouseHeatingService), +1 con la riserva del corpo sotto metà.

const ILLNESS_ID := "fever"
# Nei parametri dell'appuntamento (get_schedule_params): evento sorteggiato, parte in incubazione.
const PARAM_INCUBATION := "incubation"
const WEIGHT_BASE: float = 1.0
const WEIGHT_COLD_HOME: float = 2.0
const WEIGHT_HUNGRY: float = 1.0
const HUNGRY_BODY_RESERVE_RATIO: float = 0.5

var _victim: HumanIndividual = null
var _incubation: bool = false


func get_schedule_params() -> Dictionary:
	return {PARAM_INCUBATION: true}


func apply(context: RandomEventContext) -> bool:
	var candidates: Array[HumanIndividual] = []
	var weights: Array[float] = []
	var cold := HouseHeatingService.is_cold_season(HumanVitalsInteractionService.current_season())
	var heated_houses := _heated_house_ids(context.world)
	var total := 0.0
	for individual in context.human_individuals:
		if HealthConditionService.has_category(individual, HealthConditionRules.Category.ILLNESS) \
				or not ContagionService.can_catch(individual, ILLNESS_ID, context.game_data):
			continue
		var weight := _weight(individual, cold, heated_houses)
		candidates.append(individual)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return false
	_victim = _pick_weighted(candidates, weights, total)
	_incubation = bool(context.params.get(PARAM_INCUBATION, false))
	if _incubation:
		var days := ContagionService.start_incubation(_victim, ILLNESS_ID, context.game_data)
		if DebugLogging.ENABLED:
			print("[ILLNESS] #%d %s è il paziente zero di %s: incubazione %d gg (peso %.0f su %.0f, %d candidati)." % [
				_victim.id, _victim.name, ILLNESS_ID, days, weights[candidates.find(_victim)], total, candidates.size()
			])
		if days > 0:
			return true
	elif not HealthConditionService.add_condition(_victim, ILLNESS_ID, context.game_data):
		_victim = null
		return false
	SicknessService.on_bedridden(context.game_context(), _victim, GameEffects.new())
	if DebugLogging.ENABLED:
		print("[ILLNESS] #%d %s si ammala: %s (salute %.1f/%.1f)." % [
			_victim.id, _victim.name, HealthConditionService.debug_text(_victim), _victim.current_health, _victim.max_health
		])
	return true


# Nessun popup per il paziente zero in incubazione (lo si scopre con i sintomi).
func get_popup_text(_context: RandomEventContext) -> String:
	if _victim == null or (_incubation and not HealthConditionService.has_condition(_victim, ILLNESS_ID)):
		return ""
	return tr("random_event_illness_popup").format({"name": _victim.name, "illness": tr(HealthConditionService.get_rules(ILLNESS_ID).display_name)})


static func _weight(individual: HumanIndividual, cold: bool, heated_houses: Dictionary) -> float:
	var weight := WEIGHT_BASE
	if individual.house_id == -1 or (cold and not heated_houses.has(individual.house_id)):
		weight += WEIGHT_COLD_HOME
	if individual.body_calories_capacity > 0.0 and individual.body_calories < individual.body_calories_capacity * HUNGRY_BODY_RESERVE_RATIO:
		weight += WEIGHT_HUNGRY
	return weight


static func _heated_house_ids(world: World) -> Dictionary:
	var result := {}
	if world == null:
		return result
	for building in world.buildings:
		if building.heated_today:
			result[building.id] = true
	return result


static func _pick_weighted(candidates: Array[HumanIndividual], weights: Array[float], total: float) -> HumanIndividual:
	var roll := randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll < 0.0:
			return candidates[i]
	return candidates.back()
