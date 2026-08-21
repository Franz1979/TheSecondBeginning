extends Node2D

var world: World
var renderer: WorldRenderer
var editor_controller: MapEditorController
var _pending_leave_action: StringName = &""
# Ultimo bioma scelto esplicitamente dall'utente (via _select_biome, sia click diretto che
# ripristino automatico sotto) — persiste tra i cambi di pennello terreno, cosa che PRIMA non
# succedeva: _select_terrain_brush forzava sempre "none" ad ogni cambio pennello, quindi bastava
# cambiare pennello senza ri-cliccare esplicitamente un bioma per perderlo silenziosamente. Con
# mappe grandi questo produceva interi mondi a bioma NONE senza che l'utente se ne accorgesse.
var _last_selected_biome: GameTypes.Biome = GameTypes.Biome.NONE

@onready var primary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/PrimaryActionsBar
@onready var secondary_actions_bar: IconButtonRow = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/SecondaryActionsBar
@onready var system_menu_dialog: SystemMenuDialog = $SystemMenuDialog
@onready var save_confirmation_dialog: SaveConfirmationDialog = $SaveConfirmationDialog
@onready var save_map_file_dialog: FileDialog = $SaveMapFileDialog
@onready var terrain_water_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/TerrainWaterToolButton
@onready var terrain_plain_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/TerrainPlainToolButton
@onready var terrain_hill_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/TerrainHillToolButton
@onready var terrain_mountain_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/TerrainMountainToolButton
@onready var terrain_none_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/TerrainNoneButton
@onready var water_options_label: Label = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterOptionsLabel
@onready var water_sea_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterSeaToolButton
@onready var water_lake_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterLakeToolButton
@onready var water_river_tool_button: Button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/WaterSubmenuMargin/WaterSubmenuVBox/WaterRiverToolButton

@onready var biome_submenu_margin = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin
@onready var biome_label = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeLabel
@onready var biome_none_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeNoneToolButton
@onready var biome_forest_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeForestToolButton
@onready var biome_grassland_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeGrasslandToolButton
@onready var biome_desert_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeDesertToolButton
@onready var biome_swamp_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeSwampToolButton
@onready var biome_fertile_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeFertileToolButton
@onready var biome_rocky_tool_button = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/BiomeSubmenuMargin/BiomeSubmenuVBox/BiomeRockyToolButton

@onready var macro_cell_info_panel: MacroCellInfoPanel = $CanvasLayer/Sidebar/MarginContainer/ScrollContainer/VBoxContainer/MacroCellInfoPanel

func _ready() -> void:
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
	
	save_map_file_dialog.access = FileDialog.ACCESS_USERDATA
	save_map_file_dialog.current_dir = GameSettings.MAPS_DIR
	save_map_file_dialog.file_selected.connect(
	_on_save_map_file_selected
	)

	secondary_actions_bar.configure_slot(0, "☰", tr("menu"), &"menu")
	secondary_actions_bar.action_pressed.connect(_on_secondary_action_pressed)
	system_menu_dialog.add_action(tr("save_map"), &"save")
	system_menu_dialog.add_action(tr("back_to_menu"), &"back_to_main_menu")
	system_menu_dialog.add_action(tr("exit"), &"exit_game")
	system_menu_dialog.action_selected.connect(_on_system_menu_action_selected)
	save_confirmation_dialog.option_selected.connect(_on_save_confirmation_option_selected)

func _on_secondary_action_pressed(action_id: StringName) -> void:
	match action_id:
		&"menu":
			system_menu_dialog.open_menu()

func _on_system_menu_action_selected(action_id: StringName) -> void:
	match action_id:
		&"save":
			_on_save_map_pressed()
		&"back_to_main_menu":
			_pending_leave_action = &"back_to_main_menu"
			save_confirmation_dialog.open_dialog()
		&"exit_game":
			_pending_leave_action = &"exit_game"
			save_confirmation_dialog.open_dialog()

func _on_save_confirmation_option_selected(option: StringName) -> void:
	match option:
		&"save_and_leave":
			_on_save_map_pressed()
		&"leave_without_saving":
			_execute_pending_leave_action()
		&"cancel":
			_pending_leave_action = &""

func _execute_pending_leave_action() -> void:
	var action := _pending_leave_action
	_pending_leave_action = &""
	match action:
		&"back_to_main_menu":
			get_tree().change_scene_to_file("res://simulation/scenes/menus/MainMenu.tscn")
		&"exit_game":
			get_tree().quit()

func _on_save_map_pressed() -> void:
	save_map_file_dialog.popup_centered()

func _on_save_map_file_selected(path: String) -> void:
	var save_service := WorldSaveService.new()

	save_service.save_world_to_json(
		world,
		path
	)

	if _pending_leave_action != &"":
		_execute_pending_leave_action()
	
func _unhandled_input(event: InputEvent) -> void:
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
		macro_cell_info_panel.clear(false)
		
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
		# Ripristina l'ultimo bioma scelto dall'utente invece di azzerarlo a "none" — se non è più
		# ammesso col nuovo pennello (vedi _update_biome_buttons_for_brush, es. FERTILE disabilitato
		# su MOUNTAIN), ripiega su "none" invece di lasciare selezionato un bottone disabilitato.
		var restored_button := _get_biome_button(_last_selected_biome)
		var target_biome := _last_selected_biome
		if restored_button.disabled:
			target_biome = GameTypes.Biome.NONE
		_select_biome(target_biome, _get_biome_button(target_biome))

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

func _get_biome_button(biome: GameTypes.Biome) -> Button:
	match biome:
		GameTypes.Biome.FOREST:
			return biome_forest_tool_button
		GameTypes.Biome.GRASSLAND:
			return biome_grassland_tool_button
		GameTypes.Biome.DESERT:
			return biome_desert_tool_button
		GameTypes.Biome.SWAMP:
			return biome_swamp_tool_button
		GameTypes.Biome.FERTILE:
			return biome_fertile_tool_button
		GameTypes.Biome.ROCKY:
			return biome_rocky_tool_button
		_:
			return biome_none_tool_button

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
	_last_selected_biome = biome
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
	macro_cell_info_panel.show_cell(cell, state, world, false)
