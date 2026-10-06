class_name PickupChoiceMenu
extends RefCounted

# Menu di scelta della raccolta (2026-10-05, estratto da PickupChoiceDialog senza cambiarne aspetto né comportamento):
# l'elenco gerarchico Tutto / categoria / risorsa, diviso per sorgente (mucchio a terra / terreno) quando le sorgenti
# sono due, con la selezione radio-style. Un blocco solo usato da PickupChoiceDialog (popup della raccolta) e dalla
# voce "Raccogli" del popup del click destro con l'accetta (OptionChoiceDialog, opzioni di tipo "pickup"). Costruisce
# le righe nel VBoxContainer che riceve; quantità e "Ripeti" restano al chiamante, avvisato a ogni cambio di scelta da
# selection_changed. Vedi PickupChoiceDialog per le regole del menu.

# Scelta cambiata: is_resource = criterio NAME (una risorsa: il chiamante mostra la quantità), max_quantity = sua scorta.
signal selection_changed(is_resource: bool, max_quantity: int)

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

# Stile "selezionato" marcato — STESSI valori di OptionChoiceDialog (coerenza visiva tra i due popup).
const SELECTED_BG_COLOR := Color(0.20, 0.42, 0.78, 1.0)
const SELECTED_BORDER_COLOR := Color(0.75, 0.87, 1.0, 1.0)
const SELECTED_FONT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

# Voci selezionabili, in ordine di comparsa: {"button": Button, "kind": int, "category": int,
# "resource_name": String, "max_quantity": int, "source_kind": int (PickUpAction.SourceKind)}. La selezione e' radio-style: una sola alla volta.
var _choices: Array[Dictionary] = []
var _selected_index: int = -1
# Elenco ricevuto da build (le righe dirette) e contenitore in cui _add_source_section/_add_choice aggiungono le righe:
# l'elenco stesso, oppure il riquadro della sorgente quando le sorgenti sono due (2026-09-26).
var _list: VBoxContainer = null
var _rows_container: VBoxContainer = null


# Svuota `list` e ci costruisce il menu per `resources` (stessa forma di PickupChoiceDialog.open_dialog), poi seleziona
# `default_choice`. `single_row`: con una sola risorsa da una sola sorgente, la sola riga di quella risorsa (niente
# "Tutto" né categoria — voce "Raccogli" del popup del click destro). Ritorna il numero di righe (dimensionamento).
func build(list: VBoxContainer, resources: Array, default_choice: Dictionary = {}, single_row: bool = false) -> int:
	_list = list
	for child in list.get_children():
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
	var row_count: int = 0
	if single_row and resources.size() == 1:
		var only: Dictionary = resources[0]
		_rows_container = list
		_add_choice(
			_build_resource_row(String(only["resource_name"]), int(only["quantity"]), 0), PickUpAction.CriterionKind.NAME,
			int(only["category"]), String(only["resource_name"]), int(only["quantity"]),
			int(only.get("source_kind", PickUpAction.SourceKind.TERRAIN))
		)
		select(0)
		return 1
	var show_source_headers: bool = by_source.size() > 1
	var first_block: bool = true
	for source_kind in SOURCE_ORDER:
		if not by_source.has(source_kind):
			continue
		_rows_container = list
		if show_source_headers:
			if not first_block:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0.0, SOURCE_PANEL_GAP)
				list.add_child(gap)
				row_count += 1
			_rows_container = _build_source_block(source_kind)
			row_count += 2
		first_block = false
		row_count += _add_source_section(by_source[source_kind], source_kind, 0)
	_rows_container = list

	select(_resolve_default_index(default_choice))
	return row_count


# Voce selezionata: {"kind", "category" (-1 se non CATEGORY), "resource_name" ("" se non NAME), "max_quantity",
# "source_kind"}; {} se nessuna.
func get_selected() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _choices.size():
		return {}
	var choice: Dictionary = _choices[_selected_index]
	var kind: int = int(choice["kind"])
	return {
		"kind": kind,
		"category": int(choice["category"]) if kind == PickUpAction.CriterionKind.CATEGORY else -1,
		"resource_name": String(choice["resource_name"]) if kind == PickUpAction.CriterionKind.NAME else "",
		"max_quantity": int(choice["max_quantity"]),
		"source_kind": int(choice["source_kind"]),
	}


# Seleziona la voce `index` (radio-style) e avvisa il chiamante (riga quantità: visibile SOLO per una risorsa
# specifica, con tetto/valore pari alla quantità disponibile).
func select(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	_selected_index = index
	for i in range(_choices.size()):
		(_choices[i]["button"] as Button).button_pressed = i == index
	var choice: Dictionary = _choices[index]
	selection_changed.emit(int(choice["kind"]) == PickUpAction.CriterionKind.NAME, int(choice["max_quantity"]))


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
	_list.add_child(panel)
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
	button.pressed.connect(select.bind(index))
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
	# select che lo riporta a true): stesso trucco di OptionChoiceDialog.
	button.toggle_mode = true
	_apply_selected_style(button)
	return button


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
