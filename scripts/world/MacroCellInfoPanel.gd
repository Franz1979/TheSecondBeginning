class_name MacroCellInfoPanel
extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var geography_info: CellGeographyInfo = $MarginContainer/VBoxContainer/CellGeographyInfo
@onready var space_label: Label = $MarginContainer/VBoxContainer/SpaceLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/ShrubNumberLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TreeNumberLabel
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/EmptySpaceLabel
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer


func _ready() -> void:
	clear()


func show_cell(cell: MacroCellData, state: MacroCellState, show_resources: bool = true) -> void:
	if cell == null:
		clear(show_resources)
		return
	title_label.text = "Macro Cell Data:"
	coords_label.text = "Coords: " + str(cell.x) + ", " + str(cell.y)
	geography_info.show_geography(cell)
	_set_resources_visible(show_resources)
	if not show_resources:
		return
	space_label.text = " - - - - - - - - - -"

	if state != null:
		var stone_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
		var stone_space := state.get_dedicated_space(GameTypes.WorldObjectType.ROCK)
		var grass_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.GRASS)
		var grass_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
		var shrub_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.SHRUB)
		var shrub_space := state.get_dedicated_space(GameTypes.WorldObjectType.SHRUB)
		var tree_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.TREE)
		var tree_space := state.get_dedicated_space(GameTypes.WorldObjectType.TREE)
		stone_number_label.text = "Stone: " + NumberFormatter.format_int(stone_quantity) + " (occupied cells: " + NumberFormatter.format_int(stone_space) + ")"
		grass_number_label.text = "Grass: " + NumberFormatter.format_int(grass_quantity) + " (occupied cells: " + NumberFormatter.format_int(grass_space) + ")"
		shrub_number_label.text = "Shrub: " + NumberFormatter.format_int(shrub_quantity) + " (occupied cells: " + NumberFormatter.format_int(shrub_space) + ")"
		tree_number_label.text = "Trees: " + NumberFormatter.format_int(tree_quantity) + " (occupied cells: " + NumberFormatter.format_int(tree_space) + ")"
		resource_separator_label.text = " - - - - - - - - - -"
		# Su SEA/LAKE il calcolo "naturale" di get_empty_space() risulterebbe comunque
		# TOTAL_SPACE (nessuna risorsa terrestre ha mai popolato dedicated_space lì, essendo
		# la loro densità 0 su terrain WATER): un valore fuorviante da mostrare, dato che quello
		# spazio non sarà mai disponibile per vegetazione/roccia. Qui lo forziamo esplicitamente
		# a 0 solo per la visualizzazione; get_empty_space() stesso resta invariato (nessun
		# chiamante ne ha bisogno diverso: tutti bypassano già la lettura su terrain WATER
		# tramite i propri controlli su max_density/growth_rate, sempre 0 lì).
		var empty_ground_space: int = state.get_empty_space()
		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			empty_ground_space = 0
		empty_space_label.text = "Empty ground space: " + NumberFormatter.format_int(empty_ground_space)
	else:
		stone_number_label.text = "Stone: -"
		grass_number_label.text = "Grass: -"
		shrub_number_label.text = "Shrub: -"
		tree_number_label.text = "Trees: -"
		empty_space_label.text = "Empty ground space: -"


func clear(show_resources: bool = true) -> void:
	title_label.text = "Macro cell"
	coords_label.text = "Coords: -"
	geography_info.clear()
	_set_resources_visible(show_resources)
	if not show_resources:
		return
	stone_number_label.text = "Stone: -"
	grass_number_label.text = "Grass: -"
	shrub_number_label.text = "Shrub: -"
	tree_number_label.text = "Trees: -"
	empty_space_label.text = "Empty ground space: -"


func _set_resources_visible(value: bool) -> void:
	space_label.visible = value
	stone_number_label.visible = value
	grass_number_label.visible = value
	shrub_number_label.visible = value
	tree_number_label.visible = value
	resource_separator_label.visible = value
	empty_space_label.visible = value
