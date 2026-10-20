class_name ButcherDestinationButton
extends TooltipButton

# Pulsante della destinazione dei prodotti della caccia (2026-10-03 nella barra dei comandi; 2026-10-09 estratto da
# CommandBar per riusarlo uguale nel popup della Caccia nelle zone di lavoro, PickupChoiceDialog). Dal 2026-10-19 un
# pulsante per tipo (`kind`: carne o pelli), sempre in coppia (ButcherDestinationPair, richiesta utente: due pulsanti
# indipendenti invece di uno con due sezioni). Mostra la destinazione attuale del suo tipo (icona dell'edificio con sopra
# la piccola icona di carne o pelle) e la freccina; il clic apre la scelta tra le destinazioni del suo tipo. Stato deciso
# da GameScene (set_destination, lo stesso per tutte le copie); la scelta esce con `destination_chosen` come coppia intera
# (ButcherDestinationService.compose: cambia solo la parte del suo tipo). Le destinazioni non disponibili restano
# nell'elenco spente, con il motivo nel tooltip ("disabled_reason") e il lucchetto per quelle non ancora disponibili
# ("locked").
#
# La scelta (PopupPanel, una finestra) non è figlia del pulsante (2026-10-09, errore "_push_unhandled_input_internal:
# !is_inside_tree()"): vive nella finestra che ospita il pulsante, creata alla prima apertura, così togliere dall'albero
# il contenuto che contiene il pulsante (es. il cassetto, SideDrawer._clear_content) non toglie mai una finestra mentre
# riceve input; tolto il pulsante, la scelta si chiude e viene liberata.

signal destination_chosen(destination: String)

const ICON_SIDE: float = 22.0
# Icona piccola della risorsa (carne o pelle) in alto a sinistra sopra l'icona dell'edificio.
const BADGE_SIDE: float = 10.0
const LOCK_ICON := "🔒"
# Risorsa che rappresenta ciascun tipo nelle icone.
const KIND_ICON_RESOURCE := {
	ButcherDestinationService.KIND_MEAT: "meat",
	ButcherDestinationService.KIND_HIDE: "hide",
}
const KIND_TITLE_KEYS := {
	ButcherDestinationService.KIND_MEAT: "hunt_destination_meat_caption",
	ButcherDestinationService.KIND_HIDE: "hunt_destination_hide_caption",
}

# Tipo di questo pulsante: ButcherDestinationService.KIND_MEAT o KIND_HIDE (scelto da ButcherDestinationPair).
var kind: String = ButcherDestinationService.KIND_MEAT
var _icon_holder: CenterContainer = null
var _popup: PopupPanel = null
var _list: VBoxContainer = null
# Ultimo stato applicato — evita di ricostruire icona e scelta a ogni frame.
var _signature: String = ""
var _options: Array[Dictionary] = []
var _current_pair: String = ""
# Chiave tr() del tooltip, con {name} = le due destinazioni attuali (2026-10-16): la regola del cassetto Scorte
# (WarehousePanel) ne usa una sua, perché lì decide solo ciò che non serve ai minimi.
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


# `is_shown` = mostrarlo; `current` = {"id": coppia, "meat": voce, "hide": voce} (voce = {"id", "name",
# "building_type"}); `options` = [{"kind": "meat"/"hide", "id", "name", "building_type", "disabled_reason", "locked"}] di
# tutte le destinazioni dei due tipi (quelle con un motivo spente). Ricostruisce icona, tooltip e scelta solo quando
# qualcosa cambia. Ritorna true se la visibilità è cambiata.
func set_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> bool:
	var visibility_changed := visible != is_shown
	visible = is_shown
	if not is_shown:
		if _popup != null and _popup.visible:
			_popup.hide()
		return visibility_changed
	var parts: Array[String] = [String(current.get("id", ""))]
	for option in options:
		parts.append("%s:%s:%s:%s" % [
			String(option.get("kind", "")), String(option.get("id", "")), String(option.get("name", "")), String(option.get("disabled_reason", ""))
		])
	var signature := "|".join(parts)
	if signature == _signature:
		return visibility_changed
	_signature = signature
	_options = options.duplicate()
	_current_pair = String(current.get("id", ""))
	for child in _icon_holder.get_children():
		child.queue_free()
	var entry: Dictionary = current.get(kind, {})
	_icon_holder.add_child(_build_destination_icon(entry, kind))
	var name_text := "%s: %s" % [tr(String(KIND_TITLE_KEYS[kind])), String(entry.get("name", ""))]
	tooltip_text = TooltipText.wrap(tr(tooltip_key).format({"name": name_text}))
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
		if String(option.get("kind", "")) != kind:
			continue
		var reason := String(option.get("disabled_reason", ""))
		var row := HBoxContainer.new()
		row.tooltip_text = TooltipText.wrap(reason)
		row.add_child(_build_destination_icon(option, kind))
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


# Icona dell'edificio della destinazione con la piccola icona del tipo (carne o pelle) in alto a sinistra.
func _build_destination_icon(entry: Dictionary, for_kind: String) -> Control:
	var box := IconRegistry.build_building_icon_box(String(entry.get("building_type", "")), ICON_SIDE)
	var resource_name := String(KIND_ICON_RESOURCE.get(for_kind, ""))
	if resource_name == "":
		return box
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
	box.add_child(badge)
	# In alto a sinistra (2026-10-14): in basso a destra c'è la freccina che apre la scelta (DropdownMarker).
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	badge.position -= Vector2(3, 3)
	return box


func _on_option_pressed(target: String) -> void:
	if _popup != null:
		_popup.hide()
	var pair := ButcherDestinationService.parse(_current_pair)
	pair[kind] = target
	destination_chosen.emit(ButcherDestinationService.compose(
		String(pair[ButcherDestinationService.KIND_MEAT]), String(pair[ButcherDestinationService.KIND_HIDE])
	))
