class_name TaskAssignmentPanel
extends VBoxContainer

# Contenuto "Assegnazione delle task" del cassetto laterale (SideDrawer, 2026-10-07, richiesta utente — bottone
# "Assegnazione" della riga del governo del villaggio di GameInfoPanel). Il titolo lo mostra il cassetto.
#
# Prima bozza della disposizione (2026-10-07): NESSUN bottone ha effetto per ora.
#   - in alto, subito sotto il titolo del cassetto (senza titolo di sezione): un bottone per comando della barra dei
#     comandi (CommandBar.ACTIONS, stesso ordine e stesse icone disegnate, CommandButtonIcon), larghi uguali, icona e
#     nome sotto; tooltip provvisorio "In arrivo";
#   - separatore;
#   - "In lista": occupa il resto dell'altezza, dentro uno scroll; i lavori in lista (passo A, 2026-10-07 —
#     JobBoardService, oggi i cantieri di edifici nuovi) passati da GameScene (set_listed_entries) una volta al secondo,
#     come la scheda "In sospeso": una riga per lavoro senza nessuno assegnato, attivo o bloccato, con icona e nome
#     dell'edificio. Attivo: bottone "Blocca" (lock_requested). Bloccato: riga attenuata, "Bloccato" accanto al nome,
#     bottone "Sblocca" (unlock_requested). Clic sulla riga = centra la visuale (entry_activated). Vuota: "Nessun
#     compito in lista". Righe rifatte solo quando l'elenco cambia davvero.

# Idea che sblocca il bottone (GameScene._is_task_assignment_available) e voce tra i suoi sblocchi nell'albero
# (IdeaUnlocksService.TOOLS).
const REQUIRED_IDEA_ID := "task_assignment"
# Id del contenuto nel cassetto (SideDrawer.show_content).
const DRAWER_CONTENT_ID := &"task_assignment"

const SECTION_FONT_SIZE: int = 12
const BUTTON_LABEL_FONT_SIZE: int = 10
const BUTTON_HEIGHT: float = 58.0
const BUTTON_ICON_SIDE: float = 30.0
const BUTTON_SEPARATION: int = 4

# Clic su una riga della lista (centra la visuale) e bottoni "Blocca" / "Sblocca": GameScene decide cosa fare.
signal entry_activated(entry: Dictionary)
signal lock_requested(entry: Dictionary)
signal unlock_requested(entry: Dictionary)

const LIST_FONT_SIZE: int = 11
const LIST_ICON_SIDE: float = 20.0
const DISABLED_MODULATE := Color(1, 1, 1, 0.45)
const LOCKED_MODULATE := Color(1, 1, 1, 0.55)

var _list_box: VBoxContainer = null
var _list_signature: String = "-"
var _pending_list_entries: Array[Dictionary] = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build_new_task_section()
	add_child(HSeparator.new())
	_build_list_section()


func _build_new_task_section() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BUTTON_SEPARATION)
	add_child(row)
	for action in CommandBar.ACTIONS:
		row.add_child(_build_command_button(action))


# Bottone di un comando: icona disegnata in alto, nome sotto. Senza effetto per ora (2026-10-07).
func _build_command_button(action: Dictionary) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tr("task_assignment_coming_soon")
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)
	var icon := IconRegistry.get_command_button_icon_node(String(action.get("icon", "")))
	icon.custom_minimum_size = Vector2(BUTTON_ICON_SIDE, BUTTON_ICON_SIDE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := Label.new()
	label.text = tr(String(action.get("tooltip_key", "")))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", BUTTON_LABEL_FONT_SIZE)
	box.add_child(label)
	return button


func _build_list_section() -> void:
	add_child(_section_title(tr("task_assignment_list_section")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_list_box)
	_apply_list_entries(_pending_list_entries)


# Lavori in lista: {"key", "text", "enabled", "disabled_reason", "building_type", "building_name", ...} (voci di
# GameScene._pending_entry). Prima di _ready restano da parte e vengono mostrati appena l'elenco esiste.
func set_listed_entries(entries: Array[Dictionary]) -> void:
	_pending_list_entries = entries
	if _list_box != null:
		_apply_list_entries(entries)


func _apply_list_entries(entries: Array[Dictionary]) -> void:
	var parts: PackedStringArray = []
	for entry in entries:
		parts.append("%s|%s|%s|%s" % [
			entry["key"], entry.get("building_name", ""), str(entry.get("enabled", true)), str(entry.get("locked", false)),
		])
	var signature := "\n".join(parts)
	if signature == _list_signature:
		return
	_list_signature = signature
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("task_assignment_list_empty")
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.modulate = Color(1, 1, 1, 0.7)
		_list_box.add_child(empty_label)
		return
	for entry in entries:
		_list_box.add_child(_build_list_row(entry))


# Riga: icona dell'edificio, nome (troncato con i puntini, intero nel tooltip), "Bloccato" se lo è, poi "Blocca" o
# "Sblocca" (testo sempre intero). Clic sul nome = centra la visuale; voce che non si può centrare: nome spento,
# spiegazione nel tooltip. Bloccato: icona, nome e scritta attenuati, il bottone no.
func _build_list_row(entry: Dictionary) -> Control:
	var enabled := bool(entry.get("enabled", true))
	var locked := bool(entry.get("locked", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := IconRegistry.build_building_icon_box(String(entry.get("building_type", "")), LIST_ICON_SIDE)
	if locked:
		icon.modulate = LOCKED_MODULATE
	row.add_child(icon)
	var label := Label.new()
	label.text = String(entry.get("building_name", entry.get("text", "")))
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = String(entry.get("text", "")) if enabled else "%s\n%s" % [entry.get("text", ""), entry.get("disabled_reason", "")]
	if enabled:
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				entry_activated.emit(entry)
		)
	else:
		label.modulate = DISABLED_MODULATE
	if locked and enabled:
		label.modulate = LOCKED_MODULATE
	row.add_child(label)
	if locked:
		var locked_label := Label.new()
		locked_label.text = tr("task_assignment_locked")
		locked_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
		locked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		locked_label.modulate = LOCKED_MODULATE
		row.add_child(locked_label)
	var state_button := Button.new()
	state_button.text = tr("task_assignment_unlock") if locked else tr("task_assignment_lock")
	state_button.focus_mode = Control.FOCUS_NONE
	state_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
	state_button.pressed.connect(func() -> void:
		if locked:
			unlock_requested.emit(entry)
		else:
			lock_requested.emit(entry)
	)
	row.add_child(state_button)
	return row


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	return label
