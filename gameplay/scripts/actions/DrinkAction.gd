class_name DrinkAction
extends Action

# Bere alla riva (2026-10-30, sete — drink.tres/emergency_drink.tres, vedi ThirstService): una breve sosta sul posto,
# poi l'acqua nel corpo torna al massimo. Bersaglio temporale come LookAroundAction (accumulatore _elapsed).
# Alla Tettoia dell'acqua (2026-11-07, giare passo 4: WaterJarService.CONTEXT_DRINK_SHELTER_ID nel context) l'acqua viene
# dalle giare (WaterJarService.drink_at_shelter) e `shelter_used` fa ridisegnare la tettoia.

signal shelter_used(building: Building)

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
	if context.has(WaterJarService.CONTEXT_DRINK_SHELTER_ID):
		var shelter := WaterJarService.drink_at_shelter(individual, int(context[WaterJarService.CONTEXT_DRINK_SHELTER_ID]))
		if shelter != null:
			shelter_used.emit(shelter)
		return
	ThirstService.refill(individual)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
