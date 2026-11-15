class_name FlaxThreadIcon
extends Control

# Icona del filo di lino (2026-11-15, richiesta utente — segnaposto): un gomitolo di filo biondo argento, con qualche giro
# visibile e il capo libero. Disegnata a mano come FlaxFiberIcon, riempie il proprio Rect2.

const COLOR_BALL := Color(0.86, 0.82, 0.68, 1.0)
const COLOR_WRAP := Color(0.68, 0.64, 0.50, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var center := Vector2(0.46 * w, 0.48 * h)
	var radius := unit * 0.32
	draw_circle(center, radius, COLOR_BALL)
	var line_width := maxf(unit * 0.035, 1.0)
	for i in range(4):
		var angle := -0.9 + float(i) * 0.45
		draw_arc(center, radius * (0.45 + 0.15 * float(i)), angle, angle + PI * 0.9, 12, COLOR_WRAP, line_width, true)
	var start := center + Vector2(radius * 0.9, radius * 0.4)
	var points := PackedVector2Array([start, start + Vector2(unit * 0.10, unit * 0.12), start + Vector2(unit * 0.05, unit * 0.26),
		start + Vector2(unit * 0.16, unit * 0.36)])
	draw_polyline(points, COLOR_WRAP, line_width, true)
