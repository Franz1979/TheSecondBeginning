class_name TakeSoupIngredientsAction
extends Action

# Tappa a un magazzino per gli ingredienti della zuppa di casa (2026-11-07, richiesta utente — zuppa: passo 2,
# cook_soup.tres): breve sosta (il Walk prima porta al magazzino), poi nello zaino quello che manca ancora e c'è
# (HomeSoupService.take_at_stop: ossa, cibo di stagione, la ciotola se in casa manca). Se manca ancora qualcosa la tappa
# successiva si aggiunge al compito (fino a HomeSoupService.MAX_STOPS), altrimenti la Task si chiude senza messaggi: è
# uno svago.

signal storage_changed(building: Building)

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
	HomeSoupService.take_at_stop(individual, source_building, context)
	storage_changed.emit(source_building)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed, "soup_building_id": source_building.id if source_building != null else -1}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
