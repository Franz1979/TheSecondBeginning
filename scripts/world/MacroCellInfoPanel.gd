class_name MacroCellInfoPanel
extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var terrain_label: Label = $MarginContainer/VBoxContainer/TerrainLabel
@onready var water_label: Label = $MarginContainer/VBoxContainer/WaterLabel
@onready var coast_label: Label = $MarginContainer/VBoxContainer/CoastLabel
@onready var river_label: Label = $MarginContainer/VBoxContainer/RiverLabel
@onready var biome_label: Label = $MarginContainer/VBoxContainer/BiomeLabel
@onready var space_label: Label = $MarginContainer/VBoxContainer/SpaceLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TreeNumberLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/ShrubNumberLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/EmptySpaceLabel
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer


func _ready() -> void:
	clear()


func show_cell(cell: MacroCellData, state: MacroCellState) -> void:
	if cell == null:
		clear()
		return
	title_label.text = "Macro Cell Data:"
	coords_label.text = "Coords: " + str(cell.x) + ", " + str(cell.y)
	terrain_label.text = "Terrain: " + _terrain_to_text(cell.terrain_base)
	water_label.text = "Water: " + _water_to_text(cell.water_type)
	coast_label.text = "Coast: " + _coast_to_text(cell.coast_type)
	river_label.text = "River: " + _river_to_text(cell.river_shape)
	biome_label.text = "Biome: " + _biome_to_text(cell.biome)
	space_label.text = " - - - - - - - - - -"

	if state != null:
		var stone_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
		var stone_space := state.get_dedicated_space(GameTypes.WorldObjectType.ROCK)
		var tree_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.TREE)
		var tree_space := state.get_dedicated_space(GameTypes.WorldObjectType.TREE)
		var grass_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.GRASS)
		var grass_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
		var shrub_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.SHRUB)
		var shrub_space := state.get_dedicated_space(GameTypes.WorldObjectType.SHRUB)
		tree_number_label.text = "Trees: " + str(tree_quantity) + " (occupied cells: " + str(tree_space) + ")"
		stone_number_label.text = "Stone: " + str(stone_quantity) + " (occupied cells: " + str(stone_space) + ")"
		grass_number_label.text = "Grass: " + str(grass_quantity) + " (occupied cells: " + str(grass_space) + ")"
		shrub_number_label.text = "Shrub: " + str(shrub_quantity) + " (occupied cells: " + str(shrub_space) + ")"
		empty_space_label.text = "Empty space: " + str(state.get_empty_space())
	else:
		tree_number_label.text = "Trees: -"
		stone_number_label.text = "Stone: -"
		grass_number_label.text = "Grass: -"
		shrub_number_label.text = "Shrub: -"
		empty_space_label.text = "Empty space: -"
		
func clear() -> void:
	title_label.text = "Macro cell"
	coords_label.text = "Coords: -"
	terrain_label.text = "Terrain: -"
	water_label.text = "Water: -"
	coast_label.text = "Coast: -"
	river_label.text = "River: -"
	biome_label.text = "Biome: -"
	tree_number_label.text = "Trees: -"
	stone_number_label.text = "Stone: -"
	grass_number_label.text = "Grass: -"
	shrub_number_label.text = "Shrub: -"
	empty_space_label.text = "Empty space: -"


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
