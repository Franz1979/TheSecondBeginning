class_name MacroCellInfoPanel
extends PanelContainer

# Emesso quando l'utente clicca la riga di un PopulationGroup nella tab Fauna (2) — il chiamante
# (GameScene) ascolta per evidenziare sulla mappa le celle del territorio del gruppo (vedi
# WorldRenderer.flash_cells). cells è un Array[Vector2i] (territory.occupied_macrocells).
signal population_group_highlight_requested(cells: Array)

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
const TAB_RISORSE := 2
# Fauna è divisa in due tab (a richiesta dell'utente): FAUNA_1 per la fauna "passiva", che si
# comporta come vegetazione — cresce/decresce in MacroCellState per densità, nessun comportamento
# proprio (oggi solo FISH, in futuro BIRDS); FAUNA_2 per la fauna "vera", con comportamento e
# stato proprio via PopulationGroup (rabbit, deer, ...). Prima dello split erano un'unica tab.
const TAB_FAUNA_1 := 3
const TAB_FAUNA_2 := 4

const COLOR_LOCATE_BUTTON := Color(0.2, 0.55, 0.95) # bottone "⌖" evidenzia-sulla-mappa, blu "locate"

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
@onready var fauna_1_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/SectionTitleLabel
@onready var fish_summary_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/FishSummaryContainer
@onready var fauna_2_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/SectionTitleLabel
@onready var population_groups_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/PopulationGroupsContainer
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
	tab_container.set_tab_title(TAB_FAUNA_1, "🐟")
	tab_container.set_tab_title(TAB_FAUNA_2, "🦌")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_RISORSE, tr("tab_resources"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_1, tr("tab_fauna_1"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_2, tr("tab_fauna_2"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	resources_title_label.text = tr("tab_resources")
	fauna_1_title_label.text = tr("tab_fauna_1")
	fauna_2_title_label.text = tr("tab_fauna_2")

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

	# Le due tab Fauna mostrano dati world-level (aggregato FISH / population_groups),
	# indipendenti dalla cella selezionata: si rinfrescano solo se una delle due è già quella
	# attiva mentre la selezione cambia (es. un giorno avanza mentre l'utente la sta guardando),
	# mai ad ogni show_cell a prescindere — vedi _on_tab_changed per il rinfresco all'apertura.
	refresh_fauna_tabs_if_active()


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
	tab_container.set_tab_hidden(TAB_FAUNA_1, hidden)
	tab_container.set_tab_hidden(TAB_FAUNA_2, hidden)


func _on_tab_changed(_tab_idx: int) -> void:
	refresh_fauna_tabs_if_active()


# Rinfresca la tab Fauna (1 o 2) attualmente aperta, se una delle due lo è — punto d'ingresso
# unico usato sia da show_cell/_on_tab_changed (qui sotto) sia dal chiamante esterno
# (GameScene._on_day_advanced) per il caso in cui il mondo avanza SENZA che l'utente abbia una
# cella selezionata: le tab Fauna sono dati world-level, indipendenti dalla selezione, quindi non
# devono aspettare un click su una cella per rinfrescarsi.
func refresh_fauna_tabs_if_active() -> void:
	if tab_container.current_tab == TAB_FAUNA_1:
		_refresh_fauna_1_tab()
	elif tab_container.current_tab == TAB_FAUNA_2:
		_refresh_fauna_2_tab()


# Contenuto world-level, non legato alla cella selezionata: rinfrescato solo all'apertura del
# tab (vedi _on_tab_changed) o mentre resta quello attivo (vedi show_cell) — mai ad ogni giorno
# simulato a prescindere, dato che l'aggregazione FISH sotto itera l'intero world.cells (100x100).
func _refresh_fauna_1_tab() -> void:
	_update_fish_summary(_world)


func _refresh_fauna_2_tab() -> void:
	_update_population_groups(_world)


func _on_population_group_row_pressed(cells: Array) -> void:
	population_group_highlight_requested.emit(cells)


# Elenco piatto di tutti i PopulationGroup del world (oggi rabbit e deer, più gruppi della stessa
# specie in celle diverse possono coesistere — vedi GameScene debug buttons), non filtrato per
# cella — a differenza di MacroCellDetailPanel._update_animal_population_rows, che mostra solo i
# gruppi della cella aperta. L'identificativo di riga è group.id (assegnato una volta alla
# creazione, vedi World.allocate_population_group_id), NON un indice ricalcolato qui: resta
# stabile per tutta la vita del gruppo e coincide con quello usato nei log animali (Animal*Service),
# così le due fonti sono sempre coerenti. Conseguenza attesa: se un gruppo si estingue, la lista
# mostra un "buco" nella numerazione invece di rinumerare i successivi.
func _update_population_groups(world: World) -> void:
	for child in population_groups_container.get_children():
		child.queue_free()

	if world == null or world.population_groups.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		population_groups_container.add_child(empty_label)
		return

	var any_displayed := false
	for group in world.population_groups:
		if group.population <= 0:
			continue
		any_displayed = true

		# Elenco piatto: sempre "in N cells" (mai le coordinate esatte, nemmeno con 1 sola cella
		# come rabbit) — coerenza di formato tra tutte le specie voluta esplicitamente dall'utente,
		# anche se con 1 cella sola si potrebbe mostrare la posizione precisa. "in N cell(s)"
		# hardcoded, non tr(): stesso trattamento dei connettivi/testo di raccordo già hardcoded
		# altrove in questo pannello — nessuna CSV di traduzione esiste ancora (vedi CLAUDE.md).
		var cell_count := group.territory.get_cell_count()
		var cell_descriptor: String = "in %d cell" % cell_count
		if cell_count != 1:
			cell_descriptor += "s"

		# Riga = Label (non cliccabile, testo identico a prima) + piccolo bottone "mirino" a
		# fianco per evidenziare sulla mappa le celle del territorio (vedi WorldRenderer.
		# flash_cells) — l'intera riga cliccabile (versione precedente) non comunicava che fosse
		# interattiva, dato che appariva identica a tutte le altre righe non cliccabili del
		# pannello; un'icona dedicata è un affordance esplicito.
		var row_container := HBoxContainer.new()
		population_groups_container.add_child(row_container)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.text = "#%d - %s: %s - %s" % [
			group.id,
			group.species_name,
			NumberFormatter.format_int(group.population),
			cell_descriptor
		]
		row_container.add_child(label)

		var locate_button := Button.new()
		locate_button.flat = true
		locate_button.text = "⌖"
		locate_button.tooltip_text = "Highlight cells on map"
		locate_button.custom_minimum_size = Vector2(28, 0)
		locate_button.add_theme_font_size_override("font_size", 18)
		locate_button.add_theme_color_override("font_color", COLOR_LOCATE_BUTTON)
		locate_button.add_theme_color_override("font_hover_color", COLOR_LOCATE_BUTTON.lightened(0.3))
		locate_button.pressed.connect(_on_population_group_row_pressed.bind(group.territory.occupied_macrocells))
		row_container.add_child(locate_button)

		# Ripartizione età SOLO se la specie la traccia (AnimalRules.track_age_bands) — stesso
		# formato testuale già usato da MacroCellDetailPanel, ma qui sui totali dell'INTERO gruppo
		# (elenco piatto, non per-cella): coerente con "%s" sopra che mostra group.population, non
		# una quota.
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules != null and rules.track_age_bands:
			var young := group.get_age_count(GameTypes.AgeBand.YOUNG)
			var adult := group.get_age_count(GameTypes.AgeBand.ADULT)
			var old := group.get_age_count(GameTypes.AgeBand.OLD)

			var age_label := Label.new()
			age_label.add_theme_font_size_override("font_size", 10)
			age_label.text = "      (Y:%s - A:%s - O:%s)" % [
				NumberFormatter.format_int(young),
				NumberFormatter.format_int(adult),
				NumberFormatter.format_int(old)
			]
			population_groups_container.add_child(age_label)

	if not any_displayed:
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		population_groups_container.add_child(empty_label)


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
