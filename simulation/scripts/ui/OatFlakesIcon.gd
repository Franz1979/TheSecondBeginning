class_name OatFlakesIcon
extends Control

# Icona dei fiocchi d'avena (2026-11-15, richiesta utente): un mucchietto di scagliette piatte e chiare, ovali e un po'
# storte, con qualche pula.

const COLOR_FLAKE := Color(0.94, 0.88, 0.70, 1.0)
const COLOR_FLAKE_DARK := Color(0.76, 0.68, 0.48, 1.0)
const COLOR_HUSK := Color(0.60, 0.52, 0.30, 1.0)
# (x, y, angolo) in proporzione al riquadro: base larga, cima stretta.
const FLAKES := [
	Vector3(0.24, 0.80, 0.3), Vector3(0.42, 0.82, -0.4), Vector3(0.60, 0.80, 0.6), Vector3(0.76, 0.82, -0.2),
	Vector3(0.32, 0.66, -0.6), Vector3(0.50, 0.66, 0.2), Vector3(0.68, 0.66, -0.5),
	Vector3(0.40, 0.52, 0.5), Vector3(0.58, 0.52, -0.3), Vector3(0.49, 0.38, 0.1),
]
const HUSKS := [Vector2(0.14, 0.90), Vector2(0.82, 0.70)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	for f in FLAKES:
		var c := Vector2(f.x * w, f.y * h)
		var dark := PackedVector2Array()
		var light := PackedVector2Array()
		for k in range(12):
			var a := TAU * float(k) / 12.0
			var local := Vector2(cos(a) * 0.11, sin(a) * 0.06) * unit
			dark.append(c + local.rotated(f.z))
			light.append(c + (local * 0.75).rotated(f.z) + Vector2(-0.01, -0.01) * unit)
		draw_colored_polygon(dark, COLOR_FLAKE_DARK)
		draw_colored_polygon(light, COLOR_FLAKE)
	for husk in HUSKS:
		var p := Vector2(husk.x * w, husk.y * h)
		draw_line(p, p + Vector2(0.07 * w, -0.03 * h), COLOR_HUSK, maxf(unit * 0.04, 1.0), true)
