extends Control

# Schermata intermedia inserita nel flusso di creazione nuova partita, dopo la scelta di mappa/
# scenario (NewGameMenu) e prima dell'avvio effettivo (GameScene): raccoglie la scelta dell'eta'
# del mondo, la densita' di semina automatica degli animali e la numerosita' di ciascuna
# popolazione. NewGameMenu ha gia' impostato selected_map_type/selected_map_file prima di
# arrivare qui — questa scena non li tocca, si limita ad aggiungere GameSettings.
# selected_world_age_mode/selected_animal_density/selected_population_size e a inoltrare verso
# GameScene.
#
# Tutte le label passano da tr("chiave"), come ovunque nel resto del progetto — nessun CSV di
# traduzione e' ancora collegato (nessuna sezione [internationalization] in project.godot),
# quindi le chiavi vengono mostrate letteralmente per ora, esattamente come "back"/"options"/
# ecc. altrove: non e' un'eccezione di questa schermata, e' lo stato di fatto dell'intero
# progetto finche' la localizzazione non verra' implementata. Schema di naming replicato da
# quello gia' in uso (snake_case minuscolo, prefisso di contesto "world_age_"/"animal_density_"/
# "population_size_" per le chiavi specifiche di ciascun gruppo — stesso pattern di
# "exit_confirmation_*"/"tab_fauna_*" — chiave generica "back" riusata cosi' com'e').
#
# Tutti e tre i gruppi: bottoni toggle sempre visibili in un ButtonGroup esclusivo, invece di un
# OptionButton a tendina — stesso pattern gia' usato per i controlli di velocita' orologio in
# GameScene.tscn (Speed1x/2x/3x/4xButton + ButtonGroup_speed).
#
# I gruppi "Densita' animali"/"Numerosita' popolazioni" restano visibili anche con "Classic
# (debug)" selezionato (nessuna complicazione di layout condizionale), ma diventano
# atenuati/disabilitati in quel caso — entrambe le scelte sono comunque ignorate da
# GameScene._populate_new_world quando selected_world_age_mode == "CLASSIC" (nessuna semina
# automatica di animali), l'attenuazione visiva serve solo a non suggerire un effetto che in
# quel momento non avrebbero.

const DISABLED_PANEL_ALPHA := 0.4

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var world_age_header_label: Label = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/WorldAgeHeaderLabel
@onready var young_button: Button = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/YoungButton
@onready var adult_button: Button = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/AdultButton
@onready var old_button: Button = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/OldButton
@onready var classic_button: Button = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/ClassicButton
@onready var debug_warning_label: Label = $VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/DebugWarningLabel

@onready var density_panel: PanelContainer = $VBoxContainer/DensityPanel
@onready var density_header_label: Label = $VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/DensityHeaderLabel
@onready var few_button: Button = $VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/FewButton
@onready var medium_button: Button = $VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/MediumButton
@onready var many_button: Button = $VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/ManyButton

@onready var population_size_panel: PanelContainer = $VBoxContainer/PopulationSizePanel
@onready var population_size_header_label: Label = $VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/PopulationSizeHeaderLabel
@onready var sparse_button: Button = $VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/SparseButton
@onready var normal_button: Button = $VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/NormalButton
@onready var dense_button: Button = $VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/DenseButton

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var back_button: Button = $VBoxContainer/BackButton

# Rispecchiano SEMPRE il bottone attualmente premuto nel rispettivo ButtonGroup — aggiornati solo
# dai tre handler _on_*_toggled, mai letti/scritti altrove. Inizializzati per coincidere coi
# default reali di GameSettings (selected_world_age_mode="CLASSIC", selected_animal_density=
# "MEDIUM", selected_population_size="NORMAL") anche nell'istante prima che _ready() giri.
var _selected_world_age_mode: String = "CLASSIC"
var _selected_animal_density: String = "MEDIUM"
var _selected_population_size: String = "NORMAL"


func _ready() -> void:
	title_label.text = tr("new_game_options_title")
	world_age_header_label.text = tr("world_age_label")
	young_button.text = tr("world_age_young")
	adult_button.text = tr("world_age_adult")
	old_button.text = tr("world_age_old")
	classic_button.text = tr("world_age_classic_debug")
	start_button.text = tr("start_game")
	back_button.text = tr("back")

	debug_warning_label.text = tr("world_age_classic_warning")
	debug_warning_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))

	density_header_label.text = tr("animal_density_label")
	few_button.text = tr("animal_density_few")
	medium_button.text = tr("animal_density_medium")
	many_button.text = tr("animal_density_many")

	population_size_header_label.text = tr("population_size_label")
	sparse_button.text = tr("population_size_sparse")
	normal_button.text = tr("population_size_normal")
	dense_button.text = tr("population_size_dense")

	# "Classic (debug)" preselezionato: DEVE corrispondere al default reale di
	# GameSettings.selected_world_age_mode ("CLASSIC") — se l'utente preme "Avvia partita" senza
	# toccare nulla, deve ottenere esattamente cio' che vede selezionato. Stesso principio per
	# "Medi" <-> selected_animal_density ("MEDIUM") e "Normale" <-> selected_population_size
	# ("NORMAL").
	classic_button.button_pressed = true
	_on_age_button_toggled(true, "CLASSIC")
	medium_button.button_pressed = true
	_on_density_button_toggled(true, "MEDIUM")
	normal_button.button_pressed = true
	_on_population_size_button_toggled(true, "NORMAL")

	young_button.toggled.connect(_on_age_button_toggled.bind("YOUNG"))
	adult_button.toggled.connect(_on_age_button_toggled.bind("ADULT"))
	old_button.toggled.connect(_on_age_button_toggled.bind("OLD"))
	classic_button.toggled.connect(_on_age_button_toggled.bind("CLASSIC"))

	few_button.toggled.connect(_on_density_button_toggled.bind("FEW"))
	medium_button.toggled.connect(_on_density_button_toggled.bind("MEDIUM"))
	many_button.toggled.connect(_on_density_button_toggled.bind("MANY"))

	sparse_button.toggled.connect(_on_population_size_button_toggled.bind("SPARSE"))
	normal_button.toggled.connect(_on_population_size_button_toggled.bind("NORMAL"))
	dense_button.toggled.connect(_on_population_size_button_toggled.bind("DENSE"))

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)


# Il ButtonGroup garantisce che solo un bottone alla volta sia premuto: ad ogni cambio, Godot
# emette toggled(false) sul precedente e toggled(true) sul nuovo — agiamo solo su quest'ultimo,
# ignorando la false per non processare due volte lo stesso cambio di selezione.
func _on_age_button_toggled(pressed: bool, mode: String) -> void:
	if not pressed:
		return
	_selected_world_age_mode = mode
	debug_warning_label.visible = mode == "CLASSIC"
	_update_dependent_panels_enabled()


func _on_density_button_toggled(pressed: bool, density: String) -> void:
	if not pressed:
		return
	_selected_animal_density = density


func _on_population_size_button_toggled(pressed: bool, population_size: String) -> void:
	if not pressed:
		return
	_selected_population_size = population_size


# Atenua/disabilita i gruppi "Densita' animali"/"Numerosita' popolazioni" quando "Classic
# (debug)" e' selezionato — entrambe le scelte sarebbero comunque ignorate da GameScene, questo
# e' solo un segnale visivo per non far credere che stiano avendo effetto.
func _update_dependent_panels_enabled() -> void:
	var is_classic := _selected_world_age_mode == "CLASSIC"
	var alpha := DISABLED_PANEL_ALPHA if is_classic else 1.0

	density_panel.modulate.a = alpha
	few_button.disabled = is_classic
	medium_button.disabled = is_classic
	many_button.disabled = is_classic

	population_size_panel.modulate.a = alpha
	sparse_button.disabled = is_classic
	normal_button.disabled = is_classic
	dense_button.disabled = is_classic


func _on_start_pressed() -> void:
	GameSettings.selected_world_age_mode = _selected_world_age_mode
	GameSettings.selected_animal_density = _selected_animal_density
	GameSettings.selected_population_size = _selected_population_size
	get_tree().change_scene_to_file("res://simulation/scenes/game/GameScene.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://simulation/scenes/menus/NewGameMenu.tscn")
