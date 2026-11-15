class_name FlaxFiberIcon
extends Control

# Icona della fibra di lino (2026-11-15, richiesta utente): una matassa di fibre lunghe e ondulate, color biondo argento,
# legata in alto con un laccio. Disegnata a mano come StrawIcon, riempie il proprio Rect2.

const COLOR_FIBER := Color(0.86, 0.82, 0.68, 1.0)
const COLOR_FIBER_DARK := Color(0.70, 0.66, 0.52, 1.0)
const COLOR_TIE := Color(0.42, 0.30, 0.16, 1.0)
const FIBER_COUNT := 7
const SEGMENTS := 8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var knot := Vector2(0.5 * w, 0.18 * h)
	for i in range(FIBER_COUNT):
		var t := float(i) / float(FIBER_COUNT - 1) - 0.5
		var points := PackedVector2Array()
		for step in range(SEGMENTS + 1):
			var k := float(step) / float(SEGMENTS)
			var x := 0.5 + t * (0.08 + 0.50 * k) + sin(k * PI * 3.0 + float(i)) * 0.03
			points.append(Vector2(x * w, (0.18 + 0.74 * k) * h))
		draw_polyline(points, COLOR_FIBER if i % 2 == 0 else COLOR_FIBER_DARK, maxf(unit * 0.045, 1.0), true)
	draw_line(knot + Vector2(-0.10 * w, 0.0), knot + Vector2(0.10 * w, 0.0), COLOR_TIE, maxf(unit * 0.08, 1.5), true)
	draw_arc(knot + Vector2(0.0, -0.06 * h), unit * 0.06, 0.0, TAU, 12, COLOR_TIE, maxf(unit * 0.04, 1.0), true)
