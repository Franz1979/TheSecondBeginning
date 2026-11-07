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
# "+1" di debug su una specie con animali veri (cane passo 1): GameScene crea l'animale e aggiorna la scheda 🦌.
signal debug_add_animal_requested(species: String)

enum CardState { DOMESTICATED, IN_PROGRESS }

const ANIMALS_TAB := 0
const PLANTS_TAB := 1
# Idea «Addomesticazione» (solo da scoperta, al primo lupo addomesticato): sblocca il pannello intero.
const DOMESTICATION_IDEA_ID := "domestication"
const CARD_SIZE := Vector2(260, 150)
const DEBUG_POINTS := 100
# Stessi colori degli stati di TechTreePanel (completata/disponibile/bloccata).
const STATE_BG_COLORS := {
	CardState.DOMESTICATED: Color(0.14, 0.32, 0.18),
	CardState.IN_PROGRESS: Color(0.14, 0.24, 0.38),
}
const STATE_BORDER_COLORS := {
	CardState.DOMESTICATED: Color(0.40, 0.80, 0.46),
	CardState.IN_PROGRESS: Color(0.45, 0.68, 0.95),
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
	# Prima dell'idea solo la carta del primo animale (vedi is_available): niente piante.
	tab_container.set_tab_hidden(PLANTS_TAB, not _has_full_access())
	if not _has_full_access():
		tab_container.current_tab = ANIMALS_TAB


# Pulsante 🐾 (2026-11-07, decisione utente, strada A): con l'idea «Addomesticazione» il pannello intero; prima, solo la
# carta della prima addomesticazione (specie senza idea richiesta, il cane), dalla prima visita del suo branco selvatico
# o dal primo punto: così il giocatore vede a che punto è. Letta da GameScene._refresh_domestication_button.
static func is_available(human_folk: Folk, game_data: GameData) -> bool:
	if human_folk == null or game_data == null:
		return false
	if human_folk.completed_ideas.has(DOMESTICATION_IDEA_ID):
		return true
	for species in DomesticAnimalCalculator.list_species_for_display():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules == null or rules.required_idea_id != "":
			continue
		if DomesticationPointsService.get_points(game_data, species) > 0:
			return true
		var group := WildAnimalGroupService.find_group(game_data, rules.wild_species_name)
		if group != null and group.notified_first_visit:
			return true
	return false


func _has_full_access() -> bool:
	return _human_folk.completed_ideas.has(DOMESTICATION_IDEA_ID)


func _clear(box: Container) -> void:
	# remove_child + queue_free: i vecchi riquadri spariscono subito (stesso motivo di TechTreePanel.refresh_content).
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _fill_animals() -> void:
	if _has_full_access() and not _human_folk.completed_ideas.has("animal_domestication"):
		animals_box.add_child(_notice_label(tr("domestication_animals_locked_notice").format({
			"idea": _idea_name("animal_domestication")
		})))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	animals_box.add_child(cards)
	for species in DomesticAnimalCalculator.list_species_for_display():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules == null:
			continue
		# Il cane (nessuna idea richiesta) sempre; le altre solo con l'idea nota e la selvatica incontrata: prima non si
		# rivelano (2026-11-03, richiesta utente).
		if rules.required_idea_id != "" and (not _human_folk.completed_ideas.has(rules.required_idea_id)
				or not DomesticationEncounterService.is_encountered(_game_data, rules.wild_species_name)):
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

	# Carta in due tempi (2026-11-07, richiesta utente, uguale per tutte le specie): finché è in corso racconta la specie
	# selvatica (branco, aggressività, punti, cosa ne deriverà); addomesticata, solo la specie domestica e l'anno.
	if state == CardState.DOMESTICATED:
		_add_domesticated_rows(box, rules)
	else:
		_add_in_progress_rows(box, rules)

	# Debug, come il "+pensieri" di TechTreePanel: mai visibile in una build pulita.
	if DebugLogging.ENABLED:
		var debug_button := Button.new()
		debug_button.text = "+%d" % DEBUG_POINTS
		debug_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		debug_button.pressed.connect(func() -> void: debug_add_points_requested.emit(rules.species_name))
		box.add_child(debug_button)
		if rules.individuals_enabled:
			var add_animal_button := Button.new()
			add_animal_button.text = "+1 %s" % tr(rules.display_name)
			add_animal_button.size_flags_horizontal = Control.SIZE_SHRINK_END
			add_animal_button.pressed.connect(func() -> void: debug_add_animal_requested.emit(rules.species_name))
			box.add_child(add_animal_button)
	return card


func _add_domesticated_rows(box: VBoxContainer, rules: DomesticAnimalRules) -> void:
	box.add_child(_title_label(tr(rules.display_name)))
	var wild_name := tr("animal_species_" + rules.wild_species_name)
	var done_label := Label.new()
	if _game_data.domestication_years.has(rules.species_name):
		done_label.text = _species_text("domestication_done", rules).format({
			"species": wild_name, "year": int(_game_data.domestication_years[rules.species_name])})
	else:
		done_label.text = _species_text("domestication_done_no_year", rules).format({"species": wild_name})
	done_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	done_label.add_theme_color_override("font_color", STATE_BORDER_COLORS[CardState.DOMESTICATED])
	box.add_child(done_label)


# In corso: titolo del branco selvatico, quanti animali e aggressività media come barra senza numero (stessa regola del
# pannello del singolo animale; branco assente o vuoto: una riga sola), punti verso la soglia, cosa ne deriverà e una
# riga che spiega cosa fa salire e scendere l'aggressività.
func _add_in_progress_rows(box: VBoxContainer, rules: DomesticAnimalRules) -> void:
	box.add_child(_title_label(_species_text("domestication_wild_group", rules).format({
		"species": tr("animal_species_" + rules.wild_species_name)})))
	var group := WildAnimalGroupService.find_group(_game_data, rules.wild_species_name)
	if group == null or group.animals.is_empty():
		box.add_child(_plain_label(tr("domestication_pack_none")))
	else:
		var total := 0.0
		for animal in group.animals:
			total += animal.aggression
		box.add_child(_plain_label(tr("domestication_pack_count").format({"count": group.animals.size()})))
		box.add_child(_plain_label(tr("domestication_pack_aggression")))
		box.add_child(_bar(100, total / float(group.animals.size())))

	var points := DomesticationPointsService.get_points(_game_data, rules.species_name)
	var progress_label := _plain_label(tr("domestication_state_in_progress"))
	progress_label.add_theme_color_override("font_color", STATE_BORDER_COLORS[CardState.IN_PROGRESS])
	box.add_child(progress_label)
	box.add_child(_bar(rules.domestication_points_required, points))
	box.add_child(_plain_label("%d / %d" % [points, rules.domestication_points_required]))
	box.add_child(_plain_label(tr("domestication_will_become").format({"species": tr(rules.display_name)})))

	var hint_label := _plain_label(tr("domestication_pack_hint"))
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	box.add_child(hint_label)


# Testo per specie se c'è (es. domestication_done_dog, per il genere e il plurale giusti), altrimenti quello generico.
func _species_text(key: String, rules: DomesticAnimalRules) -> String:
	var specific_key := "%s_%s" % [key, rules.species_name]
	var specific := tr(specific_key)
	return specific if specific != specific_key else tr(key)


func _title_label(text: String) -> Label:
	var label := _plain_label(text)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _plain_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _bar(max_value: float, value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxf(max_value, 1.0)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	return bar


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
