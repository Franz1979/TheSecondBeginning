class_name WarehouseIcon
extends Control

# Icona disegnata (provvisoria) del bottone "Scorte" della riga del governo del villaggio (2026-10-10, richiesta utente —
# cassetto della gestione dei magazzini): tre casse di legno impilate a piramide, con le assi e il contorno scuro. Solo
# _draw(), coordinate relative al proprio rettangolo (lo slot di IconButtonRow lo ancora a tutto riquadro), stesso schema
# di LayersIcon.

const CRATE_COLOR := Color(0.80, 0.62, 0.38, 1.0)
const PLANK_COLOR := Color(0.56, 0.40, 0.22, 1.0)
const OUTLINE_COLOR := Color(0.22, 0.17, 0.12, 1.0)


func _ready() -> void:
	# Solo disegno: i click devono arrivare al bottone sotto.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var side: float = minf(w, h) * 0.30
	var line_width: float = minf(w, h) * 0.045
	var bottom: float = h * 0.82
	# Due casse sotto, una sopra al centro.
	_draw_crate(Vector2(w * 0.5 - side - line_width, bottom - side), side, line_width)
	_draw_crate(Vector2(w * 0.5 + line_width, bottom - side), side, line_width)
	_draw_crate(Vector2(w * 0.5 - side * 0.5, bottom - side * 2.0 - line_width * 2.0), side, line_width)


func _draw_crate(top_left: Vector2, side: float, line_width: float) -> void:
	var rect := Rect2(top_left, Vector2(side, side))
	draw_rect(rect, CRATE_COLOR)
	# Assi orizzontali e una diagonale di rinforzo.
	draw_line(top_left + Vector2(0.0, side * 0.5), top_left + Vector2(side, side * 0.5), PLANK_COLOR, line_width * 0.8, true)
	draw_line(top_left, top_left + Vector2(side, side), PLANK_COLOR, line_width * 0.8, true)
	draw_rect(rect, OUTLINE_COLOR, false, line_width)
