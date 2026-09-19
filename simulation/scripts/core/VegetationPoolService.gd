class_name VegetationPoolService
extends RefCounted

# Motore "capacità per lotto derivata da individui maturi di un tipo di vegetazione" (2026-09-16,
# richiesta utente — Step 1 del piano plant_fiber; RISCRITTA 2026-09-19, richiesta utente — refactor
# lot_source: StickPoolService/PlantFiberPoolService/MushroomPoolService, i tre thin wrapper che
# prima chiamavano questa classe passando il proprio Dictionary/debug_label, sono spariti — ora
# refresh_macrocell prende direttamente `resource_name` e scrive nel registro UNIFICATO di
# MacroCellState, lot_capacity_cache[resource_name]/lot_capacity_checkpoint_day[resource_name],
# invece del vecchio Dictionary combinato {"checkpoint_day","capacity","harvested"} passato dal
# chiamante) — chiamata SOLO da LotCapacityService.refresh_vegetation_lot_capacity, il dispatch
# lot_source non vive qui (questa classe non sa cosa sia un lot_source, resta parametrizzata
# esplicitamente su `object_type`, come da Step 1).
#
# Non tocca in alcun modo TerrainScatteredResourceService/il click destro/il rendering/
# BuildingSiteClearingService: questa classe resta il solo "motore di calcolo capacità".

# [DBG_POOL] (2026-09-16, richiesta utente) — SOLA STAMPA, nessuna logica toccata. Gated dalla
# categoria RESOURCE_POOL di DebugLogging.gd. Stampa da sé ogni volta che refresh_macrocell gira
# per davvero (cache invalidata/lotto nuovo), non ad ogni chiamata no-op.


# Risolve "unità per individuo maturo" (2026-09-16, richiesta utente) dal campo units_per_mature_
# plant sul .tres della risorsa (SecondaryResourceRules.gd), invece della vecchia costante hardcoded
# in StickPoolService/PlantFiberPoolService — tarabile senza toccare codice. `resource_name` è il
# nome file (es. "stick", "plant_fiber"), stessa convenzione di CaloricCalculator.
# get_caloric_source_rules. Campo mancante/.tres non risolvibile/valore <= 0 -> push_warning
# esplicito (MAI un default silenzioso) e ritorna comunque il valore letto così com'è (0 se non
# risolvibile): un valore 0 rende visibile il problema (capacity per lotto sempre 0) invece di
# mascherarlo con un numero che sembra normale.
static func resolve_units_per_mature_individual(resource_name: String) -> int:
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null:
		push_warning("VegetationPoolService: nessuna SecondaryResourceRules risolvibile per '%s' — units_per_mature_plant non disponibile, uso 0." % resource_name)
		return 0
	if rules.units_per_mature_plant <= 0:
		push_warning("VegetationPoolService: '%s.tres' ha units_per_mature_plant assente o 0 — capacity per lotto risulterà sempre 0 finché non lo valorizzi nel .tres." % resource_name)
	return rules.units_per_mature_plant


# Giorno assoluto dell'ultimo checkpoint growth GIÀ PASSATO (fine SPRING) — stessa unità di
# GameData.get_absolute_day (anno*DAYS_PER_YEAR+giorno, monotono). Se oggi siamo già oltre il
# giorno di fine SPRING di quest'anno, è quello di quest'anno; altrimenti (checkpoint di
# quest'anno non ancora avvenuto) è quello dell'anno scorso.
static func most_recent_growth_checkpoint_absolute_day(game_data: GameData) -> int:
	var growth_day := SeasonCalculator.get_season_end_day(GameTypes.Season.SPRING)
	if game_data.current_day >= growth_day:
		return game_data.year * GameData.DAYS_PER_YEAR + growth_day
	return (game_data.year - 1) * GameData.DAYS_PER_YEAR + growth_day


# Aggiorna macro_state.lot_capacity_cache[resource_name] per ogni lotto di `object_type` la cui
# capacità è scaduta rispetto all'ultimo checkpoint growth (2026-09-19, RISCRITTA per il registro
# unificato — vedi commento in testa al file):
#   - checkpoint cambiato rispetto a lot_capacity_checkpoint_day[resource_name] -> l'INTERA cache
#     di questa risorsa è stale (il checkpoint è per costruzione lo stesso per ogni lotto), si
#     ricalcolano TUTTI i lotti attualmente rivendicati;
#   - checkpoint invariato -> si ricalcolano SOLO i lotti rivendicati ma ASSENTI dalla cache
#     (claim comparso a metà epoch) — STESSA identica granularità/STESSO costo del vecchio
#     confronto per-lotto embedded, ora un solo scalare per risorsa invece di un campo ripetuto su
#     ogni entry.
# Nessun lotto da (ri)calcolare -> no-op immediato (anche il solo confronto scalare), stesso
# principio "trascurabile anche ripetuto ad ogni refresh" di prima di questo passo.
static func refresh_macrocell(
	macro_state: MacroCellState,
	game_data: GameData,
	object_type: GameTypes.WorldObjectType,
	resource_name: String,
	allowed_subtypes: Array = []
) -> void:
	var units_per_mature_individual := resolve_units_per_mature_individual(resource_name)
	var checkpoint_absolute_day := most_recent_growth_checkpoint_absolute_day(game_data)
	var claimed_lots := _claimed_lots_store(macro_state, object_type)

	var cache: Dictionary = macro_state.lot_capacity_cache.get(resource_name, {})
	var cached_checkpoint_day: int = int(macro_state.lot_capacity_checkpoint_day.get(resource_name, -1))
	if cached_checkpoint_day != checkpoint_absolute_day:
		cache = {}

	var stale_lots: Array = []
	for lot in claimed_lots.keys():
		if not cache.has(lot):
			stale_lots.append(lot)
	if stale_lots.is_empty() and cached_checkpoint_day == checkpoint_absolute_day:
		if DebugLogging.ENABLED and DebugLogging.SHOW_RESOURCE_POOL_LOGS:
			_debug_print_pool(macro_state, resource_name, cache)
		return

	# Raggruppamento in UNA sola passata (stesso principio già in uso nell'originale) invece di
	# riscansionare l'intera macrocella per ogni lotto stale.
	var individuals_by_lot := _group_individuals_by_lot(macro_state, object_type, stale_lots)
	for lot in stale_lots:
		cache[lot] = _compute_capacity_for_lot(
			macro_state, object_type, individuals_by_lot.get(lot, []), game_data.year,
			units_per_mature_individual, allowed_subtypes
		)
	macro_state.lot_capacity_cache[resource_name] = cache
	macro_state.lot_capacity_checkpoint_day[resource_name] = checkpoint_absolute_day
	if DebugLogging.ENABLED and DebugLogging.SHOW_RESOURCE_POOL_LOGS:
		_debug_print_pool(macro_state, resource_name, cache)


# [DBG_POOL] (vedi DebugLogging.SHOW_RESOURCE_POOL_LOGS) — RISCRITTA per il registro unificato:
# "harvested" ora vive in macro_state.lot_registry[resource_name] (separato dalla cache capacity),
# lette entrambe qui solo per la stampa. Sola lettura/stampa, nessuna logica toccata.
static func _debug_print_pool(macro_state: MacroCellState, resource_name: String, cache: Dictionary) -> void:
	var harvested_registry: Dictionary = macro_state.lot_registry.get(resource_name, {})
	var total_capacity := 0
	var total_harvested := 0
	var lots_with_capacity := 0
	var lots_with_harvested := 0
	var harvested_lots: Array = []
	for lot in cache.keys():
		var capacity: int = int(cache[lot])
		var harvested: int = int(harvested_registry.get(lot, 0))
		total_capacity += capacity
		total_harvested += harvested
		if capacity > 0:
			lots_with_capacity += 1
		if harvested > 0:
			lots_with_harvested += 1
			harvested_lots.append(lot)
	print("[DBG_POOL] macro=(%d,%d) %s: lotti=%d capacity_totale=%d harvested_totale=%d lotti_con_capacity=%d lotti_con_harvested=%d" % [
		macro_state.x, macro_state.y, resource_name, cache.size(), total_capacity, total_harvested,
		lots_with_capacity, lots_with_harvested
	])
	for lot in harvested_lots:
		print("[DBG_POOL]   lotto=%s capacity=%s harvested=%s" % [lot, cache[lot], harvested_registry[lot]])


# Dispatch TREE/SHRUB sui tre registri per-individuo di MacroCellState — STESSO identico pattern
# (duplicato deliberatamente, non riusato) di IndividualVegetationService._claimed_lots_store/
# _subtype_store/_birth_year_store: quei tre sono `_`-prefixed (privati per convenzione di questo
# progetto) e di proprietà di quella classe, non un'utility condivisa — stesso principio "nessuna
# costante/funzione condivisa tra classi diverse" già seguito ovunque nel codebase (es. Action.gd).
static func _claimed_lots_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_claimed_lots if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_claimed_lots


static func _subtype_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_individual_subtype


static func _birth_year_store(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType) -> Dictionary:
	return macro_state.tree_virtual_birth_year if object_type == GameTypes.WorldObjectType.TREE else macro_state.shrub_virtual_birth_year


static func _group_individuals_by_lot(macro_state: MacroCellState, object_type: GameTypes.WorldObjectType, lots: Array) -> Dictionary:
	var lot_set: Dictionary = {}
	for lot in lots:
		lot_set[lot] = true

	var birth_year_store := _birth_year_store(macro_state, object_type)
	var grouped: Dictionary = {}
	for key in birth_year_store.keys():
		var lot := Vector2i(key.x, key.y)
		if not lot_set.has(lot):
			continue
		var list: Array = grouped.get(lot, [])
		list.append(key)
		grouped[lot] = list
	return grouped


# Conta gli individui ADULT/OLD (non YOUNG) tra `individual_keys` (già filtrati a UN solo lotto) —
# STESSA combinazione subtype_rule+band_for_age dell'originale StickPoolService, ora generica su
# object_type. `allowed_subtypes` vuoto = qualunque subtype VALIDO conta (subtype_rule risolvibile),
# STESSO comportamento esatto di prima per stick — non vuoto = filtro aggiuntivo per un subtype
# specifico (bacche/frutti futuri, non usato da alcun chiamante in questo passo).
static func _compute_capacity_for_lot(
	macro_state: MacroCellState,
	object_type: GameTypes.WorldObjectType,
	individual_keys: Array,
	current_year: int,
	units_per_mature_individual: int,
	allowed_subtypes: Array
) -> int:
	var subtype_store := _subtype_store(macro_state, object_type)
	var birth_year_store := _birth_year_store(macro_state, object_type)
	var mature_count := 0
	for key in individual_keys:
		var subtype_name: String = subtype_store.get(key, "")
		if not allowed_subtypes.is_empty() and not allowed_subtypes.has(subtype_name):
			continue
		var subtype_rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
		if subtype_rule == null:
			continue
		var years_lived: int = current_year - int(birth_year_store[key])
		var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
			years_lived, subtype_rule.youth_duration_years, subtype_rule.adult_duration_years
		)
		if age_band != GameTypes.AgeBand.YOUNG:
			mature_count += 1
	return units_per_mature_individual * mature_count
