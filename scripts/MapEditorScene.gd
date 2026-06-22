extends Node2D

var world: World
var renderer: WorldRenderer

@onready var back_to_menu_button: Button = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var save_map_button: Button = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/SaveMapButton
@onready var save_map_file_dialog: FileDialog = $SaveMapFileDialog

func _ready() -> void:
	save_map_button.text = tr("save_map")
	back_to_menu_button.text = tr("back_to_menu")
	
	
	if GameSettings.selected_save_file != "":
		var load_service := WorldLoadService.new()
		world = load_service.load_world_from_json(GameSettings.selected_save_file)

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

	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	save_map_button.pressed.connect(_on_save_map_pressed)
	save_map_file_dialog.file_selected.connect(
	_on_save_map_file_selected
	)

func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MapEditorMenu.tscn")

func _on_save_map_pressed() -> void:
	save_map_file_dialog.popup_centered()

func _on_save_map_file_selected(path: String) -> void:
	var save_service := WorldSaveService.new()

	save_service.save_world_to_json(
		world,
		path
	)
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos: Vector2 = renderer.get_local_mouse_position()

			var cell_x: int = int(mouse_pos.x / WorldRenderer.CELL_SIZE)
			var cell_y: int = int(mouse_pos.y / WorldRenderer.CELL_SIZE)

			var cell := _get_cell_at(cell_x, cell_y)

			if cell == null:
				return

			cell.terrain_base = GameTypes.TerrainBase.WATER
			cell.water_type = GameTypes.WaterType.LAKE
			cell.river_shape = GameTypes.RiverShape.NONE
			cell.coast_type = GameTypes.CoastType.NONE
			cell.cover = GameTypes.Cover.NONE

			renderer.queue_redraw()
			
func _get_cell_at(x: int, y: int) -> MacroCellData:
	for cell in world.cells:
		if cell.x == x and cell.y == y:
			return cell

	return null
