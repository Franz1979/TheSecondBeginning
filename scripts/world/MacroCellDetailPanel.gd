class_name MacroCellDetailPanel
extends PanelContainer

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
const TAB_FAUNA := 2
const TAB_SUSSISTENZA := 3

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var geography_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/SectionTitleLabel
@onready var geography_info: CellGeographyInfo = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/CellGeographyInfo
@onready var vegetation_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/SectionTitleLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ShrubNumberLabel
@onready var shrub_subtype_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ShrubSubtypeContainer
@onready var shrub_subtype_wood_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ShrubSubtypeContainer/ShrubSubtypeWoodLabel
@onready var shrub_subtype_fruit_bearing_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ShrubSubtypeContainer/ShrubSubtypeFruitBearingLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeNumberLabel
@onready var tree_subtype_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeSubtypeContainer
@onready var tree_subtype_wood_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeSubtypeContainer/TreeSubtypeWoodLabel
@onready var tree_subtype_wild_fruit_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeSubtypeContainer/TreeSubtypeWildFruitLabel
@onready var tree_subtype_domesticable_fruit_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeSubtypeContainer/TreeSubtypeDomesticableFruitLabel
@onready var tree_subtype_conifer_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/TreeSubtypeContainer/TreeSubtypeConiferLabel
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/EmptySpaceLabel
@onready var fauna_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/SectionTitleLabel
@onready var fish_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FishNumberLabel
@onready var fauna_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaSeparatorLabel
@onready var water_empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/WaterEmptySpaceLabel
@onready var subsistence_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SectionTitleLabel
@onready var forage_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/ForageUnitsLabel
@onready var forage_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/ForageCaloriesLabel
@onready var berry_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/BerrySeparatorLabel
@onready var berry_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/BerryUnitsLabel
@onready var berry_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/BerryCaloriesLabel
@onready var acorn_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/AcornSeparatorLabel
@onready var acorn_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/AcornUnitsLabel
@onready var acorn_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/AcornCaloriesLabel
@onready var fruit_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/FruitSeparatorLabel
@onready var fruit_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/FruitUnitsLabel
@onready var fruit_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/FruitCaloriesLabel
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer


# Le tab mostrano solo un simbolo (nessun tr(): non è testo, è un'icona testuale, indipendente
# dalla lingua) — il nome leggibile della sezione compare come tooltip sulla tab e come titolo
# in cima al contenuto quando è aperta, entrambi dallo stesso tag tr() così restano coerenti
# quando arriverà la localizzazione.
func _ready() -> void:
	tab_container.set_tab_title(TAB_GEOGRAFIA, "🧭")
	tab_container.set_tab_title(TAB_VEGETAZIONE, "🌿")
	tab_container.set_tab_title(TAB_FAUNA, "🐟")
	tab_container.set_tab_title(TAB_SUSSISTENZA, "🍽️")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_FAUNA, tr("tab_fauna"))
	tab_bar.set_tab_tooltip(TAB_SUSSISTENZA, tr("tab_subsistence"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	fauna_title_label.text = tr("tab_fauna")
	subsistence_title_label.text = tr("tab_subsistence")

	clear()


func show_cell(cell: MacroCellData, state: MacroCellState, current_season: GameTypes.Season) -> void:
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
		fauna_separator_label.text = " - - - - - - - - - -"
		water_empty_space_label.text = "Water empty space: " + NumberFormatter.format_int(state.get_empty_water_space(water_capacity))

		_update_forage_calories_label(cell, state, current_season)
		_update_berry_stock_label(state)
		_update_acorn_stock_label(state)
		_update_fruit_stock_label(state)
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
		fish_number_label.text = "Fish: -"
		water_empty_space_label.text = "Water empty space: -"


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

	shrub_subtype_wood_label.text = "  - wood_only: " + NumberFormatter.format_int(wood_quantity) \
		+ _age_band_suffix(GameTypes.WorldObjectType.SHRUB, "wood_only", cell, state)
	shrub_subtype_fruit_bearing_label.text = "  - fruit_bearing: " + NumberFormatter.format_int(fruit_quantity) \
		+ _age_band_suffix(GameTypes.WorldObjectType.SHRUB, "fruit_bearing", cell, state)
	shrub_subtype_container.visible = true


# " (Y:.. - A:.. - O:..)" per i sottotipi con track_age_bands=true, stringa vuota altrimenti
# (nessun suffisso — comportamento identico a prima per i sottotipi non ancora estesi alle age
# bands, es. TREE oggi). Ogni fascia convertita da spazio a quantità con la stessa
# get_subtype_quantity già usata per il totale del sottotipo sopra, mai sul dedicated_space.
func _age_band_suffix(object_type: GameTypes.WorldObjectType, subtype_name: String, cell: MacroCellData, state: MacroCellState) -> String:
	var rule := ResourceCalculator.get_subtype_rule(object_type, subtype_name)
	if rule == null or not rule.track_age_bands:
		return ""

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

	return " (Y:%s - A:%s - O:%s)" % [
		NumberFormatter.format_int(young_quantity),
		NumberFormatter.format_int(adult_quantity),
		NumberFormatter.format_int(old_quantity)
	]


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
	tree_subtype_wild_fruit_label.text = "  - wild_fruit: " + NumberFormatter.format_int(wild_fruit_quantity)
	tree_subtype_domesticable_fruit_label.text = "  - domesticable_fruit: " + NumberFormatter.format_int(domesticable_fruit_quantity)
	tree_subtype_conifer_label.text = "  - conifer: " + NumberFormatter.format_int(conifer_quantity)
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
	fish_number_label.text = "Fish: -"
	water_empty_space_label.text = "Water empty space: -"
