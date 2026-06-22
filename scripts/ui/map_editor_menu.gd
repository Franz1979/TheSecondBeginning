extends Control

@onready var label2: Label = $CenterContainer/VBoxContainer/Label2
@onready var modify_existing_map_button: Button = $CenterContainer/VBoxContainer/ModifyExistingMapButton
@onready var create_random_map_button: Button = $CenterContainer/VBoxContainer/CreateRandomMapButton
@onready var create_new_map_button: Button = $CenterContainer/VBoxContainer/CreateNewMap
@onready var back_to_menu_button: Button = $CenterContainer/VBoxContainer/BackToMenuButton
@onready var open_map_file_dialog: FileDialog = $OpenMapFileDialog

func _ready() -> void:
	label2.text = tr("map_editor")


	modify_existing_map_button.text = tr("modify_existing_map")
	create_random_map_button.text = tr("create_random_map")
	create_new_map_button.text = tr("create_new_map")
	back_to_menu_button.text = tr("back_to_menu")

	modify_existing_map_button.pressed.connect(_on_modify_existing_map_pressed)
	create_random_map_button.pressed.connect(_on_create_random_map_pressed)
	create_new_map_button.pressed.connect(_on_create_new_map_pressed)
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	open_map_file_dialog.file_selected.connect(_on_open_map_file_selected)

func _on_modify_existing_map_pressed() -> void:
	open_map_file_dialog.popup_centered()
	
func _on_open_map_file_selected(path: String) -> void:
	GameSettings.selected_save_file = path
	get_tree().change_scene_to_file("res://scenes/MapEditorScene.tscn")


func _on_create_random_map_pressed() -> void:
	GameSettings.selected_map_type = "random"
	GameSettings.selected_save_file = ""
	get_tree().change_scene_to_file("res://scenes/MapEditorScene.tscn")


func _on_create_new_map_pressed() -> void:
	GameSettings.selected_map_type = "empty"
	GameSettings.selected_save_file = ""
	get_tree().change_scene_to_file(
		"res://scenes/MapEditorScene.tscn"
	)


func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _show_not_ready_popup() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("not_ready_title")
	dialog.dialog_text = tr("not_ready_text")
	add_child(dialog)
	dialog.popup_centered()
