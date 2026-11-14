class_name DomesticAnimalsPanel
extends VBoxContainer

# Corpo della scheda 🦌 di GameInfoTabs (2026-11-03, cane passo 1, richiesta utente): gli animali domestici del villaggio
# per specie. Ricostruito da GameScene quando la scheda è aperta (cambio scheda, giorno nuovo). Lo stato delle
# addomesticazioni resta in DomesticationPanel.
#
# Sotto-schede (2026-11-14, richiesta utente — pezzo 2 delle soglie di macellazione): "Tutte" con una riga per specie
# (totale, in tettoia / liberi, ♂ ♀ e la soglia "Macella oltre") e una scheda per ogni specie con almeno un animale
# (tabella fasce d'età × sesso, soglia, tettoie con animali e capienza, elenco dei singoli). La soglia della specie
# (GameData.domestic_slaughter_above) si scrive subito; solo per le specie che stanno nelle tettoie e col gestore scorte.

const FONT_SIZE := 12
const AGE_BANDS: Array[int] = [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]
const AGE_KEYS := {
	GameTypes.AgeBand.YOUNG: "domestic_animals_age_young",
	GameTypes.AgeBand.ADULT: "domestic_animals_age_adult",
	GameTypes.AgeBand.OLD: "domestic_animals_age_old",
}

var _game_data: GameData
var _world: World
# Sotto-scheda aperta, ritrovata dopo ogni ricostruzione: "" = Tutte, altrimenti la specie.
var _selected_species: String = ""


func refresh(game_data: GameData, world: World) -> void:
	_game_data = game_data
	_world = world
	# remove_child + queue_free: i vecchi riquadri spariscono subito (come DomesticationPanel._clear).
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _game_data == null:
		return
	var species_list := _species_with_animals()
	if species_list.is_empty():
		add_child(_make_label(tr("domestic_animals_empty")))
		return
	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(tabs)
	var all_box := _make_page(tabs, tr("domestic_animals_tab_all"))
	for species in species_list:
		_add_summary_row(all_box, species)
	var selected_index := 0
	for species in species_list:
		_fill_species_page(_make_page(tabs, _species_name(species)), species)
		if species == _selected_species:
			selected_index = tabs.get_tab_count() - 1
	tabs.current_tab = selected_index
	tabs.tab_changed.connect(func(index: int) -> void:
		_selected_species = "" if index == 0 else species_list[index - 1]
	)


# Specie (nell'ordine dei dati) con almeno un animale, libero o in tettoia.
func _species_with_animals() -> Array[String]:
	var present: Dictionary = {}
	for animal in _game_data.domestic_animals:
		present[animal.species] = true
	var result: Array[String] = []
	for species in DomesticAnimalCalculator.list_species():
		if present.has(species):
			result.append(species)
	return result


func _make_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title.validate_node_name()
	page.add_theme_constant_override("separation", 2)
	tabs.add_child(page)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	return page


# Nome della specie: la selvatica d'origine finché non è addomesticata.
func _species_name(species: String) -> String:
	return KeptAnimalService.species_display_name(species, not DomesticAnimalService.is_domesticated(_game_data, species))


func _animals_of(species: String) -> Array[DomesticAnimal]:
	var result: Array[DomesticAnimal] = []
	for animal in _game_data.domestic_animals:
		if animal.species == species:
			result.append(animal)
	return result


func _add_summary_row(box: VBoxContainer, species: String) -> void:
	var animals := _animals_of(species)
	var kept := 0
	var males := 0
	for animal in animals:
		if animal.building_id >= 0:
			kept += 1
		if animal.is_male:
			males += 1
	box.add_child(_make_label(tr("domestic_animals_summary").format({
		"name": _species_name(species), "total": animals.size(), "kept": kept, "free": animals.size() - kept,
		"males": males, "females": animals.size() - males,
	})))
	_add_slaughter_row(box, species)


func _fill_species_page(box: VBoxContainer, species: String) -> void:
	var animals := _animals_of(species)
	var today := _game_data.get_absolute_day()
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	# Tabella fasce d'età × sesso.
	var counts: Dictionary = {}
	for animal in animals:
		var band := int(animal.get_age_band(today, wild_rules)) if wild_rules != null else int(GameTypes.AgeBand.ADULT)
		var key := "%d|%s" % [band, "m" if animal.is_male else "f"]
		counts[key] = int(counts.get(key, 0)) + 1
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	var cells: Array[String] = ["", "♂", "♀"]
	for band in AGE_BANDS:
		cells.append_array([tr(AGE_KEYS[band]), str(int(counts.get("%d|m" % band, 0))), str(int(counts.get("%d|f" % band, 0)))])
	for cell_text in cells:
		# Senza a capo: in una griglia un'etichetta che va a capo resta larga zero e si scrive in verticale.
		var cell_label := _make_label(cell_text)
		cell_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(cell_label)
	box.add_child(grid)
	_add_slaughter_row(box, species)
	# Tettoie della specie: animali / capienza, e i giorni prima della fuga se troppo piena.
	if _world != null:
		var shelters: Array[Building] = []
		for building in _world.buildings:
			if KeptAnimalService.capacity(building) > 0 and building.is_complete \
					and KeptAnimalService.current_species(_game_data, building) == species:
				shelters.append(building)
		if not shelters.is_empty():
			box.add_child(_make_label(tr("domestic_animals_shelters")))
			for building in shelters:
				var count := DomesticAnimalService.get_kept_animals(_game_data, building.id).size()
				var text := tr("domestic_animals_shelter_row").format({
					"building": building.get_display_name(), "count": count, "max": KeptAnimalService.capacity(building),
				})
				var days_left := KeptAnimalService.over_capacity_days_left(_game_data, building)
				var over := count > KeptAnimalService.capacity(building)
				if over and days_left >= 0:
					text += " · " + tr("building_kept_over_capacity").format({"days": days_left})
				var label := _make_label("  " + text)
				if over:
					label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
				box.add_child(label)
	# Elenco dei singoli.
	box.add_child(HSeparator.new())
	for animal in animals:
		var row := tr("domestic_animal_row").format({
			"name": KeptAnimalService.display_name(animal), "id": animal.id,
			"sex": tr("domestic_animal_male" if animal.is_male else "domestic_animal_female"),
			"age": animal.get_age_years(today),
		})
		if animal.building_id >= 0 and _world != null:
			var building := WarehouseManagerService.find_building(_world, animal.building_id)
			if building != null:
				row += " · " + building.get_display_name()
		box.add_child(_make_label(row))


# Soglia "Macella oltre" della specie: solo per chi sta nelle tettoie e col gestore scorte.
func _add_slaughter_row(box: VBoxContainer, species: String) -> void:
	var rules := DomesticAnimalCalculator.get_rules(species)
	if rules == null or not KeptAnimalService.can_be_kept(rules) or not FeederStockService.is_rule_available():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := _make_label(tr("domestic_animals_slaughter_above"))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = TooltipText.wrap(tr("domestic_animals_slaughter_above_tooltip"))
	row.add_child(label)
	var game_data := _game_data
	row.add_child(WarehousePanel.build_level_field(KeptAnimalService.species_slaughter_above(game_data, species),
		func(value: int) -> void: KeptAnimalService.set_species_slaughter_above(game_data, species, value)
	, "domestic_animals_slaughter_above_tooltip", 1, 0, true, "∞"))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_child(row)
	box.add_child(margin)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	return label
