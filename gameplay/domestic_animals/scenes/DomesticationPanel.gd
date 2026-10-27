class_name DomesticationPanel
extends CanvasLayer

# Pannello delle Addomesticazioni (addomesticazione passo 3b, 2026-10-26, richiesta utente): overlay a tutto schermo
# come TechTreePanel, con due schede (Animali, Piante). Nessuno stato proprio: ad ogni refresh_content() rilegge
# GameData (punti, specie addomesticate e incontrate) e Folk (idee). Le addomesticazioni avanzano con le azioni, non con
# i pensieri: qui si guarda soltanto (salvo il "+100" di debug).
#
# Pausa della simulazione: come TechTreePanel, GameScene collega visibility_changed a
# _on_blocking_dialog_visibility_changed. Root/Background fermano i click verso la mappa, _input assorbe la tastiera.

# "+100" di debug su una specie: GameScene aggiunge i punti con i propri GameEffects (eventuale scoperta) e
# richiama refresh_content.
signal debug_add_points_requested(species: String)

enum CardState { DOMESTICATED, IN_PROGRESS, LOCKED }

const ANIMALS_TAB := 0
const PLANTS_TAB := 1
const CARD_SIZE := Vector2(260, 150)
const DEBUG_POINTS := 100
# Stessi colori degli stati di TechTreePanel (completata/disponibile/bloccata).
const STATE_BG_COLORS := {
	CardState.DOMESTICATED: Color(0.14, 0.32, 0.18),
	CardState.IN_PROGRESS: Color(0.14, 0.24, 0.38),
	CardState.LOCKED: Color(0.16, 0.16, 0.18),
}
const STATE_BORDER_COLORS := {
	CardState.DOMESTICATED: Color(0.40, 0.80, 0.46),
	CardState.IN_PROGRESS: Color(0.45, 0.68, 0.95),
	CardState.LOCKED: Color(0.40, 0.40, 0.44),
}

@onready var title_label: Label = $Root/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $Root/MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var tab_container: TabContainer = $Root/MarginContainer/VBoxContainer/TabContainer
@onready var animals_box: VBoxContainer = $Root/MarginContainer/VBoxContainer/TabContainer/AnimalsScroll/AnimalsBox
@onready var plants_box: VBoxContainer = $Root/MarginContainer/VBoxContainer/TabContainer/PlantsScroll/PlantsBox

var _human_folk: Folk
var _game_data: GameData


func _ready() -> void:
	title_label.text = tr("domestication_panel_title")
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	tab_container.set_tab_title(ANIMALS_TAB, tr("domestication_tab_animals"))
	tab_container.set_tab_title(PLANTS_TAB, tr("domestication_tab_plants"))


func open_dialog(human_folk: Folk, game_data: GameData) -> void:
	_human_folk = human_folk
	_game_data = game_data
	refresh_content()
	show()


func refresh_content() -> void:
	if _human_folk == null or _game_data == null:
		return
	_clear(animals_box)
	_clear(plants_box)
	_fill_animals()
	_fill_plants()


func _clear(box: Container) -> void:
	# remove_child + queue_free: i vecchi riquadri spariscono subito (stesso motivo di TechTreePanel.refresh_content).
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _fill_animals() -> void:
	if not _human_folk.completed_ideas.has("animal_domestication"):
		animals_box.add_child(_notice_label(tr("domestication_animals_locked_notice").format({
			"idea": _idea_name("animal_domestication")
		})))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	animals_box.add_child(cards)
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules == null:
			continue
		# Il cane (nessuna idea richiesta) sempre; le altre solo se la selvatica è stata incontrata: le specie mai viste
		# non si rivelano.
		if rules.required_idea_id != "" and not DomesticationEncounterService.is_encountered(_game_data, rules.wild_species_name):
			continue
		cards.add_child(_build_card(rules))


func _fill_plants() -> void:
	# Specie vegetali: arriveranno con l'agricoltura.
	if not _human_folk.completed_ideas.has("plant_domestication"):
		plants_box.add_child(_notice_label(tr("domestication_plants_locked_notice").format({
			"idea": _idea_name("plant_domestication")
		})))
	else:
		plants_box.add_child(_notice_label(tr("domestication_plants_empty")))


func _state_of(rules: DomesticAnimalRules) -> CardState:
	if _game_data.domesticated_species.has(rules.species_name):
		return CardState.DOMESTICATED
	if rules.required_idea_id != "" and not _human_folk.completed_ideas.has(rules.required_idea_id):
		return CardState.LOCKED
	return CardState.IN_PROGRESS


func _build_card(rules: DomesticAnimalRules) -> PanelContainer:
	var state := _state_of(rules)
	var style := StyleBoxFlat.new()
	style.bg_color = STATE_BG_COLORS[state]
	style.border_color = STATE_BORDER_COLORS[state]
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	card.add_child(box)

	var name_label := Label.new()
	name_label.text = tr(rules.display_name)
	name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(name_label)

	var origin_label := Label.new()
	origin_label.text = tr("domestication_from").format({"species": tr("animal_species_" + rules.wild_species_name)})
	origin_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	box.add_child(origin_label)

	var points := DomesticationPointsService.get_points(_game_data, rules.species_name)
	var bar := ProgressBar.new()
	bar.max_value = maxi(rules.domestication_points_required, 1)
	bar.value = mini(points, rules.domestication_points_required)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(bar)

	var points_label := Label.new()
	points_label.text = "%d / %d" % [points, rules.domestication_points_required]
	box.add_child(points_label)

	var state_label := Label.new()
	state_label.add_theme_color_override("font_color", STATE_BORDER_COLORS[state])
	match state:
		CardState.DOMESTICATED:
			state_label.text = tr("domestication_state_domesticated")
		CardState.IN_PROGRESS:
			state_label.text = tr("domestication_state_in_progress")
		CardState.LOCKED:
			state_label.text = tr("domestication_state_locked").format({"idea": _idea_name(rules.required_idea_id)})
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(state_label)

	# Debug, come il "+pensieri" di TechTreePanel: mai visibile in una build pulita.
	if DebugLogging.ENABLED:
		var debug_button := Button.new()
		debug_button.text = "+%d" % DEBUG_POINTS
		debug_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		debug_button.pressed.connect(func() -> void: debug_add_points_requested.emit(rules.species_name))
		box.add_child(debug_button)
	return card


func _notice_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.25))
	return label


func _idea_name(idea_id: String) -> String:
	var idea := IdeaCalculator.get_idea(idea_id)
	return tr(idea.display_name) if idea != null else idea_id


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not visible or key_event == null:
		return
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		hide()
	get_viewport().set_input_as_handled()
