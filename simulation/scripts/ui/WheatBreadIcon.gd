class_name WheatBreadIcon
extends Control

# Icona del pane di grano (2026-11-15, richiesta utente): una pagnotta ovale e alta, vista di tre quarti, crosta dorata con
# due tagli chiari sopra.

const COLOR_CRUST := Color(0.72, 0.46, 0.20, 1.0)
const COLOR_CRUST_LIGHT := Color(0.86, 0.62, 0.32, 1.0)
const COLOR_CUT := Color(0.95, 0.84, 0.62, 1.0)


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
		loaf.append(Vector2((0.5 + cos(angle) * 0.42) * w, (0.56 + sin(angle) * 0.30) * h))
		light.append(Vector2((0.48 + cos(angle) * 0.34) * w, (0.50 + sin(angle) * 0.20) * h))
	draw_colored_polygon(loaf, COLOR_CRUST)
	draw_colored_polygon(light, COLOR_CRUST_LIGHT)
	draw_line(Vector2(0.32 * w, 0.52 * h), Vector2(0.46 * w, 0.40 * h), COLOR_CUT, maxf(unit * 0.05, 1.0), true)
	draw_line(Vector2(0.52 * w, 0.54 * h), Vector2(0.66 * w, 0.42 * h), COLOR_CUT, maxf(unit * 0.05, 1.0), true)
