extends Node

const MAPS_DIR := "user://maps/"
const SAVES_DIR := "user://saves/"

var selected_map_type: String = ""
var selected_map_file: String = ""
var selected_save_file: String = ""

func _ready() -> void:
	print("GameSettings ready")
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
