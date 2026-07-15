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
