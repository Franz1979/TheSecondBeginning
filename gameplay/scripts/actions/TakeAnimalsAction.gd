class_name TakeAnimalsAction
extends Action

# Prende i piccoli domestici dalla tettoia delle gabbie (2026-11-16, lavoro "Trasferisci animali", riga Allevamento —
# DomesticTransferJobProvider). All'arrivo sceglie quelli che ci stanno nello zaino (peso da vivo, DomesticAnimalRules.
# live_carry_space_*), ciascuno con la conigliera/il pollaio con posto più vicino (DomesticTransferService.pick_for_transfer),
# li segna "in trasporto" (DomesticAnimal.carried_by) e aggiunge dopo di sé, per ogni edificio d'allevamento, il cammino e
# la tappa KeepAnimalAction che li sistema. Costa solo tempo (stamina 0); la skill Allevamento lo accorcia.

const DAYS_PER_ANIMAL: float = 0.002
const MIN_DAYS: float = 0.004

var shelter: Building = null
var _elapsed: float = 0.0
var _resolved: bool = false
var _taken_count: int = 0


func _init(p_shelter: Building = null) -> void:
	target = null
	shelter = p_shelter
	skill_effect_key = DomesticTransferService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if not _resolved:
		_resolve(individual)
	_elapsed += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return 0.0


func is_complete(individual: Variant, _context: Dictionary) -> bool:
	if not _resolved:
		_resolve(individual)
	return _elapsed >= maxf(DAYS_PER_ANIMAL * float(_taken_count), MIN_DAYS)


# Una volta sola (_resolved, salvato): sceglie gli animali e aggiunge le tappe verso gli edifici d'allevamento.
func _resolve(individual: Variant) -> void:
	_resolved = true
	if individual == null or shelter == null:
		return
	var groups := DomesticTransferService.pick_for_transfer(GameSettings.active_game_data, GameSettings.active_world,
		GameSettings.active_human_individuals, individual, shelter)
	var task: Task = individual.current_task
	if task == null or groups.is_empty():
		return
	var steps: Array[Action] = []
	var descriptions: Array[String] = []
	for group in groups.values():
		_taken_count += (group["entries"] as Array).size()
		steps.append(WalkAction.new(KeepAnimalAction.walk_point(individual, group["building"])))
		steps.append(KeepAnimalAction.new(group["building"], group["entries"]))
		descriptions.append("task_transfer_animals_step_walk_hutch")
		descriptions.append("task_transfer_animals_step_place")
	task.insert_steps_after_current(steps, descriptions)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "resolved": _resolved, "taken_count": _taken_count,
		"transfer_shelter_id": shelter.id if shelter != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_resolved = bool(data.get("resolved", false))
	_taken_count = int(data.get("taken_count", 0))
