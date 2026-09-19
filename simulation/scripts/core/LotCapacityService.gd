class_name LotCapacityService
extends RefCounted

# Servizio UNICO per le risorse "capacità per lotto" (2026-09-19, richiesta utente — refactor
# pebble/stick/plant_fiber/mushroom/wild_vegetables: prima ciascuna aveva un proprio wrapper/case
# scritto per NOME — StickPoolService/PlantFiberPoolService/MushroomPoolService, un case per
# risorsa in TerrainScatteredResourceService.get_available/consume, un blocco dedicato in
# GameScene._resolve_pickup_candidates. Obiettivo esplicito: aggiungere una risorsa nuova a questa
# famiglia deve costare un .tres (SecondaryResourceRules.lot_source + i campi che quella formula
# consulta) più le sole parti grafiche (mesh a terra e icona magazzino), NIENTE ALTRO CODICE — ogni
# funzione qui sotto legge `lot_source`/scansiona CaloricCalculator.list_secondary_resource_names(),
# mai un nome di risorsa hardcoded.
#
# Quattro formule di derivazione lotti+capacità (una per SecondaryResourceTypes.LotSource, vedi
# quell'enum per la spiegazione estesa), MA solo DUE forme di lettura/scrittura disponibilità:
#   - STONE_POSITION: lot_registry[resource_name][pos] È DIRETTAMENTE la quantità residua (nessuna
#     "capacity" separata — la generazione iniziale usa randf_range, non un hash, quindi non è
#     ri-derivabile: il valore va persistito e mutato in loco, esattamente come il vecchio
#     pebble_quantities).
#   - TREE_INDIVIDUAL/SHRUB_INDIVIDUAL/GRASS_PATCH: lot_capacity_cache[resource_name][pos] è la
#     capacità (runtime, ri-derivabile, mai persistita) e lot_registry[resource_name][pos] è
#     quanto già raccolto — disponibilità = capacità scontata dalla stagione meno raccolto.
#
# MacroCellState.lot_registry è l'UNICO Dictionary persistito da GameSaveService/GameLoadService
# per questa intera famiglia (vedi quei due file — un solo loop su get_all_lot_capacity_resource_
# names, come già avviene per TerrainScatteredResourceService.FRUIT_STOCK_SOURCES).


# Elenco per convenzione, in cache (2026-09-19) — filtra CaloricCalculator.
# list_secondary_resource_names() per lot_source: un nuovo .tres con lot_source valorizzato compare
# qui da solo, senza toccare questo file. Cache statica (RefCounted senza istanza persistente,
# stesso principio già in uso per AnimalCalculator._rules_cache/ResourceCalculator): i .tres non
# cambiano a runtime in una sessione di gioco, uno scan/parse per l'INTERA famiglia basta per
# tutta la sessione.
#
# UNA SOLA scansione per tutti e quattro i lot_source (2026-09-19, richiesta utente — correzione
# prestazioni: PRIMA ogni valore di lot_source aveva una propria entry lazy in questo stesso
# Dictionary, popolata la prima volta che qualcuno lo richiedeva — ma la popolazione ri-scandiva
# list_secondary_resource_names() e richiamava get_caloric_source_rules su OGNI .tres della
# cartella per filtrare un solo lot_source, quindi 4 scansioni complete indipendenti invece di 1,
# ciascuna che rilegge anche le risorse pertinenti agli ALTRI tre lot_source solo per scartarle).
# _names_by_lot_source_populated distingue "mai scandito" da "scandito, nessuna risorsa in questo
# lot_source" (Array vuoto valido, mai motivo di riscansionare).
static var _names_by_lot_source: Dictionary = {}
static var _names_by_lot_source_populated: bool = false

static func get_resource_names_for_lot_source(lot_source: SecondaryResourceTypes.LotSource) -> Array[String]:
	_ensure_names_by_lot_source_populated()
	# BUGFIX (2026-09-19, segnalato dall'utente — "Trying to assign an array of type Array to a
	# variable of type Array[String]") — Dictionary.get(key, default) NON applica la coercizione
	# di tipo statico al valore di DEFAULT: un letterale [] passato lì resta un Array generico
	# (Variant), mai riconosciuto a runtime come Array[String], anche se il valore di ritorno di
	# questa funzione è dichiarato Array[String] — l'assegnazione implicita falliva ogni volta che
	# lot_source non aveva ancora un'entry (es. nessuna risorsa in quel lot_source). .has() +
	# ramo esplicito invece di .get(key, []): il ramo "if" ritorna il valore già typed-array
	# presente in cache, il ramo "else" ritorna un letterale [] che QUI, a differenza del default
	# di .get(), viene coercito dal tipo di ritorno dichiarato della funzione (return type
	# coercion, applicata da GDScript sulle istruzioni `return`, mai sui default argument dei
	# metodi builtin di Dictionary).
	if _names_by_lot_source.has(lot_source):
		return _names_by_lot_source[lot_source]
	return []


# Popolazione vera e propria — UN solo passaggio su list_secondary_resource_names(), UNA sola
# get_caloric_source_rules per resource_name (invece di una per ciascuno dei quattro lot_source),
# raggruppate per lot_source in un solo Dictionary.
static func _ensure_names_by_lot_source_populated() -> void:
	if _names_by_lot_source_populated:
		return
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null:
			continue
		# STESSO bugfix di get_resource_names_for_lot_source sopra — .has()/ramo esplicito invece
		# di .get(rules.lot_source, []), per la STESSA ragione (il default di .get() non è
		# coercito, ma qui l'assegnazione è a una var locale con tipo dichiarato esplicito, quindi
		# il problema si manifesta identico).
		var names: Array[String] = []
		if _names_by_lot_source.has(rules.lot_source):
			names = _names_by_lot_source[rules.lot_source]
		names.append(resource_name)
		_names_by_lot_source[rules.lot_source] = names
	_names_by_lot_source_populated = true


# Unione dei quattro lot_source — l'elenco che save/load/reset stagionale scandiscono con UN SOLO
# loop invece di un blocco per risorsa (vedi commento in testa al file).
static func get_all_lot_capacity_resource_names() -> Array[String]:
	var names: Array[String] = []
	for lot_source in [
		SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL,
		SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL,
		SecondaryResourceTypes.LotSource.GRASS_PATCH,
		SecondaryResourceTypes.LotSource.STONE_POSITION,
	]:
		names.append_array(get_resource_names_for_lot_source(lot_source))
	return names


# ============================================================================================
# Derivazione lotti+capacità — le quattro formule
# ============================================================================================

# TREE_INDIVIDUAL/SHRUB_INDIVIDUAL (stick/mushroom su TREE, plant_fiber su SHRUB) — chiamata ad
# ogni refresh vegetazione (GameScene/MacroCellScene._refresh_resource_visuals), no-op se già
# fresca (vedi VegetationPoolService.refresh_macrocell). object_type risolto dal lot_source stesso,
# nessun parametro aggiuntivo da parte del chiamante.
static func refresh_vegetation_lot_capacity(macro_state: MacroCellState, game_data: GameData, resource_name: String) -> void:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null:
		return
	var object_type: GameTypes.WorldObjectType
	match rules.lot_source:
		SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL:
			object_type = GameTypes.WorldObjectType.TREE
		SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL:
			object_type = GameTypes.WorldObjectType.SHRUB
		_:
			return
	VegetationPoolService.refresh_macrocell(macro_state, game_data, object_type, resource_name)


# Comodità per i due chiamanti (GameScene/MacroCellScene): un'unica riga invece di un ciclo per
# ciascuno dei due lot_source — sostituisce le tre chiamate hardcoded StickPoolService/
# PlantFiberPoolService/MushroomPoolService.refresh_macrocell di prima di questo refactor.
static func refresh_all_vegetation_lot_capacities(macro_state: MacroCellState, game_data: GameData) -> void:
	for resource_name in get_resource_names_for_lot_source(SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL):
		refresh_vegetation_lot_capacity(macro_state, game_data, resource_name)
	for resource_name in get_resource_names_for_lot_source(SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL):
		refresh_vegetation_lot_capacity(macro_state, game_data, resource_name)


# GRASS_PATCH (wild_vegetables) — GENERALIZZATA da TerrainScatteredResourceService.
# compute_wild_vegetable_lots (2026-09-19, richiesta utente: STESSA identica formula, "resource_
# name" al posto di "wild_vegetables" hardcoded nei due salt — per "wild_vegetables" il salt
# risultante è carattere per carattere IDENTICO a prima, nessun cambio di comportamento; un
# secondo futuro GRASS_PATCH riceverebbe automaticamente il proprio spazio di hash indipendente).
# Ricalcolata per INTERO ad ogni chiamata (nessuna cache incrementale, nessun checkpoint_day —
# stessa cadenza/stesso principio di prima: chiamata da GameScene/MacroCellScene ogni volta che le
# posizioni GRASS vengono rigenerate). dedicated_space(GRASS) <= 0 o patch_probability <= 0.0 ->
# cache vuota per questa risorsa, mai un errore.
static func refresh_grass_patch_lot_capacity(macro_state: MacroCellState, resource_name: String, grass_positions: Array) -> void:
	var lots: Dictionary = {}
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	var grass_space: int = macro_state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
	if rules != null and rules.patch_probability > 0.0 and grass_space > 0:
		var patch_seed: int = hash(str(macro_state.micro_seed) + "_" + resource_name + "_patch")
		var capacity_seed: int = hash(str(macro_state.micro_seed) + "_" + resource_name + "_patch_capacity")
		var density_factor: float = float(grass_space) / float(MacroCellState.TOTAL_SPACE)
		for pos in grass_positions:
			var lot := Vector2i(pos.x, pos.y)
			var hash_value: float = float(hash(lot * 3 + Vector2i(patch_seed, 811)) % 100000) / 100000.0
			if hash_value >= rules.patch_probability:
				continue
			var capacity_hash: float = float(hash(lot * 5 + Vector2i(capacity_seed, 953)) % 100000) / 100000.0
			var raw_capacity: float = lerp(float(rules.patch_capacity_min), float(rules.patch_capacity_max), capacity_hash)
			var capacity: int = int(round(raw_capacity * density_factor))
			if capacity > 0:
				lots[lot] = capacity
	macro_state.lot_capacity_cache[resource_name] = lots


# STONE_POSITION (pebble) — chiamata UNA SOLA volta per macrocella, subito dopo che
# StonePositionService.generate_if_needed ha popolato stone_positions (stessa guardia one-shot
# `stone_positions_generated`, verificata dal chiamante). Formula/costanti IDENTICHE al vecchio
# StonePositionService.generate_if_needed (base PEBBLE × density_factor di ROCK per questa
# macrocella × disturbance ±20% indipendente per posizione) — GENERALIZZATA solo nel "per quali
# resource_name" (ogni risorsa STONE_POSITION registrata, non solo "pebble" hardcoded): una
# seconda risorsa in questo lot_source riceverebbe oggi la STESSA quantità di pebble a parità di
# posizione/disturbance (nessun campo .tres distingue ancora una base quantity per risorsa in
# questo lot_source — limite noto, non richiesto da questo passo, l'unica risorsa STONE_POSITION
# esistente è pebble).
const STONE_LOT_BASE_QUANTITY: float = 100.0
const STONE_LOT_DISTURBANCE_MIN: float = 0.8
const STONE_LOT_DISTURBANCE_MAX: float = 1.2

static func seed_stone_lot_capacity(macro_state: MacroCellState, cell: MacroCellData) -> void:
	var rock_base_density := ResourceCalculator.get_base_density(GameTypes.WorldObjectType.ROCK)
	var rock_max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.ROCK, cell.terrain_base, cell.biome, cell.coast_type
	)
	var density_factor: float = rock_max_density / rock_base_density if rock_base_density > 0.0 else 0.0
	for resource_name in get_resource_names_for_lot_source(SecondaryResourceTypes.LotSource.STONE_POSITION):
		var registry: Dictionary = {}
		for pos in macro_state.stone_positions:
			var disturbance := randf_range(STONE_LOT_DISTURBANCE_MIN, STONE_LOT_DISTURBANCE_MAX)
			registry[pos] = int(round(STONE_LOT_BASE_QUANTITY * density_factor * disturbance))
		macro_state.lot_registry[resource_name] = registry


# ============================================================================================
# Disponibilità/consumo — uniformi su tutti e quattro i lot_source (le due forme descritte in
# testa al file)
# ============================================================================================

# `rules` (2026-09-19, richiesta utente — correzione prestazioni: prima veniva risolta di nuovo
# qui anche quando il chiamante l'aveva già in mano, poi una TERZA volta dentro
# _apply_seasonal_availability_to_capacity — 3 lookup indipendenti per la stessa risorsa/chiamata)
# — default null = risolvila da sé, per restare chiamabile in autonomia; TerrainScatteredResource
# Service.get_available (il solo chiamante oggi) la passa già risolta, quindi con lui questa
# funzione fa ZERO chiamate proprie a CaloricCalculator.
static func get_available(macro_state: MacroCellState, resource_name: String, position: Vector2i, rules: SecondaryResourceRules = null) -> int:
	var resolved_rules: SecondaryResourceRules = rules if rules != null else CaloricCalculator.get_caloric_source_rules(resource_name)
	if resolved_rules == null:
		return 0
	match resolved_rules.lot_source:
		SecondaryResourceTypes.LotSource.STONE_POSITION:
			var remaining: int = int(macro_state.lot_registry.get(resource_name, {}).get(position, 0))
			if remaining <= 0:
				return 0
			return _apply_seasonal_availability_to_capacity(resolved_rules, remaining)
		SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL, SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL:
			if not _is_vegetation_cache_fresh(macro_state, resource_name):
				return 0
			return _capacity_minus_harvested(macro_state, resource_name, position, resolved_rules)
		SecondaryResourceTypes.LotSource.GRASS_PATCH:
			return _capacity_minus_harvested(macro_state, resource_name, position, resolved_rules)
		_:
			return 0


# STESSO principio di get_available sopra — `rules` opzionale, TerrainScatteredResourceService.
# consume (il solo chiamante oggi) la passa già risolta.
static func consume(macro_state: MacroCellState, resource_name: String, position: Vector2i, quantity: int, rules: SecondaryResourceRules = null) -> void:
	if quantity <= 0:
		return
	var resolved_rules: SecondaryResourceRules = rules if rules != null else CaloricCalculator.get_caloric_source_rules(resource_name)
	if resolved_rules == null:
		return
	match resolved_rules.lot_source:
		SecondaryResourceTypes.LotSource.STONE_POSITION:
			var remaining: int = int(macro_state.lot_registry.get(resource_name, {}).get(position, 0)) - quantity
			_set_registry_value(macro_state, resource_name, position, max(remaining, 0))
		SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL, SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL, SecondaryResourceTypes.LotSource.GRASS_PATCH:
			var capacity: int = int(macro_state.lot_capacity_cache.get(resource_name, {}).get(position, 0))
			var harvested: int = int(macro_state.lot_registry.get(resource_name, {}).get(position, 0))
			_set_registry_value(macro_state, resource_name, position, min(harvested + quantity, capacity))


# Lotto stale (checkpoint growth non ancora rinfrescato dal chiamante — vedi refresh_vegetation_
# lot_capacity) -> cache non fidata, disponibilità 0 senza ricalcolare qui (STESSO principio già
# in uso prima di questo refactor: get_available legge, mai rinfresca da sé). GameSettings.
# active_game_data assente -> fail-closed (0), stesso trattamento già in uso per ogni altra query
# di questo file prima del refactor.
static func _is_vegetation_cache_fresh(macro_state: MacroCellState, resource_name: String) -> bool:
	if GameSettings.active_game_data == null:
		return false
	var checkpoint_absolute_day := VegetationPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	return int(macro_state.lot_capacity_checkpoint_day.get(resource_name, -1)) == checkpoint_absolute_day


# capacity <= 0 (lotto mai calcolato o davvero a zero individui maturi) -> 0 senza consultare la
# stagione, stesso short-circuit già in uso per pebble/mushroom prima di questo refactor. `rules`
# già risolta dal chiamante (get_available sopra), inoltrata a _apply_seasonal_availability_to_
# capacity invece di lasciargliela ri-risolvere.
static func _capacity_minus_harvested(macro_state: MacroCellState, resource_name: String, position: Vector2i, rules: SecondaryResourceRules) -> int:
	var capacity: int = int(macro_state.lot_capacity_cache.get(resource_name, {}).get(position, 0))
	if capacity <= 0:
		return 0
	var seasonal_capacity := _apply_seasonal_availability_to_capacity(rules, capacity)
	var harvested: int = int(macro_state.lot_registry.get(resource_name, {}).get(position, 0))
	return max(seasonal_capacity - harvested, 0)


static func _set_registry_value(macro_state: MacroCellState, resource_name: String, position: Vector2i, value: int) -> void:
	var registry: Dictionary = macro_state.lot_registry.get(resource_name, {})
	registry[position] = value
	macro_state.lot_registry[resource_name] = registry


# Applica SecondaryResourceRules.seasonal_availability_multiplier (indicizzato per GameTypes.
# Season) alla capacità/quantità GREZZA di un lotto — MOSSA qui da TerrainScatteredResourceService
# (2026-09-19, stesso refactor: era già generica per resource_name, ora usata esclusivamente da
# questo servizio). RISCRITTA lo stesso giorno (correzione prestazioni) per prendere `rules` GIÀ
# RISOLTA dal chiamante invece di richiamare CaloricCalculator.get_caloric_source_rules una terza
# volta per la stessa risorsa/chiamata (get_available/consume l'hanno già risolta una volta in
# testa alla catena — vedi TerrainScatteredResourceService — questa era l'ultima ri-risoluzione
# rimasta). `rules` non è più opzionale: entrambi i chiamanti (get_available/_capacity_minus_
# harvested sopra) ce l'hanno sempre già in mano, nessun caso in cui valga la pena riofferle un
# default "risolvila da sola". floor(capacity × moltiplicatore), mai round/ceil. GameSettings.
# active_game_data assente -> capacity invariata (fail-OPEN: l'assenza di un game_data non è
# "nascondi tutto", un chiamante di solito ha già un proprio guard a monte, vedi
# _is_vegetation_cache_fresh sopra per STONE_POSITION/TREE_INDIVIDUAL/SHRUB_INDIVIDUAL —
# GRASS_PATCH non ne ha uno dedicato, stesso comportamento di prima).
static func _apply_seasonal_availability_to_capacity(rules: SecondaryResourceRules, capacity: int) -> int:
	if GameSettings.active_game_data == null:
		return capacity
	var current_season := SeasonCalculator.get_season_for_day(GameSettings.active_game_data.current_day)
	var multiplier: float = rules.seasonal_availability_multiplier[current_season]
	return int(floor(float(capacity) * multiplier))


# ============================================================================================
# Azzeramento stagionale del raccolto (TREE_INDIVIDUAL/SHRUB_INDIVIDUAL/GRASS_PATCH — MAI
# STONE_POSITION, un sasso estratto non deve mai ricrescere qualunque sia la sua curva stagionale)
# ============================================================================================

# Chiamata una volta per checkpoint stagionale (WorldTimeService, inizio di OGNI stagione) — per
# ciascuna risorsa nei tre lot_source rigenerabili, decide UNA SOLA VOLTA (non per cella) se il
# moltiplicatore stagionale sale rispetto alla stagione precedente; se nessuna risorsa sale, esce
# subito senza toccare world.cell_states. Azzeramento per intero del registro di quella risorsa
# (mai un "harvested" separato da preservare — a differenza del vecchio formato combinato di
# stick/plant_fiber/mushroom, il registro unificato contiene ORA SOLO "harvested" per questi tre
# lot_source, azzerarlo per intero è quindi sempre corretto, nessun sotto-campo da spegnare a
# parte).
static func reset_all_lot_harvests_on_season_rise(
	world: World, previous_season: GameTypes.Season, new_season: GameTypes.Season
) -> void:
	var resources_to_reset: Array[String] = []
	for lot_source in [
		SecondaryResourceTypes.LotSource.TREE_INDIVIDUAL,
		SecondaryResourceTypes.LotSource.SHRUB_INDIVIDUAL,
		SecondaryResourceTypes.LotSource.GRASS_PATCH,
	]:
		for resource_name in get_resource_names_for_lot_source(lot_source):
			var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			if rules == null:
				continue
			var previous_multiplier: float = float(rules.seasonal_availability_multiplier[previous_season])
			var new_multiplier: float = float(rules.seasonal_availability_multiplier[new_season])
			if new_multiplier > previous_multiplier:
				resources_to_reset.append(resource_name)
	if resources_to_reset.is_empty():
		return
	for state in world.cell_states:
		for resource_name in resources_to_reset:
			if not state.lot_registry.get(resource_name, {}).is_empty():
				state.lot_registry[resource_name] = {}
