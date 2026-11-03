class_name DomesticAnimalsPanel
extends VBoxContainer

# Corpo della scheda 🦌 di GameInfoTabs (2026-11-03, cane passo 1, richiesta utente): gli animali domestici del villaggio
# per specie. Un solo elenco finché il cane non ha un villaggio (passo 2). Ricostruito da GameScene quando la scheda è
# aperta (cambio scheda, giorno nuovo). Lo stato delle addomesticazioni resta in DomesticationPanel.

const FONT_SIZE := 12

var _game_data: GameData


func refresh(game_data: GameData) -> void:
	_game_data = game_data
	# remove_child + queue_free: i vecchi riquadri spariscono subito (come DomesticationPanel._clear).
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _game_data == null:
		return
	var has_animals := not _game_data.domestic_animals.is_empty()
	if not has_animals:
		add_child(_make_label(tr("domestic_animals_empty")))
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules != null and rules.individuals_enabled:
			_add_species(rules)


func _add_species(rules: DomesticAnimalRules) -> void:
	var animals := DomesticAnimalService.get_animals(_game_data, rules.species_name)
	if not animals.is_empty():
		var males := animals.filter(func(animal: DomesticAnimal) -> bool: return animal.is_male).size()
		add_child(_make_label("%s: %d  ♂ %d  ♀ %d" % [tr(rules.display_name), animals.size(), males, animals.size() - males]))
	var today := _game_data.get_absolute_day()
	for animal in animals:
		add_child(_make_label(tr("domestic_animal_row").format({
			"name": tr(rules.display_name), "id": animal.id,
			"sex": tr("domestic_animal_male" if animal.is_male else "domestic_animal_female"),
			"age": animal.get_age_years(today),
		})))


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	return label
