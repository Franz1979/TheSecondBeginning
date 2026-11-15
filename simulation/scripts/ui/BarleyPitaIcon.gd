class_name BarleyPitaIcon
extends Control

# Icona della pita d'orzo (2026-11-15, richiesta utente): una focaccia tonda e bassa vista dall'alto, color nocciola, con
# il bordo più scuro e qualche bolla bruciacchiata della cottura sulla pietra.

const COLOR_CRUST := Color(0.70, 0.52, 0.30, 1.0)
const COLOR_TOP := Color(0.84, 0.68, 0.44, 1.0)
const COLOR_CHAR := Color(0.46, 0.32, 0.16, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var unit := minf(size.x, size.y)
	var c := size * 0.5
	draw_circle(c, unit * 0.42, COLOR_CRUST)
	draw_circle(c, unit * 0.36, COLOR_TOP)
	for spot in [Vector2(-0.14, -0.10), Vector2(0.12, -0.16), Vector2(0.16, 0.10), Vector2(-0.08, 0.16), Vector2(0.0, 0.0)]:
		draw_circle(c + spot * unit, unit * 0.035, COLOR_CHAR)
