class_name ResourceDensityRules
extends Resource

@export var resource_type: GameTypes.WorldObjectType = GameTypes.WorldObjectType.NONE

@export_group("Density")
@export var base_density: float = 1.0
@export var presence_chance: float = 0.5

@export_group("Terrain Multipliers")
@export var terrain_multiplier_plain: float = 1.0
@export var terrain_multiplier_hill: float = 1.0
@export var terrain_multiplier_mountain: float = 1.0
@export var terrain_multiplier_water: float = 1.0

@export_group("Biome Multipliers")
@export var biome_multiplier_none: float = 1.0
@export var biome_multiplier_forest: float = 1.0
@export var biome_multiplier_grassland: float = 1.0
@export var biome_multiplier_desert: float = 1.0
@export var biome_multiplier_swamp: float = 1.0
@export var biome_multiplier_fertile: float = 1.0
@export var biome_multiplier_rocky: float = 1.0

@export_group("Coast Multipliers")
@export var coast_multiplier_none: float = 1.0
@export var coast_multiplier_beach: float = 1.0
@export var coast_multiplier_semi_cliff: float = 1.0
@export var coast_multiplier_cliff: float = 1.0

@export_group("Water Type Multipliers")
# Usati solo dal calcolo acquatico (ResourceCalculator.get_water_max_density), non da
# get_max_density: le risorse terrestri restano guidate da Terrain/Biome/Coast, le risorse
# acquatiche (FISH) da questo asse indipendente, dato che una cella fiume ha terrain_base
# PLAIN/HILL/MOUNTAIN (non WATER) e non può quindi passare dal terrain_multiplier_water.
@export var water_multiplier_none: float = 0.0
@export var water_multiplier_sea: float = 1.0
@export var water_multiplier_lake: float = 1.0
@export var water_multiplier_river: float = 1.0
