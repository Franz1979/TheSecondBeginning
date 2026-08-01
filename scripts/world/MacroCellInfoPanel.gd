class_name MacroCellInfoPanel
extends PanelContainer

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
const TAB_RISORSE := 2
const TAB_FAUNA := 3

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var coords_label: Label = $MarginContainer/VBoxContainer/CoordsLabel
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var geography_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/SectionTitleLabel
@onready var geography_info: CellGeographyInfo = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/CellGeographyInfo
@onready var space_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/SpaceLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/ShrubNumberLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/TreeNumberLabel
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/EmptySpaceLabel
@onready var vegetation_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/SectionTitleLabel
@onready var resources_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/RisorseTab/SectionTitleLabel
@onready var fauna_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaContent/SectionTitleLabel
@onready var population_groups_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaContent/PopulationGroupsContainer
@onready var fauna_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaContent/FaunaSeparatorLabel
@onready var fish_summary_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab/FaunaContent/FishSummaryContainer
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer

# Riferimento world tenuto solo per rinfrescare il tab Fauna (contenuto world-level, indipendente
# dalla cella selezionata) da _on_tab_changed, che non riceve altrimenti alcun parametro.
var _world: World = null


# Le tab mostrano solo un simbolo (nessun tr(): non è testo, è un'icona testuale, indipendente
# dalla lingua) — il nome leggibile della sezione compare come tooltip sulla tab e come titolo
# in cima al contenuto quando è aperta, stesso schema di MacroCellDetailPanel.
func _ready() -> void:
	tab_container.set_tab_title(TAB_GEOGRAFIA, "🧭")
	tab_container.set_tab_title(TAB_VEGETAZIONE, "🌿")
	tab_container.set_tab_title(TAB_RISORSE, "⛏️")
	tab_container.set_tab_title(TAB_FAUNA, "🐟")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_RISORSE, tr("tab_resources"))
	tab_bar.set_tab_tooltip(TAB_FAUNA, tr("tab_fauna"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	resources_title_label.text = tr("tab_resources")
	fauna_title_label.text = tr("tab_fauna")
	fauna_separator_label.text = " - - - - - - - - - -"

	tab_container.tab_changed.connect(_on_tab_changed)

	clear()


func show_cell(cell: MacroCellData, state: MacroCellState, world: World, show_resources: bool = true) -> void:
	_world = world
	_set_extra_tabs_hidden(not show_resources)

	if cell == null:
		clear(show_resources)
		return
	title_label.text = "Macro Cell Data:"
	coords_label.text = "Coords: " + str(cell.x) + ", " + str(cell.y)
	geography_info.show_geography(cell)
	_set_resources_visible(show_resources)
	if show_resources:
		space_label.text = " - - - - - - - - - -"

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
			tree_number_label.text = "Trees: " + NumberFormatter.format_int(tree_quantity) + " (occupied cells: " + NumberFormatter.format_int(tree_space) + ")"
			resource_separator_label.text = " - - - - - - - - - -"
			# Su SEA/LAKE il calcolo "naturale" di get_empty_space() risulterebbe comunque
			# TOTAL_SPACE (nessuna risorsa terrestre ha mai popolato dedicated_space lì, essendo
			# la loro densità 0 su terrain WATER): un valore fuorviante da mostrare, dato che quello
			# spazio non sarà mai disponibile per vegetazione/roccia. Qui lo forziamo esplicitamente
			# a 0 solo per la visualizzazione; get_empty_space() stesso resta invariato.
			var empty_ground_space: int = state.get_empty_space()
			if cell.terrain_base == GameTypes.TerrainBase.WATER:
				empty_ground_space = 0
			empty_space_label.text = "Empty ground space: " + NumberFormatter.format_int(empty_ground_space)
		else:
			stone_number_label.text = "Stone: -"
			grass_number_label.text = "Grass: -"
			shrub_number_label.text = "Shrub: -"
			tree_number_label.text = "Trees: -"
			empty_space_label.text = "Empty ground space: -"

	# Il tab Fauna mostra dati world-level (population_groups + aggregato FISH), indipendenti
	# dalla cella selezionata: si rinfresca solo se è già la tab attiva mentre la selezione
	# cambia (es. un giorno avanza mentre l'utente lo sta guardando), mai ad ogni show_cell a
	# prescindere — vedi _on_tab_changed per il rinfresco all'apertura del tab stesso.
	if tab_container.current_tab == TAB_FAUNA:
		_refresh_fauna_tab()


func clear(show_resources: bool = true) -> void:
	title_label.text = "Macro cell"
	coords_label.text = "Coords: -"
	geography_info.clear()
	_set_resources_visible(show_resources)
	_set_extra_tabs_hidden(not show_resources)
	if show_resources:
		stone_number_label.text = "Stone: -"
		grass_number_label.text = "Grass: -"
		shrub_number_label.text = "Shrub: -"
		tree_number_label.text = "Trees: -"
		empty_space_label.text = "Empty ground space: -"


func _set_resources_visible(value: bool) -> void:
	space_label.visible = value
	stone_number_label.visible = value
	grass_number_label.visible = value
	shrub_number_label.visible = value
	tree_number_label.visible = value
	resource_separator_label.visible = value
	empty_space_label.visible = value


# Map editor (show_resources=false) non ha simulazione né fauna: le tab world-level non hanno
# senso lì, stesso ruolo che aveva _set_resources_visible sui vecchi label piatti prima delle tab.
func _set_extra_tabs_hidden(hidden: bool) -> void:
	tab_container.set_tab_hidden(TAB_VEGETAZIONE, hidden)
	tab_container.set_tab_hidden(TAB_RISORSE, hidden)
	tab_container.set_tab_hidden(TAB_FAUNA, hidden)


func _on_tab_changed(tab_idx: int) -> void:
	if tab_idx == TAB_FAUNA:
		_refresh_fauna_tab()


# Contenuto world-level, non legato alla cella selezionata: rinfrescato solo all'apertura del
# tab (vedi _on_tab_changed) o mentre resta quello attivo (vedi show_cell) — mai ad ogni giorno
# simulato a prescindere, dato che l'aggregazione FISH sotto itera l'intero world.cells (100x100).
func _refresh_fauna_tab() -> void:
	_update_population_groups(_world)
	_update_fish_summary(_world)


# Elenco piatto di tutti i PopulationGroup del world (oggi solo rabbit), non filtrato per cella
# — a differenza di MacroCellDetailPanel._update_animal_population_rows, che mostra solo i
# gruppi della cella aperta. Un identificativo progressivo (#1, #2...) invece del nome specie
# come chiave di riga, dato che in futuro più gruppi della stessa specie potranno coesistere
# (branchi diversi nella stessa specie, vedi Territory pianificato).
func _update_population_groups(world: World) -> void:
	for child in population_groups_container.get_children():
		child.queue_free()

	if world == null or world.population_groups.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		population_groups_container.add_child(empty_label)
		return

	for i in range(world.population_groups.size()):
		var group := world.population_groups[i]
		# occupied_macrocells ha oggi sempre un solo elemento (vedi Territory): mostriamo solo
		# quella cella, stesso comportamento visibile di prima.
		var home_cell := group.territory.get_primary_cell()
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		label.text = "#%d - %s: %s - %s (%d,%d)" % [
			i + 1,
			group.species_name,
			NumberFormatter.format_int(group.population),
			tr("cell"),
			home_cell.x,
			home_cell.y
		]
		population_groups_container.add_child(label)


# Tipi di corpo d'acqua su cui FISH può crescere (vedi FaunaGrowthService/FishPositionService):
# stessa distinzione già usata da MapEditorController per i pennelli SEA/LAKE/RIVER, nessun
# campo nuovo introdotto.
const _FISH_WATER_TYPES := [
	GameTypes.WaterType.SEA,
	GameTypes.WaterType.LAKE,
	GameTypes.WaterType.RIVER,
]

# "Celle occupate" = celle con water_space[FISH] > 0 (stesso segnale di occupazione usato da
# FaunaGrowthService/FaunaMortalityService), non ogni cella d'acqua di quel tipo sulla mappa —
# una cella SEA senza fish non conta come "occupata" qui.
func _update_fish_summary(world: World) -> void:
	for child in fish_summary_container.get_children():
		child.queue_free()

	if world == null:
		return

	var totals: Dictionary = {}
	for water_type in _FISH_WATER_TYPES:
		totals[water_type] = {"quantity": 0, "cells": 0}

	for cell in world.cells:
		if not totals.has(cell.water_type):
			continue
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		var fish_space := state.get_water_space(GameTypes.WorldObjectType.FISH)
		if fish_space <= 0:
			continue
		var entry: Dictionary = totals[cell.water_type]
		entry["quantity"] += state.get_resource_quantity(GameTypes.WorldObjectType.FISH)
		entry["cells"] += 1

	_add_fish_summary_row(tr("sea"), totals[GameTypes.WaterType.SEA])
	_add_fish_summary_row(tr("lake"), totals[GameTypes.WaterType.LAKE])
	_add_fish_summary_row(tr("river"), totals[GameTypes.WaterType.RIVER])


func _add_fish_summary_row(label_text: String, totals: Dictionary) -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.text = "%s: %s %s %s %s %s" % [
		label_text,
		NumberFormatter.format_int(totals["quantity"]),
		tr("fish"),
		tr("in"),
		NumberFormatter.format_int(totals["cells"]),
		tr("cells")
	]
	fish_summary_container.add_child(label)
