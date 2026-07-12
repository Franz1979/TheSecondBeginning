class_name ResourceCalculator
extends RefCounted

const DENSITY_RULES_DIR := "res://data/resource_density/"


static func _get_density_rules(resource_type: GameTypes.WorldObjectType) -> ResourceDensityRules:
	var type_name: String = GameTypes.WorldObjectType.keys()[resource_type].to_lower()
	var path := DENSITY_RULES_DIR + type_name + "_density.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ResourceDensityRules


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
	var type_name: String = GameTypes.WorldObjectType.keys()[resource_type].to_lower()
	var path := GROWTH_RULES_DIR + type_name + "_growth.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ResourceGrowthRules


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
