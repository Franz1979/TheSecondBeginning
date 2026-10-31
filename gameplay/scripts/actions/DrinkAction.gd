class_name DrinkAction
extends Action

# Bere alla riva (2026-10-30, sete — drink.tres/emergency_drink.tres, vedi ThirstService): una breve sosta sul posto,
# poi l'acqua nel corpo torna al massimo. Bersaglio temporale come LookAroundAction (accumulatore _elapsed).

# Durata della sosta, in giorni di gioco (circa un quarto d'ora).
const DURATION_DAYS: float = 0.01

var _elapsed: float = 0.0


func _init() -> void:
	target = null
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	ThirstService.refill(individual)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
