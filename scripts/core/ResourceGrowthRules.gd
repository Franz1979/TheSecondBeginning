class_name ResourceGrowthRules
extends Resource

@export var resource_type: GameTypes.WorldObjectType = GameTypes.WorldObjectType.NONE

@export_group("Growth Rate")
@export var base_growth_rate: float = 0.1

@export_group("Migration")
@export var migration_chance: float = 0.33
@export var migration_success_rate: float = 0.1
@export var max_migration_per_year: int = 100

@export_group("Succession")
@export var succession_level: GameTypes.SuccessionLevel = GameTypes.SuccessionLevel.FORAGE
@export var encroachment_rate: float = 0.0
@export var max_encroachment_per_year: int = 100

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

@export_group("Subtypes")
# Array[SubtypeRules]. Vuoto = nessun sottotipo tracciato (comportamento invariato). Popolato
# oggi solo per SHRUB. Non tipizzato a livello di @export per evitare la sintassi più fragile
# degli array tipizzati di Resource custom nel formato .tres scritto a mano.
@export var subtypes: Array = []
