extends Control

@onready var label2: Label = $VBoxContainer/Label2
@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var load_game_button: Button = $VBoxContainer/LoadGameButton
@onready var map_editor_button: Button = $VBoxContainer/MapEditorButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
@onready var exit_button: Button = $VBoxContainer/ExitButton

func _ready() -> void:
	label2.text = tr("main_menu")
	new_game_button.text = tr("new_game")
	load_game_button.text = tr("load_game")
	map_editor_button.text = tr("map_editor")
	options_button.text = tr("options")
	exit_button.text = tr("exit")
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	map_editor_button.pressed.connect(_on_map_editor_pressed)
	options_button.pressed.connect(_on_options_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
func _on_new_game_pressed() -> void:
	_show_not_ready_popup()
	
func _on_load_game_pressed() -> void:
	_show_not_ready_popup()
	
func _on_map_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MapEditorMenu.tscn")
	
func _on_options_pressed() -> void:
	_show_not_ready_popup()
	
func _on_exit_pressed() -> void:
	get_tree().quit()


func _show_not_ready_popup() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Mondo non disponibile"
	dialog.dialog_text = "Questo mondo predefinito non è ancora pronto."
	add_child(dialog)
	dialog.popup_centered()
