class_name DiggingStickIcon
extends Control

# Icona del bastone da scavo (2026-11-15, richiesta utente): bastone diagonale appuntito con un sasso forato infilato.

const COLOR_WOOD := Color(0.55, 0.38, 0.20, 1.0)
const COLOR_WOOD_DARK := Color(0.40, 0.26, 0.12, 1.0)
const COLOR_STONE := Color(0.58, 0.56, 0.52, 1.0)
const COLOR_STONE_DARK := Color(0.40, 0.39, 0.36, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var unit := minf(w, h)
	var top := Vector2(0.80 * w, 0.12 * h)
	var tip := Vector2(0.20 * w, 0.88 * h)
	draw_line(top, tip, COLOR_WOOD_DARK, maxf(unit * 0.11, 1.0), true)
	draw_line(top, tip, COLOR_WOOD, maxf(unit * 0.07, 1.0), true)
	var point := tip + (tip - top).normalized() * unit * 0.06
	draw_line(tip, point, COLOR_WOOD_DARK, maxf(unit * 0.04, 1.0), true)
	var stone := top.lerp(tip, 0.42)
	draw_circle(stone, unit * 0.15, COLOR_STONE_DARK)
	draw_circle(stone, unit * 0.12, COLOR_STONE)
	draw_circle(stone, unit * 0.045, COLOR_WOOD)
