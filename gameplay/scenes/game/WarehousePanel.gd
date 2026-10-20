class_name WarehousePanel
extends VBoxContainer

# Cassetto "Gestione scorte" (2026-10-10, richiesta utente — gestione dei magazzini). Contenuto del SideDrawer come
# TaskAssignmentPanel: stesso posto (accanto all'info panel), stessa larghezza (SideDrawer.WIDTH), il tempo non si ferma.
# Lo apre e lo richiude il bottone della riga del governo (GameInfoPanel.WAREHOUSE_SLOT_INDEX, GameScene.
# _toggle_warehouse_drawer), acceso solo con l'idea REQUIRED_IDEA_ID completata.
#
# Elenco in sola lettura delle risorse del villaggio (VillageStockService.get_village_stock): una riga per risorsa con
# icona, nome e quantità totale; anche le risorse a zero (sbiadite), fuori solo quelle non ancora scoperte
# (TerrainScatteredResourceService.is_resource_locked). Dal 2026-10-10 (ritocco) una linguetta per categoria
# (SecondaryResourceTypes.Category, solo icona e nome nel tooltip, stile delle linguette dell'info panel): sotto solo
# l'elenco della categoria scelta, all'apertura il Cibo, poi l'ultima scelta (_last_category, per la sessione). In testa
# al Cibo il totale in calorie e i giorni di autonomia. Accanto al titolo del cassetto la barra di riempimento dei
# depositi (SideDrawer.set_header_extra). I dati li passa GameScene (refresh_stock), una volta al secondo a cassetto
# aperto come l'Assegnazione; le righe si ricostruiscono solo quando cambia l'elenco delle risorse visibili.

# Idea che accende il bottone (dopo l'assegnazione delle task nell'albero delle idee).
const REQUIRED_IDEA_ID := "warehouse_management"
# Id del contenuto nel SideDrawer.
const DRAWER_CONTENT_ID := &"warehouse"

# Stesse misure delle righe del cassetto dell'Assegnazione (TaskAssignmentPanel).
const SECTION_FONT_SIZE: int = 12
const LIST_FONT_SIZE: int = 11
const LIST_ICON_SIDE: float = 20.0
const ZERO_QUANTITY_COLOR := Color(1.0, 1.0, 1.0, 0.45)

# Linguette: icona disegnata (StockCategoryIcon) resa una volta in un SubViewport e usata come texture, come le icone
# disegnate dell'Aiuto (HelpDialog._drawn_icon_texture).
const TAB_ICON_SIDE: int = 18
const TAB_ICON_RENDER_SIDE: int = 48

# Barra di riempimento dei depositi: stesso stile della barra del carico di lavoro dell'Assegnazione
# (TaskAssignmentPanel, WORKLOAD_*), riempimento di un solo colore: verde, rosso da FILL_RED_FROM_PERCENT.
const FILL_BAR_HEIGHT: float = 16.0
const FILL_BAR_MIN_WIDTH: float = 60.0
const FILL_BAR_BG_COLOR := Color(0.08, 0.09, 0.11, 1.0)
const FILL_BAR_BORDER_COLOR := Color(0.75, 0.85, 1.0, 0.45)
const FILL_RED_FROM_PERCENT: int = 85
const FILL_GREEN := Color(0.35, 0.75, 0.35, 1.0)
const FILL_RED := Color(0.85, 0.25, 0.25, 1.0)

# Ordine delle linguette, da sinistra a destra (2026-10-10, richiesta utente).
const TAB_ORDER: Array[int] = [
	SecondaryResourceTypes.Category.FOOD, SecondaryResourceTypes.Category.RAW_MATERIAL,
	SecondaryResourceTypes.Category.SEMI_FINISHED, SecondaryResourceTypes.Category.TOOL,
	SecondaryResourceTypes.Category.MEDICINAL, SecondaryResourceTypes.Category.APPAREL,
]

# Livello minimo (2026-10-10, richiesta utente): campo − [numero] + a destra della quantità, passo 1,
# scrivibile; 0 = nessun livello (trattino). Quantità sotto il livello: numero in rosso (vince sullo sbiadito delle risorse
# a zero). Sul totale del cibo lo stesso campo in giorni di autonomia. Colonne di larghezza fissa, uguali su tutte le
# righe: quantità e campo restano allineati, il nome si tronca. Valori della partita (GameData.stock_min_levels /
# stock_min_food_days): arrivano da GameScene (set_min_levels, prima di _ready) e ogni cambio esce con min_level_changed /
# min_food_days_changed. L'aggiornamento di ogni secondo tocca solo le quantità, mai i campi: niente testo né focus persi.
# Dal 2026-10-11 (gestione scorte, primo passo) il livello dei materiali grezzi che si raccolgono, tagliano o estraggono
# (StockRequestService.source_kind_for) fa nascere ordini nella coda dei lavori (WarehouseManagerService.request_stock), con il
# suo tooltip (warehouse_min_level_auto_tooltip); per le altre risorse e per i giorni del cibo resta solo indicativo.
signal min_level_changed(resource_name: String, level: int)
# Massimo per risorsa (2026-10-18, Fossa dei rifiuti): secondo campo della riga; oltre, l'eccedenza va buttata.
signal max_level_changed(resource_name: String, level: int)
signal min_food_days_changed(days: int)
# Regole di stoccaggio (2026-10-11): riga "⚙ Regole di stoccaggio" in fondo al cassetto che apre e chiude le regole,
# come "Regole di assegnazione" del cassetto delle task. Per ora una regola: destinazione di carne e pelli in eccesso negli
# ordini di caccia del magazzino (GameData.stock_excess_meat_destination), con il pulsante delle destinazioni della caccia
# (ButcherDestinationButton). Stato e opzioni li passa GameScene (set_excess_meat_destination), la scelta esce con
# excess_meat_destination_changed. Aperta o chiusa resta per la sessione (_rules_open).
signal excess_meat_destination_changed(destination: String)
# Inventario (2026-10-11): riga in cima al cassetto con il prossimo inventario (o chi lo sta facendo), dati da GameScene
# (set_inventory_info); i numeri del cassetto sono quelli dell'ultimo inventario, non in tempo reale. Frequenza nelle
# Regole di stoccaggio (ore tra un inventario e l'altro), esce con inventory_interval_changed.
signal inventory_interval_changed(hours: int)
# Regola "Combustibile negli edifici che lo usano" (2026-10-16, FuelStockService): una casella accesa/spenta
# (GameData.stock_fuel_rule_enabled) e sotto una riga per tipo di edificio con il suo minimo (− [N] +,
# GameData.stock_fuel_min_by_type). Stato e righe da GameScene (set_fuel_rule, prima di _ready); i cambi escono con
# fuel_rule_toggled / fuel_min_changed.
signal fuel_rule_toggled(enabled: bool)
signal fuel_min_changed(type_name: String, level: int)
# Regola "Rifornisci le Attrezzerie" (2026-10-18, ToolkitStockService): accesa/spenta e pezzi voluti per tipo e attrezzo.
signal toolkit_rule_toggled(enabled: bool)
signal toolkit_target_changed(type_name: String, tool_name: String, level: int)
var _fuel_rule_enabled: bool = false
var _fuel_rows: Array[Dictionary] = []
var _toolkit_rule_enabled: bool = false
# [{"type", "name", "tools": [{"tool", "level", "max"}]}] (ToolkitStockService.get_rule_rows).
var _toolkit_rows: Array[Dictionary] = []
var _toolkit_popup: PopupPanel = null
const TOOLKIT_POPUP_INSET: int = 8
const TOOLKIT_POPUP_BG_COLOR := Color(0.12, 0.14, 0.18, 1.0)
const TOOLKIT_POPUP_BORDER_COLOR := Color(0.75, 0.85, 1.0, 0.6)
# Regola "Banchetti spontanei" (2026-10-17): casella "al massimo un terzo delle scorte" (GameData.stock_banquet_safe_only).
# Le calorie sono quelle della "Soglia calorie" dello spiazzo (2026-10-18, richiesta utente: prima c'era anche un campo
# qui). Stato da GameScene (set_banquet_rule, prima di _ready); i cambi escono con banquet_safe_only_toggled.
signal banquet_safe_only_toggled(enabled: bool)
var _banquet_safe_only: bool = true
const INVENTORY_INTERVAL_OPTIONS: Array[int] = [6, 12, 24, 48, 72, 120]
var _inventory_label: Label = null
var _inventory_info: Array = []
var _inventory_interval: int = 24
const QUANTITY_COLUMN_WIDTH: float = 46.0
const LEVEL_BUTTON_WIDTH: float = 16.0
const LEVEL_EDIT_WIDTH: float = 38.0
const LEVEL_MAX: int = 99999
const BELOW_LEVEL_COLOR := Color(0.95, 0.35, 0.3, 1.0)
# Scorta oltre il massimo (2026-10-18): ambra.
const ABOVE_MAX_COLOR := Color(0.95, 0.72, 0.25, 1.0)
const LEVEL_NONE_TEXT := "—"
# Righe compatte (2026-10-18, richiesta utente): campi Min/Max stretti con + e − piccoli impilati a destra, rotella per
# cambiarli; massimo vuoto = ∞. Stili propri (margini minimi) perché il tema di base allarga campo e bottoni.
const LEVEL_COMPACT_EDIT_WIDTH: float = 26.0
const LEVEL_COMPACT_BUTTON_SIZE := Vector2(11.0, 9.0)
# Larghezza fissa della colonna di un campo compatto (campo + bottoni), uguale nelle righe e nell'intestazione "Min"/"Max"
# (2026-10-18: prima l'intestazione misurava un campo di prova fuori dalla scena, senza tema, e le etichette scivolavano).
const LEVEL_COMPACT_COLUMN_WIDTH: float = 40.0
const LEVEL_COMPACT_FONT_SIZE: int = 10
const LEVEL_COMPACT_BUTTON_FONT_SIZE: int = 9
const LEVEL_COMPACT_BG := Color(0.10, 0.11, 0.14, 1.0)
const LEVEL_COMPACT_BORDER := Color(1.0, 1.0, 1.0, 0.18)
const LEVEL_COMPACT_BORDER_FOCUS := Color(1.0, 1.0, 1.0, 0.7)
const LEVEL_INFINITE_TEXT := "∞"
const COLUMN_HEADER_COLOR := Color(1.0, 1.0, 1.0, 0.55)

# Ultima linguetta scelta (per tutta la sessione): all'apertura successiva il cassetto riparte da qui.
static var _last_category: int = SecondaryResourceTypes.Category.FOOD
static var _rules_open: bool = false

var _rules_box: VBoxContainer = null
var _excess_meat_button: ButcherDestinationPair = null
# Ultimo stato ricevuto prima che il pulsante esistesse (set_excess_meat_destination prima di _ready).
var _excess_meat_state: Array = []

var _tab_bar: TabBar = null
var _list_box: VBoxContainer = null
# Categoria -> VBoxContainer con le sue righe (solo quella scelta è visibile).
var _category_boxes: Dictionary = {}
# Nome risorsa -> Label della quantità (aggiornata a ogni refresh_stock).
var _quantity_labels: Dictionary = {}
# Nome risorsa -> Array di LineEdit del suo livello: una risorsa può avere più righe (la carne cruda in Materie prime e in
# "Da cucinare o lavorare" del Cibo), con lo stesso livello tenuto allineato (_sync_level_edits).
var _level_edits: Dictionary = {}
# Stessa cosa per il campo del massimo (2026-10-18).
var _max_edits: Dictionary = {}
var _food_summary_label: Label = null
# Livelli minimi (copia locale dei valori della partita) e ultimi dati ricevuti, per ricolorare subito a un cambio.
var _min_levels: Dictionary = {}
var _min_food_days: int = 0
var _max_levels: Dictionary = {}
var _last_stock: Dictionary = {}
var _last_days: float = -1.0
var _food_days_label: Label = null
# Elenco delle risorse mostrate all'ultima ricostruzione (per accorgersi di una risorsa appena scoperta).
var _shown_names: Array[String] = []

var _fill_row: HBoxContainer = null
var _fill_bar: PanelContainer = null
var _fill: ColorRect = null
var _fill_empty: Control = null
var _fill_percent: Label = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_label = Label.new()
	_inventory_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_label.custom_minimum_size.x = 0.0
	_inventory_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inventory_label)
	if _inventory_info.size() == 2:
		set_inventory_info(String(_inventory_info[0]), String(_inventory_info[1]))
	_build_tabs()
	# Elenco che scorre in altezza dentro il cassetto, mai in larghezza (il cassetto resta largo SideDrawer.WIDTH).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_list_box)
	_build_rules_section()
	_build_fill_bar()
	_mount_fill_bar.call_deferred()


# Dati del villaggio (GameScene, una volta al secondo a cassetto aperto): `stock` nome -> quantità
# (VillageStockService.get_village_stock), `daily_calorie_need` = consumo giornaliero di tutti gli individui,
# `storage_fill` = [spazio occupato, spazio totale] dei depositi (VillageStockService.get_storage_fill).
func refresh_stock(stock: Dictionary, daily_calorie_need: float, storage_fill: Array = []) -> void:
	if _list_box == null:
		return
	var names := _visible_resource_names()
	if names != _shown_names:
		_rebuild_rows(names)
	_last_stock = stock
	var calories := VillageStockService.get_food_calories(stock)
	_last_days = -1.0 if daily_calorie_need <= 0.0 else calories / daily_calorie_need
	if _food_summary_label != null:
		_food_summary_label.text = tr("warehouse_food_total_label").format({"calories": roundi(calories)})
	_apply_quantities()
	if storage_fill.size() >= 2:
		_set_fill(float(storage_fill[0]), float(storage_fill[1]))


# Riga dell'inventario: testo e tooltip (GameScene, a ogni aggiornamento del cassetto).
func set_inventory_info(text: String, tooltip: String) -> void:
	_inventory_info = [text, tooltip]
	if _inventory_label != null:
		_inventory_label.text = text
		_inventory_label.tooltip_text = TooltipText.wrap(tooltip)


# Frequenza dell'inventario della partita (GameScene, prima di _ready).
func set_inventory_interval(hours: int) -> void:
	_inventory_interval = hours


# Valori della partita (GameScene, prima di aggiungere il pannello al cassetto).
func set_min_levels(levels: Dictionary, food_days: int) -> void:
	_min_levels = levels.duplicate()
	_min_food_days = maxi(food_days, 0)


# Massimi per risorsa della partita (2026-10-18), prima di aggiungere il pannello al cassetto.
func set_max_levels(levels: Dictionary) -> void:
	_max_levels = levels.duplicate()


# `rows`: [{"type", "name" (chiave tr), "level"}] (FuelStockService.get_rule_rows).
func set_fuel_rule(enabled: bool, rows: Array[Dictionary]) -> void:
	_fuel_rule_enabled = enabled
	_fuel_rows = rows.duplicate()


func set_banquet_rule(safe_only: bool) -> void:
	_banquet_safe_only = safe_only


# Regola dei banchetti spontanei: titolo e la casella del terzo delle scorte.
func _build_banquet_rule_rows() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = tr("warehouse_rule_banquet")
	title.tooltip_text = TooltipText.wrap(tr("warehouse_rule_banquet_tooltip"))
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	box.add_child(title)
	var safe_toggle := CheckBox.new()
	safe_toggle.text = tr("warehouse_rule_banquet_safe_only")
	safe_toggle.tooltip_text = TooltipText.wrap(tr("warehouse_rule_banquet_safe_only_tooltip"))
	safe_toggle.button_pressed = _banquet_safe_only
	safe_toggle.focus_mode = Control.FOCUS_NONE
	safe_toggle.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	safe_toggle.toggled.connect(func(pressed: bool) -> void:
		_banquet_safe_only = pressed
		banquet_safe_only_toggled.emit(pressed)
	)
	box.add_child(safe_toggle)
	return box


func set_toolkit_rule(enabled: bool, rows: Array[Dictionary]) -> void:
	_toolkit_rule_enabled = enabled
	_toolkit_rows = rows.duplicate(true)


# Regola "Rifornisci le Attrezzerie" (2026-10-18): casella accesa/spenta e accanto "Modifica…", che apre il dettaglio in
# un popup (2026-10-18, richiesta utente: aperto sempre nel cassetto lo allargava e occupava troppo; come "Modifica
# ordine…" delle Regole di assegnazione). Nel popup, per ogni tipo con Attrezzeria icona e nome e sotto, rientrati, gli
# attrezzi che accetta con il campo compatto dei pezzi voluti (tetto: pezzi per tipo dell'Attrezzeria). Valgono per
# tutti gli edifici di quel tipo.
func _build_toolkit_rule_rows() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var toggle := CheckBox.new()
	toggle.text = tr("warehouse_rule_toolkit")
	toggle.tooltip_text = TooltipText.wrap(tr("warehouse_rule_toolkit_tooltip"))
	toggle.button_pressed = _toolkit_rule_enabled
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.clip_text = true
	toggle.toggled.connect(func(pressed: bool) -> void:
		_toolkit_rule_enabled = pressed
		toolkit_rule_toggled.emit(pressed)
	)
	row.add_child(toggle)
	var edit_button := Button.new()
	edit_button.text = tr("warehouse_rule_toolkit_edit")
	edit_button.tooltip_text = TooltipText.wrap(tr("warehouse_rule_toolkit_edit_tooltip"))
	edit_button.focus_mode = Control.FOCUS_NONE
	edit_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	edit_button.pressed.connect(func() -> void: _open_toolkit_popup(edit_button))
	row.add_child(edit_button)
	return row


# Popup del dettaglio Attrezzerie, rifatto a ogni apertura dalle righe di adesso; largo quanto il cassetto, alto quanto
# le voci (al massimo lo schermo, poi scorrono), con il fondo appena sopra il pulsante. Si chiude con un clic fuori o Esc.
func _open_toolkit_popup(anchor: Control) -> void:
	if _toolkit_popup != null:
		_toolkit_popup.queue_free()
	_toolkit_popup = PopupPanel.new()
	_toolkit_popup.add_theme_stylebox_override("panel", _make_toolkit_popup_style())
	add_child(_toolkit_popup)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_toolkit_popup.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	var title := Label.new()
	title.text = tr("warehouse_rule_toolkit")
	title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	box.add_child(title)
	if _toolkit_rows.is_empty():
		var empty := Label.new()
		empty.text = tr("warehouse_rule_toolkit_empty")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		box.add_child(empty)
	for entry in _toolkit_rows:
		var type_name := String(entry.get("type", ""))
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 6)
		header.add_child(IconRegistry.build_building_icon_box(type_name, LIST_ICON_SIDE))
		header.add_child(_toolkit_popup_label(tr(String(entry.get("name", type_name)))))
		box.add_child(header)
		for tool_entry in entry.get("tools", []):
			var tool_name := String(tool_entry.get("tool", ""))
			var max_units := int(tool_entry.get("max", 0))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var indent := Control.new()
			indent.custom_minimum_size = Vector2(LIST_ICON_SIDE, 0.0)
			row.add_child(indent)
			var tool_label := _toolkit_popup_label(IconRegistry.get_resource_display_name(tool_name))
			tool_label.tooltip_text = TooltipText.wrap(tr("warehouse_rule_toolkit_tool_tooltip").format({"max": max_units}))
			tool_label.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(tool_label)
			row.add_child(_build_level_field(int(tool_entry.get("level", 0)), func(level: int) -> void:
				var clamped := mini(level, max_units)
				tool_entry["level"] = clamped
				toolkit_target_changed.emit(type_name, tool_name, clamped)
			, "warehouse_rule_toolkit_tool_tooltip", 1, 0, true))
			box.add_child(row)
	var style := _toolkit_popup.get_theme_stylebox("panel")
	var margins := style.get_minimum_size() if style != null else Vector2.ZERO
	var screen_height := int(get_viewport().get_visible_rect().size.y)
	var width := int(get_global_rect().size.x) - 2 * TOOLKIT_POPUP_INSET
	var height := mini(int(ceilf(box.get_combined_minimum_size().y + margins.y)), screen_height - 2 * TOOLKIT_POPUP_INSET)
	var x := int(get_global_rect().position.x) + TOOLKIT_POPUP_INSET
	var y := clampi(int(anchor.get_global_rect().position.y) - height - 4, 0, maxi(screen_height - height, 0))
	_toolkit_popup.popup(Rect2i(Vector2i(x, y), Vector2i(width, height)))


# Etichetta del popup che si accorcia con "…" invece di allargarlo.
func _toolkit_popup_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


# Fondo pieno con bordo chiaro, come il popup "Modifica ordine…" delle Regole di assegnazione.
func _make_toolkit_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TOOLKIT_POPUP_BG_COLOR
	style.set_border_width_all(1)
	style.border_color = TOOLKIT_POPUP_BORDER_COLOR
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


# Regola del combustibile: casella accesa/spenta, poi per ogni tipo icona, nome e campo − [N] + (spenti con la regola).
func _build_fuel_rule_rows() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var toggle := CheckBox.new()
	toggle.text = tr("warehouse_rule_fuel")
	toggle.tooltip_text = TooltipText.wrap(tr("warehouse_rule_fuel_tooltip"))
	toggle.button_pressed = _fuel_rule_enabled
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	box.add_child(toggle)
	var types_box := VBoxContainer.new()
	types_box.add_theme_constant_override("separation", 2)
	types_box.visible = _fuel_rule_enabled
	box.add_child(types_box)
	toggle.toggled.connect(func(pressed: bool) -> void:
		_fuel_rule_enabled = pressed
		types_box.visible = pressed
		fuel_rule_toggled.emit(pressed)
	)
	for entry in _fuel_rows:
		var type_name := String(entry.get("type", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.tooltip_text = TooltipText.wrap(tr("warehouse_rule_fuel_type_tooltip"))
		row.add_child(IconRegistry.build_building_icon_box(type_name, LIST_ICON_SIDE))
		var label := Label.new()
		label.text = tr(String(entry.get("name", type_name)))
		label.tooltip_text = TooltipText.wrap(row.tooltip_text)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		row.add_child(_build_level_field(int(entry.get("level", 0)), func(level: int) -> void:
			entry["level"] = level
			fuel_min_changed.emit(type_name, level)
		, "warehouse_rule_fuel_type_tooltip"))
		types_box.add_child(row)
	return box


# Stato del pulsante della regola "Carne e pelli in eccesso" (stessi argomenti di ButcherDestinationButton.set_destination).
func set_excess_meat_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> void:
	_excess_meat_state = [is_shown, current, options]
	if _excess_meat_button != null:
		_excess_meat_button.set_destination(is_shown, current, options)


# Regola "Frequenza dell'inventario" (2026-10-11): ogni 6 h, 12 h, 1, 2, 3 o 5 giorni.
func _build_inventory_interval_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = TooltipText.wrap(tr("warehouse_rule_inventory_interval_tooltip"))
	var label := Label.new()
	label.text = tr("warehouse_rule_inventory_interval")
	label.tooltip_text = TooltipText.wrap(row.tooltip_text)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	picker.tooltip_text = TooltipText.wrap(row.tooltip_text)
	for hours in INVENTORY_INTERVAL_OPTIONS:
		var text := tr("warehouse_inventory_every_hours").format({"hours": hours}) if hours < 24 \
			else tr("warehouse_inventory_every_days").format({"days": hours / 24})
		picker.add_item(text, hours)
	picker.select(maxi(INVENTORY_INTERVAL_OPTIONS.find(_inventory_interval), 0))
	picker.item_selected.connect(func(index: int) -> void:
		_inventory_interval = picker.get_item_id(index)
		inventory_interval_changed.emit(_inventory_interval)
	)
	row.add_child(picker)
	return row


func _build_rules_section() -> void:
	add_child(HSeparator.new())
	var toggle := Button.new()
	toggle.text = tr("warehouse_rules")
	toggle.flat = true
	toggle.toggle_mode = true
	toggle.button_pressed = _rules_open
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	add_child(toggle)
	_rules_box = VBoxContainer.new()
	_rules_box.add_theme_constant_override("separation", 4)
	_rules_box.visible = _rules_open
	add_child(_rules_box)
	toggle.toggled.connect(func(pressed: bool) -> void:
		_rules_open = pressed
		_rules_box.visible = pressed
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = TooltipText.wrap(tr("warehouse_rule_excess_meat_tooltip"))
	var label := Label.new()
	label.text = tr("warehouse_rule_excess_meat")
	label.tooltip_text = TooltipText.wrap(row.tooltip_text)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_excess_meat_button = ButcherDestinationPair.new()
	_excess_meat_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_excess_meat_button.tooltip_key = "warehouse_rule_excess_meat_button_tooltip"
	_excess_meat_button.destination_chosen.connect(func(destination: String) -> void: excess_meat_destination_changed.emit(destination))
	row.add_child(_excess_meat_button)
	# Frequenza dell'inventario per prima (2026-10-17, richiesta utente), voci divise da un tratteggio.
	DashedSeparator.add_item(_rules_box, _build_inventory_interval_row())
	DashedSeparator.add_item(_rules_box, row)
	DashedSeparator.add_item(_rules_box, _build_fuel_rule_rows())
	DashedSeparator.add_item(_rules_box, _build_toolkit_rule_rows())
	DashedSeparator.add_item(_rules_box, _build_banquet_rule_rows())
	if _excess_meat_state.size() == 3:
		var options: Array[Dictionary] = []
		options.assign(_excess_meat_state[2])
		_excess_meat_button.set_destination(bool(_excess_meat_state[0]), _excess_meat_state[1], options)


# Numeri e colori delle quantità e dei giorni di autonomia dagli ultimi dati ricevuti e dai livelli.
func _apply_quantities() -> void:
	for resource_name in _quantity_labels.keys():
		var quantity: int = int(_last_stock.get(resource_name, 0))
		var level: int = int(_min_levels.get(resource_name, 0))
		var max_level: int = int(_max_levels.get(resource_name, 0))
		for label in _quantity_labels[resource_name]:
			label.text = str(quantity)
			label.modulate = Color(1, 1, 1, 1)
			if level > 0 and quantity < level:
				label.modulate = BELOW_LEVEL_COLOR
			elif max_level > 0 and quantity > max_level:
				label.modulate = ABOVE_MAX_COLOR
			elif quantity <= 0:
				label.modulate = ZERO_QUANTITY_COLOR
	if _food_days_label != null:
		_food_days_label.text = tr("warehouse_food_days_infinite") if _last_days < 0.0 else "%.1f" % _last_days
		var below := _min_food_days > 0 and _last_days >= 0.0 and _last_days < float(_min_food_days)
		_food_days_label.modulate = BELOW_LEVEL_COLOR if below else Color(1, 1, 1, 1)


# --- Campo del livello minimo: − [numero] + ---

# `on_change(value)` alla conferma di un valore nuovo (bottoni, Invio o uscita dal campo).
# `step` e `min_value` (2026-10-17, calorie dei banchetti: passi di 100, minimo 500); di base 1 e 0, come prima.
# `compact` (2026-10-18, righe delle risorse): [campo stretto][+ sopra, − sotto]; anche la rotella cambia il valore (±1,
# Shift ±10). `none_text`: testo del valore 0 ("—", o "∞" per il massimo).
func _build_level_field(
	initial: int, on_change: Callable, tooltip_key: String = "warehouse_min_level_tooltip", step: int = 1, min_value: int = 0,
	compact: bool = false, none_text: String = LEVEL_NONE_TEXT
) -> Control:
	var tooltip := tr(tooltip_key)
	if compact:
		tooltip += "\n" + tr("warehouse_level_wheel_hint")
	var field := HBoxContainer.new()
	field.add_theme_constant_override("separation", 0)
	field.tooltip_text = TooltipText.wrap(tooltip)
	field.mouse_filter = Control.MOUSE_FILTER_PASS
	var edit := LineEdit.new()
	var minus := _level_button("−", tooltip)
	var plus := _level_button("+", tooltip)
	edit.custom_minimum_size = Vector2(LEVEL_COMPACT_EDIT_WIDTH if compact else LEVEL_EDIT_WIDTH, 0.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	edit.tooltip_text = TooltipText.wrap(tooltip)
	edit.context_menu_enabled = false
	edit.set_meta("level", initial)
	edit.set_meta("none_text", none_text)
	edit.text = _level_text(initial, none_text)
	var commit := func(value: int) -> void:
		var clamped := clampi(value, min_value, LEVEL_MAX)
		edit.text = _level_text(clamped, none_text)
		if clamped == int(edit.get_meta("level")):
			return
		edit.set_meta("level", clamped)
		on_change.call(clamped)
	minus.pressed.connect(func() -> void: commit.call(int(edit.get_meta("level")) - step))
	plus.pressed.connect(func() -> void: commit.call(int(edit.get_meta("level")) + step))
	edit.focus_entered.connect(func() -> void:
		if int(edit.get_meta("level")) <= 0:
			edit.text = ""
		edit.select_all.call_deferred()
	)
	edit.text_submitted.connect(func(text: String) -> void:
		commit.call(int(text) if text.strip_edges().is_valid_int() else 0)
		edit.release_focus()
	)
	edit.focus_exited.connect(func() -> void:
		commit.call(int(edit.text) if edit.text.strip_edges().is_valid_int() else 0)
	)
	if compact:
		edit.gui_input.connect(func(event: InputEvent) -> void:
			var wheel := event as InputEventMouseButton
			if wheel == null or not wheel.pressed:
				return
			var amount := step * (10 if wheel.shift_pressed else 1)
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				commit.call(int(edit.get_meta("level")) + amount)
				edit.accept_event()
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				commit.call(int(edit.get_meta("level")) - amount)
				edit.accept_event()
		)
		_style_compact_edit(edit)
		field.add_theme_constant_override("separation", 1)
		field.custom_minimum_size.x = LEVEL_COMPACT_COLUMN_WIDTH
		field.alignment = BoxContainer.ALIGNMENT_CENTER
		field.add_child(edit)
		var buttons := VBoxContainer.new()
		buttons.add_theme_constant_override("separation", 0)
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		for button in [plus, minus]:
			_style_compact_button(button)
			buttons.add_child(button)
		field.add_child(buttons)
		return field
	field.add_child(minus)
	field.add_child(edit)
	field.add_child(plus)
	return field


# Campo compatto: font piccolo, margini minimi, bordo sottile (più chiaro col fuoco).
func _style_compact_edit(edit: LineEdit) -> void:
	edit.add_theme_font_size_override("font_size", LEVEL_COMPACT_FONT_SIZE)
	for state in ["normal", "focus", "read_only"]:
		var box := StyleBoxFlat.new()
		box.bg_color = LEVEL_COMPACT_BG
		box.border_color = LEVEL_COMPACT_BORDER_FOCUS if state == "focus" else LEVEL_COMPACT_BORDER
		box.set_border_width_all(1)
		box.set_corner_radius_all(2)
		box.content_margin_left = 1.0
		box.content_margin_right = 1.0
		box.content_margin_top = 1.0
		box.content_margin_bottom = 1.0
		edit.add_theme_stylebox_override(state, box)


# + e − compatti: senza sfondo né margini, solo il segno, uno sopra l'altro.
func _style_compact_button(button: Button) -> void:
	button.custom_minimum_size = LEVEL_COMPACT_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", LEVEL_COMPACT_BUTTON_FONT_SIZE)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _level_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(LEVEL_BUTTON_WIDTH, 0.0)
	button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	button.tooltip_text = TooltipText.wrap(tooltip)
	return button


func _level_text(level: int, none_text: String = LEVEL_NONE_TEXT) -> String:
	return none_text if level <= 0 else str(level)


func _on_resource_level_changed(resource_name: String, level: int) -> void:
	if level > 0:
		_min_levels[resource_name] = level
	else:
		_min_levels.erase(resource_name)
	_sync_level_edits(resource_name, level)
	min_level_changed.emit(resource_name, level)
	# Minimo sopra il massimo (2026-10-18): il massimo sale con lui.
	var max_level: int = int(_max_levels.get(resource_name, 0))
	if level > 0 and max_level > 0 and level > max_level:
		_set_max_level(resource_name, level)
	_apply_quantities()


# Campo del massimo cambiato (2026-10-18). Massimo sotto il minimo: il minimo scende con lui.
func _on_resource_max_changed(resource_name: String, level: int) -> void:
	_set_max_level(resource_name, level)
	var min_level: int = int(_min_levels.get(resource_name, 0))
	if level > 0 and min_level > level:
		_min_levels[resource_name] = level
		_sync_level_edits(resource_name, level)
		min_level_changed.emit(resource_name, level)
	_apply_quantities()


func _set_max_level(resource_name: String, level: int) -> void:
	if level > 0:
		_max_levels[resource_name] = level
	else:
		_max_levels.erase(resource_name)
	for edit in _max_edits.get(resource_name, []):
		if is_instance_valid(edit) and int(edit.get_meta("level")) != level:
			edit.set_meta("level", level)
			edit.text = _level_text(level, String(edit.get_meta("none_text", LEVEL_NONE_TEXT)))
	max_level_changed.emit(resource_name, level)


# Stesso livello su tutte le righe della risorsa (quella appena cambiata è già a posto).
func _sync_level_edits(resource_name: String, level: int) -> void:
	for edit in _level_edits.get(resource_name, []):
		if is_instance_valid(edit) and int(edit.get_meta("level")) != level:
			edit.set_meta("level", level)
			edit.text = _level_text(level, String(edit.get_meta("none_text", LEVEL_NONE_TEXT)))


func _on_food_days_level_changed(days: int) -> void:
	_min_food_days = days
	_apply_quantities()
	min_food_days_changed.emit(days)


# Etichetta della colonna della quantità: larghezza fissa, allineata a destra.
func _quantity_column_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(QUANTITY_COLUMN_WIDTH, 0.0)
	label.clip_text = true
	return label


# --- Linguette per categoria ---

func _build_tabs() -> void:
	_tab_bar = TabBar.new()
	_tab_bar.clip_tabs = false
	_tab_bar.add_theme_constant_override("h_separation", 0)
	add_child(_tab_bar)
	for category in TAB_ORDER:
		var tab_index := _tab_bar.tab_count
		_tab_bar.add_tab("", _category_icon_texture(int(category)))
		_tab_bar.set_tab_icon_max_width(tab_index, TAB_ICON_SIDE)
		_tab_bar.set_tab_tooltip(tab_index, _category_name(int(category)))
		_tab_bar.set_tab_metadata(tab_index, int(category))
	_tab_bar.current_tab = clampi(_tab_index_of(_last_category), 0, _tab_bar.tab_count - 1)
	_tab_bar.tab_changed.connect(func(tab: int) -> void:
		_last_category = int(_tab_bar.get_tab_metadata(tab))
		_show_selected_category()
	)
	# Le icone sono pronte solo dopo il fotogramma in cui i SubViewport le disegnano.
	_redraw_tabs_after_render.call_deferred()


func _tab_index_of(category: int) -> int:
	for tab_index in range(_tab_bar.tab_count):
		if int(_tab_bar.get_tab_metadata(tab_index)) == category:
			return tab_index
	return 0


func _redraw_tabs_after_render() -> void:
	await get_tree().process_frame
	if is_instance_valid(_tab_bar):
		_tab_bar.queue_redraw()


func _category_icon_texture(category: int) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(TAB_ICON_RENDER_SIDE, TAB_ICON_RENDER_SIDE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var icon := StockCategoryIcon.new()
	icon.category = category
	icon.position = Vector2.ZERO
	icon.size = Vector2(TAB_ICON_RENDER_SIDE, TAB_ICON_RENDER_SIDE)
	viewport.add_child(icon)
	add_child(viewport)
	return viewport.get_texture()


func _category_name(category: int) -> String:
	return tr("category_name_%s" % String(SecondaryResourceTypes.Category.keys()[category]).to_lower())


func _show_selected_category() -> void:
	for category in _category_boxes.keys():
		(_category_boxes[category] as Control).visible = int(category) == _last_category


# --- Elenco ---

# Risorse da mostrare, in ordine alfabetico: solo quelle ottenibili (2026-10-11, regola unica): ogni risorsa
# che dipende da una scoperta dichiara la sua idea in SecondaryResourceRules.required_idea_id e compare solo con l'idea
# completata (es. erbe medicinali con "plant_lore", fish_meat con la futura "fishing").
func _visible_resource_names() -> Array[String]:
	var names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		# Rifiuti (2026-10-18, detriti): mai in magazzino, nessuna riga.
		if not TerrainScatteredResourceService.is_resource_locked(resource_name) and not WasteDisposalService.is_waste_only(resource_name):
			names.append(resource_name)
	# In ordine alfabetico del nome mostrato, nella lingua scelta (2026-10-11, richiesta utente).
	names.sort_custom(func(a: String, b: String) -> bool:
		return IconRegistry.get_resource_display_name(a).naturalnocasecmp_to(IconRegistry.get_resource_display_name(b)) < 0
	)
	return names


func _rebuild_rows(names: Array[String]) -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_category_boxes.clear()
	_quantity_labels.clear()
	_level_edits.clear()
	_max_edits.clear()
	_food_summary_label = null
	_food_days_label = null
	_shown_names = names.duplicate()
	for category in SecondaryResourceTypes.Category.values():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		_list_box.add_child(box)
		_category_boxes[int(category)] = box
		if category == SecondaryResourceTypes.Category.FOOD:
			# Riga del totale: testo (calorie), giorni di autonomia nella colonna della quantità, livello in giorni.
			var food_row := HBoxContainer.new()
			food_row.add_theme_constant_override("separation", 6)
			_food_summary_label = Label.new()
			_food_summary_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
			_food_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_food_summary_label.custom_minimum_size.x = 0.0
			_food_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_food_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			food_row.add_child(_food_summary_label)
			_food_days_label = _quantity_column_label()
			food_row.add_child(_food_days_label)
			# Giorni minimi (2026-10-18): campo compatto come le righe (+ e − impilati a destra), in fondo alla riga (colonna
			# "Max", così la scritta del totale ha più spazio) e alto quanto quelli delle righe, centrato.
			var days_field := _build_level_field(
				_min_food_days, _on_food_days_level_changed, "warehouse_food_days_auto_tooltip", 1, 0, true
			)
			days_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			food_row.add_child(days_field)
			box.add_child(food_row)
			box.add_child(HSeparator.new())
		box.add_child(_build_column_header())
		for resource_name in names:
			var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			# La carne cruda (2026-10-11): solo in "Da cucinare o lavorare" del Cibo.
			if StockRequestService.DERIVED_LEVEL_RESOURCES.has(resource_name):
				continue
			if rules != null and rules.category == category:
				box.add_child(_build_row(resource_name))
		if category == SecondaryResourceTypes.Category.FOOD:
			_add_food_ingredients_section(box, names)
	_show_selected_category()
	_apply_quantities()


# Intestazione delle colonne (2026-10-18): "Qtà", "Min", "Max" allineate ai campi delle righe.
func _build_column_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	for column in [["warehouse_column_quantity", QUANTITY_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_RIGHT],
			["warehouse_column_min", LEVEL_COMPACT_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_CENTER],
			["warehouse_column_max", LEVEL_COMPACT_COLUMN_WIDTH, HORIZONTAL_ALIGNMENT_CENTER]]:
		var label := Label.new()
		label.text = tr(String(column[0]))
		label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
		label.custom_minimum_size = Vector2(float(column[1]), 0.0)
		label.horizontal_alignment = column[2]
		label.modulate = COLUMN_HEADER_COLOR
		header.add_child(label)
	return header


func _build_row(resource_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_build_resource_chip(resource_name))
	var name_label := Label.new()
	name_label.text = IconRegistry.get_resource_display_name(resource_name)
	name_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var quantity_label := _quantity_column_label()
	row.add_child(quantity_label)
	if not _quantity_labels.has(resource_name):
		_quantity_labels[resource_name] = []
	(_quantity_labels[resource_name] as Array).append(quantity_label)
	var tooltip_key := "warehouse_min_level_auto_tooltip" if StockRequestService.source_kind_for(resource_name) != "" else "warehouse_min_level_tooltip"
	# Carne cruda (2026-10-16, richiesta utente): livello proprio, la riserva in più oltre al fabbisogno dei prodotti
	# (StockRequestService.DERIVED_LEVEL_RESOURCES); tooltip suo.
	if StockRequestService.DERIVED_LEVEL_RESOURCES.has(resource_name):
		tooltip_key = "warehouse_meat_level_tooltip"
	var on_change := func(level: int) -> void: _on_resource_level_changed(resource_name, level)
	var field := _build_level_field(int(_min_levels.get(resource_name, 0)), on_change, tooltip_key, 1, 0, true)
	row.add_child(field)
	if not _level_edits.has(resource_name):
		_level_edits[resource_name] = []
	(_level_edits[resource_name] as Array).append(field.get_child(0))
	# Massimo (2026-10-18, Fossa dei rifiuti): secondo campo, stessa forma.
	var on_max_change := func(level: int) -> void: _on_resource_max_changed(resource_name, level)
	var max_field := _build_level_field(
		int(_max_levels.get(resource_name, 0)), on_max_change, "warehouse_max_level_tooltip", 1, 0, true, LEVEL_INFINITE_TEXT
	)
	row.add_child(max_field)
	if not _max_edits.has(resource_name):
		_max_edits[resource_name] = []
	(_max_edits[resource_name] as Array).append(max_field.get_child(0))
	return row


# "Da cucinare o lavorare" (2026-10-11, richiesta utente) in fondo al Cibo: le risorse visibili NON di categoria cibo che
# sono ingrediente di una ricetta di categoria cibo (oggi la carne cruda: carne cotta, essiccata, affumicata), con la
# stessa riga della loro linguetta (stessa quantità, stesso livello). Non contano nelle calorie: lo dice la scritta.
func _add_food_ingredients_section(box: VBoxContainer, names: Array[String]) -> void:
	var ingredients := _food_ingredient_names(names)
	if ingredients.is_empty():
		return
	box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = tr("warehouse_food_ingredients_title")
	title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	box.add_child(title)
	var note := Label.new()
	note.text = tr("warehouse_food_ingredients_note")
	note.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 0.0
	note.modulate = ZERO_QUANTITY_COLOR
	box.add_child(note)
	box.add_child(_build_column_header())
	for resource_name in ingredients:
		box.add_child(_build_row(resource_name))


func _food_ingredient_names(names: Array[String]) -> Array[String]:
	var inputs: Dictionary = {}
	for recipe_name in CaloricCalculator.list_secondary_resource_names():
		var recipe_rules := CaloricCalculator.get_caloric_source_rules(recipe_name)
		if recipe_rules != null and recipe_rules.category == SecondaryResourceTypes.Category.FOOD:
			for input_name in recipe_rules.recipe_inputs.keys():
				inputs[String(input_name)] = true
	var result: Array[String] = []
	for resource_name in names:
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if inputs.has(resource_name) and rules != null and rules.category != SecondaryResourceTypes.Category.FOOD:
			result.append(resource_name)
	return result


# Icona della risorsa sul suo colore, come le righe del cassetto dell'Assegnazione (TaskAssignmentPanel._build_entry_icon,
# ramo "resource"); senza icona disegnata l'emoji o l'iniziale.
func _build_resource_chip(resource_name: String) -> Control:
	var chip := ColorRect.new()
	chip.color = IconRegistry.get_resource_color(resource_name)
	chip.custom_minimum_size = Vector2(LIST_ICON_SIDE, LIST_ICON_SIDE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var resource_icon: Control = IconRegistry.get_resource_icon_node(resource_name)
	if resource_icon == null:
		var initial := Label.new()
		var emoji := IconRegistry.get_resource_icon(resource_name)
		initial.text = emoji if emoji != "" else resource_name.substr(0, 1).to_upper()
		initial.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		resource_icon = initial
	resource_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	resource_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(resource_icon)
	return chip


# --- Barra di riempimento dei depositi (accanto al titolo del cassetto) ---

func _build_fill_bar() -> void:
	_fill_row = HBoxContainer.new()
	_fill_row.add_theme_constant_override("separation", 6)
	_fill_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_bar = PanelContainer.new()
	_fill_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fill_bar.custom_minimum_size = Vector2(FILL_BAR_MIN_WIDTH, FILL_BAR_HEIGHT)
	_fill_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_fill_bar.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = FILL_BAR_BG_COLOR
	style.border_color = FILL_BAR_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	_fill_bar.add_theme_stylebox_override("panel", style)
	_fill_row.add_child(_fill_bar)
	# Riempimento e parte vuota divisi in proporzione alla percentuale (stretch ratio), come il carico di lavoro.
	var fill_box := HBoxContainer.new()
	fill_box.add_theme_constant_override("separation", 0)
	fill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_bar.add_child(fill_box)
	_fill = ColorRect.new()
	_fill.color = FILL_GREEN
	_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.visible = false
	fill_box.add_child(_fill)
	_fill_empty = Control.new()
	_fill_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_box.add_child(_fill_empty)
	_fill_percent = Label.new()
	_fill_percent.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_fill_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fill_percent.mouse_filter = Control.MOUSE_FILTER_STOP
	_fill_row.add_child(_fill_percent)
	_set_fill(0.0, 0.0)


# La barra va nella riga del titolo del cassetto che contiene questo pannello (SideDrawer.set_header_extra), che la
# libera insieme al contenuto.
func _mount_fill_bar() -> void:
	var node := get_parent()
	while node != null and not (node is SideDrawer):
		node = node.get_parent()
	if node != null and _fill_row != null:
		(node as SideDrawer).set_header_extra(_fill_row)


func _set_fill(used: float, capacity: float) -> void:
	if _fill_bar == null:
		return
	var percent: int = clampi(roundi(100.0 * used / capacity), 0, 100) if capacity > 0.0 else 0
	_fill_percent.text = "%d%%" % percent
	var tooltip := tr("warehouse_storage_fill_tooltip").format({"used": roundi(used), "capacity": roundi(capacity)})
	_fill_bar.tooltip_text = TooltipText.wrap(tooltip)
	_fill_percent.tooltip_text = TooltipText.wrap(tooltip)
	_fill.visible = percent > 0
	_fill_empty.visible = percent < 100
	_fill.size_flags_stretch_ratio = maxf(float(percent), 0.001)
	_fill_empty.size_flags_stretch_ratio = maxf(float(100 - percent), 0.001)
	_fill.color = FILL_RED if percent >= FILL_RED_FROM_PERCENT else FILL_GREEN
