class_name OatCakeIcon
extends Control

# Icona della galletta d'avena (2026-11-15, richiesta utente): due focaccine sottili e tonde una sopra l'altra, bordo
# bruciacchiato e qualche fiocco in vista.

const COLOR_CAKE := Color(0.86, 0.72, 0.46, 1.0)
const COLOR_EDGE := Color(0.62, 0.46, 0.24, 1.0)
const COLOR_FLAKE := Color(0.95, 0.88, 0.68, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	for cake in [Vector2(0.44, 0.66), Vector2(0.56, 0.50)]:
		var edge := PackedVector2Array()
		var top := PackedVector2Array()
		for k in range(24):
			var a := TAU * float(k) / 24.0
			edge.append(Vector2((cake.x + cos(a) * 0.34) * w, (cake.y + sin(a) * 0.20) * h))
			top.append(Vector2((cake.x + cos(a) * 0.29) * w, (cake.y - 0.02 + sin(a) * 0.16) * h))
		draw_colored_polygon(edge, COLOR_EDGE)
		draw_colored_polygon(top, COLOR_CAKE)
	for dot in [Vector2(0.48, 0.44), Vector2(0.62, 0.50), Vector2(0.56, 0.42), Vector2(0.68, 0.44)]:
		draw_circle(Vector2(dot.x * w, dot.y * h), unit * 0.025, COLOR_FLAKE)
