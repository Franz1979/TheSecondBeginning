class_name MacroCellState
extends RefCounted

const TOTAL_SPACE: int = 10000

var x: int
var y: int
var micro_seed: int
var resource_quantity: Dictionary = {}
var dedicated_space: Dictionary = {}
var subtype_composition: Dictionary = {} # WorldObjectType -> Dictionary[String subtype_name, int space_count]
var river_space: int = 0
# Budget separato per risorse acquatiche (oggi solo FISH), mai sommato in
# get_total_dedicated_space()/get_empty_space(): l'acqua non compete mai con lo spazio
# terrestre, esiste solo entro la capacità restituita da
# ResourceCalculator.get_water_capacity_space() (TOTAL_SPACE per SEA/LAKE, river_space per RIVER).
var water_dedicated_space: Dictionary = {}
var active_growth_bonuses: Dictionary = {} # NaturalEventType -> {multiplier: float, trigger_absolute_day: int, duration_years: int}
# Surplus di crescita non piazzato dall'encroachment a fine primavera, in attesa che il
# checkpoint di inizio primavera dell'anno successivo lo trasformi in trasferimenti verso le
# celle vicine (vedi WorldTimeService). WorldObjectType -> quantità di surplus.
var pending_migration_surplus: Dictionary = {}
var stone_positions: Array = [] # Array[Vector2i], posizioni microcella occupate da stone (100x100)
var stone_positions_generated: bool = false # separato dall'array vuoto: distingue "mai aperta" da "aperta ma senza stone"

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

func get_subtype_composition(object_type: GameTypes.WorldObjectType) -> Dictionary:
	return subtype_composition.get(object_type, {})

func get_subtype_count(object_type: GameTypes.WorldObjectType, subtype_name: String) -> int:
	return int(get_subtype_composition(object_type).get(subtype_name, 0))

func set_subtype_count(object_type: GameTypes.WorldObjectType, subtype_name: String, amount: int) -> void:
	if not subtype_composition.has(object_type):
		subtype_composition[object_type] = {}
	subtype_composition[object_type][subtype_name] = max(amount, 0)

func get_subtype_total(object_type: GameTypes.WorldObjectType) -> int:
	var total := 0
	for amount in get_subtype_composition(object_type).values():
		total += int(amount)
	return total

# Distribuisce (delta > 0) o sottrae (delta < 0) una quantità assoluta di dedicated_space
# tra i sottotipi di object_type, mantenendo sum(subtype_composition) sempre allineato a
# dedicated_space. Di default (weights vuoto) i pesi sono la composizione locale già presente
# (un sottotipo a 0 localmente resta a 0). weights esplicito è usato da:
# - migrazione, che porta con sé la composizione della cella di origine invece di quella
#   locale (già filtrata per idoneità dal chiamante prima di arrivare qui), su delta positivo;
# - growth/encroachment (guadagno) e mortality (perdita), che pesano la composizione locale
#   per il moltiplicatore di idoneità al bioma di ciascun sottotipo (diretto per i guadagni,
#   invertito per le perdite — vedi ResourceCalculator.get_biome_weighted_subtype_composition),
#   invece della sola proporzione locale grezza.
# Se object_type non ha sottotipi registrati (nessun SubtypeRules), la funzione non fa nulla:
# stesso comportamento di oggi per GRASS/TREE finché non verranno anch'essi estesi.
func apply_subtype_space_delta(object_type: GameTypes.WorldObjectType, delta: int, weights: Dictionary = {}) -> void:
	if delta == 0:
		return

	if delta > 0:
		var source_weights: Dictionary = weights if not weights.is_empty() else get_subtype_composition(object_type)
		if source_weights.is_empty():
			return
		var split := _split_by_weight(source_weights, delta)
		for subtype_name in split.keys():
			set_subtype_count(object_type, subtype_name, get_subtype_count(object_type, subtype_name) + split[subtype_name])
	else:
		var composition := get_subtype_composition(object_type)
		if composition.is_empty():
			return
		var loss: int = min(-delta, get_subtype_total(object_type))
		if loss <= 0:
			return
		# Un peso esterno (es. inverso del moltiplicatore di bioma) può "chiedere" a un
		# sottotipo più di quanto possiede davvero, soprattutto quando è già quasi esaurito:
		# _split_by_weight_capped ridistribuisce l'eccedenza sui sottotipi non ancora saturi
		# invece di sforare. Se weights è vuoto, source_weights coincide con composition e il
		# capping non scatta mai (comportamento identico a prima, self-limiting per costruzione).
		var source_weights: Dictionary = weights if not weights.is_empty() else composition
		var split := _split_by_weight_capped(source_weights, composition, loss)
		for subtype_name in split.keys():
			set_subtype_count(object_type, subtype_name, get_subtype_count(object_type, subtype_name) - split[subtype_name])

# Ripartisce amount (intero) tra le chiavi di weights in proporzione al loro peso relativo,
# con arrotondamento "largest remainder" così la somma delle parti risulta sempre esattamente
# amount (mai perso/guadagnato per arrotondamento indipendente di ogni singola quota).
static func _split_by_weight(weights: Dictionary, amount: int) -> Dictionary:
	var shares: Dictionary = {}
	if amount <= 0:
		return shares

	var weight_total := 0.0
	for value in weights.values():
		weight_total += float(value)
	if weight_total <= 0.0:
		return shares

	var assigned := 0
	var remainders: Array = []
	for key in weights.keys():
		var exact: float = float(amount) * float(weights[key]) / weight_total
		var base: int = int(floor(exact))
		shares[key] = base
		assigned += base
		remainders.append({"key": key, "remainder": exact - base})

	var missing: int = amount - assigned
	if missing > 0:
		remainders.sort_custom(func(a, b): return a["remainder"] > b["remainder"])
		for i in range(missing):
			var key = remainders[i % remainders.size()]["key"]
			shares[key] += 1

	return shares

# Come _split_by_weight, ma nessuna chiave può ricevere più del proprio tetto in caps (qui
# sempre la composizione reale del sottotipo: non si può sottrarre più di quanto esiste). Se il
# peso proporzionale di una chiave supererebbe il suo tetto, la chiave viene saturata al tetto e
# l'eccedenza si ridistribuisce (stesso criterio di peso) sulle chiavi non ancora sature —
# "water-filling" iterativo. Il chiamante garantisce amount <= somma dei tetti, quindi una
# soluzione esiste sempre e il ciclo termina. Se weights coincide già con caps (caso di oggi,
# nessun peso esterno) nessuna chiave può mai saturare prima del normale completamento: degenera
# esattamente in _split_by_weight.
static func _split_by_weight_capped(weights: Dictionary, caps: Dictionary, amount: int) -> Dictionary:
	var shares: Dictionary = {}
	for key in weights.keys():
		shares[key] = 0
	if amount <= 0:
		return shares

	var remaining_amount := amount
	var active_weights := weights.duplicate()

	while remaining_amount > 0 and not active_weights.is_empty():
		var split := _split_by_weight(active_weights, remaining_amount)
		var saturated: Array = []
		for key in split.keys():
			var cap_remaining: int = int(caps.get(key, 0)) - shares[key]
			if split[key] >= cap_remaining:
				shares[key] += cap_remaining
				remaining_amount -= cap_remaining
				saturated.append(key)

		if saturated.is_empty():
			for key in split.keys():
				shares[key] += split[key]
			remaining_amount = 0
		else:
			for key in saturated:
				active_weights.erase(key)

	return shares

func get_river_space() -> int:
	return river_space

func set_river_space(amount: int) -> void:
	river_space = max(amount, 0)

func get_water_space(object_type: GameTypes.WorldObjectType) -> int:
	return int(water_dedicated_space.get(object_type, 0))

func set_water_space(object_type: GameTypes.WorldObjectType, amount: int) -> void:
	water_dedicated_space[object_type] = max(amount, 0)

func get_total_water_dedicated_space() -> int:
	var total := 0
	for amount in water_dedicated_space.values():
		total += amount
	return total

# capacity è la capacità fisica della cella (ResourceCalculator.get_water_capacity_space),
# non una costante fissa come TOTAL_SPACE: SEA/LAKE e RIVER hanno capacità diverse, quindi va
# passata dal chiamante invece di essere ricavata qui.
func get_empty_water_space(capacity: int) -> int:
	return capacity - get_total_water_dedicated_space()

func get_total_dedicated_space() -> int:
	var total := river_space
	for amount in dedicated_space.values():
		total += amount
	return total

func get_empty_space() -> int:
	return TOTAL_SPACE - get_total_dedicated_space()

const DAYS_PER_YEAR_FOR_BONUSES: int = 365

func register_growth_bonus(
	event_type: GameTypes.NaturalEventType, multiplier: float, duration_years: int, trigger_absolute_day: int
) -> void:
	active_growth_bonuses[event_type] = {
		"multiplier": multiplier,
		"trigger_absolute_day": trigger_absolute_day,
		"duration_years": duration_years,
	}

func get_active_event_bonus(event_type: GameTypes.NaturalEventType) -> Dictionary:
	return active_growth_bonuses.get(event_type, {})

# Un bonus resta attivo esattamente `duration_years` anni dopo il giorno reale in cui l'evento
# è scattato (nessun arrotondamento a confine d'anno): current_absolute_day è il giorno assoluto
# di oggi (vedi GameData.get_absolute_day()).
func get_active_growth_multiplier(current_absolute_day: int) -> float:
	var multiplier := 1.0
	for bonus in active_growth_bonuses.values():
		var expiry_day: int = bonus["trigger_absolute_day"] + bonus["duration_years"] * DAYS_PER_YEAR_FOR_BONUSES
		if current_absolute_day >= expiry_day:
			continue
		multiplier *= bonus["multiplier"]
	return multiplier

# "Fresco" = entro il primo anno dal giorno reale del trigger (usato dal marker in
# WorldRenderer per distinguere l'anno dell'evento dagli anni di recupero successivi).
func is_event_bonus_fresh(event_type: GameTypes.NaturalEventType, current_absolute_day: int) -> bool:
	var bonus := get_active_event_bonus(event_type)
	if bonus.is_empty():
		return false
	return current_absolute_day - int(bonus["trigger_absolute_day"]) < DAYS_PER_YEAR_FOR_BONUSES

# Il marker resta visibile un anno oltre la scadenza effettiva dell'effetto sulla crescita
# (stesso "un ciclo in più" del vecchio schema a years_remaining), così non sparisce un anno
# prima che l'effetto sia realmente esaurito agli occhi del giocatore.
func is_event_bonus_visible(event_type: GameTypes.NaturalEventType, current_absolute_day: int) -> bool:
	var bonus := get_active_event_bonus(event_type)
	if bonus.is_empty():
		return false
	var visible_until: int = int(bonus["trigger_absolute_day"]) + (int(bonus["duration_years"]) + 1) * DAYS_PER_YEAR_FOR_BONUSES
	return current_absolute_day < visible_until
