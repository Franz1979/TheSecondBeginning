class_name CommandRejectedIcon
extends Node2D

# Icona "comando rifiutato" (2026-09-26, richiesta utente — icone di comando disegnate, stesso stile
# del mirino CrosshairIcon): X rossa piena con un sottile bordo scuro, per leggersi su qualunque
# terreno. Registrata in IconRegistry.COMMAND_ICON_NODES ("task_rejected"); origine = centro
# dell'icona, pixel locali della cella (10 px = 1 microcella).

const COLOR := Color(0.9, 0.12, 0.12, 1.0)
const OUTLINE := Color(0.25, 0.02, 0.02, 1.0)
const HALF_SIZE_PX: float = 2.4
const LINE_WIDTH_PX: float = 0.8
const OUTLINE_WIDTH_PX: float = 0.3


func _draw() -> void:
	var a := Vector2(-HALF_SIZE_PX, -HALF_SIZE_PX)
	var b := Vector2(HALF_SIZE_PX, HALF_SIZE_PX)
	var c := Vector2(HALF_SIZE_PX, -HALF_SIZE_PX)
	var d := Vector2(-HALF_SIZE_PX, HALF_SIZE_PX)
	var outline_width := LINE_WIDTH_PX + OUTLINE_WIDTH_PX * 2.0
	draw_line(a, b, OUTLINE, outline_width, true)
	draw_line(c, d, OUTLINE, outline_width, true)
	draw_line(a, b, COLOR, LINE_WIDTH_PX, true)
	draw_line(c, d, COLOR, LINE_WIDTH_PX, true)
