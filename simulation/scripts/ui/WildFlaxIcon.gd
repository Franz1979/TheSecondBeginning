class_name WildFlaxIcon
extends Control

# Icona del lino selvatico (2026-11-15, richiesta utente): tre steli sottili e diritti con un fiorellino azzurro in cima.
# Disegnata a mano come PlantFiberIcon, riempie il proprio Rect2.

const COLOR_STEM := Color(0.50, 0.58, 0.30, 1.0)
const COLOR_STEM_DARK := Color(0.38, 0.45, 0.22, 1.0)
const COLOR_PETAL := Color(0.45, 0.62, 0.92, 1.0)
const COLOR_CENTER := Color(0.95, 0.88, 0.45, 1.0)
# (base_x, cima, colore) in proporzione al riquadro.
const STEMS := [
	{"base": 0.42, "top": Vector2(0.26, 0.24), "color": COLOR_STEM_DARK},
	{"base": 0.50, "top": Vector2(0.52, 0.12), "color": COLOR_STEM},
	{"base": 0.58, "top": Vector2(0.76, 0.26), "color": COLOR_STEM_DARK},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	for stem in STEMS:
		var base := Vector2(float(stem["base"]) * w, 0.92 * h)
		var top := Vector2((stem["top"] as Vector2).x * w, (stem["top"] as Vector2).y * h)
		draw_line(base, top, stem["color"], maxf(unit * 0.05, 1.0), true)
		for i in range(5):
			var angle := TAU * float(i) / 5.0 - PI / 2.0
			draw_circle(top + Vector2(cos(angle), sin(angle)) * unit * 0.065, unit * 0.06, COLOR_PETAL)
		draw_circle(top, unit * 0.035, COLOR_CENTER)
