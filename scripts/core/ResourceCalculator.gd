class_name ResourceCalculator
extends RefCounted

const DENSITY_RULES_DIR := "res://data/resource_density/"

# .tres rule files are static designer data loaded from disk; caching avoids
# re-hitting ResourceLoader.exists()+load() on every call, which dominated
# per-year simulation cost (thousands of calls/year across 10k cells x 3 types x 5 services).
static var _density_rules_cache: Dictionary = {}
static var _growth_rules_cache: Dictionary = {}


static func _get_density_rules(resource_type: GameTypes.WorldObjectType) -> ResourceDensityRules:
	if _density_rules_cache.has(resource_type):
		return _density_rules_cache[resource_type]

	var type_name: String = GameTypes.WorldObjectType.keys()[resource_type].to_lower()
	var path := DENSITY_RULES_DIR + type_name + "_density.tres"
	var rules: ResourceDensityRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as ResourceDensityRules

	_density_rules_cache[resource_type] = rules
	return rules


static func get_max_density(
	resource_type: GameTypes.WorldObjectType,
	terrain: GameTypes.TerrainBase,
	biome: GameTypes.Biome,
	coast: GameTypes.CoastType
) -> float:
	var rules := _get_density_rules(resource_type)
	if rules == null:
		return 0.0

	var terrain_mult := _get_terrain_multiplier(rules, terrain)
	var biome_mult := _get_biome_multiplier(rules, biome)
	var coast_mult := _get_coast_multiplier(rules, coast)

	return rules.base_density * terrain_mult * biome_mult * coast_mult


static func _get_coast_multiplier(rules: ResourceDensityRules, coast: GameTypes.CoastType) -> float:
	match coast:
		GameTypes.CoastType.NONE:
			return rules.coast_multiplier_none
		GameTypes.CoastType.BEACH:
			return rules.coast_multiplier_beach
		GameTypes.CoastType.SEMI_CLIFF:
			return rules.coast_multiplier_semi_cliff
		GameTypes.CoastType.CLIFF:
			return rules.coast_multiplier_cliff
		_:
			return 1.0


static func _get_water_multiplier(rules: ResourceDensityRules, water_type: GameTypes.WaterType) -> float:
	match water_type:
		GameTypes.WaterType.SEA:
			return rules.water_multiplier_sea
		GameTypes.WaterType.LAKE:
			return rules.water_multiplier_lake
		GameTypes.WaterType.RIVER:
			return rules.water_multiplier_river
		_:
			return rules.water_multiplier_none


# Densità massima per risorse acquatiche (FISH): asse indipendente da Terrain/Biome/Coast — una
# cella fiume ha terrain_base PLAIN/HILL/MOUNTAIN, non WATER, quindi get_max_density()
# applicherebbe il moltiplicatore terreno sbagliato. Vedi ResourceDensityRules.water_multiplier_*.
static func get_water_max_density(
	resource_type: GameTypes.WorldObjectType,
	water_type: GameTypes.WaterType
) -> float:
	var rules := _get_density_rules(resource_type)
	if rules == null:
		return 0.0
	return rules.base_density * _get_water_multiplier(rules, water_type)


static func get_presence_chance(
	resource_type: GameTypes.WorldObjectType,
	terrain: GameTypes.TerrainBase,
	biome: GameTypes.Biome,
	coast: GameTypes.CoastType
) -> float:
	var rules := _get_density_rules(resource_type)
	if rules == null:
		return 0.0

	var terrain_mult := _get_terrain_multiplier(rules, terrain)
	var biome_mult := _get_biome_multiplier(rules, biome)
	var coast_mult := _get_coast_multiplier(rules, coast)

	var chance := rules.presence_chance * terrain_mult * biome_mult * coast_mult
	return clamp(chance, 0.0, 1.0)


static func _get_terrain_multiplier(rules: ResourceDensityRules, terrain: GameTypes.TerrainBase) -> float:
	match terrain:
		GameTypes.TerrainBase.PLAIN:
			return rules.terrain_multiplier_plain
		GameTypes.TerrainBase.HILL:
			return rules.terrain_multiplier_hill
		GameTypes.TerrainBase.MOUNTAIN:
			return rules.terrain_multiplier_mountain
		GameTypes.TerrainBase.WATER:
			return rules.terrain_multiplier_water
		_:
			return 1.0


static func _get_biome_multiplier(rules: ResourceDensityRules, biome: GameTypes.Biome) -> float:
	match biome:
		GameTypes.Biome.NONE:
			return rules.biome_multiplier_none
		GameTypes.Biome.FOREST:
			return rules.biome_multiplier_forest
		GameTypes.Biome.GRASSLAND:
			return rules.biome_multiplier_grassland
		GameTypes.Biome.DESERT:
			return rules.biome_multiplier_desert
		GameTypes.Biome.SWAMP:
			return rules.biome_multiplier_swamp
		GameTypes.Biome.FERTILE:
			return rules.biome_multiplier_fertile
		GameTypes.Biome.ROCKY:
			return rules.biome_multiplier_rocky
		_:
			return 1.0
const GROWTH_RULES_DIR := "res://data/resource_growth/"


static func _get_growth_rules(resource_type: GameTypes.WorldObjectType) -> ResourceGrowthRules:
	if _growth_rules_cache.has(resource_type):
		return _growth_rules_cache[resource_type]

	var type_name: String = GameTypes.WorldObjectType.keys()[resource_type].to_lower()
	var path := GROWTH_RULES_DIR + type_name + "_growth.tres"
	var rules: ResourceGrowthRules = null
	if ResourceLoader.exists(path):
		rules = load(path) as ResourceGrowthRules

	_growth_rules_cache[resource_type] = rules
	return rules


static func get_growth_rate(
	resource_type: GameTypes.WorldObjectType,
	terrain: GameTypes.TerrainBase,
	biome: GameTypes.Biome,
	coast: GameTypes.CoastType
) -> float:
	var rules := _get_growth_rules(resource_type)
	if rules == null:
		return 0.0

	var terrain_mult := _get_growth_terrain_multiplier(rules, terrain)
	var biome_mult := _get_growth_biome_multiplier(rules, biome)
	var coast_mult := _get_growth_coast_multiplier(rules, coast)

	return rules.base_growth_rate * terrain_mult * biome_mult * coast_mult


static func _get_growth_terrain_multiplier(rules: ResourceGrowthRules, terrain: GameTypes.TerrainBase) -> float:
	match terrain:
		GameTypes.TerrainBase.PLAIN:
			return rules.terrain_multiplier_plain
		GameTypes.TerrainBase.HILL:
			return rules.terrain_multiplier_hill
		GameTypes.TerrainBase.MOUNTAIN:
			return rules.terrain_multiplier_mountain
		GameTypes.TerrainBase.WATER:
			return rules.terrain_multiplier_water
		_:
			return 1.0


static func _get_growth_biome_multiplier(rules: ResourceGrowthRules, biome: GameTypes.Biome) -> float:
	match biome:
		GameTypes.Biome.NONE:
			return rules.biome_multiplier_none
		GameTypes.Biome.FOREST:
			return rules.biome_multiplier_forest
		GameTypes.Biome.GRASSLAND:
			return rules.biome_multiplier_grassland
		GameTypes.Biome.DESERT:
			return rules.biome_multiplier_desert
		GameTypes.Biome.SWAMP:
			return rules.biome_multiplier_swamp
		GameTypes.Biome.FERTILE:
			return rules.biome_multiplier_fertile
		GameTypes.Biome.ROCKY:
			return rules.biome_multiplier_rocky
		_:
			return 1.0


static func _get_growth_coast_multiplier(rules: ResourceGrowthRules, coast: GameTypes.CoastType) -> float:
	match coast:
		GameTypes.CoastType.NONE:
			return rules.coast_multiplier_none
		GameTypes.CoastType.BEACH:
			return rules.coast_multiplier_beach
		GameTypes.CoastType.SEMI_CLIFF:
			return rules.coast_multiplier_semi_cliff
		GameTypes.CoastType.CLIFF:
			return rules.coast_multiplier_cliff
		_:
			return 1.0
			
static func get_growth_rules(resource_type: GameTypes.WorldObjectType) -> ResourceGrowthRules:
	return _get_growth_rules(resource_type)


static func _get_growth_water_multiplier(rules: ResourceGrowthRules, water_type: GameTypes.WaterType) -> float:
	match water_type:
		GameTypes.WaterType.SEA:
			return rules.water_multiplier_sea
		GameTypes.WaterType.LAKE:
			return rules.water_multiplier_lake
		GameTypes.WaterType.RIVER:
			return rules.water_multiplier_river
		_:
			return rules.water_multiplier_none


# Tasso di crescita per risorse acquatiche (FISH): stesso ragionamento di get_water_max_density,
# asse WaterType indipendente da Terrain/Biome/Coast.
static func get_water_growth_rate(
	resource_type: GameTypes.WorldObjectType,
	water_type: GameTypes.WaterType
) -> float:
	var rules := _get_growth_rules(resource_type)
	if rules == null:
		return 0.0
	return rules.base_growth_rate * _get_growth_water_multiplier(rules, water_type)


# Capacità fisica d'acqua di una macrocella, in microcelle — indipendente dal resource_type
# (proprietà della cella, non della risorsa che la occupa): l'intera cella per SEA/LAKE, solo
# la porzione fiume (state.river_space, già calcolata a world-gen — vedi
# InitialResourceSetupService.reserve_river_space) per RIVER, 0 altrove. Vedi CLAUDE.md /
# analisi FISH per perché non si usa RiverMicrocellService.get_river_positions() qui: sarebbe
# uno scan O(TOTAL_SPACE) per cella evitabile, dato che river_space è già il numero che serve.
static func get_water_capacity_space(cell: MacroCellData, state: MacroCellState) -> int:
	match cell.water_type:
		GameTypes.WaterType.SEA, GameTypes.WaterType.LAKE:
			return MacroCellState.TOTAL_SPACE
		GameTypes.WaterType.RIVER:
			return state.get_river_space()
		_:
			return 0


static func _get_usable_capacity_ratio(rules: ResourceGrowthRules, water_type: GameTypes.WaterType) -> float:
	match water_type:
		GameTypes.WaterType.SEA:
			return rules.usable_capacity_ratio_sea
		GameTypes.WaterType.LAKE:
			return rules.usable_capacity_ratio_lake
		GameTypes.WaterType.RIVER:
			return rules.usable_capacity_ratio_river
		_:
			return rules.usable_capacity_ratio_none


# Capacità EFFETTIVA/sfruttabile: get_water_capacity_space (fisica) scalata per
# usable_capacity_ratio_* (ResourceGrowthRules — limiti ecologici oltre alla densità, es.
# ossigeno/territorio). A differenza della capacità fisica, dipende da resource_type (il
# rapporto è specifico per risorsa) — è il tetto verso cui punta la crescita
# (FaunaGrowthService), il surplus (get_water_growth_surplus sotto), il lato destinazione della
# migrazione (FaunaMigrationService) e il fill_ratio della mortalità (FaunaMortalityService).
# get_water_capacity_space stessa resta invariata e continua a rappresentare la disponibilità
# fisica reale mostrata in MacroCellInfoPanel (Water empty space) — questa funzione non la
# sostituisce, le sta accanto per gli usi "interni" alla formula di crescita.
static func get_water_usable_capacity_space(
	resource_type: GameTypes.WorldObjectType,
	cell: MacroCellData,
	state: MacroCellState
) -> int:
	var physical_capacity := get_water_capacity_space(cell, state)
	if physical_capacity <= 0:
		return 0

	var rules := _get_growth_rules(resource_type)
	if rules == null:
		return physical_capacity

	var ratio := _get_usable_capacity_ratio(rules, cell.water_type)
	return int(round(float(physical_capacity) * ratio))


static func get_subtype_rules(resource_type: GameTypes.WorldObjectType) -> Array:
	var rules := _get_growth_rules(resource_type)
	if rules == null:
		return []
	return rules.subtypes


# Pesa la composizione locale dei sottotipi di resource_type per il moltiplicatore di idoneità
# growth_multiplier_by_biome del bioma della cella — usato da growth/encroachment (invert=false,
# per distribuire le NUOVE unità in proporzione a quanto il bioma locale favorisce ciascun
# sottotipo) e da mortality (invert=true, così un sottotipo sfavorito dal bioma perde più che
# proporzionalmente). Se resource_type non ha sottotipi registrati, o non ha ancora
# composizione locale nella cella, restituisce {}: il chiamante ricade sul comportamento
# invariato di apply_subtype_space_delta (proporzione locale pura).
static func get_biome_weighted_subtype_composition(
	resource_type: GameTypes.WorldObjectType,
	state: MacroCellState,
	biome: GameTypes.Biome,
	invert: bool = false
) -> Dictionary:
	var subtype_rules := get_subtype_rules(resource_type)
	if subtype_rules.is_empty():
		return {}

	var composition := state.get_subtype_composition(resource_type)
	if composition.is_empty():
		return {}

	var rules_by_name: Dictionary = {}
	for rule in subtype_rules:
		rules_by_name[rule.subtype_name] = rule

	var weighted: Dictionary = {}
	for subtype_name in composition.keys():
		var count: int = int(composition[subtype_name])
		if count <= 0:
			continue

		var multiplier: float = 1.0
		var rule = rules_by_name.get(subtype_name)
		if rule != null:
			multiplier = float(rule.growth_multiplier_by_biome.get(biome, 1.0))
		if multiplier <= 0.0:
			multiplier = 1.0 # sicurezza: l'esclusione totale è compito di suitable_biomes, non di questo peso
		if invert:
			multiplier = 1.0 / multiplier

		weighted[subtype_name] = float(count) * multiplier

	return weighted


static func compute_growth_surplus(
	resource_type: GameTypes.WorldObjectType,
	cell: MacroCellData,
	state: MacroCellState
) -> float:
	var current_quantity: int = state.get_resource_quantity(resource_type)
	if current_quantity <= 0:
		return 0.0

	var growth_rate := get_growth_rate(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	if growth_rate <= 0.0:
		return 0.0

	var max_density := get_max_density(resource_type, cell.terrain_base, cell.biome, cell.coast_type)
	if max_density <= 0.0:
		return 0.0

	var desired_growth_quantity: float = growth_rate * current_quantity
	var empty_space: int = state.get_empty_space()
	var local_capacity_quantity: float = float(empty_space) * max_density
	var local_growth_quantity: float = min(desired_growth_quantity, local_capacity_quantity)
	var surplus_quantity: float = desired_growth_quantity - local_growth_quantity

	return max(surplus_quantity, 0.0)


# Gemella di compute_growth_surplus sopra, sull'asse acqua invece che Terrain/Biome/Coast:
# quanta della crescita desiderata di resource_type non trova posto nella capacità d'acqua
# SFRUTTABILE locale (get_water_usable_capacity_space, non quella fisica — lo stesso tetto verso
# cui punta FaunaGrowthService), usata da FaunaMigrationService per alimentare la migrazione
# diretta verso le celle d'acqua vicine — nessun encroachment/seed-bank di mezzo.
static func get_water_growth_surplus(
	resource_type: GameTypes.WorldObjectType,
	cell: MacroCellData,
	state: MacroCellState
) -> float:
	var current_quantity: int = state.get_resource_quantity(resource_type)
	if current_quantity <= 0:
		return 0.0

	var growth_rate := get_water_growth_rate(resource_type, cell.water_type)
	if growth_rate <= 0.0:
		return 0.0

	var max_density := get_water_max_density(resource_type, cell.water_type)
	if max_density <= 0.0:
		return 0.0

	# Capacità sfruttabile, non fisica: il surplus deve generarsi avvicinandosi al tetto verso
	# cui FaunaGrowthService fa effettivamente crescere la popolazione, non a TOTAL_SPACE/
	# river_space (che growth non raggiunge mai se usable_capacity_ratio < 1.0).
	var capacity := get_water_usable_capacity_space(resource_type, cell, state)
	var desired_growth_quantity: float = growth_rate * current_quantity
	var empty_space: int = state.get_empty_water_space(capacity)
	var local_capacity_quantity: float = float(empty_space) * max_density
	var local_growth_quantity: float = min(desired_growth_quantity, local_capacity_quantity)
	var surplus_quantity: float = desired_growth_quantity - local_growth_quantity

	return max(surplus_quantity, 0.0)


static func get_encroachment_efficiency(
	own_growth_rules: ResourceGrowthRules,
	target_succession_level: GameTypes.SuccessionLevel
) -> float:
	var gap: int = own_growth_rules.succession_level - target_succession_level
	if gap <= 0:
		return 0.0
	return clamp(own_growth_rules.encroachment_rate * gap, 0.0, 1.0)


# Shared processing-order rule for growth/encroachment/migration: lowest succession_level
# (encroachment number) first. Centralized here so every service that iterates a set of
# resource types applies the same priority instead of relying on how the types happen to
# be listed in each service's own const array. Expected to be refined per-service later
# (e.g. once seasons are introduced), but for now everything follows this single order.
static func get_types_ordered_by_succession(types: Array) -> Array:
	var entries: Array = []
	for resource_type in types:
		var growth_rules := get_growth_rules(resource_type)
		var level: int = growth_rules.succession_level if growth_rules != null else 0
		entries.append({"type": resource_type, "level": level})

	entries.sort_custom(func(a, b): return a["level"] < b["level"])

	var ordered_types: Array = []
	for entry in entries:
		ordered_types.append(entry["type"])
	return ordered_types
