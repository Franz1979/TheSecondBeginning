class_name PickupChoiceDialog
extends Window

# Popup di scelta del comando di raccolta (2026-09-20, zaino multi-risorsa, passo 3) — SOSTITUISCE l'uso di
# OptionChoiceDialog per il pickup (quello resta solo per la Transport, che sceglie sempre UNA risorsa da un
# edificio). Menu GERARCHICO a tre livelli, tutto sempre visibile (righe indentate, stesso stile a bottoni
# "selezionato" di OptionChoiceDialog):
#
#   Tutto                          <- livello 1: criterio ALL (tutto quello che c'e' nella microcella)
#   └ Cibo                         <- livello 2: solo intestazione di categoria, non selezionabile
#      └ Tutto il cibo             <- livello 3: criterio CATEGORY
#      └ funghi                    <- livello 3: criterio NAME (una risorsa, con quantita')
#      └ ghiande
#   └ Materiali
#      └ Tutti i materiali
#      └ rametti
#
# Regole:
#   - compaiono SOLO le risorse realmente presenti (`resources` porta solo quelle con scorta) e solo le
#     categorie che ne hanno almeno una;
#   - scegliendo "Tutto" o il "tutto" di una categoria non si sceglie nessun livello inferiore;
#   - la riga quantita' (SpinBox) e' visibile SOLO con una risorsa specifica selezionata, con "tutto"/categoria
#     sparisce (la quantita' verrebbe ignorata da PickUpAction);
#   - preselezione: `default_choice` (per ora sempre "Tutto", fisso, deciso dal chiamante). Se il nodo di default
#     non e' presente si risale al nodo disponibile piu' vicino: la sua categoria ("tutto" della categoria), poi
#     "Tutto".
#
# "Pannello muto" (stesso principio di OptionChoiceDialog): open_dialog riceve testi e dati GIA' RISOLTI dal
# chiamante e non legge mai il mondo. Il criterio scelto esce dal segnale choice_made con gli stessi valori di
# PickUpAction.CriterionKind (NAME/CATEGORY/ALL), pronti per _assign_pickup_task.
#
# NESSUN visibility_changed collegato a GameScene._on_blocking_dialog_visibility_changed (come
# OptionChoiceDialog): scegliere cosa raccogliere e' un'azione rapida a gioco in corso, l'orologio non si ferma.

# kind: PickUpAction.CriterionKind (NAME = una risorsa, CATEGORY = tutta la categoria, ALL = tutto);
# category: SecondaryResourceTypes.Category come int (solo con CATEGORY, altrimenti -1); resource_name: solo
# con NAME, altrimenti ""; quantity: solo con NAME (quella scelta nello SpinBox), altrimenti -1; repeat: stato
# del flag "Ripeti fino a N volte" (2026-09-20), indipendente dal criterio.
# source_kind (2026-09-26, ground drop): PickUpAction.SourceKind della voce scelta (mucchio a terra o terreno).
signal choice_made(kind: int, category: int, resource_name: String, quantity: int, repeat: bool, source_kind: int)
# Modalità caccia (2026-10-01, comando Caccia nelle zone — open_hunt_dialog): solo il selettore "Carne", nessun elenco.
# `butcher_destination` (2026-10-03): destinazione dei prodotti della macellazione (ButcherDestinationService).
signal hunt_choice_made(meat_target: int, butcher_destination: String)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var choice_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ChoiceScroll/ChoiceListContainer
@onready var choice_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ChoiceScroll
@onready var repeat_check_box: CheckBox = $MarginContainer/VBoxContainer/RepeatCheckBox
@onready var quantity_row: HBoxContainer = $MarginContainer/VBoxContainer/QuantityRow
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $MarginContainer/VBoxContainer/QuantityRow/QuantitySpinBox
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton

# Chiavi tr() per categoria: [nome della categoria (intestazione), "tutto" della categoria].
const CATEGORY_TEXT_KEYS := {
	SecondaryResourceTypes.Category.FOOD: ["pickup_choice_category_food", "pickup_choice_all_food"],
	SecondaryResourceTypes.Category.RAW_MATERIAL: ["pickup_choice_category_raw_material", "pickup_choice_all_raw_material"],
	SecondaryResourceTypes.Category.MEDICINAL: ["pickup_choice_category_medicinal", "pickup_choice_all_medicinal"],
	SecondaryResourceTypes.Category.SEMI_FINISHED: ["pickup_choice_category_semi_finished", "pickup_choice_all_semi_finished"],
	SecondaryResourceTypes.Category.TOOL: ["pickup_choice_category_tool", "pickup_choice_all_tool"],
}

# Sorgenti nell'ordine in cui compaiono (2026-09-26, ground drop): prima il mucchio a terra (sta sopra), poi il
# terreno, con la chiave tr() della loro intestazione. Le intestazioni compaiono solo se le sorgenti sono due.
const SOURCE_ORDER: Array[int] = [PickUpAction.SourceKind.GROUND_PILE, PickUpAction.SourceKind.TERRAIN]
# Riquadri delle sorgenti (2026-09-26, richiesta utente — con due sorgenti le sezioni si distinguevano poco):
# sfondo leggermente diverso per sorgente (terroso per il mucchio, verdastro per il terreno), bordo, intestazione
# più grande staccata da un separatore, spazio vuoto tra un riquadro e l'altro.
const SOURCE_PANEL_COLORS := {
	PickUpAction.SourceKind.GROUND_PILE: Color(0.30, 0.24, 0.17, 1.0),
	PickUpAction.SourceKind.TERRAIN: Color(0.19, 0.25, 0.18, 1.0),
}
const SOURCE_PANEL_BORDER_COLOR := Color(0.55, 0.52, 0.45, 1.0)
const SOURCE_HEADER_FONT_SIZE: int = 15
const SOURCE_PANEL_GAP: float = 10.0
const SOURCE_TEXT_KEYS := {
	PickUpAction.SourceKind.GROUND_PILE: "pickup_choice_source_ground_pile",
	PickUpAction.SourceKind.TERRAIN: "pickup_choice_source_terrain",
}

const INDENT_PER_LEVEL: float = 16.0
const RESOURCE_ROW_ICON_SIZE: float = 24.0

# Dimensionamento del popup (stesso principio di OptionChoiceDialog): base = messaggio + riga quantita' +
# separatore + riga bottoni; poi una riga per voce del menu. Tetto al valore di MAX_DIALOG_HEIGHT, oltre il
# quale la lista scorre (ScrollContainer).
const DIALOG_BASE_HEIGHT: float = 224.0
const ROW_HEIGHT: float = 34.0
const MAX_DIALOG_HEIGHT: float = 640.0
const DIALOG_WIDTH: int = 320

# Voci selezionabili, in ordine di comparsa: {"button": Button, "kind": int, "category": int,
# "resource_name": String, "max_quantity": int, "source_kind": int (PickUpAction.SourceKind)}. La selezione e' radio-style: una sola alla volta.
var _choices: Array[Dictionary] = []
var _selected_index: int = -1
# Contenitore in cui _add_source_section/_add_choice aggiungono le righe: la lista stessa, oppure il riquadro
# della sorgente quando le sorgenti sono due (2026-09-26).
var _rows_container: VBoxContainer = null
# false = nessuna scelta della quantità (2026-09-27, raccolta nelle zone di lavoro: la quantità non si sceglie).
var _quantity_enabled: bool = true
# Selettore "viaggi" (2026-10-01, raccolta nelle zone): al posto della casella delle ripetizioni quando open_dialog riceve
# trips > 0. Riga costruita in codice sotto la casella (_ensure_trips_row). Il valore scelto è in selected_trips al
# momento di choice_made (repeat = selected_trips > 1); 0 = modalità casella (clic su una cella).
var selected_trips: int = 0
var _trips_mode: bool = false
var _trips_row: HBoxContainer = null
var _trips_spin_box: SpinBox = null
# Modalità caccia (open_hunt_dialog): riga "Carne" con i valori ammessi, costruita in codice come la riga dei viaggi.
var _hunt_mode: bool = false
var _meat_row: HBoxContainer = null
var _meat_option: OptionButton = null
var _meat_values: Array[int] = []
# Altezza di partenza in modalità caccia: la finestra poi si adatta al contenuto (_fit_to_content).
const HUNT_DIALOG_HEIGHT: float = 120.0
# Sezione "Destinazione" della caccia (2026-10-03): una riga per opzione, a scelta singola.
const DESTINATION_ICON_SIZE: float = 20.0
const DESTINATION_LOCK_ICON := "🔒"
var _destination_section: VBoxContainer = null
var _destination_rows: VBoxContainer = null
var _destination_group: ButtonGroup = null
# Bottone di scelta -> id della destinazione.
var _destination_ids: Dictionary = {}


func _ready() -> void:
	quantity_label.text = tr("transport_dialog_quantity_label")
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": TaskRepeatRules.MAX_TRIPS})
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)
	# Esc chiude senza fare nulla, in entrambe le modalità (2026-10-01).
	window_input.connect(_on_window_input)


# `resources`: Array di Dictionary {"resource_name": String, "category": int, "quantity": int (> 0),
# "source_kind": PickUpAction.SourceKind (facoltativo, default TERRAIN)} — SOLO
# quelle realmente presenti nella microcella. `default_choice`: {"kind": PickUpAction.CriterionKind,
# "category": int, "resource_name": String}; vuoto o senza "kind" = "Tutto" (il default fisso di oggi).
# `repeat_default`: stato iniziale del flag "Ripeti fino a N viaggi" (2026-09-20: UserOptions.repeat_default).
# repeat_max/quantity_enabled (2026-09-27, work areas passo 3a): ripetizioni mostrate nella spunta (3 per il clic su una
# cella, 5 per la raccolta nelle zone) e scelta della quantità (spenta per le zone).
func open_dialog(
	dialog_title: String, message: String, resources: Array, default_choice: Dictionary = {}, repeat_default: bool = false,
	repeat_max: int = TaskRepeatRules.MAX_REPEATS, quantity_enabled: bool = true, trips: int = 0, trips_max: int = 0
) -> void:
	_set_hunt_mode(false)
	title = dialog_title
	message_label.text = message
	repeat_check_box.button_pressed = repeat_default
	# Il testo conta i viaggi in tutto (2026-10-05): il primo più repeat_max ripetizioni.
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": repeat_max + 1})
	_trips_mode = trips > 0
	repeat_check_box.visible = not _trips_mode
	_ensure_trips_row()
	_trips_row.visible = _trips_mode
	selected_trips = 0
	if _trips_mode:
		_trips_spin_box.max_value = maxi(trips_max, 1)
		_trips_spin_box.value = clampi(trips, 1, maxi(trips_max, 1))
	_quantity_enabled = quantity_enabled

	for child in choice_list_container.get_children():
		child.queue_free()
	_choices.clear()
	_selected_index = -1

	# Sorgenti presenti (2026-09-26, ground drop): una voce senza "source_kind" e' del terreno. Con due sorgenti
	# ogni sezione ha la propria intestazione e il proprio "Tutto"/categorie, perche' una raccolta prende da una
	# sola sorgente; con una sola sorgente il menu e' quello di sempre.
	var by_source: Dictionary = {}
	for entry in resources:
		var source_kind: int = int(entry.get("source_kind", PickUpAction.SourceKind.TERRAIN))
		if not by_source.has(source_kind):
			by_source[source_kind] = []
		by_source[source_kind].append(entry)
	var show_source_headers: bool = by_source.size() > 1
	var row_count: int = 0
	var first_block: bool = true
	for source_kind in SOURCE_ORDER:
		if not by_source.has(source_kind):
			continue
		_rows_container = choice_list_container
		if show_source_headers:
			if not first_block:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0.0, SOURCE_PANEL_GAP)
				choice_list_container.add_child(gap)
				row_count += 1
			_rows_container = _build_source_block(source_kind)
			row_count += 2
		first_block = false
		row_count += _add_source_section(by_source[source_kind], source_kind, 0)
	_rows_container = choice_list_container

	_select_choice(_resolve_default_index(default_choice))

	exclusive = true
	var height: float = minf(DIALOG_BASE_HEIGHT + float(row_count) * ROW_HEIGHT, MAX_DIALOG_HEIGHT)
	_popup_fitted(height)


# Riquadro di una sorgente (solo con due sorgenti): PanelContainer con sfondo proprio e bordo, dentro
# l'intestazione e un separatore; ritorna il VBoxContainer in cui aggiungere le righe della sezione.
func _build_source_block(source_kind: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SOURCE_PANEL_COLORS.get(source_kind, Color(0.2, 0.2, 0.2, 1.0))
	style.border_color = SOURCE_PANEL_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", style)
	choice_list_container.add_child(panel)
	var block := VBoxContainer.new()
	panel.add_child(block)
	var header := Label.new()
	header.text = tr(SOURCE_TEXT_KEYS[source_kind])
	header.add_theme_font_size_override("font_size", SOURCE_HEADER_FONT_SIZE)
	block.add_child(header)
	block.add_child(HSeparator.new())
	return block


# Sezione del menu per una sorgente: "Tutto", poi per categoria (ordine di priorita' di PickUpAction:
# cibo, materiali, medicinali...) l'intestazione, il "tutto" della categoria e le singole risorse per nome
# leggibile. `base_level` sposta tutta la sezione di un rientro sotto l'intestazione della sorgente. Ritorna il
# numero di righe aggiunte (per il dimensionamento del popup).
func _add_source_section(entries: Array, source_kind: int, base_level: int) -> int:
	var by_category: Dictionary = {}
	for entry in entries:
		var category: int = int(entry["category"])
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append(entry)
	var present_categories: Array[int] = []
	for category in PickUpAction.PRIORITY_CATEGORIES:
		if by_category.has(int(category)):
			present_categories.append(int(category))
			by_category[int(category)].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return IconRegistry.get_resource_display_name(String(a["resource_name"])) < IconRegistry.get_resource_display_name(String(b["resource_name"]))
			)

	# Livello 1: "Tutto".
	_add_choice(_build_text_row(tr("pickup_choice_all"), base_level), PickUpAction.CriterionKind.ALL, -1, "", 0, source_kind)
	var row_count: int = 1
	for category in present_categories:
		var text_keys: Array = CATEGORY_TEXT_KEYS.get(category, ["", ""])
		# Livello 2: intestazione della categoria (non selezionabile).
		var header := Label.new()
		header.text = tr(text_keys[0]) if text_keys[0] != "" else str(category)
		var header_row := HBoxContainer.new()
		header_row.add_child(_build_indent(base_level + 1))
		header_row.add_child(header)
		_rows_container.add_child(header_row)
		# Livello 3: "tutto" della categoria + le singole risorse.
		_add_choice(_build_text_row(tr(text_keys[1]) if text_keys[1] != "" else str(category), base_level + 2), PickUpAction.CriterionKind.CATEGORY, category, "", 0, source_kind)
		for entry in by_category[category]:
			var resource_name: String = entry["resource_name"]
			var quantity: int = int(entry["quantity"])
			_add_choice(_build_resource_row(resource_name, quantity, base_level + 2), PickUpAction.CriterionKind.NAME, category, resource_name, quantity, source_kind)
			row_count += 1
		row_count += 2
	return row_count


# Indice della voce di default. Ripiego risalendo (2026-09-20, richiesta utente): se la voce richiesta non c'e',
# la "tutto" della sua categoria (se quella categoria e' presente), altrimenti "Tutto" (indice 0, sempre
# presente).
func _resolve_default_index(default_choice: Dictionary) -> int:
	var kind: int = int(default_choice.get("kind", PickUpAction.CriterionKind.ALL))
	var category: int = int(default_choice.get("category", -1))
	var resource_name: String = String(default_choice.get("resource_name", ""))
	if kind == PickUpAction.CriterionKind.NAME:
		var resource_index: int = _find_choice(PickUpAction.CriterionKind.NAME, category, resource_name)
		if resource_index != -1:
			return resource_index
		kind = PickUpAction.CriterionKind.CATEGORY
	if kind == PickUpAction.CriterionKind.CATEGORY:
		var category_index: int = _find_choice(PickUpAction.CriterionKind.CATEGORY, category, "")
		if category_index != -1:
			return category_index
	return 0


func _find_choice(kind: int, category: int, resource_name: String) -> int:
	for i in range(_choices.size()):
		var choice: Dictionary = _choices[i]
		if int(choice["kind"]) != kind:
			continue
		if kind == PickUpAction.CriterionKind.CATEGORY and int(choice["category"]) != category:
			continue
		if kind == PickUpAction.CriterionKind.NAME and String(choice["resource_name"]) != resource_name:
			continue
		return i
	return -1


# Registra una voce selezionabile: `row` e' la riga gia' costruita (contiene il suo Button toggle, ultimo figlio).
func _add_choice(row: Control, kind: int, category: int, resource_name: String, max_quantity: int, source_kind: int) -> void:
	var button: Button = row.get_child(row.get_child_count() - 1) as Button
	var index: int = _choices.size()
	_choices.append({
		"button": button, "kind": kind, "category": category, "resource_name": resource_name, "max_quantity": max_quantity,
		"source_kind": source_kind,
	})
	button.pressed.connect(_select_choice.bind(index))
	_rows_container.add_child(row)


func _build_indent(level: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(INDENT_PER_LEVEL * float(level), 0.0)
	return spacer


# Riga testuale senza icona ("Tutto", "Tutto il cibo"): rientro + Button che riempie il resto.
func _build_text_row(text: String, level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_build_indent(level))
	row.add_child(_build_choice_button(text))
	return row


# Riga di una risorsa: rientro + icona (disegnata/emoji/iniziale, stesso schema a 3 livelli di
# OptionChoiceDialog e BuildingInfoPanel) + Button "Nome (quantita')".
func _build_resource_row(resource_name: String, quantity: int, level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_build_indent(level))

	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(RESOURCE_ROW_ICON_SIZE, RESOURCE_ROW_ICON_SIZE)
	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		icon_box.add_child(icon_node)
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		var fallback_label := Label.new()
		var icon_text: String = IconRegistry.get_resource_icon(resource_name)
		fallback_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.anchor_right = 1.0
		fallback_label.anchor_bottom = 1.0
		icon_box.add_child(fallback_label)
	row.add_child(icon_box)

	row.add_child(_build_choice_button("%s (%d)" % [IconRegistry.get_resource_display_name(resource_name), quantity]))
	return row


func _build_choice_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# toggle_mode SOLO per lo stile "pressed" del selezionato (radio-style, ogni pressione passa da
	# _select_choice che lo riporta a true): stesso trucco di OptionChoiceDialog.
	button.toggle_mode = true
	_apply_selected_style(button)
	return button


# Stile "selezionato" marcato — STESSI valori di OptionChoiceDialog (coerenza visiva tra i due popup).
const SELECTED_BG_COLOR := Color(0.20, 0.42, 0.78, 1.0)
const SELECTED_BORDER_COLOR := Color(0.75, 0.87, 1.0, 1.0)
const SELECTED_FONT_COLOR := Color(1.0, 1.0, 1.0, 1.0)


func _apply_selected_style(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = SELECTED_BG_COLOR
	style.border_color = SELECTED_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", style)
	button.add_theme_color_override("font_pressed_color", SELECTED_FONT_COLOR)
	button.add_theme_color_override("font_hover_pressed_color", SELECTED_FONT_COLOR)


# Seleziona la voce `index` (radio-style) e mostra/nasconde la riga quantita': visibile SOLO per una risorsa
# specifica, con tetto/valore pari alla quantita' disponibile.
func _select_choice(index: int) -> void:
	_selected_index = index
	for i in range(_choices.size()):
		(_choices[i]["button"] as Button).button_pressed = i == index
	var choice: Dictionary = _choices[index]
	var is_resource: bool = int(choice["kind"]) == PickUpAction.CriterionKind.NAME
	quantity_row.visible = is_resource and _quantity_enabled
	if is_resource:
		var max_quantity: int = int(choice["max_quantity"])
		quantity_spin_box.max_value = max_quantity
		quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
		quantity_spin_box.value = max_quantity


# Modalità caccia (2026-10-01, comando Caccia nelle zone): stesso dialog e stesso stile di Raccogli, con titolo e
# messaggio della caccia, senza elenco delle risorse, con il solo selettore "Carne" (`meat_options`, preselezionato
# `default_target` o il primo valore) e Conferma/Annulla. Conferma -> hunt_choice_made(valore); Annulla/Esc -> nulla.
# Ritorna false (dialog NON aperto, nessun pannello lasciato sullo schermo) se la riga non si costruisce o non ci sono
# valori: il chiamante non deve aspettarsi una risposta.
# `destination_options` (2026-10-03): [{"id", "name", "building_type", "disabled_reason", "locked"}] in ordine (vedi
# GameScene._build_butcher_destination_options); `default_destination` preselezionata, se abilitata.
func open_hunt_dialog(
	dialog_title: String, message: String, meat_options: Array[int], default_target: int,
	destination_options: Array[Dictionary] = [], default_destination: String = ""
) -> bool:
	_ensure_meat_row()
	_ensure_destination_section()
	_fill_destination_section(destination_options, default_destination)
	if _meat_option == null or meat_options.is_empty():
		push_error("PickupChoiceDialog.open_hunt_dialog: riga \"Carne\" non disponibile o nessun valore — dialog non aperto.")
		hide()
		return false
	_set_hunt_mode(true)
	title = dialog_title
	message_label.text = message
	_meat_values = meat_options.duplicate()
	_meat_option.clear()
	var selected_index := 0
	for i in range(_meat_values.size()):
		_meat_option.add_item(str(_meat_values[i]), i)
		if _meat_values[i] == default_target:
			selected_index = i
	_meat_option.select(selected_index)
	exclusive = true
	_popup_fitted(HUNT_DIALOG_HEIGHT)
	return true


# Apre centrato con l'altezza voluta e poi (2026-10-01, bugfix "bottoni tagliati") adatta la finestra al contenuto: il
# messaggio va a capo solo quando conosce la propria larghezza, quindi l'altezza minima vera si legge dopo il primo
# layout. Mai più bassa del contenuto (bottoni sempre interi), mai più stretta di DIALOG_WIDTH; in Raccogli resta
# l'altezza calcolata dalle righe se è maggiore (l'elenco scorre).
func _popup_fitted(desired_height: float) -> void:
	popup_centered(Vector2i(DIALOG_WIDTH, int(desired_height)))
	_fit_to_content.call_deferred(desired_height)


func _fit_to_content(desired_height: float) -> void:
	await get_tree().process_frame
	if not visible:
		return
	var content := get_node_or_null("MarginContainer") as Control
	if content == null:
		return
	var min_size := content.get_combined_minimum_size()
	var fitted := Vector2i(maxi(DIALOG_WIDTH, ceili(min_size.x)), maxi(int(desired_height), ceili(min_size.y)))
	if fitted != size:
		size = fitted
		move_to_center()


# Mostra solo ciò che serve alla modalità: elenco/casella/quantità/viaggi per la raccolta, riga "Carne" per la caccia.
func _set_hunt_mode(enabled: bool) -> void:
	_hunt_mode = enabled
	choice_scroll.visible = not enabled
	if enabled:
		repeat_check_box.visible = false
		quantity_row.visible = false
		if _trips_row != null:
			_trips_row.visible = false
	if _meat_row != null:
		_meat_row.visible = enabled
	if _destination_section != null:
		_destination_section.visible = enabled


func _ensure_meat_row() -> void:
	if _meat_row != null:
		return
	# Una frase con il menu dentro (2026-10-01): «Fermati dopo aver portato a casa [10] di carne». La prima parte va a
	# capo se serve, così la finestra resta larga DIALOG_WIDTH.
	_meat_row = HBoxContainer.new()
	_meat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prefix := Label.new()
	prefix.text = tr("hunt_order_dialog_stop_prefix")
	prefix.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prefix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefix.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_meat_row.add_child(prefix)
	_meat_option = OptionButton.new()
	_meat_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meat_row.add_child(_meat_option)
	var suffix := Label.new()
	suffix.text = tr("hunt_order_dialog_stop_suffix")
	_meat_row.add_child(suffix)
	var parent := repeat_check_box.get_parent()
	parent.add_child(_meat_row)
	parent.move_child(_meat_row, repeat_check_box.get_index() + 1)
	_meat_row.visible = false


# Sezione "Destinazione" (2026-10-03), creata alla prima apertura in modalità caccia sotto la riga "Carne".
func _ensure_destination_section() -> void:
	if _destination_section != null:
		return
	_destination_section = VBoxContainer.new()
	var caption := Label.new()
	caption.text = tr("hunt_destination_caption")
	_destination_section.add_child(caption)
	_destination_rows = VBoxContainer.new()
	_destination_section.add_child(_destination_rows)
	var parent := repeat_check_box.get_parent()
	parent.add_child(_destination_section)
	var anchor: Node = _meat_row if _meat_row != null else repeat_check_box
	parent.move_child(_destination_section, anchor.get_index() + 1)
	_destination_section.visible = false


# Una riga per opzione: icona dell'edificio e casella a scelta singola. Un'opzione non disponibile resta visibile ma
# disabilitata, con il motivo nel tooltip (e il lucchetto per quelle non ancora disponibili). Preselezionata
# `default_destination` se abilitata, altrimenti la prima abilitata.
func _fill_destination_section(options: Array[Dictionary], default_destination: String) -> void:
	for child in _destination_rows.get_children():
		child.queue_free()
	_destination_ids = {}
	_destination_group = ButtonGroup.new()
	_destination_section.visible = not options.is_empty()
	var to_select: CheckBox = null
	var first_enabled: CheckBox = null
	for option in options:
		var reason := String(option.get("disabled_reason", ""))
		var row := HBoxContainer.new()
		row.tooltip_text = reason
		row.add_child(_build_destination_icon(String(option.get("building_type", ""))))
		var choice := CheckBox.new()
		choice.button_group = _destination_group
		var text := String(option.get("name", ""))
		if bool(option.get("locked", false)):
			text = "%s %s — %s" % [text, DESTINATION_LOCK_ICON, reason]
		choice.text = text
		choice.disabled = reason != ""
		choice.tooltip_text = reason
		row.add_child(choice)
		_destination_rows.add_child(row)
		_destination_ids[choice] = String(option.get("id", ""))
		if not choice.disabled:
			if first_enabled == null:
				first_enabled = choice
			if String(option.get("id", "")) == default_destination:
				to_select = choice
	if to_select == null:
		to_select = first_enabled
	if to_select != null:
		to_select.button_pressed = true


# Icona dell'edificio (IconRegistry.build_building_icon_box: disegnata se c'è, altrimenti l'emoji).
func _build_destination_icon(building_type: String) -> Control:
	return IconRegistry.build_building_icon_box(building_type, DESTINATION_ICON_SIZE)


# Destinazione selezionata, il magazzino se nessuna (sezione vuota).
func _selected_destination() -> String:
	if _destination_group != null:
		var pressed := _destination_group.get_pressed_button()
		if pressed != null and _destination_ids.has(pressed):
			return String(_destination_ids[pressed])
	return ButcherDestinationService.WAREHOUSE


func _on_window_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		_on_cancel_pressed()


func _on_confirm_pressed() -> void:
	if _hunt_mode:
		var index := _meat_option.selected if _meat_option != null else -1
		var destination := _selected_destination()
		hide()
		if index >= 0 and index < _meat_values.size():
			hunt_choice_made.emit(_meat_values[index], destination)
		return
	if _selected_index < 0 or _selected_index >= _choices.size():
		return
	var choice: Dictionary = _choices[_selected_index]
	var kind: int = int(choice["kind"])
	var category: int = int(choice["category"]) if kind == PickUpAction.CriterionKind.CATEGORY else -1
	var resource_name: String = String(choice["resource_name"]) if kind == PickUpAction.CriterionKind.NAME else ""
	var quantity: int = int(quantity_spin_box.value) if kind == PickUpAction.CriterionKind.NAME and _quantity_enabled else -1
	selected_trips = int(_trips_spin_box.value) if _trips_mode else 0
	var repeat: bool = selected_trips > 1 if _trips_mode else repeat_check_box.button_pressed
	hide()
	choice_made.emit(kind, category, resource_name, quantity, repeat, int(choice["source_kind"]))


# Riga "Viaggi: [1..N]" sotto la casella delle ripetizioni, creata alla prima apertura in modalità viaggi.
func _ensure_trips_row() -> void:
	if _trips_row != null:
		return
	_trips_row = HBoxContainer.new()
	var label := Label.new()
	label.text = tr("work_area_gather_trips_label")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trips_row.add_child(label)
	_trips_spin_box = SpinBox.new()
	_trips_spin_box.min_value = 1
	_trips_spin_box.step = 1
	_trips_spin_box.rounded = true
	_trips_row.add_child(_trips_spin_box)
	var parent := repeat_check_box.get_parent()
	parent.add_child(_trips_row)
	parent.move_child(_trips_row, repeat_check_box.get_index() + 1)


# Nessun segnale all'annullamento (stesso principio di OptionChoiceDialog): il chiamante non ha ancora impostato
# nulla.
func _on_cancel_pressed() -> void:
	hide()
