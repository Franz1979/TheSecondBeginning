class_name MacroCellData

var x: int
var y: int

var terrain_base: GameTypes.TerrainBase
var water_type: GameTypes.WaterType
var coast_type: GameTypes.CoastType
var biome: GameTypes.Biome
var river_shape: GameTypes.RiverShape

func _init(_x: int, _y: int):
	x = _x
	y = _y

	terrain_base = GameTypes.TerrainBase.PLAIN
	water_type = GameTypes.WaterType.NONE
	coast_type = GameTypes.CoastType.NONE
	biome = GameTypes.Biome.NONE
	river_shape = GameTypes.RiverShape.NONE
