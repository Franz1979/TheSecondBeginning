extends Control

@onready var label2: Label = $VBoxContainer/Label2
@onready var new_random_world_button: Button = $VBoxContainer/NewRandomWorldButton
@onready var choose_scenario_button: Button = $VBoxContainer/ChooseScenarioButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var open_scenario_file_dialog: FileDialog = $OpenScenarioFileDialog


func _ready() -> void:
	label2.text = tr("new_game_menu")
	new_random_world_button.text = tr("new_random_world")
	choose_scenario_button.text = tr("choose_scenario")
	back_button.text = tr("back")

	new_random_world_button.pressed.connect(_on_new_random_world_pressed)
	choose_scenario_button.pressed.connect(_on_choose_scenario_pressed)
	back_button.pressed.connect(_on_back_pressed)
	open_scenario_file_dialog.file_selected.connect(_on_open_scenario_file_selected)
	open_scenario_file_dialog.access = FileDialog.ACCESS_USERDATA
	open_scenario_file_dialog.current_dir = GameSettings.MAPS_DIR


func _on_new_random_world_pressed() -> void:
	GameSettings.selected_map_type = "random"
	GameSettings.selected_map_file = ""
	GameSettings.selected_save_file = ""

	# Scelta mappa fatta — prima di avviare la partita vera e propria, passa dalla schermata
	# opzioni (eta' del mondo) invece di andare direttamente a WorldScene.
	get_tree().change_scene_to_file("res://simulation/scenes/menus/NewGameOptionsMenu.tscn")


func _on_choose_scenario_pressed() -> void:
	open_scenario_file_dialog.popup_centered()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://simulation/scenes/menus/MainMenu.tscn")
	
func _show_not_ready_popup() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Mondo non disponibile"
	dialog.dialog_text = "Questo mondo predefinito non è ancora pronto."
	add_child(dialog)
	dialog.popup_centered()

func _on_open_scenario_file_selected(path: String) -> void:
	GameSettings.selected_map_type = "saved"
	GameSettings.selected_map_file = path
	GameSettings.selected_save_file = ""

	# Stesso inoltro di _on_new_random_world_pressed sopra: la mappa e' scelta, manca solo l'eta'
	# del mondo prima di avviare davvero.
	get_tree().change_scene_to_file("res://simulation/scenes/menus/NewGameOptionsMenu.tscn")
