class_name StrawIcon
extends Control

# Icona della paglia (2026-11-15, richiesta utente): un covone di steli gialli legati a metà con un laccio scuro, aperto a
# ventaglio in alto e in basso. Disegnata a mano come WildFlaxIcon, riempie il proprio Rect2.

const COLOR_STALK := Color(0.86, 0.74, 0.40, 1.0)
const COLOR_STALK_DARK := Color(0.68, 0.56, 0.26, 1.0)
const COLOR_TIE := Color(0.42, 0.30, 0.16, 1.0)
const STALK_COUNT := 7


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var waist := Vector2(0.5 * w, 0.55 * h)
	for i in range(STALK_COUNT):
		var t := float(i) / float(STALK_COUNT - 1) - 0.5
		var top := Vector2((0.5 + t * 0.62) * w, 0.10 * h)
		var bottom := Vector2((0.5 + t * 0.42) * w, 0.92 * h)
		var color := COLOR_STALK if i % 2 == 0 else COLOR_STALK_DARK
		var width := maxf(unit * 0.05, 1.0)
		draw_line(waist + Vector2(t * 0.12 * w, 0.0), top, color, width, true)
		draw_line(waist + Vector2(t * 0.12 * w, 0.0), bottom, color, width, true)
	draw_line(waist + Vector2(-0.13 * w, 0.0), waist + Vector2(0.13 * w, 0.0), COLOR_TIE, maxf(unit * 0.08, 1.5), true)
