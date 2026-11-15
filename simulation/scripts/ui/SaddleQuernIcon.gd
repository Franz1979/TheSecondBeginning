class_name SaddleQuernIcon
extends Control

# Icona della macina a sella (2026-11-15, richiesta utente): una pietra piatta lunga e incavata al centro, vista di fianco,
# con sopra il macinello tondeggiante e un po' di farina chiara nella conca.

const COLOR_STONE := Color(0.62, 0.61, 0.58, 1.0)
const COLOR_STONE_DARK := Color(0.40, 0.39, 0.36, 1.0)
const COLOR_RUBBER := Color(0.52, 0.50, 0.46, 1.0)
const COLOR_FLOUR := Color(0.93, 0.89, 0.78, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	# Pietra a sella: bordo superiore incavato (alto ai capi, basso al centro).
	var base := PackedVector2Array([
		Vector2(0.06 * w, 0.82 * h), Vector2(0.94 * w, 0.82 * h), Vector2(0.94 * w, 0.58 * h),
		Vector2(0.75 * w, 0.66 * h), Vector2(0.50 * w, 0.70 * h), Vector2(0.25 * w, 0.66 * h), Vector2(0.06 * w, 0.58 * h),
	])
	draw_colored_polygon(base, COLOR_STONE)
	var outline := base.duplicate()
	outline.append(base[0])
	draw_polyline(outline, COLOR_STONE_DARK, maxf(unit * 0.04, 1.0), true)
	# Farina nella conca.
	draw_line(Vector2(0.30 * w, 0.68 * h), Vector2(0.70 * w, 0.68 * h), COLOR_FLOUR, maxf(unit * 0.05, 1.0), true)
	# Macinello sopra.
	var rubber_center := Vector2(0.52 * w, 0.52 * h)
	draw_circle(rubber_center, unit * 0.17, COLOR_STONE_DARK)
	draw_circle(rubber_center, unit * 0.145, COLOR_RUBBER)
