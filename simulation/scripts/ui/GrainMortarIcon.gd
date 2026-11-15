class_name GrainMortarIcon
extends Control

# Icona del mortaio (2026-11-15, richiesta utente): un ceppo di legno scavato visto di fianco, con la conca in cima, e il
# pestello appoggiato di traverso.

const COLOR_WOOD := Color(0.55, 0.38, 0.20, 1.0)
const COLOR_WOOD_DARK := Color(0.36, 0.24, 0.12, 1.0)
const COLOR_HOLLOW := Color(0.24, 0.16, 0.08, 1.0)
const COLOR_PESTLE := Color(0.66, 0.50, 0.30, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	# Ceppo: un po' più stretto in alto, bordo scuro.
	var body := PackedVector2Array([
		Vector2(0.24 * w, 0.92 * h), Vector2(0.76 * w, 0.92 * h), Vector2(0.70 * w, 0.42 * h), Vector2(0.30 * w, 0.42 * h),
	])
	draw_colored_polygon(body, COLOR_WOOD)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, COLOR_WOOD_DARK, maxf(unit * 0.04, 1.0), true)
	# Conca in cima e due venature.
	draw_line(Vector2(0.34 * w, 0.44 * h), Vector2(0.66 * w, 0.44 * h), COLOR_HOLLOW, maxf(unit * 0.08, 1.5), true)
	draw_line(Vector2(0.40 * w, 0.55 * h), Vector2(0.38 * w, 0.86 * h), COLOR_WOOD_DARK, maxf(unit * 0.025, 1.0), true)
	draw_line(Vector2(0.60 * w, 0.55 * h), Vector2(0.62 * w, 0.86 * h), COLOR_WOOD_DARK, maxf(unit * 0.025, 1.0), true)
	# Pestello di traverso, con la testa più grossa nella conca.
	draw_line(Vector2(0.52 * w, 0.44 * h), Vector2(0.86 * w, 0.08 * h), COLOR_WOOD_DARK, maxf(unit * 0.10, 1.5), true)
	draw_line(Vector2(0.52 * w, 0.44 * h), Vector2(0.86 * w, 0.08 * h), COLOR_PESTLE, maxf(unit * 0.07, 1.0), true)
	draw_circle(Vector2(0.54 * w, 0.42 * h), unit * 0.07, COLOR_PESTLE)
