class_name ManureIcon
extends Control

# Icona del letame (2026-11-17, richiesta utente): un mucchio bruno scuro a cupola con qualche filo di paglia chiara.
# Disegnata a mano come StrawIcon, riempie il proprio Rect2.

const COLOR_HEAP := Color(0.33, 0.22, 0.12, 1.0)
const COLOR_HEAP_LIGHT := Color(0.45, 0.31, 0.17, 1.0)
const COLOR_STRAW := Color(0.80, 0.68, 0.36, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var heap := PackedVector2Array()
	var steps := 12
	for i in range(steps + 1):
		var angle := PI + PI * float(i) / float(steps)
		heap.append(Vector2(0.5 * w + cos(angle) * 0.42 * w, 0.85 * h + sin(angle) * 0.55 * h))
	draw_colored_polygon(heap, COLOR_HEAP)
	draw_circle(Vector2(0.40 * w, 0.62 * h), 0.12 * unit, COLOR_HEAP_LIGHT)
	draw_circle(Vector2(0.62 * w, 0.70 * h), 0.09 * unit, COLOR_HEAP_LIGHT)
	var width := maxf(unit * 0.05, 1.0)
	draw_line(Vector2(0.22 * w, 0.72 * h), Vector2(0.42 * w, 0.66 * h), COLOR_STRAW, width, true)
	draw_line(Vector2(0.55 * w, 0.48 * h), Vector2(0.72 * w, 0.58 * h), COLOR_STRAW, width, true)
	draw_line(Vector2(0.48 * w, 0.78 * h), Vector2(0.66 * w, 0.82 * h), COLOR_STRAW, width, true)
