class_name CountChoiceDialog
extends Window

# Piccolo popup "quanti" (2026-10-05, Quarry in zona — "Pietre da estrarre" del comando Estrai): messaggio, una riga
# etichetta + selettore intero, Conferma/Annulla. Stesso stile del popup della caccia in zona (PickupChoiceDialog in
# modalità caccia): margini 10, messaggio a capo, separatore sopra i bottoni, larghezza minima 320 e altezza adattata al
# contenuto. Costruito in codice, "pannello muto": riceve testi e limiti già risolti, emette solo il valore confermato.
# Annulla, X o Esc chiudono senza segnale.

signal count_chosen(value: int)

const DIALOG_WIDTH: int = 320
const DIALOG_HEIGHT: int = 140

var _content: Control = null
var _message_label: Label = null
var _count_label: Label = null
var _spin_box: SpinBox = null
var _confirm_button: Button = null
var _cancel_button: Button = null
# Posizione accanto a un pannello (2026-10-09, richiesta utente — Taglia ed Estrai dalla lista degli individui): se prima
# di open_dialog il chiamante imposta `popup_anchor` (vedi DialogPlacement.place), la finestra resta identica ma compare
# accanto all'info panel invece che al centro. Vale per quell'apertura sola; {} = al centro come sempre.
var popup_anchor: Dictionary = {}
var _anchor: Dictionary = {}
# Interruttore della zona automatica (2026-10-09): mostrato se il chiamante lo chiede (Taglia ed Estrai nelle zone).
var show_auto_zone_toggle: bool = false
var _auto_zone_row: HBoxContainer = null
var _box: VBoxContainer = null
var _separator: HSeparator = null
# Scelta facoltativa sopra il numero (2026-11-04, Pietra/Argilla del comando Estrai): righe con le icone, come la raccolta.
# Impostata con set_choices prima di open_dialog, vale per quell'apertura sola (anche il tooltip sul numero); letta alla
# conferma con get_selected_choice.
var _choice_rows: ResourceChoiceRows = null
var _pending_choices: Array[Dictionary] = []
var _pending_choice_id: String = ""
var _pending_count_tooltip: String = ""


func _ready() -> void:
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	add_child(margin)
	_content = margin
	var box := VBoxContainer.new()
	margin.add_child(box)
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_count_label = Label.new()
	_count_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_count_label)
	_spin_box = SpinBox.new()
	_spin_box.step = 1
	_spin_box.rounded = true
	row.add_child(_spin_box)
	box.add_child(row)
	_box = box
	_separator = HSeparator.new()
	box.add_child(_separator)
	var buttons := HBoxContainer.new()
	_confirm_button = Button.new()
	_confirm_button.text = tr("transport_dialog_confirm")
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = tr("transport_dialog_cancel")
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.pressed.connect(hide)
	buttons.add_child(_cancel_button)
	box.add_child(buttons)
	close_requested.connect(hide)
	window_input.connect(_on_window_input)


# `choices`: vedi ResourceChoiceRows, `selected_id` quella proposta. Meno di due voci = nessuna scelta da mostrare.
# `count_tooltip`: spiegazione al passaggio sul numero.
func set_choices(choices: Array[Dictionary], selected_id: String, count_tooltip: String = "") -> void:
	_pending_choices = choices
	_pending_choice_id = selected_id
	_pending_count_tooltip = count_tooltip


# Voce scelta nell'ultima apertura ("" se il dialogo non mostrava una scelta).
func get_selected_choice() -> String:
	if _choice_rows == null or not _choice_rows.visible:
		return ""
	return _choice_rows.get_selected()


func _apply_choices() -> void:
	var has_choices := _pending_choices.size() >= 2
	if has_choices and _choice_rows == null:
		_choice_rows = ResourceChoiceRows.new()
		_box.add_child(_choice_rows)
		_box.move_child(_choice_rows, _count_label.get_parent().get_index())
	if _choice_rows != null:
		_choice_rows.visible = has_choices
	if has_choices:
		_choice_rows.set_choices(_pending_choices, _pending_choice_id)
	var count_tooltip := TooltipText.wrap(_pending_count_tooltip) if _pending_count_tooltip != "" else ""
	_count_label.tooltip_text = count_tooltip
	_spin_box.tooltip_text = count_tooltip
	_spin_box.get_line_edit().tooltip_text = count_tooltip
	_pending_choices = []
	_pending_count_tooltip = ""


func open_dialog(dialog_title: String, message: String, count_label: String, min_value: int, max_value: int, default_value: int) -> void:
	title = dialog_title
	_apply_choices()
	_message_label.text = message
	_count_label.text = count_label
	_spin_box.min_value = min_value
	_spin_box.max_value = max_value
	_spin_box.value = clampi(default_value, min_value, max_value)
	if show_auto_zone_toggle and _auto_zone_row == null:
		_auto_zone_row = _ensure_auto_zone_row(_box, _separator)
	if _auto_zone_row != null:
		_auto_zone_row.visible = show_auto_zone_toggle
	_anchor = popup_anchor
	popup_anchor = {}
	exclusive = true
	popup_centered(Vector2i(DIALOG_WIDTH, DIALOG_HEIGHT))
	DialogPlacement.place(self, _anchor)
	_fit_to_content.call_deferred()


# Stesso adattamento di PickupChoiceDialog._fit_to_content: dopo il primo layout, mai più piccolo del contenuto.
func _fit_to_content() -> void:
	await get_tree().process_frame
	if not visible:
		return
	if _content == null:
		return
	var min_size := _content.get_combined_minimum_size()
	var fitted := Vector2i(maxi(DIALOG_WIDTH, ceili(min_size.x)), maxi(DIALOG_HEIGHT, ceili(min_size.y)))
	if fitted != size:
		size = fitted
		DialogPlacement.place(self, _anchor)


# Riga "Scegli zona in automatico [interruttore]" (2026-10-09, AutoZoneToggle: lo stesso della barra dei comandi, legato a
# UserOptions.work_area_auto_zone, letto alla conferma da GameScene), creata alla prima apertura sopra il separatore dei
# bottoni.
func _ensure_auto_zone_row(box: VBoxContainer, separator: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = tr("command_bar_auto_zone")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := AutoZoneToggle.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)
	box.add_child(row)
	box.move_child(row, separator.get_index())
	return row


func _on_window_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		hide()


func _on_confirm_pressed() -> void:
	# Numero scritto a mano e non ancora confermato con Invio (2026-10-06, bugfix): senza apply() il valore restava quello
	# di prima (es. scritto 2 sopra il 3 ricordato -> serie di 3). apply() equivale a Invio nel campo del selettore.
	_spin_box.apply()
	var value := int(_spin_box.value)
	hide()
	count_chosen.emit(value)
