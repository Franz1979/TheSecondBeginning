class_name ButcherDestinationButton
extends TooltipButton

# Pulsante della destinazione dei prodotti della caccia (2026-10-03 nella barra dei comandi; 2026-10-09 estratto da
# CommandBar per riusarlo uguale nel popup della Caccia nelle zone di lavoro, PickupChoiceDialog): icona dell'edificio
# della destinazione attuale e freccina; il clic apre una piccola scelta tra le destinazioni disponibili. Stato deciso da
# GameScene (set_destination, lo stesso per tutte le copie: GameData.last_butcher_destination); la scelta esce con
# `destination_chosen`. Le destinazioni non disponibili (2026-10-09, dalla vecchia sezione del popup della caccia)
# restano nell'elenco spente, con il motivo nel tooltip ("disabled_reason") e il lucchetto per quelle non ancora
# disponibili ("locked").
#
# La scelta (PopupPanel, una finestra) non è figlia del pulsante (2026-10-09, errore "_push_unhandled_input_internal:
# !is_inside_tree()"): vive nella finestra che ospita il pulsante, creata alla prima apertura, così togliere dall'albero
# il contenuto che contiene il pulsante (es. il cassetto, SideDrawer._clear_content) non toglie mai una finestra mentre
# riceve input; tolto il pulsante, la scelta si chiude e viene liberata.

signal destination_chosen(destination: String)

const ICON_SIDE: float = 22.0
# Icone piccole di cosa va alla postazione (2026-10-14, richiesta utente — "Essiccatoio – solo carne" e simili si
# distinguono senza aprire la scelta): in alto a sinistra sopra l'icona dell'edificio.
const BADGE_SIDE: float = 10.0
const LOCK_ICON := "🔒"

var _icon_holder: Control = null
var _popup: PopupPanel = null
var _list: VBoxContainer = null
# Ultimo stato applicato: [attuale, disponibili come "id:nome|..."] — evita di ricostruire icona e scelta a ogni frame.
var _signature: String = ""
var _options: Array[Dictionary] = []
# Chiave tr() del tooltip, con {name} = destinazione attuale (2026-10-16, richiesta utente): la regola "Carne e pelli in
# eccesso" del cassetto Scorte (WarehousePanel) ne usa una sua, perché lì non decide la destinazione di tutti i prodotti.
var tooltip_key: String = "command_bar_butcher_destination_tooltip"


func _init() -> void:
	custom_minimum_size = CommandBar.TOGGLE_BUTTON_SIZE
	focus_mode = Control.FOCUS_NONE
	_icon_holder = CenterContainer.new()
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_holder)
	_icon_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pressed.connect(_open_popup)
	var dropdown_marker := DropdownMarker.new()
	add_child(dropdown_marker)
	dropdown_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _popup != null:
		_popup.hide()
		_popup.queue_free()
		_popup = null
		_list = null


# `is_shown` = mostrarlo; `current` = destinazione che la caccia userebbe adesso; `options` = [{"id", "name",
# "building_type", "disabled_reason", "locked"}] di tutte le destinazioni (quelle con un motivo spente). Ricostruisce icona, tooltip e scelta solo quando qualcosa
# cambia. Ritorna true se la visibilità è cambiata.
func set_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> bool:
	var visibility_changed := visible != is_shown
	visible = is_shown
	if not is_shown:
		if _popup != null and _popup.visible:
			_popup.hide()
		return visibility_changed
	var parts: Array[String] = [String(current.get("id", ""))]
	for option in options:
		parts.append("%s:%s:%s" % [String(option.get("id", "")), String(option.get("name", "")), String(option.get("disabled_reason", ""))])
	var signature := "|".join(parts)
	if signature == _signature:
		return visibility_changed
	_signature = signature
	_options = options.duplicate()
	for child in _icon_holder.get_children():
		child.queue_free()
	_icon_holder.add_child(_build_destination_icon(current))
	tooltip_text = TooltipText.wrap(tr(tooltip_key).format({"name": String(current.get("name", ""))}))
	return visibility_changed


func _open_popup() -> void:
	if not is_inside_tree():
		return
	if _popup == null:
		_popup = PopupPanel.new()
		_list = VBoxContainer.new()
		_popup.add_child(_list)
		get_viewport().add_child(_popup)
	# Tolte subito (non solo queue_free), così la misura del contenuto sotto non conta le righe della volta prima.
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for option in _options:
		var reason := String(option.get("disabled_reason", ""))
		var row := HBoxContainer.new()
		row.tooltip_text = TooltipText.wrap(reason)
		row.add_child(_build_destination_icon(option))
		var choice := Button.new()
		choice.text = String(option.get("name", ""))
		if bool(option.get("locked", false)):
			choice.text = "%s %s" % [choice.text, LOCK_ICON]
		choice.disabled = reason != ""
		choice.tooltip_text = TooltipText.wrap(reason)
		choice.flat = true
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.pressed.connect(_on_option_pressed.bind(String(option.get("id", ""))))
		row.add_child(choice)
		_list.add_child(row)
	_popup.reset_size()
	var content_size := Vector2i(_list.get_combined_minimum_size()) + Vector2i(8, 8)
	# Posizione nelle coordinate di chi ospita la scelta (get_screen_position): la finestra di gioco con le sottofinestre
	# incorporate (default del progetto), anche dentro un popup incorporato; lo schermo altrimenti.
	var screen_position := Vector2i(get_screen_position())
	_popup.popup(Rect2i(screen_position - Vector2i(0, content_size.y), content_size))


# Icona dell'edificio della destinazione con, per le postazioni di lavorazione, le icone piccole delle risorse che ci
# vanno (ButcherDestinationService.get_processing_resources): carne, pelle o entrambe.
func _build_destination_icon(entry: Dictionary) -> Control:
	var box := IconRegistry.build_building_icon_box(String(entry.get("building_type", "")), ICON_SIDE)
	var resources := ButcherDestinationService.get_processing_resources(String(entry.get("id", "")))
	if resources.is_empty():
		return box
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 0)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for resource_name in resources:
		var badge := Control.new()
		badge.custom_minimum_size = Vector2(BADGE_SIDE, BADGE_SIDE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_node := IconRegistry.get_resource_icon_node(resource_name)
		if icon_node != null:
			icon_node.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(icon_node)
		else:
			var label := Label.new()
			label.text = IconRegistry.get_resource_icon(resource_name)
			label.add_theme_font_size_override("font_size", 7)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			badge.add_child(label)
		badges.add_child(badge)
	box.add_child(badges)
	# In alto a sinistra (2026-10-14): in basso a destra c'è la freccina che apre la scelta (DropdownMarker).
	badges.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	badges.position -= Vector2(3, 3)
	return box


func _on_option_pressed(destination: String) -> void:
	if _popup != null:
		_popup.hide()
	destination_chosen.emit(destination)
