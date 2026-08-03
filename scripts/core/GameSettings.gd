extends Node

const MAPS_DIR := "user://maps/"
const SAVES_DIR := "user://saves/"

var selected_map_type: String = ""
var selected_map_file: String = ""
var selected_save_file: String = ""
var selected_macro_cell_x: int = -1
var selected_macro_cell_y: int = -1
var active_world: World = null
var active_game_data: GameData = null
var returning_to_game_scene: bool = false
var active_clock_is_playing: bool = false
var active_clock_speed: int = 0 # GameClockController.Speed.X1 — kept as plain int here to
# avoid GameSettings (an autoload, parsed before the global script class cache is ready)
# depending on GameClockController's class_name at parse time.
# Stato dei due toggle di visualizzazione di MacroCellScene (visibilità animali, aggiornamenti
# flora giornalieri) — MacroCellScene è un'istanza NUOVA ogni volta che ci si entra
# (change_scene_to_file ricrea l'intero albero di nodi), quindi le variabili locali dello script
# perderebbero lo stato ad ogni uscita/rientro senza salvarlo qui. Persistito solo per la sessione
# corrente (non nei save su disco), stesso trattamento di active_clock_is_playing sopra.
var macro_cell_animals_visible: bool = true
var macro_cell_flora_updates_enabled: bool = true

func _ready() -> void:
	print("GameSettings ready")
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
