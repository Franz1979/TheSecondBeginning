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
signal choice_made(kind: int, category: int, resource_name: String, quantity: int, repeat: bool)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var choice_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ChoiceScroll/ChoiceListContainer
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
# "resource_name": String, "max_quantity": int}. La selezione e' radio-style: una sola alla volta.
var _choices: Array[Dictionary] = []
var _selected_index: int = -1


func _ready() -> void:
	quantity_label.text = tr("transport_dialog_quantity_label")
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": TaskRepeatRules.MAX_REPEATS})
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)


# `resources`: Array di Dictionary {"resource_name": String, "category": int, "quantity": int (> 0)} — SOLO
# quelle realmente presenti nella microcella. `default_choice`: {"kind": PickUpAction.CriterionKind,
# "category": int, "resource_name": String}; vuoto o senza "kind" = "Tutto" (il default fisso di oggi).
# `repeat_default`: stato iniziale del flag "Ripeti fino a N volte" (2026-09-20: UserOptions.repeat_default).
func open_dialog(dialog_title: String, message: String, resources: Array, default_choice: Dictionary = {}, repeat_default: bool = false) -> void:
	title = dialog_title
	message_label.text = message
	repeat_check_box.button_pressed = repeat_default

	for child in choice_list_container.get_children():
		child.queue_free()
	_choices.clear()
	_selected_index = -1

	# Raggruppa per categoria, nell'ordine di priorita' di PickUpAction (cibo, materiali, medicinali); dentro la
	# categoria, per nome leggibile — solo le categorie con almeno una risorsa.
	var by_category: Dictionary = {}
	for entry in resources:
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
	_add_choice(_build_text_row(tr("pickup_choice_all"), 0), PickUpAction.CriterionKind.ALL, -1, "", 0)
	var row_count: int = 1
	for category in present_categories:
		var text_keys: Array = CATEGORY_TEXT_KEYS.get(category, ["", ""])
		# Livello 2: intestazione della categoria (non selezionabile).
		var header := Label.new()
		header.text = tr(text_keys[0]) if text_keys[0] != "" else str(category)
		var header_row := HBoxContainer.new()
		header_row.add_child(_build_indent(1))
		header_row.add_child(header)
		choice_list_container.add_child(header_row)
		# Livello 3: "tutto" della categoria + le singole risorse.
		_add_choice(_build_text_row(tr(text_keys[1]) if text_keys[1] != "" else str(category), 2), PickUpAction.CriterionKind.CATEGORY, category, "", 0)
		for entry in by_category[category]:
			var resource_name: String = entry["resource_name"]
			var quantity: int = int(entry["quantity"])
			_add_choice(_build_resource_row(resource_name, quantity, 2), PickUpAction.CriterionKind.NAME, category, resource_name, quantity)
			row_count += 1
		row_count += 2

	_select_choice(_resolve_default_index(default_choice))

	exclusive = true
	var height: float = minf(DIALOG_BASE_HEIGHT + float(row_count) * ROW_HEIGHT, MAX_DIALOG_HEIGHT)
	popup_centered(Vector2i(DIALOG_WIDTH, int(height)))


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
func _add_choice(row: Control, kind: int, category: int, resource_name: String, max_quantity: int) -> void:
	var button: Button = row.get_child(row.get_child_count() - 1) as Button
	var index: int = _choices.size()
	_choices.append({
		"button": button, "kind": kind, "category": category, "resource_name": resource_name, "max_quantity": max_quantity,
	})
	button.pressed.connect(_select_choice.bind(index))
	choice_list_container.add_child(row)


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
	quantity_row.visible = is_resource
	if is_resource:
		var max_quantity: int = int(choice["max_quantity"])
		quantity_spin_box.max_value = max_quantity
		quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
		quantity_spin_box.value = max_quantity


func _on_confirm_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _choices.size():
		return
	var choice: Dictionary = _choices[_selected_index]
	var kind: int = int(choice["kind"])
	var category: int = int(choice["category"]) if kind == PickUpAction.CriterionKind.CATEGORY else -1
	var resource_name: String = String(choice["resource_name"]) if kind == PickUpAction.CriterionKind.NAME else ""
	var quantity: int = int(quantity_spin_box.value) if kind == PickUpAction.CriterionKind.NAME else -1
	hide()
	choice_made.emit(kind, category, resource_name, quantity, repeat_check_box.button_pressed)


# Nessun segnale all'annullamento (stesso principio di OptionChoiceDialog): il chiamante non ha ancora impostato
# nulla.
func _on_cancel_pressed() -> void:
	hide()
