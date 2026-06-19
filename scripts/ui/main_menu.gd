extends Control

@onready var random_map_button: Button = $VBoxContainer/RandomMapButton
@onready var preset_island_button: Button = $VBoxContainer/PresetIslandButton
@onready var preset_valley_button: Button = $VBoxContainer/PresetValleyButton
@onready var preset_mountain_button: Button = $VBoxContainer/PresetMountainButton
@onready var exit_button: Button = $VBoxContainer/ExitButton

func _ready() -> void:
	random_map_button.pressed.connect(_on_random_map_pressed)
	preset_island_button.pressed.connect(_on_preset_island_pressed)
	preset_valley_button.pressed.connect(_on_preset_valley_pressed)
	preset_mountain_button.pressed.connect(_on_preset_mountain_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _on_random_map_pressed() -> void:
	GameSettings.selected_map_type = "random"
	get_tree().change_scene_to_file("res://scenes/WorldScene.tscn")


func _on_preset_island_pressed() -> void:
	GameSettings.selected_map_type = "island"
	get_tree().change_scene_to_file("res://scenes/WorldScene.tscn")


func _on_preset_valley_pressed() -> void:
	_show_not_ready_popup()


func _on_preset_mountain_pressed() -> void:
	_show_not_ready_popup()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _show_not_ready_popup() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Mondo non disponibile"
	dialog.dialog_text = "Questo mondo predefinito non è ancora pronto."
	add_child(dialog)
	dialog.popup_centered()
