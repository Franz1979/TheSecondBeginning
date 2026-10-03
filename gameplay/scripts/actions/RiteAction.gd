class_name RiteAction
extends Action

# Step "celebra il rito" della Task Rite (2026-10-02, richiesta utente — rite.tres: Walk → Rite). Presso un edificio
# che ammette il rito (RiteService), dura RiteRules.duration_days giorni di gioco consumando STAMINA_DRAIN_PER_DAY; al
# completamento applica gli effetti (RiteEffectService). La Task non è sospendibile: interrotta o annullata si chiude
# senza effetti. Se l'edificio non è più utilizzabile (demolito, da demolire) o il rito non esiste più, la Task si
# chiude (pending_task_abort).

const STAMINA_DRAIN_PER_DAY: float = 100.0
# Chiave di SkillEffectService (skill_action_effects.tres): fattore della skill di chi celebra sulla fede dei presenti.
const SKILL_EFFECT_KEY := "rite"

var target_building: Building = null
var rite_id: String = ""
var _elapsed: float = 0.0
# true se il bersaglio non è più valido: lo step si dichiara completo per far chiudere la Task (pending_task_abort,
# gestito da HumanIndividualActionService.finish_current_step) senza effetti.
var _aborted: bool = false
# true dopo l'applicazione degli effetti (rito concluso davvero): GameScene._track_rite_tasks lo legge per distinguere
# un rito finito da uno interrotto. Non salvato: un rito concluso non sopravvive alla propria Task.
var completed: bool = false


func _init(p_target_building: Building = null, p_rite_id: String = "") -> void:
	target = null
	target_building = p_target_building
	rite_id = p_rite_id
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	skill_effect_key = SKILL_EFFECT_KEY


func get_rules() -> RiteRules:
	return RiteService.get_rules(rite_id)


func is_target_valid() -> bool:
	var rules := get_rules()
	return rules != null and RiteService.is_building_usable(target_building) \
		and rules.building_types.has(target_building.building_type_name)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _aborted:
		return 0.0
	if not is_target_valid():
		_aborted = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "edificio o rito non più validi"
		return 0.0
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	if _aborted:
		return true
	var rules := get_rules()
	return rules != null and is_target_valid() and _elapsed >= rules.duration_days


func on_complete(individual: Variant, context: Dictionary) -> void:
	if _aborted or not is_target_valid():
		return
	RiteEffectService.apply_completion(individual as HumanIndividual, target_building, get_rules(), GameSettings.active_human_individuals)
	completed = true


# Punto nella microcella dell'edificio (stessa formula di DemolishAction).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return PathfindingService.random_point_in_microcell(Vector2(target_building.micro_x, target_building.micro_y) + macro_offset)


func get_save_data() -> Dictionary:
	var data := {"rite_id": rite_id, "elapsed": _elapsed}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
