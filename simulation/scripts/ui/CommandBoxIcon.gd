class_name CommandBoxIcon
extends Node2D

# Icona del comando "transport" (2026-09-26, richiesta utente — icone di comando disegnate, stesso stile
# del mirino CrosshairIcon): scatola di cartone in prospettiva a tre quarti, come l'emoji 📦 che
# sostituisce — faccia frontale, lato destro più scuro, coperchio più chiaro, nastro che corre sul
# coperchio e scende sul davanti. (Una prima versione frontale, "dritta", non convinceva.) Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px =
# 1 microcella).

const TOP := Color(0.88, 0.7, 0.46, 1.0)
const FRONT := Color(0.8, 0.6, 0.36, 1.0)
const SIDE := Color(0.64, 0.46, 0.26, 1.0)
const TAPE := Color(0.95, 0.88, 0.7, 1.0)
const OUTLINE := Color(0.3, 0.2, 0.1, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3

# Faccia frontale (rettangolo) e spostamento verso il fondo della scatola (profondità in prospettiva).
const FRONT_LEFT: float = -2.6
const FRONT_RIGHT: float = 1.2
const FRONT_TOP: float = -0.6
const FRONT_BOTTOM: float = 2.4
const DEPTH := Vector2(1.4, -1.2)
# Nastro: mezza larghezza e posizione (al centro della faccia frontale).
const TAPE_HALF_WIDTH: float = 0.3


func _draw() -> void:
	var front_top_left := Vector2(FRONT_LEFT, FRONT_TOP)
	var front_top_right := Vector2(FRONT_RIGHT, FRONT_TOP)
	var front_bottom_right := Vector2(FRONT_RIGHT, FRONT_BOTTOM)
	var front_bottom_left := Vector2(FRONT_LEFT, FRONT_BOTTOM)

	var front := PackedVector2Array([front_top_left, front_top_right, front_bottom_right, front_bottom_left])
	var top := PackedVector2Array([front_top_left, front_top_right, front_top_right + DEPTH, front_top_left + DEPTH])
	var side := PackedVector2Array([front_top_right, front_top_right + DEPTH, front_bottom_right + DEPTH, front_bottom_right])
	draw_colored_polygon(front, FRONT)
	draw_colored_polygon(top, TOP)
	draw_colored_polygon(side, SIDE)

	# Nastro: striscia lungo la profondità sul coperchio, poi giù per la faccia frontale.
	var tape_center_x: float = (FRONT_LEFT + FRONT_RIGHT) / 2.0
	var tape_left := Vector2(tape_center_x - TAPE_HALF_WIDTH, FRONT_TOP)
	var tape_right := Vector2(tape_center_x + TAPE_HALF_WIDTH, FRONT_TOP)
	draw_colored_polygon(PackedVector2Array([tape_left, tape_right, tape_right + DEPTH, tape_left + DEPTH]), TAPE)
	draw_colored_polygon(PackedVector2Array([
		tape_left, tape_right, Vector2(tape_right.x, FRONT_TOP + 1.3), Vector2(tape_left.x, FRONT_TOP + 1.3),
	]), TAPE)

	for face in [front, top, side]:
		var outline: PackedVector2Array = face.duplicate()
		outline.append(face[0])
		draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)
