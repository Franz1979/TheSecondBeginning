class_name CellGeographyInfo
extends VBoxContainer

@onready var terrain_label: Label = $TerrainLabel
@onready var water_label: Label = $WaterLabel
@onready var coast_label: Label = $CoastLabel
@onready var river_label: Label = $RiverLabel
@onready var biome_label: Label = $BiomeLabel


func show_geography(cell: MacroCellData) -> void:
	if cell == null:
		clear()
		return
	terrain_label.text = "Terrain: " + _terrain_to_text(cell.terrain_base)
	water_label.text = "Water: " + _water_to_text(cell.water_type)
	coast_label.text = "Coast: " + _coast_to_text(cell.coast_type)
	river_label.text = "River: " + _river_to_text(cell.river_shape)
	biome_label.text = "Biome: " + _biome_to_text(cell.biome)


func clear() -> void:
	terrain_label.text = "Terrain: -"
	water_label.text = "Water: -"
	coast_label.text = "Coast: -"
	river_label.text = "River: -"
	biome_label.text = "Biome: -"


func _terrain_to_text(value: GameTypes.TerrainBase) -> String:
	match value:
		GameTypes.TerrainBase.WATER:
			return "Water"
		GameTypes.TerrainBase.PLAIN:
			return "Plain"
		GameTypes.TerrainBase.HILL:
			return "Hill"
		GameTypes.TerrainBase.MOUNTAIN:
			return "Mountain"
		_:
			return "None"


func _water_to_text(value: GameTypes.WaterType) -> String:
	match value:
		GameTypes.WaterType.NONE:
			return "None"
		GameTypes.WaterType.SEA:
			return "Sea"
		GameTypes.WaterType.LAKE:
			return "Lake"
		GameTypes.WaterType.RIVER:
			return "River"
		_:
			return "Unknown"


func _coast_to_text(value: GameTypes.CoastType) -> String:
	match value:
		GameTypes.CoastType.NONE:
			return "None"
		GameTypes.CoastType.BEACH:
			return "Beach"
		GameTypes.CoastType.SEMI_CLIFF:
			return "Semi cliff"
		GameTypes.CoastType.CLIFF:
			return "Cliff"
		_:
			return "Unknown"


func _river_to_text(value: GameTypes.RiverShape) -> String:
	match value:
		GameTypes.RiverShape.NONE:
			return "None"
		GameTypes.RiverShape.VERTICAL:
			return "Vertical"
		GameTypes.RiverShape.HORIZONTAL:
			return "Horizontal"
		_:
			return "River shape"


func _biome_to_text(value: GameTypes.Biome) -> String:
	match value:
		GameTypes.Biome.NONE:
			return "None"
		GameTypes.Biome.FOREST:
			return "Forest"
		GameTypes.Biome.GRASSLAND:
			return "Grassland"
		GameTypes.Biome.DESERT:
			return "Desert"
		GameTypes.Biome.SWAMP:
			return "Swamp"
		GameTypes.Biome.FERTILE:
			return "Fertile"
		GameTypes.Biome.ROCKY:
			return "Rocky"
		_:
			return "Unknown"
