class_name MacroCellState
extends RefCounted

const TOTAL_SPACE: int = 10000

var x: int
var y: int
var micro_seed: int
var resource_quantity: Dictionary = {}
var dedicated_space: Dictionary = {}
var river_space: int = 0
var active_growth_bonuses: Dictionary = {} # NaturalEventType -> {multiplier: float, years_remaining: int, total_duration: int}

func _init(_x: int, _y: int) -> void:
	x = _x
	y = _y
	micro_seed = hash(str(x) + "_" + str(y))

func get_resource_quantity(object_type: GameTypes.WorldObjectType) -> int:
	return int(resource_quantity.get(object_type, 0))

func set_resource_quantity(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	resource_quantity[object_type] = max(amount, 0)

func add_resource_quantity(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	set_resource_quantity(object_type, get_resource_quantity(object_type) + amount)

func get_dedicated_space(object_type: GameTypes.WorldObjectType) -> int:
	return int(dedicated_space.get(object_type, 0))

func set_dedicated_space(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	dedicated_space[object_type] = max(amount, 0)
	
func get_river_space() -> int:
	return river_space

func set_river_space(amount: int) -> void:
	river_space = max(amount, 0)

func get_total_dedicated_space() -> int:
	var total := river_space
	for amount in dedicated_space.values():
		total += amount
	return total

func get_empty_space() -> int:
	return TOTAL_SPACE - get_total_dedicated_space()

func register_growth_bonus(event_type: GameTypes.NaturalEventType, multiplier: float, years: int) -> void:
	active_growth_bonuses[event_type] = {"multiplier": multiplier, "years_remaining": years, "total_duration": years}

func get_active_event_bonus(event_type: GameTypes.NaturalEventType) -> Dictionary:
	return active_growth_bonuses.get(event_type, {})

func get_active_growth_multiplier() -> float:
	var multiplier := 1.0
	for bonus in active_growth_bonuses.values():
		if bonus["years_remaining"] <= 0:
			continue # ultimo anno già consumato: resta visibile un ciclo in più solo per il marker
		multiplier *= bonus["multiplier"]
	return multiplier

# years_remaining arriva a 0 nell'anno in cui il bonus è stato usato per l'ultima volta dalla
# crescita (get_active_growth_multiplier lo ignora già a 0): lo si rimuove un ciclo dopo, così il
# marker resta visibile esattamente quanto l'effetto è stato attivo (1 fresco + N di recupero).
func tick_growth_bonuses() -> void:
	var expired: Array = []
	for event_type in active_growth_bonuses.keys():
		active_growth_bonuses[event_type]["years_remaining"] -= 1
		if active_growth_bonuses[event_type]["years_remaining"] < 0:
			expired.append(event_type)
	for event_type in expired:
		active_growth_bonuses.erase(event_type)
