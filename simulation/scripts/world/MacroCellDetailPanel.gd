class_name MacroCellDetailPanel
extends PanelContainer

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
# Fauna è divisa in tre tab (a richiesta dell'utente): FAUNA_1 per la fauna "passiva", che si
# comporta come vegetazione — cresce/decresce in MacroCellState per densità, nessun comportamento
# proprio (oggi solo FISH, in futuro BIRDS); FAUNA_2 per gli erbivori "veri", con comportamento e
# stato proprio via PopulationGroup (rabbit, deer, ...); FAUNA_3 per i PREDATORI (PredatorRules,
# oggi wolf) — mostra solo i branchi il cui territorio include QUESTA cella (a differenza di
# WorldInfoPanel.TAB_FAUNA_3, che è world-level e li mostra tutti). Prima dello split FAUNA_1/2
# erano un'unica tab.
const TAB_FAUNA_1 := 2
const TAB_FAUNA_2 := 3
const TAB_FAUNA_3 := 4
const TAB_SUSSISTENZA := 5

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var geography_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/SectionTitleLabel
@onready var geography_info: CellGeographyInfo = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/CellGeographyInfo
@onready var vegetation_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/SectionTitleLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubNumberLabel
@onready var shrub_subtype_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubSubtypeContainer
@onready var shrub_subtype_wood_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubSubtypeContainer/ShrubSubtypeWoodLabel
@onready var shrub_subtype_wood_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubSubtypeContainer/ShrubSubtypeWoodAgeLabel
@onready var shrub_subtype_fruit_bearing_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubSubtypeContainer/ShrubSubtypeFruitBearingLabel
@onready var shrub_subtype_fruit_bearing_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubSubtypeContainer/ShrubSubtypeFruitBearingAgeLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeNumberLabel
@onready var tree_subtype_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer
@onready var tree_subtype_wood_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeWoodLabel
@onready var tree_subtype_wood_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeWoodAgeLabel
@onready var tree_subtype_wild_fruit_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeWildFruitLabel
@onready var tree_subtype_wild_fruit_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeWildFruitAgeLabel
@onready var tree_subtype_domesticable_fruit_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeDomesticableFruitLabel
@onready var tree_subtype_domesticable_fruit_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeDomesticableFruitAgeLabel
@onready var tree_subtype_conifer_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeConiferLabel
@onready var tree_subtype_conifer_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeSubtypeContainer/TreeSubtypeConiferAgeLabel
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/EmptySpaceLabel
@onready var fauna_1_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/SectionTitleLabel
@onready var fish_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/FishNumberLabel
@onready var water_empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/WaterEmptySpaceLabel
@onready var birds_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/BirdsSeparatorLabel
@onready var birds_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/BirdsNumberLabel
@onready var land_empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/LandEmptySpaceLabel
@onready var fauna_2_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/SectionTitleLabel
@onready var animal_population_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/AnimalPopulationContainer
@onready var fauna_3_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab3/FaunaContent/SectionTitleLabel
@onready var predator_population_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab3/FaunaContent/PredatorPopulationContainer
@onready var subsistence_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/SectionTitleLabel
@onready var forage_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/ForageUnitsLabel
@onready var forage_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/ForageCaloriesLabel
@onready var berry_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/BerrySeparatorLabel
@onready var berry_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/BerryUnitsLabel
@onready var berry_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/BerryCaloriesLabel
@onready var acorn_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/AcornSeparatorLabel
@onready var acorn_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/AcornUnitsLabel
@onready var acorn_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/AcornCaloriesLabel
@onready var fruit_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/FruitSeparatorLabel
@onready var fruit_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/FruitUnitsLabel
@onready var fruit_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/FruitCaloriesLabel
@onready var eggs_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/EggsSeparatorLabel
@onready var eggs_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/EggsUnitsLabel
@onready var eggs_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SussistenzaContent/EggsCaloriesLabel
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer


# Le tab mostrano solo un simbolo (nessun tr(): non è testo, è un'icona testuale, indipendente
# dalla lingua) — il nome leggibile della sezione compare come tooltip sulla tab e come titolo
# in cima al contenuto quando è aperta, entrambi dallo stesso tag tr() così restano coerenti
# quando arriverà la localizzazione.
func _ready() -> void:
	# Font più piccolo sulla barra delle tab (non sul contenuto): con 6 tab invece di 5 il testo di
	# default farebbe allargare la barra oltre la larghezza fissa del pannello, o farebbe comparire
	# le freccette di scroll di TabBar — le etichette sono comunque solo emoji singole, restano
	# perfettamente leggibili anche ridotte. h_separation/side_margin azzerati per non sprecare
	# pixel tra un'icona e l'altra (col tema di default aggiungono margine visibile ma qui inutile,
	# le tab sono già distinguibili dallo sfondo/selezione).
	tab_container.add_theme_font_size_override("font_size", 11)
	tab_container.add_theme_constant_override("side_margin", 0)

	tab_container.set_tab_title(TAB_GEOGRAFIA, "🧭")
	tab_container.set_tab_title(TAB_VEGETAZIONE, "🌿")
	tab_container.set_tab_title(TAB_FAUNA_1, "🐟")
	tab_container.set_tab_title(TAB_FAUNA_2, "🦌")
	tab_container.set_tab_title(TAB_FAUNA_3, "🐺")
	# Fork/knife/plate con variation selector (🍽️) è visibilmente più larga delle emoji a singolo
	# codepoint delle altre tab (il VS16 forza la presentazione "emoji" a piena larghezza in molti
	# font) — sostituita con 🍴 (forchetta e coltello, singolo codepoint, stesso tema "sussistenza").
	tab_container.set_tab_title(TAB_SUSSISTENZA, "🍴")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.add_theme_constant_override("h_separation", 0)
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_1, tr("tab_fauna_1"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_2, tr("tab_fauna_2"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_3, tr("tab_fauna_3"))
	tab_bar.set_tab_tooltip(TAB_SUSSISTENZA, tr("tab_subsistence"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	fauna_1_title_label.text = tr("tab_fauna_1")
	fauna_2_title_label.text = tr("tab_fauna_2")
	fauna_3_title_label.text = tr("tab_fauna_3")
	subsistence_title_label.text = tr("tab_subsistence")

	clear()


func show_cell(cell: MacroCellData, state: MacroCellState, current_season: GameTypes.Season, world: World) -> void:
	if cell == null:
		clear()
		return
	title_label.text = "Macro Cell Data:"
	coords_label.text = "Coords: " + str(cell.x) + ", " + str(cell.y)
	geography_info.show_geography(cell)

	if state != null:
		var stone_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
		var stone_space := state.get_dedicated_space(GameTypes.WorldObjectType.ROCK)
		var grass_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.GRASS)
		var grass_space := state.get_dedicated_space(GameTypes.WorldObjectType.GRASS)
		var shrub_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.SHRUB)
		var shrub_space := state.get_dedicated_space(GameTypes.WorldObjectType.SHRUB)
		var tree_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.TREE)
		var tree_space := state.get_dedicated_space(GameTypes.WorldObjectType.TREE)
		stone_number_label.text = "Stone: " + NumberFormatter.format_int(stone_quantity) + " (occupied cells: " + NumberFormatter.format_int(stone_space) + ")"
		grass_number_label.text = "Grass: " + NumberFormatter.format_int(grass_quantity) + " (occupied cells: " + NumberFormatter.format_int(grass_space) + ")"
		shrub_number_label.text = "Shrub: " + NumberFormatter.format_int(shrub_quantity) + " (occupied cells: " + NumberFormatter.format_int(shrub_space) + ")"
		_update_shrub_subtype_label(cell, state)
		tree_number_label.text = "Trees: " + NumberFormatter.format_int(tree_quantity) + " (occupied cells: " + NumberFormatter.format_int(tree_space) + ")"
		_update_tree_subtype_label(cell, state)
		resource_separator_label.text = " - - - - - - - - - -"
		# Su SEA/LAKE il calcolo "naturale" di get_empty_space() risulterebbe comunque
		# TOTAL_SPACE (nessuna risorsa terrestre ha mai popolato dedicated_space lì, essendo
		# la loro densità 0 su terrain WATER): un valore fuorviante da mostrare, dato che quello
		# spazio non sarà mai disponibile per vegetazione/roccia. Qui lo forziamo esplicitamente
		# a 0 solo per la visualizzazione; get_empty_space() stesso resta invariato (nessun
		# chiamante ne ha bisogno diverso: tutti bypassano già la lettura su terrain WATER
		# tramite i propri controlli su max_density/growth_rate, sempre 0 lì).
		var empty_ground_space: int = state.get_empty_space()
		if cell.terrain_base == GameTypes.TerrainBase.WATER:
			empty_ground_space = 0
		empty_space_label.text = "Empty ground space: " + NumberFormatter.format_int(empty_ground_space)

		var fish_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.FISH)
		var fish_space := state.get_water_space(GameTypes.WorldObjectType.FISH)
		var water_capacity := ResourceCalculator.get_water_capacity_space(cell, state)
		fish_number_label.text = "Fish: " + NumberFormatter.format_int(fish_quantity) + " (occupied cells: " + NumberFormatter.format_int(fish_space) + ")"
		water_empty_space_label.text = "Water empty space: " + NumberFormatter.format_int(state.get_empty_water_space(water_capacity))

		var birds_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.BIRDS)
		var birds_space := state.get_terrestrial_space(GameTypes.WorldObjectType.BIRDS)
		var land_capacity := ResourceCalculator.get_land_capacity_space(cell, state)
		birds_separator_label.text = " - - - - - - - - - -"
		birds_number_label.text = "Birds: " + NumberFormatter.format_int(birds_quantity) + " (occupied cells: " + NumberFormatter.format_int(birds_space) + ")"
		land_empty_space_label.text = "Habitat empty space: " + NumberFormatter.format_int(state.get_empty_terrestrial_space(land_capacity))

		_update_animal_population_rows(world, Vector2i(cell.x, cell.y))
		_update_predator_population_rows(world, Vector2i(cell.x, cell.y))

		_update_forage_calories_label(cell, state, current_season)
		_update_berry_stock_label(state)
		_update_acorn_stock_label(state)
		_update_fruit_stock_label(state)
		_update_eggs_stock_label(state)
	else:
		stone_number_label.text = "Stone: -"
		grass_number_label.text = "Grass: -"
		shrub_number_label.text = "Shrub: -"
		shrub_subtype_container.visible = false
		tree_number_label.text = "Trees: -"
		tree_subtype_container.visible = false
		empty_space_label.text = "Empty ground space: -"
		forage_units_label.visible = false
		forage_calories_label.visible = false
		berry_units_label.visible = false
		berry_calories_label.visible = false
		acorn_units_label.visible = false
		acorn_calories_label.visible = false
		fruit_units_label.visible = false
		fruit_calories_label.visible = false
		eggs_units_label.visible = false
		eggs_calories_label.visible = false
		fish_number_label.text = "Fish: -"
		water_empty_space_label.text = "Water empty space: -"
		birds_number_label.text = "Birds: -"
		land_empty_space_label.text = "Habitat empty space: -"
		_clear_animal_population_rows()
		_clear_predator_population_rows()


# Nessun nodo fisso per specie (a differenza dei sottotipi vegetali, che hanno una Label dedicata
# per ogni sottotipo noto già nel .tscn): la lista delle specie animali presenti in questa cella è
# aperta (world.get_population_groups_at(coords)), quindi le righe sono generate a runtime —
# stesso precedente già usato da TooltipButton.gd (Label.new() invece di istanziare nodi .tscn
# fissi).
#
# Step 5 (territori multi-cella): questo pannello è per-cella, quindi mostra solo la quota di
# animali EFFETTIVAMENTE presenti in questa macrocella (PopulationGroup.get_population_by_cell —
# ripartizione uniforme del gruppo sul suo territorio), non il totale dell'intero gruppo, che
# potrebbe occupare anche altre celle. Con territorio a una sola cella (rabbit, o deer già oggi)
# la quota coincide col totale e il formato degrada a "  - specie: N" come prima di questo step.
# Con più celle: "  - specie: N of M (K cells)". La riga età (Y/A/O) sotto è la ripartizione
# della SOLA quota di questa cella (PopulationGroup.get_age_composition_in_cell) — derivata a
# scopo di visualizzazione (non esiste age tracking per cella nel modello), coerente per
# costruzione con la quota mostrata sopra (la somma Y+A+O torna sempre esattamente N).
func _update_animal_population_rows(world: World, coords: Vector2i) -> void:
	_clear_animal_population_rows()

	for group in world.get_population_groups_at(coords):
		if group.population <= 0:
			continue

		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		# I predatori (PredatorRules) hanno la propria tab dedicata (Fauna 3, vedi
		# _update_predator_population_rows) — esclusi qui per non comparire due volte.
		if rules is PredatorRules:
			continue
		var cell_count := group.territory.get_cell_count()
		var cell_population: int = int(group.get_population_by_cell().get(coords, 0))
		if cell_population <= 0:
			continue

		var number_label := Label.new()
		number_label.add_theme_font_size_override("font_size", 11)
		if cell_count > 1:
			# Testo hardcoded, non tr(): stesso trattamento delle altre parole di raccordo già
			# usate in questi pannelli (es. "Y:"/"A:"/"O:" sotto) — nessuna CSV di traduzione
			# esiste ancora (vedi CLAUDE.md), un tr() qui mostrerebbe la chiave grezza a schermo.
			number_label.text = "  - %s: %s of %s (%d cells)" % [
				group.species_name,
				NumberFormatter.format_int(cell_population),
				NumberFormatter.format_int(group.population),
				cell_count
			]
		else:
			number_label.text = "  - %s: %s" % [group.species_name, NumberFormatter.format_int(cell_population)]
		animal_population_container.add_child(number_label)

		if rules != null and rules.track_age_bands:
			var cell_age_composition := group.get_age_composition_in_cell(coords)
			var young := int(cell_age_composition.get(GameTypes.AgeBand.YOUNG, 0))
			var adult := int(cell_age_composition.get(GameTypes.AgeBand.ADULT, 0))
			var old := int(cell_age_composition.get(GameTypes.AgeBand.OLD, 0))

			var age_label := Label.new()
			age_label.add_theme_font_size_override("font_size", 10)
			age_label.text = "      (Y:%s - A:%s - O:%s)" % [
				NumberFormatter.format_int(young),
				NumberFormatter.format_int(adult),
				NumberFormatter.format_int(old)
			]
			animal_population_container.add_child(age_label)


func _clear_animal_population_rows() -> void:
	for child in animal_population_container.get_children():
		child.queue_free()


# Solo i branchi predatori il cui territorio include QUESTA cella (world.get_population_groups_at,
# stesso filtro di _update_animal_population_rows sopra) — a differenza di
# WorldInfoPanel._update_predator_groups, che è world-level e li mostra tutti indipendentemente
# dalla cella aperta. Finestra di pattugliamento/cronologia caccia/totale annuale restano dati
# dell'INTERO branco (non esiste un tracking per-cella della caccia), etichettati di conseguenza
# per non far pensare che siano limitati a questa sola cella.
func _update_predator_population_rows(world: World, coords: Vector2i) -> void:
	_clear_predator_population_rows()

	for group in world.get_population_groups_at(coords):
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if not (rules is PredatorRules):
			continue
		var cell_population: int = int(group.get_population_by_cell().get(coords, 0))
		if cell_population <= 0:
			continue
		_add_predator_population_block(group, rules as PredatorRules, coords, cell_population)


func _clear_predator_population_rows() -> void:
	for child in predator_population_container.get_children():
		child.queue_free()


# Blocco multi-riga per UN branco presente in questa cella: quota locale (individui in QUESTA
# cella su popolazione totale del branco, stesso formato "N of M" di _update_animal_population_rows
# sopra), poi i dati del branco intero (finestra di oggi, bookkeeping calorico, cronologia ultimi
# giorni, totale anno corrente) — identici a WorldInfoPanel._add_predator_group_block, duplicati
# qui deliberatamente (stesso principio di non-condivisione già dichiarato in testa al file per
# CellGeographyInfo/altre parti in comune tra i due pannelli).
func _add_predator_population_block(
	group: PopulationGroup, rules: PredatorRules, coords: Vector2i, cell_population: int
) -> void:
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 11)
	header.text = "  - %s #%d: %s of %s (branco: %d cells totali)" % [
		group.species_name,
		group.id,
		NumberFormatter.format_int(cell_population),
		NumberFormatter.format_int(group.population),
		group.territory.get_cell_count()
	]
	predator_population_container.add_child(header)

	if rules.track_age_bands:
		var cell_age_composition := group.get_age_composition_in_cell(coords)
		var young := int(cell_age_composition.get(GameTypes.AgeBand.YOUNG, 0))
		var adult := int(cell_age_composition.get(GameTypes.AgeBand.ADULT, 0))
		var old := int(cell_age_composition.get(GameTypes.AgeBand.OLD, 0))

		var age_label := Label.new()
		age_label.add_theme_font_size_override("font_size", 10)
		age_label.text = "      (Y:%s - A:%s - O:%s)" % [
			NumberFormatter.format_int(young),
			NumberFormatter.format_int(adult),
			NumberFormatter.format_int(old)
		]
		predator_population_container.add_child(age_label)

	var window_label := Label.new()
	window_label.add_theme_font_size_override("font_size", 10)
	if group.patrol_route.is_empty():
		window_label.text = "      day window (intero branco): nessuna (patrol_route vuoto)"
	else:
		var anchor: Vector2i = group.patrol_route[group.patrol_index]
		window_label.text = "      day window (intero branco): (%d,%d) %dx%d" % [
			anchor.x, anchor.y, rules.hunting_window_size, rules.hunting_window_size
		]
	predator_population_container.add_child(window_label)

	var bookkeeping_label := Label.new()
	bookkeeping_label.add_theme_font_size_override("font_size", 10)
	bookkeeping_label.text = "      debt=%s  surplus=%s (intero branco)" % [
		NumberFormatter.format_int(int(round(group.predation_calorie_debt))),
		NumberFormatter.format_int(int(round(group.predation_surplus_carryover)))
	]
	predator_population_container.add_child(bookkeeping_label)

	# Nessuna intestazione "ultimi N giorni": si capisce comunque dal contesto (vedi
	# PopulationGroup.RECENT_HUNT_LOG_MAX_DAYS per il numero di entry). Nessun "Anno N": l'anno è
	# già visibile nel calendario sopra, ripeterlo qui su ogni riga era ridondante. Una riga per
	# giorno, col primo animale catturato subito accanto al numero di giorno (non più a capo) —
	# solo eventuali animali AGGIUNTIVI catturati lo stesso giorno vanno a capo, indentati sotto
	# (vedi _add_day_capture_lines).
	if group.recent_hunt_log.is_empty():
		var no_history_label := Label.new()
		no_history_label.add_theme_font_size_override("font_size", 10)
		no_history_label.text = "            (nessun dato ancora)"
		predator_population_container.add_child(no_history_label)
	else:
		for i in range(group.recent_hunt_log.size() - 1, -1, -1):
			var entry: Dictionary = group.recent_hunt_log[i]
			_add_day_capture_lines(predator_population_container, int(entry["day"]), entry["captures"])

	# "tot current year", non "tot year N": l'anno è già visibile nel calendario sopra, il numero
	# qui era ridondante (stesso principio delle righe giorno sopra).
	if group.yearly_prey_totals_year < 0:
		var yearly_header_label := Label.new()
		yearly_header_label.add_theme_font_size_override("font_size", 10)
		yearly_header_label.text = "      tot current year (intero branco): (nessun dato ancora)"
		predator_population_container.add_child(yearly_header_label)
	else:
		var yearly_header_label := Label.new()
		yearly_header_label.add_theme_font_size_override("font_size", 10)
		yearly_header_label.text = "      tot current year (intero branco):"
		predator_population_container.add_child(yearly_header_label)
		_add_capture_lines(predator_population_container, group.yearly_prey_totals)

	var separator := Label.new()
	separator.add_theme_font_size_override("font_size", 8)
	separator.text = " - - - - - - - - - -"
	predator_population_container.add_child(separator)


# Stesso formato di WorldInfoPanel._add_capture_lines, duplicato qui (vedi commento a
# _add_predator_population_block sopra sul perché). Una Label per SPECIE — "%s x%d (%s cal)",
# specie in ordine alfabetico — invece di un'unica riga con le specie separate da virgola, che
# nella larghezza fissa del pannello troncava tutto dopo la prima specie e mezza. Usata solo per il
# totale annuale (per il log giornaliero vedi _add_day_capture_lines sotto, che accorpa il primo
# animale sulla riga del giorno). "— no catches —" se non c'è stata alcuna cattura.
func _add_capture_lines(container: VBoxContainer, captures: Dictionary) -> void:
	if captures.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.text = "            — no catches —"
		container.add_child(empty_label)
		return
	var species_names: Array = captures.keys()
	species_names.sort()
	for species_name in species_names:
		var entry: Dictionary = captures[species_name]
		var line_label := Label.new()
		line_label.add_theme_font_size_override("font_size", 10)
		line_label.text = "            %s x%d (%s cal)" % [
			species_name,
			int(entry["quantity"]),
			NumberFormatter.format_int(int(round(float(entry["calories"]))))
		]
		container.add_child(line_label)


# Stesso formato di WorldInfoPanel._add_day_capture_lines, duplicato qui (vedi commento a
# _add_predator_population_block sopra sul perché). Il primo animale catturato quel giorno sta
# sulla STESSA riga del numero di giorno; eventuali animali ULTERIORI vanno a capo, allineati in
# colonna sotto il primo tramite una Label prefisso a larghezza fissa (non spazi di testo: con un
# font proporzionale un rientro a spazi non allinea mai esattamente sotto un prefisso di lunghezza
# diversa come "Day 237:" vs "Day 5:"). Colonna più larga della controparte in WorldInfoPanel
# perché include anche il rientro base "            " di questo blocco (nidificato sotto la riga
# di quota per-cella, a differenza del blocco world-level). "— no catches —" anch'esso sulla riga
# del giorno se captures è vuoto.
const DAY_PREFIX_COLUMN_WIDTH := 98.0

func _add_day_capture_lines(container: VBoxContainer, day: int, captures: Dictionary) -> void:
	var prefix := "            Day %d:" % day
	if captures.is_empty():
		_add_day_capture_row(container, prefix, "— no catches —")
		return
	var species_names: Array = captures.keys()
	species_names.sort()
	for i in range(species_names.size()):
		var species_name = species_names[i]
		var entry: Dictionary = captures[species_name]
		var species_text := "%s x%d (%s cal)" % [
			species_name,
			int(entry["quantity"]),
			NumberFormatter.format_int(int(round(float(entry["calories"]))))
		]
		_add_day_capture_row(container, prefix if i == 0 else "", species_text)


# Riga a due colonne: colonna prefisso a larghezza fissa (vuota per le righe di continuazione,
# così il testo della colonna successiva parte sempre alla stessa X) + colonna contenuto.
func _add_day_capture_row(container: VBoxContainer, prefix: String, content: String) -> void:
	var row := HBoxContainer.new()
	container.add_child(row)

	var prefix_label := Label.new()
	prefix_label.add_theme_font_size_override("font_size", 10)
	prefix_label.custom_minimum_size = Vector2(DAY_PREFIX_COLUMN_WIDTH, 0)
	# clip_text (non solo il floor di custom_minimum_size): senza, un giorno a 3 cifre ("Day
	# 237:") supererebbe la colonna e sfaserebbe l'allineamento rispetto a un giorno a 1 cifra
	# ("Day 5:") o rispetto alle righe di continuazione vuote sotto.
	prefix_label.clip_text = true
	prefix_label.text = prefix
	row.add_child(prefix_label)

	var content_label := Label.new()
	content_label.add_theme_font_size_override("font_size", 10)
	content_label.size_flags_horizontal = SIZE_EXPAND_FILL
	content_label.clip_text = true
	content_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content_label.text = content
	row.add_child(content_label)


# Due righe di verifica temporanea per il calcolo di FORAGE (erba consumata direttamente, vedi
# CaloricCalculator): unità disponibili (passo intermedio) e calorie risultanti.
func _update_forage_calories_label(cell: MacroCellData, state: MacroCellState, current_season: GameTypes.Season) -> void:
	var forage_units := CaloricCalculator.get_forage_available_units(cell, state, current_season)
	var forage_calories := CaloricCalculator.get_forage_available_calories(cell, state, current_season)
	forage_units_label.text = "  - forage units available: " + NumberFormatter.format_int(int(round(forage_units)))
	forage_calories_label.text = "  - forage calories available: " + NumberFormatter.format_int(int(round(forage_calories)))
	forage_units_label.visible = true
	forage_calories_label.visible = true


# A differenza di FORAGE (stateless, ricalcolato ogni volta da _get_base_quantity), BERRY ha
# uno stock persistente (MacroCellState.secondary_resource_stock) aggiornato dai checkpoint
# stagionali (CaloricCalculator.update_secondary_resource_stock) — qui lo si legge soltanto,
# non lo si ricalcola. Stesso pattern riusabile per acorn/fruit quando arriveranno (basta
# un'altra funzione sorella con resource_name diverso).
func _update_berry_stock_label(state: MacroCellState) -> void:
	var berry_units := CaloricCalculator.get_secondary_resource_stock_units(state, "berry")
	var berry_calories := CaloricCalculator.get_secondary_resource_stock_calories(state, "berry")
	berry_separator_label.text = " - - - - - - - - - -"
	berry_units_label.text = "  - berry stock available: " + NumberFormatter.format_int(int(round(berry_units)))
	berry_calories_label.text = "  - berry calories available: " + NumberFormatter.format_int(int(round(berry_calories)))
	berry_units_label.visible = true
	berry_calories_label.visible = true


# Stesso pattern di _update_berry_stock_label sopra, per ACORN (sottotipo wild_fruit di TREE).
func _update_acorn_stock_label(state: MacroCellState) -> void:
	var acorn_units := CaloricCalculator.get_secondary_resource_stock_units(state, "acorn")
	var acorn_calories := CaloricCalculator.get_secondary_resource_stock_calories(state, "acorn")
	acorn_separator_label.text = " - - - - - - - - - -"
	acorn_units_label.text = "  - acorn stock available: " + NumberFormatter.format_int(int(round(acorn_units)))
	acorn_calories_label.text = "  - acorn calories available: " + NumberFormatter.format_int(int(round(acorn_calories)))
	acorn_units_label.visible = true
	acorn_calories_label.visible = true


# Stesso pattern di _update_berry_stock_label sopra, per FRUIT (sottotipo domesticable_fruit di TREE).
func _update_fruit_stock_label(state: MacroCellState) -> void:
	var fruit_units := CaloricCalculator.get_secondary_resource_stock_units(state, "fruit")
	var fruit_calories := CaloricCalculator.get_secondary_resource_stock_calories(state, "fruit")
	fruit_separator_label.text = " - - - - - - - - - -"
	fruit_units_label.text = "  - fruit stock available: " + NumberFormatter.format_int(int(round(fruit_units)))
	fruit_calories_label.text = "  - fruit calories available: " + NumberFormatter.format_int(int(round(fruit_calories)))
	fruit_units_label.visible = true
	fruit_calories_label.visible = true


# Stesso pattern di _update_berry_stock_label sopra, per EGGS (fonte source_subtype vuoto,
# derivata direttamente dall'aggregato BIRDS — stesso path stateless già usato da FORAGE/GRASS,
# non un sottotipo come berry/acorn/fruit).
func _update_eggs_stock_label(state: MacroCellState) -> void:
	var eggs_units := CaloricCalculator.get_secondary_resource_stock_units(state, "eggs")
	var eggs_calories := CaloricCalculator.get_secondary_resource_stock_calories(state, "eggs")
	eggs_separator_label.text = " - - - - - - - - - -"
	eggs_units_label.text = "  - eggs stock available: " + NumberFormatter.format_int(int(round(eggs_units)))
	eggs_calories_label.text = "  - eggs calories available: " + NumberFormatter.format_int(int(round(eggs_calories)))
	eggs_units_label.visible = true
	eggs_calories_label.visible = true


# Seconda riga, indentata, sotto la riga principale di SHRUB: nascosta se la cella non ha ancora
# una subtype_composition tracciata (nessuno shrub presente). subtype_composition resta ancorata a
# dedicated_space (unità di spazio, invariato): qui si converte solo il valore mostrato in
# resource_quantity, con la stessa densità già usata per l'aggregato SHRUB della cella (identica
# formula di ResourceGrowthService/InitialResourceSetupService ecc.: quantity = round(space * max_density)).
func _update_shrub_subtype_label(cell: MacroCellData, state: MacroCellState) -> void:
	var composition := state.get_subtype_composition(GameTypes.WorldObjectType.SHRUB)
	if composition.is_empty():
		shrub_subtype_container.visible = false
		return

	var wood_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.SHRUB, int(composition.get("wood_only", 0)), cell
	)
	var fruit_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.SHRUB, int(composition.get("fruit_bearing", 0)), cell
	)

	shrub_subtype_wood_label.text = "  - wood_only: " + NumberFormatter.format_int(wood_quantity)
	_set_age_band_line(shrub_subtype_wood_age_label, GameTypes.WorldObjectType.SHRUB, "wood_only", cell, state)
	shrub_subtype_fruit_bearing_label.text = "  - fruit_bearing: " + NumberFormatter.format_int(fruit_quantity)
	_set_age_band_line(shrub_subtype_fruit_bearing_age_label, GameTypes.WorldObjectType.SHRUB, "fruit_bearing", cell, state)
	shrub_subtype_container.visible = true


# Riga propria (invece che in coda alla riga principale, che altrimenti andava a capo male nella
# sidebar stretta): "      (Y:.. - A:.. - O:..)" per i sottotipi con track_age_bands=true,
# nascosta del tutto altrimenti (nessun suffisso — comportamento identico a prima per i sottotipi
# non ancora estesi alle age bands). Ogni fascia convertita da spazio a quantità con la stessa
# get_subtype_quantity già usata per il totale del sottotipo sopra, mai sul dedicated_space.
func _set_age_band_line(label: Label, object_type: GameTypes.WorldObjectType, subtype_name: String, cell: MacroCellData, state: MacroCellState) -> void:
	var rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
	if rule == null or not rule.track_age_bands:
		label.visible = false
		return

	var age_counts := state.get_age_composition(object_type, subtype_name)
	var young_quantity := ResourceCalculator.get_subtype_quantity(
		object_type, int(age_counts.get(GameTypes.AgeBand.YOUNG, 0)), cell
	)
	var adult_quantity := ResourceCalculator.get_subtype_quantity(
		object_type, int(age_counts.get(GameTypes.AgeBand.ADULT, 0)), cell
	)
	var old_quantity := ResourceCalculator.get_subtype_quantity(
		object_type, int(age_counts.get(GameTypes.AgeBand.OLD, 0)), cell
	)

	label.text = "      (Y:%s - A:%s - O:%s)" % [
		NumberFormatter.format_int(young_quantity),
		NumberFormatter.format_int(adult_quantity),
		NumberFormatter.format_int(old_quantity)
	]
	label.visible = true


# Stesso formato a due righe di _update_shrub_subtype_label sopra, con le tre chiavi di TREE
# invece delle due di SHRUB.
func _update_tree_subtype_label(cell: MacroCellData, state: MacroCellState) -> void:
	var composition := state.get_subtype_composition(GameTypes.WorldObjectType.TREE)
	if composition.is_empty():
		tree_subtype_container.visible = false
		return

	var wood_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.TREE, int(composition.get("wood_only", 0)), cell
	)
	var wild_fruit_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.TREE, int(composition.get("wild_fruit", 0)), cell
	)
	var domesticable_fruit_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.TREE, int(composition.get("domesticable_fruit", 0)), cell
	)
	var conifer_quantity := ResourceCalculator.get_subtype_quantity(
		GameTypes.WorldObjectType.TREE, int(composition.get("conifer", 0)), cell
	)

	tree_subtype_wood_label.text = "  - wood_only: " + NumberFormatter.format_int(wood_quantity)
	_set_age_band_line(tree_subtype_wood_age_label, GameTypes.WorldObjectType.TREE, "wood_only", cell, state)
	tree_subtype_wild_fruit_label.text = "  - wild_fruit: " + NumberFormatter.format_int(wild_fruit_quantity)
	_set_age_band_line(tree_subtype_wild_fruit_age_label, GameTypes.WorldObjectType.TREE, "wild_fruit", cell, state)
	tree_subtype_domesticable_fruit_label.text = "  - domesticable_fruit: " + NumberFormatter.format_int(domesticable_fruit_quantity)
	_set_age_band_line(tree_subtype_domesticable_fruit_age_label, GameTypes.WorldObjectType.TREE, "domesticable_fruit", cell, state)
	tree_subtype_conifer_label.text = "  - conifer: " + NumberFormatter.format_int(conifer_quantity)
	_set_age_band_line(tree_subtype_conifer_age_label, GameTypes.WorldObjectType.TREE, "conifer", cell, state)
	tree_subtype_container.visible = true


func clear() -> void:
	title_label.text = "Macro cell"
	coords_label.text = "Coords: -"
	geography_info.clear()
	stone_number_label.text = "Stone: -"
	grass_number_label.text = "Grass: -"
	shrub_number_label.text = "Shrub: -"
	shrub_subtype_container.visible = false
	tree_number_label.text = "Trees: -"
	tree_subtype_container.visible = false
	empty_space_label.text = "Empty ground space: -"
	forage_units_label.visible = false
	forage_calories_label.visible = false
	berry_units_label.visible = false
	berry_calories_label.visible = false
	acorn_units_label.visible = false
	acorn_calories_label.visible = false
	fruit_units_label.visible = false
	fruit_calories_label.visible = false
	eggs_units_label.visible = false
	eggs_calories_label.visible = false
	fish_number_label.text = "Fish: -"
	water_empty_space_label.text = "Water empty space: -"
	birds_number_label.text = "Birds: -"
	land_empty_space_label.text = "Habitat empty space: -"
	_clear_animal_population_rows()
	_clear_predator_population_rows()
