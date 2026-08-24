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

# Emesso quando l'utente clicca la riga di un PopulationGroup nella tab Fauna (2) — il chiamante
# (WorldScene) ascolta per evidenziare sulla mappa le celle del territorio del gruppo (vedi
# WorldRenderer.flash_cells). cells è un Array[Vector2i] (territory.occupied_macrocells).
signal population_group_highlight_requested(cells: Array)

# Emesso dal pulsante "Mostra tutti" (solo quando il filtro specie è su una specie specifica, vedi
# _add_species_summary_row) — il chiamante (WorldScene) ascolta per evidenziare CONTEMPORANEAMENTE
# sulla mappa i territori di tutti i gruppi di quella specie (vedi WorldRenderer.
# highlight_group_territories). entries è un Array di Dictionary {"cells": Array[Vector2i],
# "color": Color, "label_text": String, "label_cell": Vector2i} — forma diversa dal segnale sopra
# (multi-territorio, colore/etichetta per voce), quindi un segnale a parte invece di riusare
# population_group_highlight_requested con un payload più ricco.
signal population_species_highlight_requested(entries: Array)

const TAB_GEOGRAFIA := 0
const TAB_VEGETAZIONE := 1
const TAB_RISORSE := 2
# Fauna è divisa in tre tab (a richiesta dell'utente): FAUNA_1 per la fauna "passiva", che si
# comporta come vegetazione — cresce/decresce in MacroCellState per densità, nessun comportamento
# proprio (oggi solo FISH, in futuro BIRDS); FAUNA_2 per gli erbivori "veri", con comportamento e
# stato proprio via PopulationGroup (rabbit, deer, ...); FAUNA_3 per i PREDATORI (PredatorRules,
# oggi wolf) — separata da FAUNA_2 perché i branchi predatori hanno dati specifici che gli
# erbivori non hanno (finestra di pattugliamento, cronologia di caccia, bookkeeping calorico) e
# mostrarli mischiati nell'elenco generico di FAUNA_2 non avrebbe senso. Prima dello split
# FAUNA_1/2 erano un'unica tab.
const TAB_FAUNA_1 := 3
const TAB_FAUNA_2 := 4
const TAB_FAUNA_3 := 5

const COLOR_LOCATE_BUTTON := Color(0.2, 0.55, 0.95) # bottone "⌖" evidenzia-sulla-mappa, blu "locate"

# Riga filtro specie (tab Fauna 2, vedi _rebuild_species_filter_row): dimensioni ridotte al
# minimo leggibile — sono selettori, non il contenuto principale della tab, non devono competere
# in ingombro con l'elenco dei gruppi sotto.
const FILTER_BUTTON_SIZE := Vector2(22, 20)
const FILTER_ICON_SIZE := Vector2(14, 14)

# Vista "Mostra tutti i territori" (solo con filtro specie attivo, vedi _add_species_summary_row/
# _on_show_all_territories_pressed) — più lunga di WorldScene.POPULATION_HIGHLIGHT_DURATION (2.0s,
# singolo gruppo): con più territori insieme serve più tempo per osservarli tutti.
const SPECIES_TERRITORY_HIGHLIGHT_DURATION: float = 3.0
# Alpha del riempimento colorato di ciascun territorio nella vista "Mostra tutti" — abbastanza
# trasparente da lasciar leggere il terreno sottostante, ma netto a sufficienza da distinguere i
# gruppi tra loro.
const SPECIES_TERRITORY_OVERLAY_ALPHA: float = 0.6
# Variazione HSV per gruppo (vedi _get_group_variant_color): hue solo un piccolo scarto (mai
# libero su tutto il cerchio) così il colore resta riconoscibile come "quella specie", value/
# saturation invece variano di più (step "golden ratio" per la massima distinguibilità anche con
# molti gruppi, senza cluster di colori simili).
const GROUP_COLOR_HUE_JITTER_RANGE: float = 0.15
const GROUP_COLOR_VALUE_RANGE := Vector2(0.65, 1.15)
const GROUP_COLOR_SATURATION_RANGE := Vector2(0.8, 1.2)
const GOLDEN_RATIO_CONJUGATE: float = 0.6180339887498949

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
@onready var veg_eggs_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/VegetazioneTab/VegetazioneContent/EggsNumberLabel
@onready var resources_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/RisorseTab/RisorseContent/SectionTitleLabel
# Totale mondo, stesso principio dei veg_* sopra.
@onready var res_stone_number_label: Label = $MarginContainer/VBoxContainer/TabContainer/RisorseTab/RisorseContent/StoneNumberLabel
@onready var fauna_1_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/SectionTitleLabel
@onready var fish_summary_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/FishSummaryContainer
@onready var birds_separator_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/BirdsSeparatorLabel
@onready var birds_summary_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab1/FaunaContent/BirdsSummaryLabel
@onready var fauna_2_title_row: HBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/FaunaTitleRow
@onready var fauna_2_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/FaunaTitleRow/SectionTitleLabel
# HFlowContainer (non HBoxContainer): va a capo su più righe quando i bottoni specie non ci
# stanno più su una riga sola, invece di continuare a crescere in larghezza — con HBoxContainer
# la riga cresceva senza limiti e finiva per allargare l'intero pannello (che deve restare a
# larghezza fissa) ogni volta che si aggiungeva una nuova specie animale.
@onready var species_filter_container: HFlowContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/SpeciesFilterContainer
@onready var population_groups_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab2/FaunaContent/PopulationGroupsContainer
@onready var fauna_3_title_label: Label = $MarginContainer/VBoxContainer/TabContainer/FaunaTab3/FaunaContent/SectionTitleLabel
@onready var predator_groups_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/FaunaTab3/FaunaContent/PredatorGroupsContainer
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer

# Riferimento world tenuto solo per rinfrescare il tab Fauna (contenuto world-level, indipendente
# dalla cella selezionata) da _on_tab_changed, che non riceve altrimenti alcun parametro.
var _world: World = null

# Filtro specie del tab Fauna 2 (riga di pulsanti sopra population_groups_container) — stringa
# vuota = "Tutti" (nessun filtro, comportamento di sempre), altrimenti species_name esatto. Si
# resetta a "" ogni volta che la tab Fauna 2 torna quella attiva (vedi _on_tab_changed), MAI
# durante un refresh mentre resta già aperta (es. l'utente clicca un'altra cella sulla mappa) —
# altrimenti perderebbe la selezione dell'utente ad ogni click sulla mappa invece che solo quando
# "riapre" davvero la tab.
var _fauna_species_filter: String = ""

# Stato aperto/chiuso di ciascuna riga di riepilogo specie (Caso 1, filtro="Tutti" — vedi
# _add_species_summary_row/_on_species_expand_toggled): species_name -> bool, chiave assente =
# chiusa (default). A differenza di _fauna_species_filter sopra, NON viene mai azzerato da
# _on_tab_changed — persiste per tutta la vita di questa istanza del pannello (l'intera sessione
# di gioco così come oggi la si intende: sopravvive a cambio cella/tab/avanzamento anni, non a un
# reload completo della scena, che ricrea comunque da zero l'intero pannello — stesso limite già
# esistente per ogni altro stato di questo pannello, non specifico di questa funzionalità).
var _fauna_species_expanded: Dictionary = {}


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
	tab_container.set_tab_title(TAB_FAUNA_2, "🦌")
	tab_container.set_tab_title(TAB_FAUNA_3, "🐺")

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.add_theme_constant_override("h_separation", 0)
	tab_bar.set_tab_tooltip(TAB_GEOGRAFIA, tr("tab_geography"))
	tab_bar.set_tab_tooltip(TAB_VEGETAZIONE, tr("tab_vegetation"))
	tab_bar.set_tab_tooltip(TAB_RISORSE, tr("tab_resources"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_1, tr("tab_fauna_1"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_2, tr("tab_fauna_2"))
	tab_bar.set_tab_tooltip(TAB_FAUNA_3, tr("tab_fauna_3"))

	geography_title_label.text = tr("tab_geography")
	vegetation_title_label.text = tr("tab_vegetation")
	resources_title_label.text = tr("tab_resources")
	fauna_1_title_label.text = tr("tab_fauna_1")
	fauna_2_title_label.text = tr("tab_fauna_2")
	fauna_3_title_label.text = tr("tab_fauna_3")

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
	tab_container.set_tab_hidden(TAB_FAUNA_2, hidden)
	tab_container.set_tab_hidden(TAB_FAUNA_3, hidden)


func _on_tab_changed(tab_idx: int) -> void:
	# Riapertura della tab Fauna 2 (non un refresh mentre resta già quella attiva, vedi
	# _fauna_species_filter sopra): il filtro torna sempre a "Tutti", nessuna persistenza tra
	# un'apertura e l'altra.
	if tab_idx == TAB_FAUNA_2:
		_fauna_species_filter = ""
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
	elif tab_container.current_tab == TAB_FAUNA_2:
		_refresh_fauna_2_tab()
	elif tab_container.current_tab == TAB_FAUNA_3:
		_refresh_fauna_3_tab()


# Totali mondo (somma su ogni world.cells, stessa iterazione 100x100 già usata da
# _update_fish_summary/_update_birds_summary sotto) per le tre risorse vegetali rinnovabili, più
# una sezione separata per i loro sottoprodotti deperibili (acorn/fruit/berry/eggs — derivati da
# sottotipi di TREE/SHRUB/BIRDS, stock persistente per cella via
# MacroCellState.secondary_resource_stock, vedi CaloricCalculator.update_secondary_resource_stock:
# già aggiornato realmente ad ogni checkpoint stagionale, non un placeholder). "eggs" era escluso
# in una versione precedente (nessun produttore reale, BIRDS non ancora implementato) — BIRDS
# esiste da tempo ormai, quindi eggs è trattato qui esattamente come acorn/fruit/berry, stesso
# meccanismo generico.
func _refresh_vegetazione_tab() -> void:
	if _world == null:
		veg_grass_number_label.text = "Grass: -"
		veg_shrub_number_label.text = "Shrub: -"
		veg_tree_number_label.text = "Trees: -"
		veg_acorn_number_label.text = "Acorn: -"
		veg_fruit_number_label.text = "Fruit: -"
		veg_berry_number_label.text = "Berry: -"
		veg_eggs_number_label.text = "Eggs: -"
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
	var eggs_stock := 0.0

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
		eggs_stock += state.get_secondary_resource_stock("eggs")

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
	veg_eggs_number_label.text = "Eggs: " + NumberFormatter.format_int(int(round(eggs_stock)))


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
	_update_birds_summary(_world)


func _refresh_fauna_2_tab() -> void:
	_update_population_groups(_world)


func _refresh_fauna_3_tab() -> void:
	_update_predator_groups(_world)


# Unico punto che distingue erbivori da predatori in questo pannello (usato sia da
# _update_population_groups/_rebuild_species_filter_row per ESCLUDERE i predatori da Fauna 2, sia
# da _update_predator_groups per INCLUDERLI in Fauna 3) — stesso downcast già usato ovunque nel
# codebase (PredationService, AnimalConsumptionService, ...) per distinguere le due famiglie.
func _is_predator_species(species_name: String) -> bool:
	var rules := AnimalCalculator.get_animal_rules(species_name)
	return rules is PredatorRules


func _on_population_group_row_pressed(cells: Array) -> void:
	population_group_highlight_requested.emit(cells)


# Elenco piatto di tutti i PopulationGroup del world (oggi rabbit e deer, più gruppi della stessa
# specie in celle diverse possono coesistere — vedi WorldScene debug buttons), non filtrato per
# cella — a differenza di MacroCellDetailPanel._update_animal_population_rows, che mostra solo i
# gruppi della cella aperta. L'identificativo di riga è group.id (assegnato una volta alla
# creazione, vedi World.allocate_population_group_id), NON un indice ricalcolato qui: resta
# stabile per tutta la vita del gruppo e coincide con quello usato nei log animali (Animal*Service),
# così le due fonti sono sempre coerenti. Conseguenza attesa: se un gruppo si estingue, la lista
# mostra un "buco" nella numerazione invece di rinumerare i successivi.
func _update_population_groups(world: World) -> void:
	_rebuild_species_filter_row(world)

	for child in population_groups_container.get_children():
		child.queue_free()

	if world == null or world.population_groups.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		population_groups_container.add_child(empty_label)
		return

	# Raggruppati per specie PRIMA di disegnare (non più un elenco piatto diretto): serve sia per
	# la riga di riepilogo aggregata sia per decidere quali dettagli mostrare sotto — vedi
	# _add_species_summary_row/_add_population_group_detail_row sotto. Con _fauna_species_filter
	# attivo (Caso 2) questo dizionario ha per costruzione una sola chiave: il filtro ha già
	# escluso ogni altra specie qui sopra.
	var groups_by_species: Dictionary = {} # species_name -> Array[PopulationGroup]
	for group in world.population_groups:
		if group.population <= 0:
			continue
		# I predatori (PredatorRules) hanno la propria tab dedicata (Fauna 3, vedi
		# _update_predator_groups) - esclusi qui per non comparire due volte.
		if _is_predator_species(group.species_name):
			continue
		if _fauna_species_filter != "" and group.species_name != _fauna_species_filter:
			continue
		if not groups_by_species.has(group.species_name):
			groups_by_species[group.species_name] = []
		groups_by_species[group.species_name].append(group)

	if groups_by_species.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		population_groups_container.add_child(empty_label)
		return

	var species_names: Array = groups_by_species.keys()
	species_names.sort()

	for species_name in species_names:
		var species_groups: Array = groups_by_species[species_name]
		# Caso 1 (filtro="Tutti"): riepilogo con +/-, dettagli visibili solo se espansa. Caso 2
		# (filtro su una specie): riepilogo SENZA +/-, dettagli sempre visibili (implicitamente
		# "sempre aperta" — sotto c'è comunque solo quella specie).
		var show_toggle: bool = _fauna_species_filter == ""
		var expanded: bool = (not show_toggle) or _fauna_species_expanded.get(species_name, false)

		_add_species_summary_row(species_name, species_groups, show_toggle, expanded)

		if expanded:
			for group in species_groups:
				_add_population_group_detail_row(group)


# Riga aggregata "{specie} — {N} popolazioni, {pop totale} individui, {celle totali} celle" —
# somma_celle è la somma di territory.get_cell_count() di ogni gruppo della specie, sicura senza
# doppi conteggi dato che due gruppi della stessa specie non hanno mai celle sovrapposte per
# costruzione (esclusione stessa specie già garantita da TerritoryBuilderService). show_toggle
# controlla solo se il pulsante +/- compare (Caso 1 vs Caso 2, vedi _update_population_groups);
# `expanded` invece ne determina il simbolo mostrato ("-"/"+").
func _add_species_summary_row(
	species_name: String, groups: Array, show_toggle: bool, expanded: bool
) -> void:
	var total_population := 0
	var total_cells := 0
	for group in groups:
		total_population += group.population
		total_cells += group.territory.get_cell_count()

	var row := HBoxContainer.new()
	population_groups_container.add_child(row)

	if show_toggle:
		var toggle_button := Button.new()
		toggle_button.flat = true
		toggle_button.text = "-" if expanded else "+"
		toggle_button.tooltip_text = "Espandi/comprimi"
		toggle_button.custom_minimum_size = Vector2(20, 0)
		toggle_button.add_theme_font_size_override("font_size", 13)
		toggle_button.pressed.connect(_on_species_expand_toggled.bind(species_name))
		row.add_child(toggle_button)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	# Ellissi invece di "no_trimming" (default): senza questo, il minimum_size orizzontale della
	# Label riflette l'intero testo e si propaga fino al pannello attraverso lo ScrollContainer
	# (FaunaTab2, scroll orizzontale disabilitato) — con numeri a più cifre il pannello si
	# allargherebbe rispetto alla larghezza fissa delle altre tab. clip_text + overrun a ellissi
	# garantiscono che questa label non possa MAI forzare il pannello ad allargarsi, qualunque sia
	# la lunghezza del testo.
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# "grp"/"ind"/"cl" hardcoded (non tr()): nessuna CSV di traduzione esiste ancora nel progetto
	# — tr() su una chiave senza traduzione caricata mostrerebbe la chiave stessa, molto più
	# lunga dell'abbreviazione e controproducente qui. Stesso trattamento già riservato ad altri
	# connettivi brevi in questo pannello (vedi "in %d cell(s)" sotto).
	label.text = "%s — %s grp, %s ind, %s cl" % [
		species_name,
		NumberFormatter.format_int(groups.size()),
		NumberFormatter.format_int(total_population),
		NumberFormatter.format_int(total_cells)
	]
	row.add_child(label)

	# "Mostra tutti" SOLO in Caso 2 (filtro su una specie specifica, show_toggle=false qui) — in
	# Caso 1 ("Tutti") il meccanismo +/- di aggregazione già serve allo scopo, nessun bisogno di
	# un secondo modo di vedere più territori insieme (vedi report/conferma utente).
	if not show_toggle:
		var show_all_button := Button.new()
		show_all_button.flat = true
		show_all_button.text = "Mostra tutti"
		show_all_button.add_theme_font_size_override("font_size", 10)
		show_all_button.tooltip_text = "Evidenzia sulla mappa i territori di tutti i gruppi di questa specie"
		show_all_button.pressed.connect(_on_show_all_territories_pressed.bind(groups))
		row.add_child(show_all_button)


# Riga di dettaglio di UN singolo PopulationGroup — contenuto/formato invariati rispetto a prima
# dell'aggregazione per specie, solo estratti in una funzione riusabile (Caso 1 quando la specie
# è espansa, Caso 2 sempre).
func _add_population_group_detail_row(group: PopulationGroup) -> void:
	# Elenco piatto: sempre "in N cells" (mai le coordinate esatte, nemmeno con 1 sola cella come
	# rabbit) — coerenza di formato tra tutte le specie voluta esplicitamente dall'utente, anche
	# se con 1 cella sola si potrebbe mostrare la posizione precisa. "in N cell(s)" hardcoded, non
	# tr(): stesso trattamento dei connettivi/testo di raccordo già hardcoded altrove in questo
	# pannello — nessuna CSV di traduzione esiste ancora (vedi CLAUDE.md).
	var cell_count := group.territory.get_cell_count()
	var cell_descriptor: String = "in %d cell" % cell_count
	if cell_count != 1:
		cell_descriptor += "s"

	# Riga = Label (non cliccabile) + piccolo bottone "mirino" a fianco per evidenziare sulla
	# mappa le celle del territorio (vedi WorldRenderer.flash_cells) — l'intera riga cliccabile
	# (versione precedente) non comunicava che fosse interattiva, dato che appariva identica a
	# tutte le altre righe non cliccabili del pannello; un'icona dedicata è un affordance esplicito.
	var row_container := HBoxContainer.new()
	population_groups_container.add_child(row_container)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	# Stessa protezione di _add_species_summary_row sopra: id/popolazione a molte cifre non
	# devono poter allargare il pannello attraverso lo ScrollContainer di FaunaTab2.
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.text = "      #%d - %s: %s - %s" % [
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
		age_label.size_flags_horizontal = SIZE_EXPAND_FILL
		age_label.clip_text = true
		age_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		age_label.text = "            (Y:%s - A:%s - O:%s)" % [
			NumberFormatter.format_int(young),
			NumberFormatter.format_int(adult),
			NumberFormatter.format_int(old)
		]
		population_groups_container.add_child(age_label)


func _on_species_expand_toggled(species_name: String) -> void:
	_fauna_species_expanded[species_name] = not _fauna_species_expanded.get(species_name, false)
	_update_population_groups(_world)


# Riga di pulsanti sopra l'elenco (selezione esclusiva stile radio, via ButtonGroup nativo di
# Godot): "Tutti" (_fauna_species_filter = "") + un pulsante per ciascuna specie DISTINTA con
# almeno un gruppo vivo in world.population_groups in questo momento — dinamico, MAI hardcoded:
# una specie futura ottiene il proprio pulsante da sola, senza modifiche al codice (vedi
# _get_species_color/AnimalSilhouetteIcon per il fallback quando non ha una sagoma dedicata).
# "Tutti" vive nella riga del titolo (fauna_2_title_row, accanto a "Fauna 2"), NON dentro
# species_filter_container insieme ai pulsanti specie — separato apposta: species_filter_container
# è un HFlowContainer che va a capo su più righe quando i pulsanti specie non ci stanno più su una
# riga sola (il pannello deve restare a larghezza fissa indipendentemente da quante specie
# esistono), mentre "Tutti" deve restare sempre visibile in cima, non scorrere via con le righe
# extra. Entrambe le righe sono comunque ricostruite ad ogni refresh insieme all'elenco sotto
# (stesso pattern "queue_free + rebuild" già usato da population_groups_container/
# fish_summary_container in questo file) — pochi pulsanti, nessun bisogno di un aggiornamento
# incrementale. Nella riga del titolo si distrugge solo il vecchio "Tutti", mai
# fauna_2_title_label (l'unico figlio permanente di quella riga).
func _rebuild_species_filter_row(world: World) -> void:
	for child in species_filter_container.get_children():
		child.queue_free()
	for child in fauna_2_title_row.get_children():
		if child != fauna_2_title_label:
			child.queue_free()

	var button_group := ButtonGroup.new()

	var all_button := Button.new()
	all_button.text = tr("fauna_filter_all")
	all_button.add_theme_font_size_override("font_size", 9)
	all_button.toggle_mode = true
	all_button.button_group = button_group
	all_button.button_pressed = _fauna_species_filter == ""
	all_button.custom_minimum_size = Vector2(0, FILTER_BUTTON_SIZE.y)
	all_button.pressed.connect(_on_species_filter_pressed.bind(""))
	fauna_2_title_row.add_child(all_button)

	if world == null:
		return

	var species_names: Array = []
	for group in world.population_groups:
		if group.population <= 0:
			continue
		if _is_predator_species(group.species_name):
			continue
		if not species_names.has(group.species_name):
			species_names.append(group.species_name)
	species_names.sort()

	for species_name in species_names:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = button_group
		button.button_pressed = _fauna_species_filter == species_name
		button.tooltip_text = species_name
		button.custom_minimum_size = FILTER_BUTTON_SIZE
		button.pressed.connect(_on_species_filter_pressed.bind(species_name))

		# Icona come figlio del bottone invece di Button.icon (che richiede una Texture2D — qui
		# niente texture/Viewport, vedi AnimalSilhouetteIcon): mouse_filter = IGNORE su icona e
		# contenitore così il click passa sempre al Button sottostante invece di essere
		# intercettato dai figli.
		var icon := AnimalSilhouetteIcon.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = FILTER_ICON_SIZE
		icon.configure(species_name, _get_species_color(species_name))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(icon)

		species_filter_container.add_child(button)


func _on_species_filter_pressed(species_name: String) -> void:
	_fauna_species_filter = species_name
	_update_population_groups(_world)


# Elenco piatto di tutti i branchi predatori (world-level, non filtrato per cella — a differenza
# di MacroCellDetailPanel._update_predator_population_rows, che mostra solo i branchi il cui
# territorio include la cella aperta). Nessun filtro specie/espandi-comprimi come Fauna 2: i
# branchi predatori sono presumibilmente pochi (non decine come rabbit), un elenco diretto con un
# blocco ricco per gruppo è più utile di un riepilogo aggregato da espandere.
func _update_predator_groups(world: World) -> void:
	for child in predator_groups_container.get_children():
		child.queue_free()

	if world == null:
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		predator_groups_container.add_child(empty_label)
		return

	var predator_groups: Array = []
	for group in world.population_groups:
		if group.population <= 0:
			continue
		if _is_predator_species(group.species_name):
			predator_groups.append(group)

	if predator_groups.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.text = tr("no_population_groups")
		predator_groups_container.add_child(empty_label)
		return

	# Stesso criterio di ordinamento di _on_show_all_territories_pressed: per id, stabile e
	# indipendente dall'ordine di iterazione di world.population_groups.
	predator_groups.sort_custom(func(a, b): return a.id < b.id)

	for group in predator_groups:
		_add_predator_group_block(group)


# Blocco multi-riga per UN branco predatore: identità/territorio, finestra di pattugliamento di
# oggi, bookkeeping calorico, cronologia ultimi giorni, totale anno corrente. Molto più ricco
# della riga singola di _add_population_group_detail_row (Fauna 2) perché qui il numero di gruppi
# è tipicamente piccolo — non serve la stessa compattezza.
func _add_predator_group_block(group: PopulationGroup) -> void:
	var rules := AnimalCalculator.get_animal_rules(group.species_name) as PredatorRules

	# Header + bottone-mirino sulla stessa riga (HBoxContainer, stesso pattern di
	# _add_population_group_detail_row/Fauna 2): prima era una riga tutta sua sotto l'header,
	# uno spreco di spazio verticale per un singolo bottoncino.
	var header_row := HBoxContainer.new()
	predator_groups_container.add_child(header_row)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 12)
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Nessuna icona/emoji davanti al nome specie: nessun altro blocco animale in questo pannello
	# ne ha una (Fauna 2 usa solo testo, vedi _add_population_group_detail_row), niente motivo
	# perché i predatori facciano eccezione. "territorio" tolto per lo stesso motivo di
	# concisione già seguito da Fauna 2 ("in %d cells", non "territorio di %d celle").
	header.text = "%s #%d — pop %s, %s cells" % [
		group.species_name,
		group.id,
		NumberFormatter.format_int(group.population),
		NumberFormatter.format_int(group.territory.get_cell_count())
	]
	header_row.add_child(header)

	# Stesso pattern icona-mirino di _add_population_group_detail_row (Fauna 2): "Highlight cells
	# on map" hardcoded, non tr() — nessuna CSV di traduzione esiste ancora (vedi CLAUDE.md).
	var locate_button := Button.new()
	locate_button.flat = true
	locate_button.text = "⌖"
	locate_button.tooltip_text = "Highlight cells on map"
	locate_button.custom_minimum_size = Vector2(28, 0)
	locate_button.add_theme_font_size_override("font_size", 14)
	locate_button.add_theme_color_override("font_color", COLOR_LOCATE_BUTTON)
	locate_button.add_theme_color_override("font_hover_color", COLOR_LOCATE_BUTTON.lightened(0.3))
	# Il padding verticale di default dello stylebox del bottone lo rende più alto della riga di
	# testo dell'header — dato che ora condividono la stessa HBoxContainer (vedi commento sopra),
	# quel padding allargava l'intera riga, lasciando un vuoto visibile prima della riga età sotto.
	# Stylebox vuoto (margini 0) per farlo combaciare con l'altezza del testo.
	var locate_button_style := StyleBoxEmpty.new()
	locate_button.add_theme_stylebox_override("normal", locate_button_style)
	locate_button.add_theme_stylebox_override("hover", locate_button_style)
	locate_button.add_theme_stylebox_override("pressed", locate_button_style)
	locate_button.pressed.connect(_on_population_group_row_pressed.bind(group.territory.occupied_macrocells))
	header_row.add_child(locate_button)

	# Ripartizione età SOLO se la specie la traccia (AnimalRules.track_age_bands, vero per wolf) —
	# stesso formato/font-size della riga età di Fauna 2 (_add_population_group_detail_row), sui
	# totali dell'INTERO branco.
	if rules != null and rules.track_age_bands:
		var young := group.get_age_count(GameTypes.AgeBand.YOUNG)
		var adult := group.get_age_count(GameTypes.AgeBand.ADULT)
		var old := group.get_age_count(GameTypes.AgeBand.OLD)

		var age_label := Label.new()
		age_label.add_theme_font_size_override("font_size", 10)
		age_label.size_flags_horizontal = SIZE_EXPAND_FILL
		age_label.clip_text = true
		age_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		age_label.text = "            (Y:%s - A:%s - O:%s)" % [
			NumberFormatter.format_int(young),
			NumberFormatter.format_int(adult),
			NumberFormatter.format_int(old)
		]
		predator_groups_container.add_child(age_label)

	var window_label := Label.new()
	window_label.add_theme_font_size_override("font_size", 10)
	if group.patrol_route.is_empty() or rules == null:
		window_label.text = "   day window: nessuna (patrol_route vuoto)"
	else:
		var anchor: Vector2i = group.patrol_route[group.patrol_index]
		window_label.text = "   day window: (%d,%d) %dx%d" % [
			anchor.x, anchor.y, rules.hunting_window_size, rules.hunting_window_size
		]
	predator_groups_container.add_child(window_label)

	var bookkeeping_label := Label.new()
	bookkeeping_label.add_theme_font_size_override("font_size", 10)
	bookkeeping_label.text = "   debt=%s  surplus=%s" % [
		NumberFormatter.format_int(int(round(group.predation_calorie_debt))),
		NumberFormatter.format_int(int(round(group.predation_surplus_carryover)))
	]
	predator_groups_container.add_child(bookkeeping_label)

	# Nessuna intestazione "ultimi N giorni": si capisce comunque dal contesto (vedi
	# PopulationGroup.RECENT_HUNT_LOG_MAX_DAYS per il numero di entry). Nessun "Anno N": l'anno è
	# già visibile nel calendario sopra, ripeterlo qui su ogni riga era ridondante. Una riga per
	# giorno, col primo animale catturato subito accanto al numero di giorno (non più a capo) —
	# solo eventuali animali AGGIUNTIVI catturati lo stesso giorno vanno a capo, indentati sotto
	# (vedi _add_day_capture_lines).
	if group.recent_hunt_log.is_empty():
		var no_history_label := Label.new()
		no_history_label.add_theme_font_size_override("font_size", 10)
		no_history_label.text = "      (nessun dato ancora)"
		predator_groups_container.add_child(no_history_label)
	else:
		# Più recente per primo (l'array è FIFO, l'ultimo elemento è il giorno più recente).
		for i in range(group.recent_hunt_log.size() - 1, -1, -1):
			var entry: Dictionary = group.recent_hunt_log[i]
			_add_day_capture_lines(predator_groups_container, int(entry["day"]), entry["captures"])

	# "tot current year", non "tot year N": l'anno è già visibile nel calendario sopra, il numero
	# qui era ridondante (stesso principio delle righe giorno sopra).
	if group.yearly_prey_totals_year < 0:
		var yearly_header_label := Label.new()
		yearly_header_label.add_theme_font_size_override("font_size", 10)
		yearly_header_label.text = "   tot current year: (nessun dato ancora)"
		predator_groups_container.add_child(yearly_header_label)
	else:
		var yearly_header_label := Label.new()
		yearly_header_label.add_theme_font_size_override("font_size", 10)
		yearly_header_label.text = "   tot current year:"
		predator_groups_container.add_child(yearly_header_label)
		_add_capture_lines(predator_groups_container, group.yearly_prey_totals)

	var separator := Label.new()
	separator.add_theme_font_size_override("font_size", 8)
	separator.text = " - - - - - - - - - -"
	predator_groups_container.add_child(separator)


# Una Label per SPECIE (non più un'unica riga con le specie separate da virgola, che nella
# larghezza fissa del pannello troncava tutto dopo la prima specie e mezza) — "%s x%d (%s cal)",
# specie in ordine alfabetico (deterministico tra un refresh e l'altro, a differenza dell'ordine
# di iterazione di un Dictionary). Usata solo per il totale annuale (per il log giornaliero vedi
# _add_day_capture_lines sotto, che inoltre accorpa il primo animale sulla riga del giorno). "— no
# catches —" se non c'è stata alcuna cattura (totals vuoto).
func _add_capture_lines(container: VBoxContainer, captures: Dictionary) -> void:
	if captures.is_empty():
		var empty_label := Label.new()
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.text = "      — no catches —"
		container.add_child(empty_label)
		return
	var species_names: Array = captures.keys()
	species_names.sort()
	for species_name in species_names:
		var entry: Dictionary = captures[species_name]
		var line_label := Label.new()
		line_label.add_theme_font_size_override("font_size", 10)
		line_label.size_flags_horizontal = SIZE_EXPAND_FILL
		line_label.clip_text = true
		line_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line_label.text = "      %s x%d (%s cal)" % [
			species_name,
			int(entry["quantity"]),
			NumberFormatter.format_int(int(round(float(entry["calories"]))))
		]
		container.add_child(line_label)


# Riga di log giornaliero: "   Day %d: primo_animale x%d (%s cal)" — il primo animale catturato
# quel giorno sta sulla STESSA riga del numero di giorno (non più a capo), per non sprecare una
# riga intera solo per l'etichetta "Day N". Eventuali animali ULTERIORI catturati lo stesso
# giorno vanno a capo, allineati in colonna sotto il primo (non sotto "Day N:") — colonna fissa
# via DAY_PREFIX_COLUMN_WIDTH (Label dedicata, non spazi di testo: con un font proporzionale un
# rientro a spazi non allinea mai esattamente sotto un prefisso di lunghezza diversa come "Day
# 237:" vs "Day 5:"). "— no catches —" anch'esso sulla riga del giorno (non più una riga a sé) se
# captures è vuoto.
const DAY_PREFIX_COLUMN_WIDTH := 58.0

func _add_day_capture_lines(container: VBoxContainer, day: int, captures: Dictionary) -> void:
	var prefix := "   Day %d:" % day
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


# rabbit/deer/boar/tarpan/aurochs/wild_donkey/mouflon/bezoar/wolf: stessi colori del renderer sul
# campo (AnimalGroupRenderer), un solo posto li definisce. Specie future senza un colore dedicato:
# derivato deterministicamente dal nome (stesso hash ad ogni refresh, quindi lo stesso colore
# ogni volta per la stessa specie) invece di un colore casuale che cambierebbe ad ogni apertura
# del pannello.
func _get_species_color(species_name: String) -> Color:
	match species_name:
		"rabbit":
			return AnimalGroupRenderer.RABBIT_COLOR
		"deer":
			return AnimalGroupRenderer.DEER_COLOR
		"boar":
			return AnimalGroupRenderer.BOAR_COLOR
		"tarpan":
			return AnimalGroupRenderer.TARPAN_COLOR
		"aurochs":
			return AnimalGroupRenderer.AUROCHS_COLOR
		"wild_donkey":
			return AnimalGroupRenderer.WILD_DONKEY_COLOR
		"mouflon":
			return AnimalGroupRenderer.MOUFLON_COLOR
		"bezoar":
			return AnimalGroupRenderer.BEZOAR_COLOR
		"wolf":
			return AnimalGroupRenderer.WOLF_COLOR
		_:
			# abs(): String.hash() è tipato int ma sempre trattato come valore a 32 bit non
			# firmato internamente — il modulo su un intero GDScript negativo può restituire un
			# risultato negativo (troncato, non floored), qui evitato a prescindere.
			var hue: float = float(abs(species_name.hash()) % 360) / 360.0
			return Color.from_hsv(hue, 0.55, 0.75, 0.95)


# "Mostra tutti" (solo Caso 2, filtro specie attivo — vedi _add_species_summary_row): costruisce
# un'entry {"cells", "color", "label_text", "label_cell"} per OGNI gruppo passato e le invia tutte
# insieme a WorldRenderer via population_species_highlight_requested. `groups` arriva già filtrato
# a una sola specie dal chiamante (_update_population_groups), quindi il colore base è lo stesso
# per tutti — solo _get_group_variant_color li differenzia.
func _on_show_all_territories_pressed(groups: Array) -> void:
	if groups.is_empty():
		return

	# Ordinati per id (non per ordine di inserimento in world.population_groups, che non è
	# garantito coincidere) — determinismo: stesso gruppo -> stessa variante di colore ad ogni
	# apertura, non dipendente dall'ordine con cui i gruppi sono stati creati/iterati.
	var sorted_groups: Array = groups.duplicate()
	sorted_groups.sort_custom(func(a, b): return a.id < b.id)

	var base_color := _get_species_color(sorted_groups[0].species_name)
	var entries: Array = []
	for i in range(sorted_groups.size()):
		var group: PopulationGroup = sorted_groups[i]
		entries.append({
			"cells": group.territory.occupied_macrocells,
			"color": _get_group_variant_color(base_color, i, sorted_groups.size()),
			"label_text": "#%d" % group.id,
			"label_cell": group.territory.get_centroid(),
		})

	population_species_highlight_requested.emit(entries)


# Varia il colore base della specie per l'i-esimo gruppo (su `total`) così territori diversi
# della STESSA specie restano distinguibili tra loro nella vista "Mostra tutti", pur restando
# riconoscibili come quella specie. Hue: solo un piccolo scarto oscillante (mai libero su tutto
# il cerchio, vedi GROUP_COLOR_HUE_JITTER_RANGE) — il colore non deve mai derivare verso una
# tinta estranea alla specie. Value/Saturation: variazione principale, con uno step "golden
# ratio" (GOLDEN_RATIO_CONJUGATE) — distribuisce i valori nel range il più uniformemente
# possibile anche con molti gruppi, senza cluster di varianti troppo simili tra loro come
# capiterebbe con uno step lineare (i/total) su pochi gruppi ravvicinati.
func _get_group_variant_color(base_color: Color, index: int, total: int) -> Color:
	if total <= 1:
		return Color(base_color.r, base_color.g, base_color.b, SPECIES_TERRITORY_OVERLAY_ALPHA)

	var step: float = fmod(float(index) * GOLDEN_RATIO_CONJUGATE, 1.0)

	var hue_offset: float = (step - 0.5) * 2.0 * GROUP_COLOR_HUE_JITTER_RANGE
	var new_hue: float = fmod(base_color.h + hue_offset + 1.0, 1.0)

	var value_step: float = fmod(step + 0.5, 1.0) # sfasato rispetto a hue_offset, stesso step riusato senza farli covariare
	var new_value: float = clamp(
		base_color.v * lerp(GROUP_COLOR_VALUE_RANGE.x, GROUP_COLOR_VALUE_RANGE.y, value_step), 0.15, 1.0
	)
	var new_saturation: float = clamp(
		base_color.s * lerp(GROUP_COLOR_SATURATION_RANGE.x, GROUP_COLOR_SATURATION_RANGE.y, step), 0.0, 1.0
	)

	var variant := Color.from_hsv(new_hue, new_saturation, new_value)
	variant.a = SPECIES_TERRITORY_OVERLAY_ALPHA
	return variant


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


# Aggregato unico su tutta la mappa, nessun breakdown per TerrainBase (a differenza del
# breakdown SEA/LAKE/RIVER di FISH sopra — scelta esplicita, vedi analisi BIRDS). "Celle
# occupate" = celle con terrestrial_space[BIRDS] > 0, stesso segnale di occupazione usato da
# _update_fish_summary sopra e dai service Fauna (FaunaGrowthService/FaunaMortalityService).
func _update_birds_summary(world: World) -> void:
	if world == null:
		birds_summary_label.text = ""
		return

	var total_quantity := 0
	var total_cells := 0
	for cell in world.cells:
		var state := world.get_cell_state_at(cell.x, cell.y)
		if state == null:
			continue
		var birds_space := state.get_terrestrial_space(GameTypes.WorldObjectType.BIRDS)
		if birds_space <= 0:
			continue
		total_quantity += state.get_resource_quantity(GameTypes.WorldObjectType.BIRDS)
		total_cells += 1

	birds_separator_label.text = " - - - - - - - - - -"
	birds_summary_label.text = "%s: %s %s %s %s" % [
		tr("birds"),
		NumberFormatter.format_int(total_quantity),
		tr("in"),
		NumberFormatter.format_int(total_cells),
		tr("cells")
	]
