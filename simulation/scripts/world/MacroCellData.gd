class_name MacroCellData

var x: int
var y: int

var terrain_base: GameTypes.TerrainBase
var water_type: GameTypes.WaterType
var coast_type: GameTypes.CoastType
var biome: GameTypes.Biome
var river_shape: GameTypes.RiverShape
# Ruscello (vedi StreamNetworkGenerator): maschera dei lati da cui il ruscello entra/esce
# (StreamNetworkGenerator.EDGE_N/E/S/W), 0 = nessun ruscello. Sempre coerente tra celle vicine:
# bit Est qui <=> bit Ovest nella cella a destra (tranne verso acqua o fuori mappa).
var stream_edges: int = 0
# La sorgente del ruscello è in questa cella (con stream_edges == 0: sorgente/pozza isolata).
var stream_has_spring: bool = false

func _init(_x: int, _y: int):
	x = _x
	y = _y

	terrain_base = GameTypes.TerrainBase.PLAIN
	water_type = GameTypes.WaterType.NONE
	coast_type = GameTypes.CoastType.NONE
	biome = GameTypes.Biome.NONE
	river_shape = GameTypes.RiverShape.NONE
