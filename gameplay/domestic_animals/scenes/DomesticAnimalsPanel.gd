class_name DomesticAnimalsPanel
extends VBoxContainer

# Corpo della scheda 🦌 di GameInfoTabs (2026-11-03, cane passo 1, richiesta utente): gli animali domestici del villaggio
# per specie. Ricostruito da GameScene quando la scheda è aperta (cambio scheda, giorno nuovo). Lo stato delle
# addomesticazioni resta in DomesticationPanel.
#
# Sotto-schede (2026-11-14, richiesta utente — pezzo 2 delle soglie di macellazione): "Tutte" con una riga per specie
# (totale, in tettoia / liberi, ♂ ♀ e la soglia "Macella oltre") e una scheda per ogni specie con almeno un animale
# (tabella fasce d'età × sesso, soglia, tettoie con animali e capienza). La soglia della specie
# (GameData.domestic_slaughter_above) si scrive subito; solo per le specie che stanno nelle tettoie e col gestore scorte.
# Dal 2026-11-17 (richiesta utente): niente più elenco dei singoli (basta la tabella; i singoli stanno nel pannello del loro
# edificio) e, nella scheda della specie, i default dei suoi edifici che prima erano regole del gestore scorte: giorni di
# cibo nelle mangiatoie e di paglia nelle lettiere, ognuno solo se c'è un edificio finito della specie che lo usa. Una
# specie compare anche senza animali se ha un edificio suo (es. conigliera vuota), per poterne regolare i default.

const FONT_SIZE := 12
const AGE_BANDS: Array[int] = [GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD]
const AGE_KEYS := {
	GameTypes.AgeBand.YOUNG: "domestic_animals_age_young",
	GameTypes.AgeBand.ADULT: "domestic_animals_age_adult",
	GameTypes.AgeBand.OLD: "domestic_animals_age_old",
}

# Simbolo della specie nella linguetta (2026-11-17); senza simbolo, l'iniziale del nome.
const SPECIES_SYMBOLS := {
	"dog": "🐕",
	"domestic_rabbit": "🐇",
	"chicken": "🐔",
	"cattle": "🐄",
	"goat": "🐐",
	"horse": "🐎",
	"pig": "🐖",
	"sheep": "🐑",
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
	_retitle_tabs(tabs, species_list)
	tabs.tab_changed.connect(func(index: int) -> void:
		_selected_species = "" if index == 0 else species_list[index - 1]
		_retitle_tabs(tabs, species_list)
	)


# Linguette (2026-11-17, richiesta utente — i nomi non ci stavano): solo il simbolo della specie, anche per quella aperta
# (2026-11-18, richiesta utente): il nome sta in cima alla pagina (_fill_species_page). "Tutte" resta scritta.
func _retitle_tabs(tabs: TabContainer, species_list: Array[String]) -> void:
	for i in range(species_list.size()):
		var species := species_list[i]
		tabs.set_tab_title(i + 1, _species_symbol(species))
		tabs.set_tab_tooltip(i + 1, _species_name(species))


func _species_symbol(species: String) -> String:
	return String(SPECIES_SYMBOLS.get(species, _species_name(species).left(1)))


# Specie (in ordine alfabetico del nome mostrato) con almeno un animale, libero o in tettoia, o con un edificio finito che la tiene.
func _species_with_animals() -> Array[String]:
	var present: Dictionary = {}
	for animal in _game_data.domestic_animals:
		present[animal.species] = true
	if _world != null:
		for building in _world.buildings:
			if building != null and building.is_complete and not building.is_demolished and KeptAnimalService.capacity(building) > 0:
				var kept_species := KeptAnimalService.current_species(_game_data, building)
				if kept_species != "":
					present[kept_species] = true
	var result: Array[String] = []
	for species in DomesticAnimalCalculator.list_species():
		if present.has(species):
			result.append(species)
	# Ordine alfabetico del nome mostrato (2026-11-17, richiesta utente): Cane, Coniglio selvatico, Gallo selvatico.
	result.sort_custom(func(a: String, b: String) -> bool: return _species_name(a).naturalnocasecmp_to(_species_name(b)) < 0)
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
	# Due righe (2026-11-16, richiesta utente): nome e totali; sotto ♂ ♀ e, sulla stessa riga, "Macella oltre".
	box.add_child(_make_label(tr("domestic_animals_summary").format({
		"name": _species_name(species), "total": animals.size(), "kept": kept, "free": animals.size() - kept,
	})))
	_add_slaughter_row(box, species, tr("domestic_animals_sexes").format({"males": males, "females": animals.size() - males}))


func _fill_species_page(box: VBoxContainer, species: String) -> void:
	var animals := _animals_of(species)
	var today := _game_data.get_absolute_day()
	var wild_rules := DomesticAnimalCalculator.get_wild_rules(species)
	# Nome della specie in cima alla pagina (2026-11-18, richiesta utente): nella linguetta solo il simbolo.
	box.add_child(_make_label("%s %s" % [_species_symbol(species), _species_name(species)]))
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
	_add_building_defaults(box, species)
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


# Default degli edifici della specie (2026-11-17, richiesta utente — prima regole del gestore scorte): giorni di cibo nelle
# mangiatoie e di paglia nelle lettiere. Ogni riga solo col gestore scorte e con un edificio finito della specie che la usa
# (con la sola tettoia delle gabbie, niente paglia). Il singolo edificio può avere il suo valore (D/↺ nel suo pannello).
func _add_building_defaults(box: VBoxContainer, species: String) -> void:
	if _world == null or not FeederStockService.is_rule_available():
		return
	var with_feeder := false
	var with_bedding := false
	var manure_max := 0
	var with_live_products := false
	for building in _world.buildings:
		if building == null or building.is_demolished or not building.is_complete:
			continue
		if KeptAnimalService.current_species(_game_data, building) != species:
			continue
		if AnimalFeederService.has_feeder(building):
			with_feeder = true
		if BeddingService.has_bedding(building):
			with_bedding = true
		if ManureService.has_manure_store(building):
			manure_max = maxi(manure_max, ManureService.capacity(building))
		if LiveProductStockService.is_served(building):
			with_live_products = true
	if not with_feeder and not with_bedding and manure_max <= 0 and not with_live_products:
		return
	var game_data := _game_data
	box.add_child(_make_label(tr("domestic_animals_building_defaults")))
	if with_feeder:
		_add_days_row(box, "domestic_animals_feeder_days", FeederStockService.species_days(game_data, species),
			func(days: int) -> void: FeederStockService.set_species_days(game_data, species, days), WarehousePanel.FEEDER_DAYS_MAX)
	if with_bedding:
		_add_days_row(box, "domestic_animals_bedding_days", BeddingStockService.species_days(game_data, species),
			func(days: int) -> void: BeddingStockService.set_species_days(game_data, species, days), WarehousePanel.FEEDER_DAYS_MAX)
	# Pulizia del letame (2026-11-17, ManureStockService): percentuale della capienza di ogni edificio.
	if manure_max > 0:
		_add_days_row(box, "domestic_animals_manure_clean", ManureStockService.species_clean_above(game_data, species),
			func(value: int) -> void: ManureStockService.set_species_clean_above(game_data, species, value), 100, 5)
	# Raccolta dei prodotti da vivi (2026-11-17, LiveProductStockService): percentuale della capienza di ogni edificio.
	if with_live_products:
		_add_days_row(box, "domestic_animals_live_product_collect", LiveProductStockService.species_collect_above(game_data, species),
			func(value: int) -> void: LiveProductStockService.set_species_collect_above(game_data, species, value), 100, 5)


# "Giorni di …: [N]" col campo compatto (0 = nessun rifornimento o pulizia); `key` è la scritta, key + "_tooltip" il
# tooltip; `step` il passo di +/−.
func _add_days_row(box: VBoxContainer, key: String, value: int, on_change: Callable, max_value: int, step: int = 1) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := _make_label(tr(key))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = TooltipText.wrap(tr(key + "_tooltip"))
	row.add_child(label)
	row.add_child(WarehousePanel.build_level_field(value, on_change, key + "_tooltip", step, 0, true, WarehousePanel.LEVEL_NONE_TEXT,
		max_value))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_child(row)
	box.add_child(margin)


# Soglia "Macella oltre" della specie: solo per chi sta nelle tettoie e col gestore scorte. `lead_text` (es. "♂ 1  ♀ 0"),
# se c'è, apre la riga a sinistra; senza soglia la riga resta col solo `lead_text`.
func _add_slaughter_row(box: VBoxContainer, species: String, lead_text: String = "") -> void:
	var rules := DomesticAnimalCalculator.get_rules(species)
	var with_threshold := rules != null and KeptAnimalService.can_be_kept(rules) and FeederStockService.is_rule_available()
	if not with_threshold and lead_text == "":
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if lead_text != "":
		var lead := _make_label(lead_text)
		lead.autowrap_mode = TextServer.AUTOWRAP_OFF
		lead.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lead.custom_minimum_size.x = 70.0
		row.add_child(lead)
	if not with_threshold:
		var margin_only := MarginContainer.new()
		margin_only.add_theme_constant_override("margin_left", 12)
		margin_only.add_child(row)
		box.add_child(margin_only)
		return
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
