class_name FlintSickleIcon
extends Control

# Icona del falcetto di selce (2026-11-15, richiesta utente): manico di legno e una fila di schegge di pietra a dente di
# sega lungo la curva, legate col filo.

const COLOR_WOOD := Color(0.55, 0.38, 0.20, 1.0)
const COLOR_WOOD_DARK := Color(0.40, 0.26, 0.12, 1.0)
const COLOR_FLINT := Color(0.66, 0.64, 0.58, 1.0)
const COLOR_FLINT_DARK := Color(0.42, 0.41, 0.37, 1.0)
const COLOR_TIE := Color(0.78, 0.70, 0.48, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	# Manico, in basso a sinistra.
	var grip_end := Vector2(0.18 * w, 0.88 * h)
	var grip_start := Vector2(0.38 * w, 0.62 * h)
	draw_line(grip_start, grip_end, COLOR_WOOD_DARK, maxf(unit * 0.12, 1.0), true)
	draw_line(grip_start, grip_end, COLOR_WOOD, maxf(unit * 0.08, 1.0), true)
	# Lama curva: arco di schegge.
	var center := Vector2(0.62 * w, 0.62 * h)
	var radius := unit * 0.34
	var points := PackedVector2Array()
	for i in range(7):
		var angle := lerpf(PI * 1.05, PI * 1.85, float(i) / 6.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, COLOR_WOOD_DARK, maxf(unit * 0.07, 1.0), true)
	for i in range(1, 7):
		var base := points[i]
		var inward := (center - base).normalized()
		var tangent := Vector2(-inward.y, inward.x)
		var flake := PackedVector2Array([
			base - tangent * unit * 0.05, base + tangent * unit * 0.05, base + inward * unit * 0.11,
		])
		draw_colored_polygon(flake, COLOR_FLINT if i % 2 == 0 else COLOR_FLINT_DARK)
	# Legatura tra manico e lama.
	draw_circle(grip_start, unit * 0.06, COLOR_TIE)
