class_name RyeBreadIcon
extends Control

# Icona del pane nero di segale (2026-11-15, richiesta utente): una pagnotta tonda e bassa, crosta scura con una spolverata
# di farina chiara sopra e una crepa.

const COLOR_CRUST := Color(0.36, 0.24, 0.14, 1.0)
const COLOR_CRUST_LIGHT := Color(0.48, 0.33, 0.20, 1.0)
const COLOR_DUST := Color(0.82, 0.78, 0.70, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var loaf := PackedVector2Array()
	var light := PackedVector2Array()
	for k in range(24):
		var angle := TAU * float(k) / 24.0
		loaf.append(Vector2((0.5 + cos(angle) * 0.40) * w, (0.56 + sin(angle) * 0.34) * h))
		light.append(Vector2((0.48 + cos(angle) * 0.30) * w, (0.50 + sin(angle) * 0.24) * h))
	draw_colored_polygon(loaf, COLOR_CRUST)
	draw_colored_polygon(light, COLOR_CRUST_LIGHT)
	for dot in [Vector2(0.40, 0.42), Vector2(0.52, 0.38), Vector2(0.60, 0.46), Vector2(0.46, 0.52), Vector2(0.34, 0.50)]:
		draw_circle(Vector2(dot.x * w, dot.y * h), unit * 0.03, COLOR_DUST)
	draw_line(Vector2(0.34 * w, 0.62 * h), Vector2(0.50 * w, 0.58 * h), COLOR_DUST, maxf(unit * 0.03, 1.0), true)
	draw_line(Vector2(0.50 * w, 0.58 * h), Vector2(0.64 * w, 0.64 * h), COLOR_DUST, maxf(unit * 0.03, 1.0), true)
