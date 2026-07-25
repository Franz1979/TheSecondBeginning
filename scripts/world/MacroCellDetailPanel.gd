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
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/EmptySpaceLabel
@onready var fauna_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/SectionTitleLabel
@onready var fish_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FishNumberLabel
@onready var fauna_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaSeparatorLabel
@onready var water_empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/WaterEmptySpaceLabel
@onready var subsistence_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/SectionTitleLabel
@onready var forage_units_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/ForageUnitsLabel
@onready var forage_calories_label: Label = $MarginContainer/VBoxContainer/TabContainer/SussistenzaTab/ForageCaloriesLabel
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
		stone_number_label.text = "Stone: " + str(stone_quantity) + " (occupied cells: " + str(stone_space) + ")"
		grass_number_label.text = "Grass: " + str(grass_quantity) + " (occupied cells: " + str(grass_space) + ")"
		shrub_number_label.text = "Shrub: " + str(shrub_quantity) + " (occupied cells: " + str(shrub_space) + ")"
		_update_shrub_subtype_label(cell, state)
		tree_number_label.text = "Trees: " + str(tree_quantity) + " (occupied cells: " + str(tree_space) + ")"
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
		empty_space_label.text = "Empty ground space: " + str(empty_ground_space)

		var fish_quantity := state.get_resource_quantity(GameTypes.WorldObjectType.FISH)
		var fish_space := state.get_water_space(GameTypes.WorldObjectType.FISH)
		var water_capacity := ResourceCalculator.get_water_capacity_space(cell, state)
		fish_number_label.text = "Fish: " + str(fish_quantity) + " (occupied cells: " + str(fish_space) + ")"
		fauna_separator_label.text = " - - - - - - - - - -"
		water_empty_space_label.text = "Water empty space: " + str(state.get_empty_water_space(water_capacity))

		_update_forage_calories_label(state, current_season)
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
		fish_number_label.text = "Fish: -"
		water_empty_space_label.text = "Water empty space: -"


# Due righe di verifica temporanea per il calcolo di FORAGE (erba consumata direttamente, vedi
# CaloricCalculator): unità disponibili (passo intermedio) e calorie risultanti.
func _update_forage_calories_label(state: MacroCellState, current_season: GameTypes.Season) -> void:
	var forage_units := CaloricCalculator.get_forage_available_units(state, current_season)
	var forage_calories := CaloricCalculator.get_forage_available_calories(state, current_season)
	forage_units_label.text = "  - forage units available: " + str(int(round(forage_units)))
	forage_calories_label.text = "  - forage calories available: " + str(int(round(forage_calories)))
	forage_units_label.visible = true
	forage_calories_label.visible = true


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

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.SHRUB, cell.terrain_base, cell.biome, cell.coast_type
	)
	var wood_quantity: int = int(round(int(composition.get("wood_only", 0)) * max_density))
	var fruit_quantity: int = int(round(int(composition.get("fruit_bearing", 0)) * max_density))

	shrub_subtype_wood_label.text = "  - wood_only: " + str(wood_quantity)
	shrub_subtype_fruit_bearing_label.text = "  - fruit_bearing: " + str(fruit_quantity)
	shrub_subtype_container.visible = true


# Stesso formato a due righe di _update_shrub_subtype_label sopra, con le tre chiavi di TREE
# invece delle due di SHRUB.
func _update_tree_subtype_label(cell: MacroCellData, state: MacroCellState) -> void:
	var composition := state.get_subtype_composition(GameTypes.WorldObjectType.TREE)
	if composition.is_empty():
		tree_subtype_container.visible = false
		return

	var max_density := ResourceCalculator.get_max_density(
		GameTypes.WorldObjectType.TREE, cell.terrain_base, cell.biome, cell.coast_type
	)
	var wood_quantity: int = int(round(int(composition.get("wood_only", 0)) * max_density))
	var wild_fruit_quantity: int = int(round(int(composition.get("wild_fruit", 0)) * max_density))
	var domesticable_fruit_quantity: int = int(round(int(composition.get("domesticable_fruit", 0)) * max_density))

	tree_subtype_wood_label.text = "  - wood_only: " + str(wood_quantity)
	tree_subtype_wild_fruit_label.text = "  - wild_fruit: " + str(wild_fruit_quantity)
	tree_subtype_domesticable_fruit_label.text = "  - domesticable_fruit: " + str(domesticable_fruit_quantity)
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
	fish_number_label.text = "Fish: -"
	water_empty_space_label.text = "Water empty space: -"
