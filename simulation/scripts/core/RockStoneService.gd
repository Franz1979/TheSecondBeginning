class_name RockStoneService
extends RefCounted

# Pietra di ogni singola roccia (2026-10-05, richiesta utente — Quarry passo 1). Stesso schema di stick, fibra ed erba
# (LotCapacityService): la quantità iniziale si ricava dai dati già salvati e non si salva, si salva solo quanto è
# stato tolto (MacroCellState.quarried_stone_by_position, le sole rocce toccate).
#
# Quota iniziale di ogni roccia: il totale RICOSTRUITO della macrocella (resource_quantity[ROCK] attuale più la somma
# della roccia tolta, cioè il valore iniziale) ripartito fra le stone_positions con un peso tra WEIGHT_MIN e WEIGHT_MAX
# ricavato da un hash della posizione salato con micro_seed. Quote intere col metodo del resto maggiore (a parità di
# resto decide un secondo hash), così la somma delle rocce è esattamente il totale. Il giro sulle posizioni si fa una
# volta per macrocella alla prima richiesta e resta in MacroCellState.rock_stone_cache (mai salvata, mai invalidata:
# posizioni e totale ricostruito non cambiano, nemmeno dopo un'estrazione o un caricamento). Stateless, funzioni
# statiche. La pietra non è una risorsa lot_source: non compare tra i candidati della raccolta.
#
# Estrazione (2026-10-05, Quarry — ricavo, gemello del taglio): extract toglie roccia dalla quota della roccia
# (quarried_stone_by_position) e la primaria cala davvero (resource_quantity[ROCK]), come cut_individual per gli alberi.
# Resa e scarto dal gruppo Extraction di rock_density.tres (ResourceDensityRules). dedicated_space[ROCK] e la sparizione
# della roccia esaurita restano per un passo a parte.

const WEIGHT_MIN: float = 0.6
const WEIGHT_MAX: float = 1.4
const HASH_RESOLUTION: int = 100000


# Pietra iniziale della roccia in `position`; 0 se lì non c'è una roccia.
static func get_initial_stone(macro_state: MacroCellState, position: Vector2i) -> int:
	if macro_state == null:
		return 0
	_ensure_cache(macro_state)
	return int(macro_state.rock_stone_cache.get(position, 0))


# Roccia tolta dalla roccia in `position` (0 se mai toccata).
static func get_quarried_stone(macro_state: MacroCellState, position: Vector2i) -> int:
	if macro_state == null:
		return 0
	return int(macro_state.quarried_stone_by_position.get(position, 0))


# Pietra rimasta nella roccia in `position`: iniziale meno tolta, mai sotto zero.
static func get_remaining_stone(macro_state: MacroCellState, position: Vector2i) -> int:
	return maxi(get_initial_stone(macro_state, position) - get_quarried_stone(macro_state, position), 0)


# Pietra rimasta nella zona (macrocella): resource_quantity[ROCK] attuale, che l'estrazione abbassa.
static func get_zone_remaining_stone(macro_state: MacroCellState) -> int:
	if macro_state == null:
		return 0
	return macro_state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)


# Estrae dalla roccia in `position` (regole: gruppo Extraction di rock_density.tres). Ritorna {"resource_name",
# "quantity"} con le pietre ottenute, {} se la roccia è a zero, non c'è o ROCK non si estrae: in quel caso non toglie
# nulla e non lascia scarto. Altrimenti: roccia tolta registrata sulla posizione, resource_quantity[ROCK] abbassato della
# stessa quantità, scarto aggiunto alla roccia (LotCapacityService.add_extra_units, la stessa di add_pebbles).
static func extract(macro_state: MacroCellState, position: Vector2i) -> Dictionary:
	if macro_state == null:
		return {}
	var rules := ResourceCalculator.get_density_rules(GameTypes.WorldObjectType.ROCK)
	if rules == null or rules.extraction_yield_resource_name == "" or rules.extraction_units_per_extraction <= 0:
		return {}
	var primary_per_unit: int = maxi(rules.extraction_primary_per_unit, 1)
	# Con meno roccia di un'estrazione piena si ottiene quanto ne resta, in unità intere.
	var units: int = mini(rules.extraction_units_per_extraction, get_remaining_stone(macro_state, position) / primary_per_unit)
	if units <= 0:
		return {}
	var primary_removed: int = units * primary_per_unit
	macro_state.quarried_stone_by_position[position] = get_quarried_stone(macro_state, position) + primary_removed
	macro_state.add_resource_quantity(GameTypes.WorldObjectType.ROCK, -primary_removed)
	if rules.extraction_waste_resource_name != "" and rules.extraction_waste_per_extraction > 0:
		LotCapacityService.add_extra_units(
			macro_state, rules.extraction_waste_resource_name, position, rules.extraction_waste_per_extraction
		)
	return {"resource_name": rules.extraction_yield_resource_name, "quantity": units}


static func _ensure_cache(macro_state: MacroCellState) -> void:
	if macro_state.rock_stone_cache_built:
		return
	# Posizioni non ancora generate (cella mai aperta): niente cache, così la prossima richiesta la costruisce davvero.
	if not macro_state.stone_positions_generated:
		return
	macro_state.rock_stone_cache = _compute_initial_stone(macro_state)
	macro_state.rock_stone_cache_built = true


static func _compute_initial_stone(macro_state: MacroCellState) -> Dictionary:
	var result: Dictionary = {}
	var positions: Array = macro_state.stone_positions
	# Totale ricostruito: quantità attuale più la roccia già tolta, cioè il totale iniziale.
	var total: int = macro_state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
	for amount in macro_state.quarried_stone_by_position.values():
		total += int(amount)
	if positions.is_empty() or total <= 0:
		for pos in positions:
			result[pos] = 0
		return result

	var weight_salt: int = hash(str(macro_state.micro_seed) + "_rock_stone_weight")
	var priority_salt: int = hash(str(macro_state.micro_seed) + "_rock_stone_priority")
	var weights: Array[float] = []
	var total_weight := 0.0
	for pos in positions:
		var weight: float = WEIGHT_MIN + (WEIGHT_MAX - WEIGHT_MIN) * _hash_unit(pos * 7 + Vector2i(weight_salt, 409))
		weights.append(weight)
		total_weight += weight

	# Parte intera di ogni quota, poi le unità che restano una a testa ai resti più grandi.
	var entries: Array = []
	var assigned := 0
	for i in range(positions.size()):
		var exact: float = float(total) * weights[i] / total_weight
		var share: int = int(floor(exact))
		result[positions[i]] = share
		assigned += share
		entries.append({
			"pos": positions[i],
			"remainder": exact - float(share),
			"priority": _hash_unit(positions[i] * 13 + Vector2i(priority_salt, 677)),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["remainder"] != b["remainder"]:
			return a["remainder"] > b["remainder"]
		return a["priority"] > b["priority"]
	)
	var leftover: int = total - assigned
	for i in range(mini(leftover, entries.size())):
		result[entries[i]["pos"]] += 1
	return result


# ============================================================================================
# Pebble per roccia (2026-10-05, richiesta utente — stesso schema della pietra): la quantità iniziale è una capacità
# ricavata dalla posizione e messa da LotCapacityService in MacroCellState.lot_capacity_cache (mai salvata, mai
# invalidata); il raccolto delle sole rocce toccate sta in lot_registry. Ogni lettura passa da
# TerrainScatteredResourceService/LotCapacityService.get_available.
# ============================================================================================

const PEBBLE_RESOURCE_NAME := "pebble"
# Stessa formula di prima (era in LotCapacityService con randf_range): base × fattore di densità di ROCK della zona
# (solo i moltiplicatori di terreno/bioma/costa, la densità di base si semplifica) × disturbo per posizione, ora da un
# hash invece che da un numero casuale.
const PEBBLE_BASE_QUANTITY: float = 100.0
const PEBBLE_DISTURBANCE_MIN: float = 0.8
const PEBBLE_DISTURBANCE_MAX: float = 1.2


# Capacità iniziale di ogni roccia della macrocella per una risorsa STONE_POSITION: Vector2i -> int. Un giro sulle
# posizioni; chiamata solo da LotCapacityService, una volta per macrocella.
static func compute_pebble_capacities(macro_state: MacroCellState, cell: MacroCellData, resource_name: String) -> Dictionary:
	var capacities: Dictionary = {}
	var rock_base_density := ResourceCalculator.get_base_density(GameTypes.WorldObjectType.ROCK)
	var rock_max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.ROCK, cell.terrain_base, cell.biome, cell.coast_type
	)
	var density_factor: float = rock_max_density / rock_base_density if rock_base_density > 0.0 else 0.0
	var disturbance_salt: int = hash(str(macro_state.micro_seed) + "_" + resource_name + "_stone_capacity")
	for pos in macro_state.stone_positions:
		var disturbance: float = PEBBLE_DISTURBANCE_MIN \
			+ (PEBBLE_DISTURBANCE_MAX - PEBBLE_DISTURBANCE_MIN) * _hash_unit(pos * 5 + Vector2i(disturbance_salt, 523))
		capacities[pos] = int(round(PEBBLE_BASE_QUANTITY * density_factor * disturbance))
	return capacities


# Pebble disponibili sulla roccia in `position`, ignorando il blocco di scoperta (lo stesso valore dei segni sulla
# mappa).
static func get_pebble_available(macro_state: MacroCellState, position: Vector2i) -> int:
	if macro_state == null:
		return 0
	return TerrainScatteredResourceService.get_available_ignoring_lock(macro_state, PEBBLE_RESOURCE_NAME, position)


# Aggiunge `quantity` pebble alla roccia in `position` (es. lo scarto dell'estrazione): raccolto negativo, restano per
# sempre (il registro dei pebble non si azzera mai).
static func add_pebbles(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	LotCapacityService.add_extra_units(macro_state, PEBBLE_RESOURCE_NAME, position, quantity)


# Valore in [0, 1) da un hash, stessa forma degli hash di LotCapacityService/IndividualVegetationService.
static func _hash_unit(key: Vector2i) -> float:
	return float(absi(hash(key)) % HASH_RESOLUTION) / float(HASH_RESOLUTION)
