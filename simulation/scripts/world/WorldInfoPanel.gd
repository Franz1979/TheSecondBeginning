class_name WorldInfoPanel
extends PanelContainer

# Copia di MacroCellInfoPanel (scripts/world/MacroCellInfoPanel.gd), biforcata per WorldScene —
# le due viste sono divergenti da tempo (questa porta filtro specie/evidenziazione territori
# world-level che MapEditorScene non ha mai usato) e MacroCellInfoPanel.show_resources=false in
# MapEditorScene nascondeva già di fatto tutto tranne Geografia, quindi il nome "cella macro" non
# descriveva più bene cosa mostra questo pannello in WorldScene (mix dati-cella + dati-mondo).
# MacroCellInfoPanel resta il pannello INVARIATO per MapEditorScene (sempre e solo una cella:
# nessun mix, nome ancora accurato lì). Duplicazione deliberata, non un refactor condiviso:
# eventuali fix genuinamente comuni (es. nell'integrazione con CellGeographyInfo) vanno applicati
# in entrambi i file.

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
const TAB_RISORSE := 2
# Fauna "passiva" (FISH): cresce e cala in MacroCellState per densità. Le mandrie non sono dati del mondo.
const TAB_FAUNA_1 := 3

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var geography_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/SectionTitleLabel
# Coordinate della cella selezionata, spostate qui (dentro Geografia) invece che in testa al
# pannello come nel MacroCellInfoPanel originale: in WorldScene le tab Fauna 1/2 mostrano dati
# world-level indipendenti dalla cella selezionata (vedi show_cell sotto), quindi delle
# coordinate sempre visibili in testa risulterebbero fuorvianti quando l'utente è su quelle tab.
# Restano invece sempre corrette qui, dato che Geografia (insieme ai numeri risorsa sotto,
# ancora non spostati in Vegetazione/Risorse) è genuinamente sempre sulla cella selezionata.
@onready var coords_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/CoordsLabel
@onready var geography_info: CellGeographyInfo = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/CellGeographyInfo
@onready var space_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/SpaceLabel
@onready var stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/StoneNumberLabel
@onready var grass_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/GrassNumberLabel
@onready var shrub_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/ShrubNumberLabel
@onready var tree_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/TreeNumberLabel
@onready var resource_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/ResourceSeparatorLabel
@onready var empty_space_label: Label = $MarginContainer/VBoxContainer/TabContainer/GeografiaTab/GeografiaContent/EmptySpaceLabel
@onready var vegetation_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/SectionTitleLabel
# Totali MONDO (somma su tutti i world.cells), a differenza degli omonimi senza prefisso "veg_"
# sopra (grass_number_label ecc.) che restano sulla sola cella selezionata in Geografia — nomi
# di variabile distinti obbligatori: stesso nome di nodo ("GrassNumberLabel" ecc.) ma genitore
# diverso (VegetazioneContent invece di GeografiaContent), quindi @onready avrebbe comunque
# bisogno di identificatori Python-side univoci anche se i node name coincidessero per caso.
@onready var veg_grass_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/GrassNumberLabel
@onready var veg_shrub_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/ShrubNumberLabel
@onready var veg_tree_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/TreeNumberLabel
@onready var veg_perishables_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/PerishablesSeparatorLabel
@onready var veg_perishables_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/PerishablesTitleLabel
@onready var veg_acorn_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/AcornNumberLabel
@onready var veg_fruit_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/FruitNumberLabel
@onready var veg_berry_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/BerryNumberLabel
@onready var resources_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/RisorseTab/RisorseContent/SectionTitleLabel
# Totale mondo, stesso principio dei veg_* sopra.
@onready var res_stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/RisorseTab/RisorseContent/StoneNumberLabel
@onready var fauna_1_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/SectionTitleLabel
@onready var fish_summary_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/FishSummaryContainer
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer

# Riferimento world tenuto solo per rinfrescare il tab Fauna (contenuto world-level, indipendente
# dalla cella selezionata) da _on_tab_changed, che non riceve altrimenti alcun parametro.
var _world: World = null

# Le tab mostrano solo un simbolo (nessun tr(): non è testo, è un'icona testuale, indipendente
# dalla lingua) — il nome leggibile della sezione compare come tooltip sulla tab e come titolo
# in cima al contenuto quando è aperta, stesso schema di MacroCellDetailPanel.
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
	# Pickaxe con variation selector (⛏️) è visibilmente più larga delle emoji a singolo
	# codepoint delle altre tab (il VS16 forza la presentazione "emoji" a piena larghezza in molti
	# font) — sostituita con 🪨 (roccia, singolo codepoint, stesso tema "risorse minerarie").
	tab_container.set_tab_title(TAB_RISORSE, "🪨")
	tab_container.set_tab_title(TAB_FAUNA_1, "🐟")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.add_theme_constant_override("h_separation", 0)
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_RISORSE, tr("tab_resources"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_1, tr("tab_fauna_1"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	resources_title_label.text = tr("tab_resources")
	fauna_1_title_label.text = tr("tab_fauna_1")

	tab_container.tab_changed.connect(_on_tab_changed)

	clear()


func show_cell(cell: MacroCellData, state: MacroCellState, world: World, show_resources: bool = true) -> void:
	_world = world
	_set_extra_tabs_hidden(not show_resources)

	if cell == null:
		clear(show_resources)
		return
	title_label.text = "World Data:"
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

	# Le cinque tab world-level (Vegetazione/Risorse/Fauna1/Fauna2/Fauna3) mostrano dati aggregati
	# sull'intero world, indipendenti dalla cella selezionata: si rinfrescano solo se una di
	# esse è già quella attiva mentre la selezione cambia (es. un giorno avanza mentre l'utente
	# la sta guardando), mai ad ogni show_cell a prescindere — vedi _on_tab_changed per il
	# rinfresco all'apertura.
	refresh_world_tabs_if_active()


func clear(show_resources: bool = true) -> void:
	title_label.text = "World Data:"
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


func _on_tab_changed(_tab_idx: int) -> void:
	refresh_world_tabs_if_active()


# Rinfresca la tab world-level attualmente aperta (Vegetazione/Risorse/Fauna1/Fauna2/Fauna3), se
# una di queste lo è — punto d'ingresso unico usato sia da show_cell/_on_tab_changed (qui sotto) sia
# dal chiamante esterno (WorldScene._on_day_advanced) per il caso in cui il mondo avanza SENZA che
# l'utente abbia una cella selezionata: queste tab mostrano dati aggregati sull'intero world,
# indipendenti dalla selezione, quindi non devono aspettare un click su una cella per rinfrescarsi.
# Rinominata da refresh_fauna_tabs_if_active (nome non più accurato da quando Vegetazione/Risorse
# hanno guadagnato contenuto reale, anch'esso world-level) — WorldScene.gd aggiornato di conseguenza.
func refresh_world_tabs_if_active() -> void:
	if tab_container.current_tab == TAB_VEGETAZIONE:
		_refresh_vegetazione_tab()
	elif tab_container.current_tab == TAB_RISORSE:
		_refresh_risorse_tab()
	elif tab_container.current_tab == TAB_FAUNA_1:
		_refresh_fauna_1_tab()


# Totali mondo (somma su ogni world.cells, stessa iterazione 100x100 già usata da
# _update_fish_summary sotto) per le tre risorse vegetali rinnovabili, più
# una sezione separata per i loro sottoprodotti deperibili (acorn/fruit/berry — derivati da
# sottotipi di TREE/SHRUB, stock persistente per cella via
# MacroCellState.secondary_resource_stock, vedi CaloricCalculator.update_secondary_resource_stock:
# già aggiornato realmente ad ogni checkpoint stagionale, non un placeholder). Le uova dal 2026-11-07 sono lotti
# sull'erba senza scorta della macrocella: niente totale qui.
func _refresh_vegetazione_tab() -> void:
	if _world == null:
		veg_grass_number_label.text = "Grass: -"
		veg_shrub_number_label.text = "Shrub: -"
		veg_tree_number_label.text = "Trees: -"
		veg_acorn_number_label.text = "Acorn: -"
		veg_fruit_number_label.text = "Fruit: -"
		veg_berry_number_label.text = "Berry: -"
		return

	var grass_quantity := 0
	var grass_cells := 0
	var shrub_quantity := 0
	var shrub_cells := 0
	var tree_quantity := 0
	var tree_cells := 0
	var acorn_stock := 0.0
	var fruit_stock := 0.0
	var berry_stock := 0.0

	for cell in _world.cells:
		var state := _world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue

		var cell_grass := state.get_resource_quantity(GameTypes.WorldObjectType.GRASS)
		grass_quantity += cell_grass
		if state.get_dedicated_space(GameTypes.WorldObjectType.GRASS) > 0:
			grass_cells += 1

		var cell_shrub := state.get_resource_quantity(GameTypes.WorldObjectType.SHRUB)
		shrub_quantity += cell_shrub
		if state.get_dedicated_space(GameTypes.WorldObjectType.SHRUB) > 0:
			shrub_cells += 1

		var cell_tree := state.get_resource_quantity(GameTypes.WorldObjectType.TREE)
		tree_quantity += cell_tree
		if state.get_dedicated_space(GameTypes.WorldObjectType.TREE) > 0:
			tree_cells += 1

		acorn_stock += state.get_secondary_resource_stock("acorn")
		fruit_stock += state.get_secondary_resource_stock("fruit")
		berry_stock += state.get_secondary_resource_stock("berry")

	# "%s in %s cells" invece di "(occupied cells: %s)" — stesso formato compatto già usato da
	# _add_fish_summary_row sotto (tab Fauna 1): con totali mondo (fino a 10000 celle) la forma
	# lunga occupava troppo spazio orizzontale.
	veg_grass_number_label.text = "Grass: %s %s %s %s" % [NumberFormatter.format_int(grass_quantity), tr("in"), NumberFormatter.format_int(grass_cells), tr("cells")]
	veg_shrub_number_label.text = "Shrub: %s %s %s %s" % [NumberFormatter.format_int(shrub_quantity), tr("in"), NumberFormatter.format_int(shrub_cells), tr("cells")]
	veg_tree_number_label.text = "Trees: %s %s %s %s" % [NumberFormatter.format_int(tree_quantity), tr("in"), NumberFormatter.format_int(tree_cells), tr("cells")]
	veg_perishables_separator_label.text = " - - - - - - - - - -"
	veg_perishables_title_label.text = "Perishables:"
	veg_acorn_number_label.text = "Acorn: " + NumberFormatter.format_int(int(round(acorn_stock)))
	veg_fruit_number_label.text = "Fruit: " + NumberFormatter.format_int(int(round(fruit_stock)))
	veg_berry_number_label.text = "Berry: " + NumberFormatter.format_int(int(round(berry_stock)))



# Stone (ROCK), oggi l'unica risorsa minerale — spazio pronto per oil/coal/argilla quando
# arriveranno (stessa formula, un'altra coppia di variabili quantity/cells). Stessa iterazione
# world.cells di _refresh_vegetazione_tab sopra.
func _refresh_risorse_tab() -> void:
	if _world == null:
		res_stone_number_label.text = "Stone: -"
		return

	var stone_quantity := 0
	var stone_cells := 0

	for cell in _world.cells:
		var state := _world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		stone_quantity += state.get_resource_quantity(GameTypes.WorldObjectType.ROCK)
		if state.get_dedicated_space(GameTypes.WorldObjectType.ROCK) > 0:
			stone_cells += 1

	# Stesso formato compatto di _refresh_vegetazione_tab sopra, stesso motivo.
	res_stone_number_label.text = "Stone: %s %s %s %s" % [NumberFormatter.format_int(stone_quantity), tr("in"), NumberFormatter.format_int(stone_cells), tr("cells")]


# Contenuto world-level, non legato alla cella selezionata: rinfrescato solo all'apertura del
# tab (vedi _on_tab_changed) o mentre resta quello attivo (vedi show_cell) — mai ad ogni giorno
# simulato a prescindere, dato che l'aggregazione FISH sotto itera l'intero world.cells (100x100).
func _refresh_fauna_1_tab() -> void:
	_update_fish_summary(_world)


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
