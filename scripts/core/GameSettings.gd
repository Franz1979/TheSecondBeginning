extends Node

const MAPS_DIR := "user://maps/"
const SAVES_DIR := "user://saves/"

var selected_map_type: String = ""
var selected_map_file: String = ""
var selected_save_file: String = ""
var selected_macro_cell_x: int = -1
var selected_macro_cell_y: int = -1

func _ready() -> void:
	print("GameSettings ready")
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
