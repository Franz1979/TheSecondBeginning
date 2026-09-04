extends Control

# Schermata intermedia inserita nel flusso di creazione nuova partita, dopo la scelta di mappa/
# scenario (NewGameMenu) e prima dell'avvio effettivo (WorldScene): raccoglie la scelta dell'eta'
# del mondo, la densita' di semina automatica degli animali, la numerosita' di ciascuna
# popolazione, se escludere le zone ostili e/o i territori dei predatori, la fascia di ricchezza
# (povera/normale/ricca) dalla scelta della macrocella di partenza del player (vedi
# FirstStartMacroCellSelectionService/CellRichnessCalculator), e con quanti individui il player
# sceglie di iniziare (nessun effetto pratico finche' il modulo player non esiste — vedi
# GameData.starting_group_size_preference — oggi alimenta solo la difficolta'). NewGameMenu ha
# gia' impostato selected_map_type/selected_map_file prima di arrivare qui — questa scena non li
# tocca, si limita ad aggiungere GameSettings.selected_world_age_mode/selected_animal_density/
# selected_population_size/selected_exclude_hostile_start/
# selected_exclude_predator_territories/selected_resource_richness_preference/
# selected_group_size_preference e a inoltrare verso WorldScene.
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
# WorldScene.tscn (Speed1x/2x/3x/4xButton + ButtonGroup_speed).
#
# I gruppi "Densita' animali"/"Numerosita' popolazioni" restano visibili anche con "Classic
# (debug)" selezionato (nessuna complicazione di layout condizionale), ma diventano
# atenuati/disabilitati in quel caso — entrambe le scelte sono comunque ignorate da
# WorldScene._populate_new_world quando selected_world_age_mode == "CLASSIC" (nessuna semina
# automatica di animali), l'attenuazione visiva serve solo a non suggerire un effetto che in
# quel momento non avrebbero.

const DISABLED_PANEL_ALPHA := 0.4

@onready var title_label: Label = $RootColumn/TitleLabel
@onready var world_age_header_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/WorldAgeHeaderLabel
@onready var young_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/YoungButton
@onready var adult_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/AdultButton
@onready var old_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/OldButton
@onready var classic_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/ClassicButton
@onready var debug_warning_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/OptionsPanel/MarginContainer/VBoxContainer/DebugWarningLabel

@onready var density_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/DensityPanel
@onready var density_header_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/DensityHeaderLabel
@onready var few_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/FewButton
@onready var medium_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/MediumButton
@onready var many_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/DensityPanel/MarginContainer/VBoxContainer/ManyButton

@onready var population_size_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PopulationSizePanel
@onready var population_size_header_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/PopulationSizeHeaderLabel
@onready var sparse_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/SparseButton
@onready var normal_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/NormalButton
@onready var dense_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PopulationSizePanel/MarginContainer/VBoxContainer/DenseButton

@onready var hostile_start_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/HostileStartPanel
@onready var hostile_start_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/HostileStartPanel/MarginContainer/HBoxContainer/HostileStartLabel
@onready var hostile_start_check_button: CheckButton = $RootColumn/MainRow/ScrollContainer/VBoxContainer/HostileStartPanel/MarginContainer/HBoxContainer/HostileStartCheckButton

@onready var predator_exclusion_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PredatorExclusionPanel
@onready var predator_exclusion_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PredatorExclusionPanel/MarginContainer/HBoxContainer/PredatorExclusionLabel
@onready var predator_exclusion_check_button: CheckButton = $RootColumn/MainRow/ScrollContainer/VBoxContainer/PredatorExclusionPanel/MarginContainer/HBoxContainer/PredatorExclusionCheckButton

@onready var animal_presence_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/AnimalPresencePanel
@onready var animal_presence_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/AnimalPresencePanel/MarginContainer/HBoxContainer/AnimalPresenceLabel
@onready var animal_presence_check_button: CheckButton = $RootColumn/MainRow/ScrollContainer/VBoxContainer/AnimalPresencePanel/MarginContainer/HBoxContainer/AnimalPresenceCheckButton

@onready var resource_richness_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/ResourceRichnessPanel
@onready var resource_richness_header_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/ResourceRichnessPanel/MarginContainer/VBoxContainer/ResourceRichnessHeaderLabel
@onready var rich_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/ResourceRichnessPanel/MarginContainer/VBoxContainer/RichButton
@onready var normal_richness_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/ResourceRichnessPanel/MarginContainer/VBoxContainer/NormalRichnessButton
@onready var poor_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/ResourceRichnessPanel/MarginContainer/VBoxContainer/PoorButton

@onready var group_size_panel: PanelContainer = $RootColumn/MainRow/ScrollContainer/VBoxContainer/GroupSizePanel
@onready var group_size_header_label: Label = $RootColumn/MainRow/ScrollContainer/VBoxContainer/GroupSizePanel/MarginContainer/VBoxContainer/GroupSizeHeaderLabel
@onready var couple_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/GroupSizePanel/MarginContainer/VBoxContainer/CoupleButton
@onready var family_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/GroupSizePanel/MarginContainer/VBoxContainer/FamilyButton
@onready var group_button: Button = $RootColumn/MainRow/ScrollContainer/VBoxContainer/GroupSizePanel/MarginContainer/VBoxContainer/GroupButton

@onready var thermometer_panel: PanelContainer = $RootColumn/MainRow/ThermometerPanel
@onready var difficulty_header_label: Label = $RootColumn/MainRow/ThermometerPanel/MarginContainer/VBoxContainer/DifficultyHeaderLabel
@onready var difficulty_bar: ProgressBar = $RootColumn/MainRow/ThermometerPanel/MarginContainer/VBoxContainer/DifficultyBar
@onready var difficulty_percent_label: Label = $RootColumn/MainRow/ThermometerPanel/MarginContainer/VBoxContainer/DifficultyPercentLabel

@onready var start_button: Button = $RootColumn/MainRow/ThermometerPanel/MarginContainer/VBoxContainer/StartButton
@onready var back_button: Button = $RootColumn/MainRow/ThermometerPanel/MarginContainer/VBoxContainer/BackButton

# Verde (facile) -> giallo -> arancione -> rosso (difficile), su tutto il range NOMINALE 0-100%
# — anche se con i moltiplicatori attuali (DifficultyRules) il minimo raggiungibile e' ~50%, la
# mappatura resta valida quando in futuro nuovi parametri/valori porteranno il minimo reale piu'
# in basso: nessun ricalcolo di questa tabella necessario in quel momento (stesso principio del
# "niente rescaling" gia' deciso per la percentuale stessa).
# Tinta applicata via self_modulate quando un toggle booleano (zone ostili / territori predatori)
# e' attivo — self_modulate invece di uno StyleBoxFlat perche' CheckButton disegna il suo switch
# on/off da icone di tema, non da uno stylebox: tingere l'intero controllo e' il modo piu'
# semplice per colorarlo senza fornire texture custom. Color(1,1,1,1) (nessuna tinta) quando
# spento lascia il grigio di default del tema — esattamente l'aspetto "com'e' adesso" richiesto
# per lo stato non attivo. Condivisa da entrambi i toggle, stesso significato "attivo" per tutti e
# due.
const TOGGLE_ON_COLOR := Color(0.2, 0.75, 0.3, 1)
const TOGGLE_OFF_COLOR := Color(1, 1, 1, 1)

const DIFFICULTY_COLOR_STOPS: Array[Color] = [
	Color(0.20, 0.75, 0.30), # 0%: verde
	Color(0.90, 0.85, 0.15), # ~33%: giallo
	Color(0.95, 0.55, 0.10), # ~66%: arancione
	Color(0.85, 0.15, 0.15), # 100%: rosso
]

# Rispecchiano SEMPRE il bottone attualmente premuto nel rispettivo ButtonGroup — aggiornati solo
# dai tre handler _on_*_toggled, mai letti/scritti altrove. Inizializzati per coincidere coi
# default reali di GameSettings (selected_world_age_mode="CLASSIC", selected_animal_density=
# "MEDIUM", selected_population_size="NORMAL") anche nell'istante prima che _ready() giri.
var _selected_world_age_mode: String = "CLASSIC"
var _selected_animal_density: String = "MEDIUM"
var _selected_population_size: String = "NORMAL"
var _selected_exclude_hostile_start: bool = false
var _selected_exclude_predator_territories: bool = false
var _selected_resource_richness_preference: String = "NORMAL"
var _selected_group_size_preference: String = "GROUP"
var _selected_guarantee_animal_presence: bool = false


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

	hostile_start_label.text = tr("hostile_start_label")
	hostile_start_check_button.button_pressed = false
	_update_toggle_color(hostile_start_check_button, false)

	predator_exclusion_label.text = tr("predator_exclusion_label")
	predator_exclusion_check_button.button_pressed = false
	_update_toggle_color(predator_exclusion_check_button, false)

	animal_presence_label.text = tr("animal_presence_label")
	animal_presence_check_button.button_pressed = false
	_update_toggle_color(animal_presence_check_button, false)

	resource_richness_header_label.text = tr("resource_richness_label")
	rich_button.text = tr("resource_richness_rich")
	normal_richness_button.text = tr("resource_richness_normal")
	poor_button.text = tr("resource_richness_poor")

	group_size_header_label.text = tr("group_size_label")
	couple_button.text = tr("group_size_couple")
	family_button.text = tr("group_size_family")
	group_button.text = tr("group_size_group")

	difficulty_header_label.text = tr("difficulty_label")
	difficulty_bar.min_value = 0.0
	difficulty_bar.max_value = 100.0

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
	normal_richness_button.button_pressed = true
	_on_resource_richness_button_toggled(true, "NORMAL")
	group_button.button_pressed = true
	_on_group_size_button_toggled(true, "GROUP")

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

	hostile_start_check_button.toggled.connect(_on_hostile_start_toggled)
	predator_exclusion_check_button.toggled.connect(_on_predator_exclusion_toggled)
	animal_presence_check_button.toggled.connect(_on_animal_presence_toggled)

	rich_button.toggled.connect(_on_resource_richness_button_toggled.bind("RICH"))
	normal_richness_button.toggled.connect(_on_resource_richness_button_toggled.bind("NORMAL"))
	poor_button.toggled.connect(_on_resource_richness_button_toggled.bind("POOR"))

	couple_button.toggled.connect(_on_group_size_button_toggled.bind("COUPLE"))
	family_button.toggled.connect(_on_group_size_button_toggled.bind("FAMILY"))
	group_button.toggled.connect(_on_group_size_button_toggled.bind("GROUP"))

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
	_update_difficulty_display()


func _on_density_button_toggled(pressed: bool, density: String) -> void:
	if not pressed:
		return
	_selected_animal_density = density
	_update_difficulty_display()


func _on_population_size_button_toggled(pressed: bool, population_size: String) -> void:
	if not pressed:
		return
	_selected_population_size = population_size
	_update_difficulty_display()


func _on_resource_richness_button_toggled(pressed: bool, preference: String) -> void:
	if not pressed:
		return
	_selected_resource_richness_preference = preference
	_update_difficulty_display()


func _on_group_size_button_toggled(pressed: bool, preference: String) -> void:
	if not pressed:
		return
	_selected_group_size_preference = preference
	_update_difficulty_display()


func _on_hostile_start_toggled(pressed: bool) -> void:
	_selected_exclude_hostile_start = pressed
	_update_toggle_color(hostile_start_check_button, pressed)
	_update_difficulty_display()


func _on_predator_exclusion_toggled(pressed: bool) -> void:
	_selected_exclude_predator_territories = pressed
	_update_toggle_color(predator_exclusion_check_button, pressed)
	_update_difficulty_display()


func _on_animal_presence_toggled(pressed: bool) -> void:
	_selected_guarantee_animal_presence = pressed
	_update_toggle_color(animal_presence_check_button, pressed)
	_update_difficulty_display()


func _update_toggle_color(check_button: CheckButton, pressed: bool) -> void:
	check_button.self_modulate = TOGGLE_ON_COLOR if pressed else TOGGLE_OFF_COLOR


# Atenua/disabilita i gruppi "Densita' animali"/"Numerosita' popolazioni"/"Escludi partenza in
# zone ostili"/"Escludi partenza vicino ai predatori"/"Ricchezza cella di partenza"/"Numerosita'
# gruppo di partenza" quando "Classic (debug)" e' selezionato — tutte e sei le scelte sarebbero
# comunque ignorate da WorldScene, questo e' solo un segnale visivo per non far credere che
# stiano avendo effetto. La barra di difficolta' segue lo stesso trattamento (vedi
# _update_difficulty_display, che gestisce anche il testo "N/D" per quel caso) — dimmata qui
# insieme alle altre per coerenza visiva.
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

	hostile_start_panel.modulate.a = alpha
	hostile_start_check_button.disabled = is_classic

	predator_exclusion_panel.modulate.a = alpha
	predator_exclusion_check_button.disabled = is_classic

	animal_presence_panel.modulate.a = alpha
	animal_presence_check_button.disabled = is_classic

	resource_richness_panel.modulate.a = alpha
	rich_button.disabled = is_classic
	normal_richness_button.disabled = is_classic
	poor_button.disabled = is_classic

	group_size_panel.modulate.a = alpha
	couple_button.disabled = is_classic
	family_button.disabled = is_classic
	group_button.disabled = is_classic

	thermometer_panel.modulate.a = alpha


# Ricalcola e mostra la difficolta' per la combinazione attualmente selezionata — chiamata da
# tutti e sette gli handler di toggle (eta'/densita'/numerosita'/zone ostili/predatori/ricchezza/
# gruppo di partenza), mai una volta sola: qualunque cambio a uno qualunque dei sette gruppi puo'
# cambiare il risultato. "Classic (debug)" non ha una difficolta' applicabile (DifficultyCalculator.
# compute_difficulty_ratio ritorna -1.0 in quel caso, gli altri sei parametri sono comunque
# ignorati da WorldScene) — barra a 0, testo "N/D" invece di una percentuale falsa. Arrotondamento
# all'unita' percentuale SOLO qui, in visualizzazione: il valore salvato in GameData/nel file di
# partita resta sempre il prodotto grezzo non arrotondato (vedi DifficultyCalculator/GameData).
func _update_difficulty_display() -> void:
	var ratio := DifficultyCalculator.compute_difficulty_ratio(
		_selected_world_age_mode,
		_selected_animal_density,
		_selected_population_size,
		_selected_exclude_hostile_start,
		_selected_exclude_predator_territories,
		_selected_resource_richness_preference,
		_selected_group_size_preference,
		_selected_guarantee_animal_presence
	)

	if ratio < 0.0:
		difficulty_bar.value = 0.0
		difficulty_bar.add_theme_stylebox_override("fill", _build_difficulty_fill_stylebox(0.0))
		difficulty_percent_label.text = tr("difficulty_not_applicable")
		return

	var percent: float = ratio * 100.0
	difficulty_bar.value = percent
	difficulty_bar.add_theme_stylebox_override("fill", _build_difficulty_fill_stylebox(percent))
	difficulty_percent_label.text = "%d%%" % int(round(percent))


func _build_difficulty_fill_stylebox(percent: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _get_difficulty_color(percent)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


# Interpola lungo DIFFICULTY_COLOR_STOPS (verde->giallo->arancione->rosso) in base a percent/100,
# a 3 segmenti uguali — stesso principio di un gradiente a piu' tappe, nessuna libreria esterna
# necessaria per 4 sole tappe fisse.
func _get_difficulty_color(percent: float) -> Color:
	var t: float = clamp(percent / 100.0, 0.0, 1.0)
	var segment_count := DIFFICULTY_COLOR_STOPS.size() - 1
	var segment_t := t * segment_count
	var segment_index: int = clamp(int(floor(segment_t)), 0, segment_count - 1)
	var local_t: float = segment_t - segment_index
	return DIFFICULTY_COLOR_STOPS[segment_index].lerp(DIFFICULTY_COLOR_STOPS[segment_index + 1], local_t)


func _on_start_pressed() -> void:
	GameSettings.selected_world_age_mode = _selected_world_age_mode
	GameSettings.selected_animal_density = _selected_animal_density
	GameSettings.selected_population_size = _selected_population_size
	GameSettings.selected_exclude_hostile_start = _selected_exclude_hostile_start
	GameSettings.selected_exclude_predator_territories = _selected_exclude_predator_territories
	GameSettings.selected_resource_richness_preference = _selected_resource_richness_preference
	GameSettings.selected_group_size_preference = _selected_group_size_preference
	GameSettings.selected_guarantee_animal_presence = _selected_guarantee_animal_presence
	get_tree().change_scene_to_file("res://simulation/scenes/game/WorldScene.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://simulation/scenes/menus/NewGameMenu.tscn")
