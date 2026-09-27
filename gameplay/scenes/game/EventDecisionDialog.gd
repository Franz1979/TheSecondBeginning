class_name EventDecisionDialog
extends Window

# Popup di decisione GENERICO per gli eventi (2026-09-27, richiesta utente — primo uso: arrivo dei visitatori):
# titolo, testo e due pulsanti con etichette decise dal chiamante. "Pannello muto" come DemolishConfirmation
# Dialog: riceve tutto già tradotto e composto, non conosce eventi né visitatori; alla scelta emette
# option_chosen con l'indice del pulsante (0 = primo, 1 = secondo) e il `context` passato all'apertura, così il
# chiamante sa a cosa si riferiva la domanda.
#
# Bloccante: GameScene collega visibility_changed a _on_blocking_dialog_visibility_changed (tempo e camera
# fermi), `exclusive` blocca l'input al resto della scena. Non si chiude senza scegliere: X nativa nascosta
# e close_requested non collegato (stesso meccanismo di HelpDialog), una Window semplice non si chiude con Esc.
#
# Costruita interamente via codice, nessun .tscn — stesso pattern di NotificationPopup.

signal option_chosen(option_index: int, context: Variant)

const DIALOG_WIDTH: int = 380
const DIALOG_MIN_HEIGHT: int = 180
const CONTENT_MARGIN: int = 12

var _context: Variant = null
var _message_label: Label
var _first_button: Button
var _second_button: Button


func _init() -> void:
	visible = false
	exclusive = true
	transient = true
	unresizable = true
	wrap_controls = true


func _ready() -> void:
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, CONTENT_MARGIN)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CONTENT_MARGIN)
	margin.add_child(box)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(DIALOG_WIDTH - 2 * CONTENT_MARGIN, 0)
	_message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_message_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", CONTENT_MARGIN)
	box.add_child(buttons)

	_first_button = Button.new()
	_first_button.custom_minimum_size = Vector2(120, 32)
	_first_button.pressed.connect(_choose.bind(0))
	buttons.add_child(_first_button)

	_second_button = Button.new()
	_second_button.custom_minimum_size = Vector2(120, 32)
	_second_button.pressed.connect(_choose.bind(1))
	buttons.add_child(_second_button)


func open_dialog(dialog_title: String, message: String, first_label: String, second_label: String, context: Variant = null) -> void:
	_context = context
	title = dialog_title
	_message_label.text = message
	_first_button.text = first_label
	_second_button.text = second_label
	popup_centered(Vector2i(DIALOG_WIDTH, DIALOG_MIN_HEIGHT))


func _choose(option_index: int) -> void:
	var context: Variant = _context
	_context = null
	hide()
	option_chosen.emit(option_index, context)
