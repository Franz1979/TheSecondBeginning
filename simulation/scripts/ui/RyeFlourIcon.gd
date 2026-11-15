class_name RyeFlourIcon
extends Control

# Icona della farina di segale (2026-11-15, richiesta utente): lo stesso mucchietto della farina di grano (WheatFlourIcon),
# grigio-bruno e con più crusca.

const COLOR_FLOUR := Color(0.80, 0.76, 0.68, 1.0)
const COLOR_FLOUR_SHADE := Color(0.64, 0.60, 0.52, 1.0)
const COLOR_BRAN := Color(0.46, 0.36, 0.24, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var heap := PackedVector2Array([
		Vector2(0.10 * w, 0.86 * h), Vector2(0.90 * w, 0.86 * h), Vector2(0.62 * w, 0.30 * h), Vector2(0.50 * w, 0.22 * h),
		Vector2(0.38 * w, 0.30 * h),
	])
	draw_colored_polygon(heap, COLOR_FLOUR)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.50 * w, 0.86 * h), Vector2(0.90 * w, 0.86 * h), Vector2(0.62 * w, 0.30 * h), Vector2(0.50 * w, 0.22 * h),
	]), COLOR_FLOUR_SHADE)
	for dot in [Vector2(0.30, 0.74), Vector2(0.44, 0.58), Vector2(0.66, 0.70), Vector2(0.54, 0.44), Vector2(0.24, 0.82),
			Vector2(0.58, 0.80), Vector2(0.40, 0.70)]:
		draw_circle(Vector2(dot.x * w, dot.y * h), unit * 0.025, COLOR_BRAN)
