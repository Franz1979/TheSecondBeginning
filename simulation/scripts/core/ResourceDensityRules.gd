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

# Asse di moltiplicatori DEDICATO alla sola PROBABILITÀ DI PRESENZA (get_presence_chance/
# get_water_presence_chance), separato dai moltiplicatori sopra — quelli restano usati solo da
# get_max_density/get_water_max_density (densità/crescita, invariati). Prima di questo asse,
# presence_chance e max_density condividevano lo stesso moltiplicatore per costruzione: dove la
# densità doveva essere bassa (es. terrain_multiplier_mountain=0.1 per GRASS,
# water_multiplier_river=0.3 per FISH), anche la probabilità di presenza crollava con essa,
# anche nei casi dove concettualmente la risorsa dovrebbe restare quasi ubiqua e solo la
# quantità scalare. Stesso principio già usato da ResourceGrowthRules.usable_capacity_ratio_*
# (che separa "quanto/quanto in fretta" da "fino a che tetto" per la crescita).
# Default 1.0 su ogni campo: finché un .tres non li sovrascrive esplicitamente, get_presence_
# chance/get_water_presence_chance si comportano come prima di questo asse (nessuna riduzione
# aggiuntiva). Oggi impostati esplicitamente a 1.0 (nessuna calibrazione) solo per GRASS/SHRUB/
# FISH/BIRDS — STONE e TREE non li impostano, quindi restano sui default di classe qui sotto,
# comportamento identico a prima anche per loro.
@export_group("Presence Terrain Multipliers")
@export var presence_terrain_multiplier_plain: float = 1.0
@export var presence_terrain_multiplier_hill: float = 1.0
@export var presence_terrain_multiplier_mountain: float = 1.0
@export var presence_terrain_multiplier_water: float = 1.0

@export_group("Presence Biome Multipliers")
@export var presence_biome_multiplier_none: float = 1.0
@export var presence_biome_multiplier_forest: float = 1.0
@export var presence_biome_multiplier_grassland: float = 1.0
@export var presence_biome_multiplier_desert: float = 1.0
@export var presence_biome_multiplier_swamp: float = 1.0
@export var presence_biome_multiplier_fertile: float = 1.0
@export var presence_biome_multiplier_rocky: float = 1.0

@export_group("Presence Coast Multipliers")
@export var presence_coast_multiplier_none: float = 1.0
@export var presence_coast_multiplier_beach: float = 1.0
@export var presence_coast_multiplier_semi_cliff: float = 1.0
@export var presence_coast_multiplier_cliff: float = 1.0

@export_group("Presence Water Type Multipliers")
# Stessa indipendenza da Terrain/Biome/Coast dei water_multiplier_* sopra — usati solo da
# get_water_presence_chance (FISH).
@export var presence_water_multiplier_none: float = 1.0
@export var presence_water_multiplier_sea: float = 1.0
@export var presence_water_multiplier_lake: float = 1.0
@export var presence_water_multiplier_river: float = 1.0
