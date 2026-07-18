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
@onready var tree_subtype_label: Label = $MarginContainer/VBoxContainer/TreeSubtypeLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/ShrubNumberLabel
@onready var shrub_subtype_label: Label = $MarginContainer/VBoxContainer/ShrubSubtypeLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/EmptySpaceLabel
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer


func _ready() -> void:
	clear()


# show_subtype_detail: mostra la ripartizione dei sottotipi di SHRUB (wood_only/fruit_bearing).
# Di default false per non alterare il pannello riusato in GameScene/MapEditorScene: solo
# MacroCellScene (vista zoomata di una singola macrocella) lo passa a true.
func show_cell(cell: MacroCellData, state: MacroCellState, show_subtype_detail: bool = false) -> void:
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
		_update_shrub_subtype_label(cell, state, show_subtype_detail)
		_update_tree_subtype_label(cell, state, show_subtype_detail)
	else:
		tree_number_label.text = "Trees: -"
		tree_subtype_label.visible = false
		stone_number_label.text = "Stone: -"
		grass_number_label.text = "Grass: -"
		shrub_number_label.text = "Shrub: -"
		shrub_subtype_label.visible = false
		empty_space_label.text = "Empty space: -"
		
# Seconda riga, indentata, sotto la riga principale di SHRUB: nascosta se show_subtype_detail è
# false (uso condiviso in GameScene/MapEditorScene) o se la cella non ha ancora una
# subtype_composition tracciata (nessuno shrub presente). subtype_composition resta ancorata a
# dedicated_space (unità di spazio, invariato): qui si converte solo il valore mostrato in
# resource_quantity, con la stessa densità già usata per l'aggregato SHRUB della cella (identica
# formula di ResourceGrowthService/InitialResourceSetupService ecc.: quantity = round(space * max_density)).
func _update_shrub_subtype_label(cell: MacroCellData, state: MacroCellState, show_subtype_detail: bool) -> void:
	if not show_subtype_detail:
		shrub_subtype_label.visible = false
		return

	var composition := state.get_subtype_composition(GameTypes.WorldObjectType.SHRUB)
	if composition.is_empty():
		shrub_subtype_label.visible = false
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.SHRUB, cell.terrain_base, cell.biome, cell.coast_type
	)
	var wood_quantity: int = int(round(int(composition.get("wood_only", 0)) * max_density))
	var fruit_quantity: int = int(round(int(composition.get("fruit_bearing", 0)) * max_density))

	shrub_subtype_label.text = "  - wood_only: " + str(wood_quantity) + " / fruit_bearing: " + str(fruit_quantity)
	shrub_subtype_label.visible = true


# Stesso formato a due righe di _update_shrub_subtype_label sopra, con le tre chiavi di TREE
# invece delle due di SHRUB.
func _update_tree_subtype_label(cell: MacroCellData, state: MacroCellState, show_subtype_detail: bool) -> void:
	if not show_subtype_detail:
		tree_subtype_label.visible = false
		return

	var composition := state.get_subtype_composition(GameTypes.WorldObjectType.TREE)
	if composition.is_empty():
		tree_subtype_label.visible = false
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.TREE, cell.terrain_base, cell.biome, cell.coast_type
	)
	var wood_quantity: int = int(round(int(composition.get("wood_only", 0)) * max_density))
	var wild_fruit_quantity: int = int(round(int(composition.get("wild_fruit", 0)) * max_density))
	var domesticable_fruit_quantity: int = int(round(int(composition.get("domesticable_fruit", 0)) * max_density))

	tree_subtype_label.text = "  - wood_only: " + str(wood_quantity) + " / wild_fruit: " + str(wild_fruit_quantity) + " / domesticable_fruit: " + str(domesticable_fruit_quantity)
	tree_subtype_label.visible = true


func clear() -> void:
	title_label.text = "Macro cell"
	coords_label.text = "Coords: -"
	terrain_label.text = "Terrain: -"
	water_label.text = "Water: -"
	coast_label.text = "Coast: -"
	river_label.text = "River: -"
	biome_label.text = "Biome: -"
	tree_number_label.text = "Trees: -"
	tree_subtype_label.visible = false
	stone_number_label.text = "Stone: -"
	grass_number_label.text = "Grass: -"
	shrub_number_label.text = "Shrub: -"
	shrub_subtype_label.visible = false
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
