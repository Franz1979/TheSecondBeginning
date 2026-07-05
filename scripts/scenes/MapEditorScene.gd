extends Node2D

var world: World
var renderer: WorldRenderer
var editor_controller: MapEditorController

@onready var back_to_menu_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var save_map_button: Button = $CanvasLayer/ActionPanelContainer/MarginContainer/VBoxContainer/SaveMapButton
@onready var save_map_file_dialog: FileDialog = $SaveMapFileDialog
@onready var terrain_water_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/TerrainWaterToolButton
@onready var terrain_plain_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/TerrainPlainToolButton
@onready var terrain_hill_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/TerrainHillToolButton
@onready var terrain_mountain_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/TerrainMountainToolButton
@onready var terrain_none_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/TerrainNoneButton
@onready var water_options_label: Label = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterOptionsLabel
@onready var water_sea_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterSeaToolButton
@onready var water_lake_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterLakeToolButton
@onready var water_river_tool_button: Button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterRiverToolButton

@onready var biome_submenu_margin = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin
@onready var biome_label = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeLabel
@onready var biome_none_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeNoneToolButton
@onready var biome_forest_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeForestToolButton
@onready var biome_grassland_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeGrasslandToolButton
@onready var biome_desert_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeDesertToolButton
@onready var biome_swamp_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeSwampToolButton
@onready var biome_fertile_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeFertileToolButton
@onready var biome_rocky_tool_button = $CanvasLayer/BrushPanelContainer/MarginContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeRockyToolButton

@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/MacroCellInfoPanel

func _ready() -> void:
	save_map_button.text = tr("save_map")
	back_to_menu_button.text = tr("back_to_menu")
	terrain_water_tool_button.text = tr("water")
	water_options_label.text = tr("water_type")
	water_sea_tool_button.text = tr("sea")
	water_lake_tool_button.text = tr("lake")
	water_river_tool_button.text = tr("river")
	terrain_plain_tool_button.text = tr("plain")
	terrain_hill_tool_button.text = tr("hill")
	terrain_mountain_tool_button.text = tr("mountain")
	terrain_none_button.text = tr("select")
	
	biome_label.text = tr("biome")
	biome_none_tool_button.text = tr("none")
	biome_forest_tool_button.text = tr("forest")
	biome_grassland_tool_button.text = tr("grassland")
	biome_fertile_tool_button.text = tr("fertile")
	biome_desert_tool_button.text = tr("desert")
	biome_swamp_tool_button.text = tr("swamp")
	biome_rocky_tool_button.text = tr("rocky")
	
	water_options_label.visible = false
	water_sea_tool_button.visible = false
	water_lake_tool_button.visible = false
	water_river_tool_button.visible = false
	
	biome_submenu_margin.visible = false
	macro_cell_info_panel.visible = false
	
	biome_none_tool_button.pressed.connect(_on_biome_none_pressed)
	biome_forest_tool_button.pressed.connect(_on_biome_forest_pressed)
	biome_grassland_tool_button.pressed.connect(_on_biome_grassland_pressed)
	biome_desert_tool_button.pressed.connect(_on_biome_desert_pressed)
	biome_swamp_tool_button.pressed.connect(_on_biome_swamp_pressed)
	biome_fertile_tool_button.pressed.connect(_on_biome_fertile_pressed)
	biome_rocky_tool_button.pressed.connect(_on_biome_rocky_pressed)
	
	
	if GameSettings.selected_map_file != "":
		var load_service := WorldLoadService.new()
		world = load_service.load_world_from_json(GameSettings.selected_map_file)

		if world == null:
			print("Caricamento fallito. Genero una nuova mappa.")
			world = World.new()
			world.generate_empty_world()
	else:
		world = World.new()
		world.generate_empty_world()

	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)
	
	editor_controller = MapEditorController.new()
	editor_controller.setup(world, renderer)
	
	editor_controller.cell_selected.connect(_on_cell_selected)
	
	terrain_none_button.pressed.connect(
	func(): _select_terrain_brush(
		MapEditorController.TerrainBrush.NONE,
		terrain_none_button
	)
)

	terrain_water_tool_button.pressed.connect(
	func(): _select_terrain_brush(
		MapEditorController.TerrainBrush.WATER,
		terrain_water_tool_button
	)
)

	water_sea_tool_button.pressed.connect(
	func(): _select_water_type(
		GameTypes.WaterType.SEA,
		water_sea_tool_button
	)
)

	water_lake_tool_button.pressed.connect(
	func(): _select_water_type(
		GameTypes.WaterType.LAKE,
		water_lake_tool_button
	)
)

	water_river_tool_button.pressed.connect(
	func(): _select_water_type(
		GameTypes.WaterType.RIVER,
		water_river_tool_button
	)
)

	terrain_plain_tool_button.pressed.connect(
	func(): _select_terrain_brush(
		MapEditorController.TerrainBrush.PLAIN,
		terrain_plain_tool_button
	)
)

	terrain_hill_tool_button.pressed.connect(
	func(): _select_terrain_brush(
		MapEditorController.TerrainBrush.HILL,
		terrain_hill_tool_button
	)
)

	terrain_mountain_tool_button.pressed.connect(
	func(): _select_terrain_brush(
		MapEditorController.TerrainBrush.MOUNTAIN,
		terrain_mountain_tool_button
	)
)

	_select_terrain_brush(
	MapEditorController.TerrainBrush.NONE,
	terrain_none_button
)
	
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	save_map_button.pressed.connect(_on_save_map_pressed)
	save_map_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_map_file_dialog.current_dir = GameSettings.MAPS_DIR
	save_map_file_dialog.file_selected.connect(
	_on_save_map_file_selected
	)

func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MapEditorMenu.tscn")

func _on_save_map_pressed() -> void:
	save_map_file_dialog.popup_centered()

func _on_save_map_file_selected(path: String) -> void:
	var save_service := WorldSaveService.new()

	save_service.save_world_to_json(
		world,
		path
	)
	
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_0:
				_select_terrain_brush(
					MapEditorController.TerrainBrush.NONE,
					terrain_none_button
				)
			KEY_1:
				_select_terrain_brush(
					MapEditorController.TerrainBrush.WATER,
					terrain_water_tool_button
				)
			KEY_2:
				_select_terrain_brush(
					MapEditorController.TerrainBrush.PLAIN,
					terrain_plain_tool_button
				)
			KEY_3:
				_select_terrain_brush(
					MapEditorController.TerrainBrush.HILL,
					terrain_hill_tool_button
				)
			KEY_4:
				_select_terrain_brush(
					MapEditorController.TerrainBrush.MOUNTAIN,
					terrain_mountain_tool_button
				)

	editor_controller.handle_input(event)

	
func _select_terrain_brush(
	brush: MapEditorController.TerrainBrush,
	selected_button: Button
) -> void:
	editor_controller.set_terrain_brush(brush)
	macro_cell_info_panel.visible = brush == MapEditorController.TerrainBrush.NONE
	
	if brush == MapEditorController.TerrainBrush.NONE:
		macro_cell_info_panel.clear()
		
	var is_water := brush == MapEditorController.TerrainBrush.WATER
	
	var has_biome := brush == MapEditorController.TerrainBrush.PLAIN \
		or brush == MapEditorController.TerrainBrush.HILL \
		or brush == MapEditorController.TerrainBrush.MOUNTAIN

	water_options_label.visible = is_water
	water_sea_tool_button.visible = is_water
	water_lake_tool_button.visible = is_water
	water_river_tool_button.visible = is_water

	if is_water:
		_select_water_type(
		GameTypes.WaterType.SEA,
		water_sea_tool_button
	)
	
	biome_submenu_margin.visible = has_biome

	if has_biome:
		_move_biome_submenu_under_button(selected_button)
		_update_biome_buttons_for_brush(brush)
		_select_biome(
		GameTypes.Biome.NONE,
		biome_none_tool_button
	)

	terrain_none_button.button_pressed = false
	terrain_water_tool_button.button_pressed = false
	terrain_plain_tool_button.button_pressed = false
	terrain_hill_tool_button.button_pressed = false
	terrain_mountain_tool_button.button_pressed = false

	terrain_none_button.text = tr("select")
	terrain_water_tool_button.text = tr("water")
	terrain_plain_tool_button.text = tr("plain")
	terrain_hill_tool_button.text = tr("hill")
	terrain_mountain_tool_button.text = tr("mountain")

	selected_button.button_pressed = true
	selected_button.text = "▶ " + selected_button.text
	
func _move_biome_submenu_under_button(selected_button: Button) -> void:
	var parent := biome_submenu_margin.get_parent()

	parent.remove_child(biome_submenu_margin)

	var button_index := selected_button.get_index()

	parent.add_child(biome_submenu_margin)
	parent.move_child(biome_submenu_margin, button_index + 1)
	
func _update_biome_buttons_for_brush(
	brush: MapEditorController.TerrainBrush
) -> void:
	biome_none_tool_button.disabled = false
	biome_forest_tool_button.disabled = false
	biome_grassland_tool_button.disabled = false
	biome_desert_tool_button.disabled = false

	biome_swamp_tool_button.disabled = brush != MapEditorController.TerrainBrush.PLAIN
	biome_fertile_tool_button.disabled = brush == MapEditorController.TerrainBrush.MOUNTAIN
	biome_rocky_tool_button.disabled = brush == MapEditorController.TerrainBrush.PLAIN
	
func _on_biome_none_pressed() -> void:
	_select_biome(GameTypes.Biome.NONE, biome_none_tool_button)

func _on_biome_forest_pressed() -> void:
	_select_biome(GameTypes.Biome.FOREST, biome_forest_tool_button)

func _on_biome_grassland_pressed() -> void:
	_select_biome(GameTypes.Biome.GRASSLAND, biome_grassland_tool_button)

func _on_biome_desert_pressed() -> void:
	_select_biome(GameTypes.Biome.DESERT, biome_desert_tool_button)

func _on_biome_swamp_pressed() -> void:
	_select_biome(GameTypes.Biome.SWAMP, biome_swamp_tool_button)

func _on_biome_fertile_pressed() -> void:
	_select_biome(GameTypes.Biome.FERTILE, biome_fertile_tool_button)

func _on_biome_rocky_pressed() -> void:
	_select_biome(GameTypes.Biome.ROCKY, biome_rocky_tool_button)
	
	
func _select_water_type(
	water_type: GameTypes.WaterType,
	selected_button: Button
) -> void:
	editor_controller.set_water_type(water_type)

	water_sea_tool_button.button_pressed = false
	water_lake_tool_button.button_pressed = false
	water_river_tool_button.button_pressed = false

	water_sea_tool_button.text = tr("sea")
	water_lake_tool_button.text = tr("lake")
	water_river_tool_button.text =tr("river")

	selected_button.button_pressed = true
	selected_button.text = "▶ " + selected_button.text
func _select_biome(
	biome: GameTypes.Biome,
	selected_button: Button
) -> void:
	editor_controller.set_biome(biome)

	biome_none_tool_button.button_pressed = false
	biome_forest_tool_button.button_pressed = false
	biome_grassland_tool_button.button_pressed = false
	biome_desert_tool_button.button_pressed = false
	biome_swamp_tool_button.button_pressed = false
	biome_fertile_tool_button.button_pressed = false
	biome_rocky_tool_button.button_pressed = false

	biome_none_tool_button.text = tr("none")
	biome_forest_tool_button.text = tr("forest")
	biome_grassland_tool_button.text = tr("grassland")
	biome_desert_tool_button.text = tr("desert")
	biome_swamp_tool_button.text = tr("swamp")
	biome_fertile_tool_button.text = tr("fertile")
	biome_rocky_tool_button.text = tr("rocky")

	selected_button.button_pressed = true
	selected_button.text = "▶ " + selected_button.text
	
func _on_cell_selected(cell: MacroCellData, state: MacroCellState) -> void:
	macro_cell_info_panel.show_cell(cell, state)
