class_name BuildingInfoPanel
extends VBoxContainer

# Corpo del pannello edificio dentro GameInfoTabs.selection_content — Step 5 del piano "centra
# generalizzato + selezione edifici" (richiesta utente, 2026-09-04), stesso principio "muto" di
# VegetationInfoPanel/HumanIndividualInfoPanel: istanziato dinamicamente da GameScene, riceve solo
# l'oggetto Building già risolto (stesso schema di HumanIndividualInfoPanel.show_individual, che
# prende l'HumanIndividual intero) — non conosce GameScene/selezione/BuildingCalculator. Label
# tr()-wrapped (richiesta utente 2026-09-06, insieme a VegetationInfoPanel/HumanIndividualInfoPanel/
# DeadBodyInfoPanel): solo le chiavi, nessuna riga aggiunta ancora a strings.csv/
# strings.it.translation. building.rules.building_name già tr()-wrapped da prima (documentato in
# BuildingRules stessa). Nascosto di default (nessuna selezione all'apertura della scena). Solo
# consultazione, nessuna interazione (a differenza di VegetationInfoPanel.cut_requested) — non
# esiste ancora alcuna azione giocatore su un edificio già piazzato.
#
# TypeLabel (Step 6, richiesta utente 2026-09-04): mai esistita qui come nodo separato dall'inizio
# — sollevata direttamente dentro GameInfoTabs.title_label, sulla STESSA riga del bottone "🎯".
# GameScene la imposta (game_info_tabs.set_selection_title) subito insieme a show_building, con la
# stessa formula tr(building.rules.building_name)/building_type_name che sarebbe finita qui.
#
# StorageGrid (2026-09-09, richiesta utente — sostituisce StoredResourcesLabel, un flat testo
# "resource_name quantity, ..." che non comunicava lo spazio/slot occupati) — griglia di
# building.rules.storage_slot_count riquadri (es. deposit_site = 9 -> 3x3), uno per SLOT, non uno
# per tipo di risorsa: vedi BuildingStorageService.get_slot_breakdown per il modello "slot univoci"
# (una risorsa può occupare più slot consecutivi, mai condivisi con un'altra risorsa). Ogni slot
# pieno mostra l'icona della risorsa (stesso fallback a 3 livelli — icona disegnata/emoji/iniziale
# — già in uso in HumanIndividualInfoPanel per il riquadro trasportato) più il numero di OGGETTI
# presenti (non lo spazio occupato — 2026-09-10, richiesta utente, vedi _build_storage_slot per il
# perché), con tooltip al passaggio del mouse (solo nome risorsa) e una barra verticale di
# riempimento sul bordo destro (spazio_occupato/capacità, a colpo d'occhio). Slot oltre quelli
# restituiti da
# get_slot_breakdown sono vuoti (grigio spento, nessuna icona/tooltip/barra).
#
# Sezione "Impostazioni" (2026-09-09, richiesta utente) — DENTRO questo pannello, non un menu/
# popup a parte (deciso esplicitamente con l'utente: nessun pattern "icona in un pannello di
# selezione apre un secondo pannello" esiste già nel progetto, costruirne uno per due checkbox +
# un bottone placeholder è prematuro — se le impostazioni-edificio cresceranno, estrarle in un
# pannello dedicato resta un refactor contenuto). Strutturata GENERICA/estensibile per tipo, non
# hardcoded al solo storage: _refresh_settings_section sotto è il punto in cui una futura
# capacità diversa (edificio X ha la caratteristica Y) aggiungerebbe il proprio blocco — oggi
# l'unico blocco esistente è "building.rules.storage_slot_count > 0 -> mostra i toggle categoria".
# Toggle categoria (Building.enabled_categories, il filtro PER-ISTANZA — vedi BuildingStorageService.
# can_accept) mostrati SOLO tra le categorie che il TIPO già accetta (building.rules.
# accepted_categories, o TUTTE le categorie esistenti se il tipo non ha restrizioni proprie — vuoto
# = nessun limite di tipo) — richiesta esplicita utente: l'istanza può solo restringere, mai
# scegliere tra categorie che il tipo comunque rifiuterebbe.

const STORAGE_SLOT_SIZE: float = 32.0
const EMPTY_STORAGE_SLOT_COLOR := Color(0.3, 0.3, 0.3, 0.4)

# "Serbatoietto" di riempimento slot (2026-09-10, richiesta utente — "se vogliamo esagerare
# potremmo provare a mettere sull'icona una specie di serbatoietto") — striscia verticale sul bordo
# destro dello slot, alta quanto lo slot intero (track, sempre visibile, semitrasparente) con sopra
# una seconda striscia (fill) ancorata al FONDO la cui altezza è space_used/space_capacity ×
# STORAGE_SLOT_SIZE — si riempie dal basso verso l'alto come un vero serbatoio. Posizione/size
# ESPLICITI (non anchor), non serve l'anchor math altrove usato per icon_node/space_label: box è
# sempre esattamente STORAGE_SLOT_SIZE×STORAGE_SLOT_SIZE (custom_minimum_size fissa), nessun
# ridimensionamento dinamico da inseguire.
const STORAGE_SLOT_FILL_BAR_WIDTH: float = 4.0
const STORAGE_SLOT_FILL_BAR_TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const STORAGE_SLOT_FILL_BAR_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.85)

@onready var status_label: Label = $StatusLabel
@onready var durability_label: Label = $DurabilityLabel
@onready var built_year_label: Label = $BuiltYearLabel
@onready var storage_grid: GridContainer = $StorageGrid
@onready var id_label: Label = $IdLabel
@onready var settings_separator: HSeparator = $SettingsSeparator
@onready var settings_caption: Label = $SettingsCaption
@onready var accepted_categories_caption: Label = $AcceptedCategoriesCaption
@onready var category_toggles_container: VBoxContainer = $CategoryTogglesContainer
@onready var empty_all_button: Button = $EmptyAllButton

# Edificio correntemente mostrato (2026-09-09) — MAI esistito prima come campo: show_building
# riceveva `building` solo come parametro locale, nessun consumatore ne aveva bisogno dopo il
# ritorno della funzione. I toggle categoria sotto sono l'eccezione: un CheckBox premuto dal
# player deve sapere SU QUALE Building scrivere enabled_categories, in un momento (il callback
# `toggled`) in cui `building` del parametro originale non è più in scope — stesso motivo per cui
# un riferimento va tenuto qui, non ricavato altrove (questo pannello non conosce GameScene/
# selezione, resta "muto" come dichiarato in testa al file).
var _current_building: Building = null


func _ready() -> void:
	clear()
	settings_caption.text = tr("building_settings_caption")
	accepted_categories_caption.text = tr("building_settings_accepted_categories_caption")
	empty_all_button.text = tr("building_settings_empty_all_button")


func show_building(building: Building) -> void:
	visible = true
	_current_building = building
	status_label.text = tr("building_status_label").format({
		"status": tr("building_status_complete") if building.is_complete else tr("building_status_under_construction")
	})

	var max_durability: int = building.rules.max_durability if building.rules != null else 0
	durability_label.text = tr("building_durability_label").format({"current": building.current_durability, "max": max_durability})

	built_year_label.text = (
		tr("building_built_year_label").format({"year": building.built_year}) if building.built_year >= 0
		else tr("building_not_yet_built")
	)

	_refresh_storage_grid(building)
	_refresh_settings_section(building)

	id_label.text = tr("building_id_label").format({"id": building.id})


func clear() -> void:
	visible = false
	_current_building = null


# Ricostruita per intero ad ogni show_building (stesso principio "rebuild da zero" già in uso
# ovunque nel progetto per contenuto derivato, es. MicroCellRenderer._rebuild_pebble_multimeshes) —
# nessuna logica di aggiornamento incrementale slot-per-slot, il costo è trascurabile (al più
# storage_slot_count nodi, oggi 4-9). Nascosta del tutto per un edificio senza storage
# (storage_slot_count <= 0, es. Stone Circle) — nessuna griglia vuota fuorviante per un edificio
# che non può mai stoccare nulla.
func _refresh_storage_grid(building: Building) -> void:
	for child in storage_grid.get_children():
		child.queue_free()

	var slot_count: int = building.rules.storage_slot_count if building.rules != null else 0
	if slot_count <= 0:
		storage_grid.visible = false
		return

	storage_grid.visible = true
	# Colonne = ceil(sqrt(slot_count)) — 3x3 per 9 (deposit_site), 2x2 per 4 (hut), un default
	# ragionevole/generico per qualunque futuro slot_count senza doverlo configurare a mano per tipo.
	storage_grid.columns = max(int(ceil(sqrt(float(slot_count)))), 1)

	var breakdown: Array = BuildingStorageService.get_slot_breakdown(building)
	for i in range(slot_count):
		var slot_data: Dictionary = breakdown[i] if i < breakdown.size() else {}
		storage_grid.add_child(_build_storage_slot(slot_data))


# slot_data vuoto ({}) = slot libero — riquadro grigio spento, nessuna icona/testo/tooltip. Slot
# occupato ({"resource_name","quantity","space_used","space_capacity"}, vedi BuildingStorageService.
# get_slot_breakdown): stesso schema icona a 3 livelli (disegnata/emoji/iniziale) già in uso per
# HumanIndividualInfoPanel._update_carried_resource_box, qui riletto da IconRegistry invece di
# duplicato — colore di sfondo/nome tooltip risolti dalla STESSA fonte (IconRegistry.
# get_resource_color/get_resource_display_name), quindi una risorsa ha sempre lo stesso colore/nome
# sia nello zaino individuo che qui.
#
# quantity/tooltip/serbatoietto (2026-09-10, richiesta utente — "se deposito 4 bastoni, mi dice
# 40/100... avrebbe più senso indicare il numero degli oggetti"): la scritta grande sull'icona ora
# mostra `quantity` (numero di oggetti, non più lo spazio occupato); il tooltip resta il solo nome
# risorsa (un tentativo intermedio ci aveva aggiunto anche spazio/capacità, tolto su richiesta
# esplicita — quell'informazione si legge dalla barra sotto); una striscia verticale
# ("serbatoietto", STORAGE_SLOT_FILL_BAR_*) sul bordo destro dello slot mostra il livello di
# riempimento a colpo d'occhio senza dover leggere numeri — vedi sotto per l'ordine esatto in cui
# questi elementi vengono aggiunti a `box` (il numero è ristretto di STORAGE_SLOT_FILL_BAR_WIDTH sul
# lato destro apposta per non finire coperto dalla barra, disegnata per ultima/sopra).
func _build_storage_slot(slot_data: Dictionary) -> Control:
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(STORAGE_SLOT_SIZE, STORAGE_SLOT_SIZE)

	if slot_data.is_empty():
		box.color = EMPTY_STORAGE_SLOT_COLOR
		return box

	var resource_name: String = String(slot_data["resource_name"])
	var space_used: int = int(slot_data["space_used"])
	var space_capacity: int = int(slot_data["space_capacity"])
	box.color = IconRegistry.get_resource_color(resource_name)
	# Tooltip TORNATO al solo nome risorsa (2026-09-10, richiesta utente — "tooltip togli 80/100,
	# lascia solo il nome della risorsa": lo spazio occupato/capacità restano leggibili dalla barra
	# di riempimento sotto, non serve più ripeterli anche qui).
	box.tooltip_text = IconRegistry.get_resource_display_name(resource_name)

	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		box.add_child(icon_node)
		# PRESET_FULL_RECT via ancore+offset DIRETTI (stesso bugfix già documentato in
		# IconButtonRow.configure_slot/HumanIndividualInfoPanel._update_carried_resource_box per
		# queste stesse icone: il preset di default userebbe la minimum size del figlio, zero per
		# un Control senza testo/figli come queste icone).
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		var initial_label := Label.new()
		var icon_text: String = IconRegistry.get_resource_icon(resource_name)
		initial_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial_label.anchor_right = 1.0
		initial_label.anchor_bottom = 1.0
		box.add_child(initial_label)

	# Quantità di OGGETTI in questo slot (2026-09-10, richiesta utente — "avrebbe più senso indicare
	# il numero degli oggetti": prima qui c'era lo spazio occupato "80/100", che si leggeva come "80
	# bastoni" anche quando erano solo 4 — RIMPIAZZATO, non affiancato: lo spazio ora si legge dalla
	# barra di riempimento sotto) — basso a destra, stesso trattamento ombra/colore di
	# CarriedResourceBox/QuantityLabel in HumanIndividualInfoPanel.tscn per coerenza visiva tra i due
	# riquadri risorsa del progetto.
	#
	# offset_right = -STORAGE_SLOT_FILL_BAR_WIDTH (BUGFIX 2026-09-10, richiesta utente — "non hai
	# messo il numero di oggetti sopra l'icona": era presente ma INVISIBILE, la barra di riempimento
	# sotto viene disegnata DOPO — quindi SOPRA nell'ordine di disegno — e occupa esattamente lo
	# stesso angolo in basso a destra dove il numero era ancorato, coprendolo. Restringere il rect
	# del label di STORAGE_SLOT_FILL_BAR_WIDTH sul lato destro libera esattamente lo spazio dov'è la
	# barra, così i due elementi convivono senza sovrapporsi.
	var quantity_label := Label.new()
	quantity_label.text = str(int(slot_data["quantity"]))
	quantity_label.add_theme_font_size_override("font_size", 8)
	quantity_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	quantity_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.anchor_right = 1.0
	quantity_label.anchor_bottom = 1.0
	quantity_label.offset_right = -STORAGE_SLOT_FILL_BAR_WIDTH
	box.add_child(quantity_label)

	# "Serbatoietto" di riempimento (2026-09-10, richiesta utente, opzione scelta esplicitamente tra
	# le due proposte) — vedi le costanti STORAGE_SLOT_FILL_BAR_* in testa al file per il principio.
	# Aggiunto PER ULTIMO (sopra icona/quantity_label nell'ordine di disegno) così resta sempre
	# visibile sul bordo destro invece di finire coperto.
	var fill_bar_track := ColorRect.new()
	fill_bar_track.color = STORAGE_SLOT_FILL_BAR_TRACK_COLOR
	fill_bar_track.size = Vector2(STORAGE_SLOT_FILL_BAR_WIDTH, STORAGE_SLOT_SIZE)
	fill_bar_track.position = Vector2(STORAGE_SLOT_SIZE - STORAGE_SLOT_FILL_BAR_WIDTH, 0.0)
	fill_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill_bar_track)

	var fill_ratio: float = clampf(float(space_used) / float(space_capacity), 0.0, 1.0) if space_capacity > 0 else 0.0
	var fill_height: float = STORAGE_SLOT_SIZE * fill_ratio
	var fill_bar_fill := ColorRect.new()
	fill_bar_fill.color = STORAGE_SLOT_FILL_BAR_FILL_COLOR
	fill_bar_fill.size = Vector2(STORAGE_SLOT_FILL_BAR_WIDTH, fill_height)
	fill_bar_fill.position = Vector2(STORAGE_SLOT_SIZE - STORAGE_SLOT_FILL_BAR_WIDTH, STORAGE_SLOT_SIZE - fill_height)
	fill_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill_bar_fill)

	return box


# Punto di estensione GENERICO per contenuto condizionale-al-tipo (2026-09-09, richiesta utente —
# vedi commento in testa al file): oggi un solo blocco (storage -> toggle categoria), una futura
# capacità diversa aggiungerebbe il proprio `if`/blocco qui, ciascuno responsabile di mostrare/
# nascondere SOLO i propri nodi — mai un blocco che nasconde ciò che un altro ha appena mostrato.
# Nessun edificio con capacità da configurare oggi -> l'intera sezione (separatore+titolo compresi)
# resta nascosta, stesso principio già seguito da StorageGrid per storage_slot_count<=0.
func _refresh_settings_section(building: Building) -> void:
	var has_storage: bool = building.rules != null and building.rules.storage_slot_count > 0
	_refresh_accepted_categories_toggles(building, has_storage)

	# Almeno un blocco visibile -> mostra la "chrome" condivisa (separatore/titolo/bottone
	# placeholder). Oggi has_storage è l'unica condizione, ma scritta così non richiede modifiche
	# quando un secondo blocco esisterà (basterà aggiungerlo all'OR).
	var any_section_visible: bool = has_storage
	settings_separator.visible = any_section_visible
	settings_caption.visible = any_section_visible
	empty_all_button.visible = any_section_visible


# Toggle CheckBox per Building.enabled_categories (2026-09-09, richiesta utente) — SOLO per edifici
# con storage (has_storage, dal chiamante): un edificio senza storage non ha categorie da filtrare.
# Categorie mostrate: building.rules.accepted_categories se il TIPO ne ha (vuoto = nessuna
# restrizione di tipo, in quel caso mostra TUTTE le categorie esistenti — SecondaryResourceTypes.
# Category.values()) — richiesta esplicita: l'istanza può scegliere solo tra ciò che il tipo già
# accetta, mai categorie che il tipo rifiuterebbe comunque.
#
# Stato checkbox: checked = categoria attualmente abilitata per QUESTA istanza — building.
# enabled_categories VUOTO significa "nessuna restrizione propria, tutto ciò che il tipo accetta è
# abilitato" (vedi Building.gd), quindi ogni checkbox parte spuntata finché il player non ne
# deflagga almeno una esplicitamente (vedi _on_category_toggled sotto per come si materializza
# l'elenco esplicito al primo deflag).
func _refresh_accepted_categories_toggles(building: Building, has_storage: bool) -> void:
	for child in category_toggles_container.get_children():
		child.queue_free()

	accepted_categories_caption.visible = has_storage
	category_toggles_container.visible = has_storage
	if not has_storage:
		return

	var categories_to_show: Array = (
		building.rules.accepted_categories if not building.rules.accepted_categories.is_empty()
		else SecondaryResourceTypes.Category.values()
	)
	for category in categories_to_show:
		var check_box := CheckBox.new()
		check_box.text = _category_display_name(category)
		# Font ridotto (richiesta utente 2026-09-09) — stessa taglia di AcceptedCategoriesCaption/
		# DurabilityLabel/BuiltYearLabel/IdLabel sopra, più piccola del default tema per un elenco
		# di opzioni secondarie come questo.
		check_box.add_theme_font_size_override("font_size", 10)
		check_box.button_pressed = building.enabled_categories.is_empty() or building.enabled_categories.has(category)
		check_box.toggled.connect(_on_category_toggled.bind(category, building, categories_to_show))
		category_toggles_container.add_child(check_box)


# Chiave tr() "category_name_<nome_enum_minuscolo>" (es. FOOD -> "category_name_food") — deriva la
# chiave dal nome dell'enum invece di un match hardcoded: una futura categoria aggiunta a
# SecondaryResourceTypes.Category compare qui da sola (con la chiave grezza come fallback finché
# non le si aggiunge una riga in strings.csv, stesso idioma "tr() ritorna la chiave se non trovata"
# già in uso altrove nel progetto, es. IconRegistry.get_resource_display_name).
func _category_display_name(category: int) -> String:
	var key := "category_name_%s" % SecondaryResourceTypes.Category.keys()[category].to_lower()
	return tr(key)


# ENTRAMBI i rami scrivono direttamente su Building.enabled_categories, MAI su BuildingRules
# (quello resta il tipo, condiviso — vedi Building.gd/BuildingStorageService.can_accept per la
# spiegazione completa dei due livelli). Solo controllo IN ENTRATA (richiesta esplicita utente):
# questo toggle non tocca mai building.stored_resources, solo cosa store() accetterà d'ora in poi.
#
# `categories_to_show` (bind, dallo stesso elenco già risolto da _refresh_accepted_categories_
# toggles) — necessario per materializzare "tutto tranne questa" al primo deflag (pressed=false con
# enabled_categories ancora vuoto, cioè "implicitamente tutto abilitato": vedi Building.gd) E per
# la normalizzazione inversa sotto (se il player riabilita l'ultima categoria mancante, l'elenco
# esplicito torna a coincidere con categories_to_show — a quel punto si ricollassa a [] per
# restare nella forma canonica "nessuna restrizione propria", equivalente ma più pulita).
func _on_category_toggled(pressed: bool, category: int, building: Building, categories_to_show: Array) -> void:
	if pressed:
		if not building.enabled_categories.is_empty() and not building.enabled_categories.has(category):
			building.enabled_categories.append(category)
	else:
		if building.enabled_categories.is_empty():
			for shown_category in categories_to_show:
				if shown_category != category:
					building.enabled_categories.append(shown_category)
		else:
			building.enabled_categories.erase(category)

	# Normalizzazione (vedi commento sopra): elenco esplicito che ormai copre di nuovo TUTTO
	# categories_to_show -> ricollassa a [] (forma canonica "nessuna restrizione propria").
	if not building.enabled_categories.is_empty():
		var covers_everything := true
		for shown_category in categories_to_show:
			if not building.enabled_categories.has(shown_category):
				covers_everything = false
				break
		if covers_everything:
			building.enabled_categories.clear()

	if _current_building == building:
		_refresh_settings_section(building)
