class_name TakeJarAction
extends Action

# Presa della giara da riempire (2026-11-06, richiesta utente — giare: passo 1, fill_jar.tres): dalla Tettoia dell'acqua
# la giara non piena con meno acqua, da un magazzino una giara vuota (WaterJarService.take_jar). Breve sosta sul posto (il
# Walk prima porta all'edificio), poi la giara nello zaino. Niente giara o niente posto: la Task si chiude con il motivo.

signal jar_moved(building: Building)

const DURATION_DAYS: float = 0.005

var source_building: Building = null
var _elapsed: float = 0.0


func _init(p_source_building: Building) -> void:
	target = null
	source_building = p_source_building
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var failure := WaterJarService.take_jar(individual, source_building, context)
	if failure != "":
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = failure
		context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = failure
		return
	jar_moved.emit(source_building)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "jar_building_id": source_building.id if source_building != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
