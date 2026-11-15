class_name BarleyGroatsIcon
extends Control

# Icona della semola d'orzo (2026-11-15, richiesta utente): un mucchietto di chicchi spezzati chiari, di forme irregolari,
# con qualche scaglia di pula più scura.

const COLOR_GROAT := Color(0.93, 0.84, 0.60, 1.0)
const COLOR_GROAT_DARK := Color(0.78, 0.66, 0.40, 1.0)
const COLOR_HUSK := Color(0.62, 0.48, 0.26, 1.0)
# (x, y, raggio) in proporzione al riquadro: base larga, cima stretta.
const GRAINS := [
	Vector3(0.22, 0.80, 0.09), Vector3(0.38, 0.82, 0.10), Vector3(0.55, 0.81, 0.10), Vector3(0.72, 0.80, 0.09),
	Vector3(0.30, 0.66, 0.09), Vector3(0.47, 0.65, 0.10), Vector3(0.64, 0.66, 0.09),
	Vector3(0.39, 0.51, 0.09), Vector3(0.56, 0.51, 0.09), Vector3(0.48, 0.37, 0.08),
]
const HUSKS := [Vector2(0.16, 0.90), Vector2(0.80, 0.70), Vector2(0.86, 0.88)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	for i in range(GRAINS.size()):
		var g: Vector3 = GRAINS[i]
		var c := Vector2(g.x * w, g.y * h)
		var r := g.z * unit
		# Chicco spezzato: un mezzo ovale con il lato rotto più scuro.
		draw_circle(c, r, COLOR_GROAT_DARK)
		draw_circle(c + Vector2(-0.15, -0.15) * r, r * 0.8, COLOR_GROAT)
	for husk in HUSKS:
		var p := Vector2(husk.x * w, husk.y * h)
		draw_line(p, p + Vector2(0.07 * w, -0.03 * h), COLOR_HUSK, maxf(unit * 0.04, 1.0), true)
