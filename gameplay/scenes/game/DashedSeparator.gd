class_name DashedSeparator
extends Control

# Tratteggio orizzontale - - - - tra una voce e l'altra delle regole (2026-10-17, richiesta utente: Regole di stoccaggio e
# Regole di assegnazione), più leggero dell'HSeparator che chiude le sezioni.

const HEIGHT: float = 9.0
const DASH: float = 4.0
const COLOR := Color(1.0, 1.0, 1.0, 0.22)


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var y := roundf(size.y * 0.5) + 0.5
	draw_dashed_line(Vector2(0.0, y), Vector2(size.x, y), COLOR, 1.0, DASH)


# Aggiunge `item` a `box`, preceduto da un tratteggio se non è la prima voce.
static func add_item(box: Container, item: Control) -> void:
	if box.get_child_count() > 0:
		box.add_child(DashedSeparator.new())
	box.add_child(item)
