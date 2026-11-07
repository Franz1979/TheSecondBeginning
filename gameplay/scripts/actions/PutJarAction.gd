class_name PutJarAction
extends Action

# Giara riposta nella Tettoia dell'acqua (2026-11-06, richiesta utente — giare: passo 1, fill_jar.tres): ultimo step di un
# viaggio di riempimento (WaterJarService.put_jar). Breve sosta, poi la giara con la sua acqua al suo posto. Se mancano
# altri viaggi il compito si allunga (WaterJarService.CONTEXT_PENDING_NEXT_TRIP, letto da HumanIndividualActionService).
# Tettoia sparita o piena: la Task si chiude con il motivo e la giara resta nello zaino.

signal jar_moved(building: Building)

const DURATION_DAYS: float = 0.005

var shelter: Building = null
var _elapsed: float = 0.0


func _init(p_shelter: Building) -> void:
	target = null
	shelter = p_shelter
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var failure := WaterJarService.put_jar(individual, shelter, context)
	if failure != "":
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = failure
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = failure
		return
	jar_moved.emit(shelter)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "jar_building_id": shelter.id if shelter != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
