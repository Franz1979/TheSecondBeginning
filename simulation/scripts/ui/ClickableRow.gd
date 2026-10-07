class_name ClickableRow
extends PanelContainer

# Riga cliccabile di un elenco (2026-10-07, richiesta utente — un solo gesto in tutti gli elenchi): clic sinistro in un
# punto qualsiasi della riga = `clicked` (chi la crea collega la stessa funzione che prima stava sul 🎯); al passaggio del
# mouse la riga si illumina leggermente e il cursore diventa la manina. I bottoni dentro la riga tengono il loro clic
# (mouse_filter STOP: l'evento non arriva qui). Il contenuto si aggiunge come figlio, come in un PanelContainer: senza
# illuminazione il fondo è vuoto e senza margini, quindi l'impaginazione della riga non cambia.
# MOUSE_FILTER_PASS (non STOP): la rotella e gli altri eventi non usati risalgono allo scorrimento dell'elenco.
# `clickable` = false: riga spenta (voce che non si può centrare), niente clic, niente illuminazione, cursore normale.

signal clicked

const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const HOVER_CORNER_RADIUS: int = 3

var clickable: bool = true:
	set(value):
		clickable = value
		_apply_cursor(self)
		_apply_style()

var _hovered: bool = false
var _empty_style := StyleBoxEmpty.new()
var _hover_style: StyleBoxFlat = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = HOVER_COLOR
	_hover_style.set_corner_radius_all(HOVER_CORNER_RADIUS)
	_hover_style.content_margin_left = 0
	_hover_style.content_margin_right = 0
	_hover_style.content_margin_top = 0
	_hover_style.content_margin_bottom = 0
	mouse_entered.connect(func() -> void:
		_hovered = true
		_apply_style()
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		_apply_style()
	)
	_apply_style()


# Il contenuto è già stato aggiunto: manina anche sui figli che lasciano passare il clic (es. testi con tooltip), non su
# bottoni ed elementi STOP, che tengono il loro clic e il loro cursore.
func _ready() -> void:
	_apply_cursor(self)


func _gui_input(event: InputEvent) -> void:
	if not clickable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _hover_style if _hovered and clickable else _empty_style)


func _apply_cursor(node: Node) -> void:
	# Bottoni e altri elementi che tengono il proprio clic (STOP, es. l'icona della casa): cursore loro, nessuna manina.
	if node is BaseButton or (node != self and node is Control and (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP):
		return
	if node is Control:
		(node as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	for child in node.get_children():
		_apply_cursor(child)
