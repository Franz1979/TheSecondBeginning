class_name CookSoupAction
extends Action

# Cottura della zuppa di casa (2026-11-07, richiesta utente — zuppa: passo 2, cook_soup.tres): fermo davanti alla Capanna
# per HomeSoupService.COOK_DAYS; la skill "produce" (SkillEffectService, come la ProduceAction) accorcia la cottura. Alla
# fine HomeSoupService.cook: ciotola nel deposito di casa, ingredienti consumati, un uso della ciotola, legna se la casa
# oggi non è scaldata, pentola piena. Se nel frattempo qualcosa è cambiato (zuppa già cotta da un altro, niente fuoco) la
# Task si chiude e gli ingredienti tornano in magazzino come carico senza proprietario.

signal storage_changed(building: Building)

var house: Building = null
var ingredients: Dictionary = {}
var _progress: float = 0.0


func _init(p_house: Building, p_ingredients: Dictionary) -> void:
	target = null
	house = p_house
	ingredients = p_ingredients.duplicate()
	skill_effect_key = "produce"
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func is_target_valid() -> bool:
	return house != null and not house.is_demolished and HomeSoupService.is_soup_house(house)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_progress += delta * SkillEffectService.get_factor_for_action(self, individual, context)
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _progress >= HomeSoupService.COOK_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var failure := HomeSoupService.cook(individual, house, ingredients)
	if failure != "":
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "soup_" + failure
		return
	storage_changed.emit(house)


func get_save_data() -> Dictionary:
	return {"progress": _progress, "soup_house_id": house.id if house != null else -1, "soup_ingredients": ingredients}


func load_save_data(data: Dictionary) -> void:
	_progress = float(data.get("progress", 0.0))
