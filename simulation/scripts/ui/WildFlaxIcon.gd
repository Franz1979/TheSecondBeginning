class_name WildFlaxIcon
extends Control

# Icona dei semi di lino selvatico (2026-11-15, richiesta utente — erano tre steli fioriti, quando il lino selvatico era la
# fibra): un mucchietto di semi piatti, ovali e lucidi, con un fiorellino azzurro accanto per riconoscere la pianta.
# FlaxSeedsIcon (semi domestici) cambia solo i colori e toglie il fiore. Disegnata a mano, riempie il proprio Rect2.

var color_seed := Color(0.48, 0.32, 0.18, 1.0)
var color_seed_dark := Color(0.34, 0.22, 0.12, 1.0)
var color_shine := Color(0.85, 0.70, 0.50, 0.9)
var show_flower := true

const COLOR_PETAL := Color(0.45, 0.62, 0.92, 1.0)
const COLOR_CENTER := Color(0.95, 0.88, 0.45, 1.0)
# (centro, angolo) in proporzione al riquadro.
const SEEDS := [
	{"pos": Vector2(0.30, 0.70), "angle": -0.5},
	{"pos": Vector2(0.50, 0.76), "angle": 0.3},
	{"pos": Vector2(0.70, 0.68), "angle": 0.9},
	{"pos": Vector2(0.40, 0.52), "angle": 1.4},
	{"pos": Vector2(0.60, 0.50), "angle": -1.1},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	for i in range(SEEDS.size()):
		var seed_data: Dictionary = SEEDS[i]
		var center := Vector2((seed_data["pos"] as Vector2).x * w, (seed_data["pos"] as Vector2).y * h)
		var angle: float = seed_data["angle"]
		var points := PackedVector2Array()
		for step in range(12):
			var t := TAU * float(step) / 12.0
			points.append(center + Vector2(cos(t) * unit * 0.13, sin(t) * unit * 0.07).rotated(angle))
		draw_colored_polygon(points, color_seed if i % 2 == 0 else color_seed_dark)
		draw_circle(center + Vector2(-unit * 0.04, -unit * 0.015).rotated(angle), unit * 0.022, color_shine)
	if show_flower:
		var top := Vector2(0.74 * w, 0.24 * h)
		for i in range(5):
			var petal_angle := TAU * float(i) / 5.0 - PI / 2.0
			draw_circle(top + Vector2(cos(petal_angle), sin(petal_angle)) * unit * 0.07, unit * 0.065, COLOR_PETAL)
		draw_circle(top, unit * 0.04, COLOR_CENTER)
