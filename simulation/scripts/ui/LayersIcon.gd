class_name LayersIcon
extends Control

# Icona disegnata del bottone "Layer" della barra in alto (2026-09-27, richiesta utente — menu dei layer della mappa):
# tre fogli a rombo sovrapposti, visti in prospettiva. Con un layer attivo (`active`) il foglio in cima si colora e
# compare un pallino nell'angolo in alto a destra: il segnale "un layer è acceso". Solo _draw(), coordinate relative
# al proprio rettangolo (lo slot 32x32 di IconButtonRow lo ancora a tutto riquadro), stesso schema di PebbleCircleIcon.

const SHEET_COLOR := Color(0.72, 0.74, 0.78, 1.0)
const SHEET_ACTIVE_COLOR := Color(0.45, 0.78, 0.95, 1.0)
const OUTLINE_COLOR := Color(0.22, 0.24, 0.28, 1.0)
const ACTIVE_DOT_COLOR := Color(0.35, 0.85, 1.0, 1.0)
const SHEET_COUNT: int = 3

var active: bool = false:
	set(value):
		active = value
		queue_redraw()


func _ready() -> void:
	# Solo disegno: i click devono arrivare al bottone sotto.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var line_width: float = minf(w, h) * 0.045
	# Dal foglio più in basso a quello in cima, ognuno spostato verso l'alto.
	for i in range(SHEET_COUNT):
		var center_y: float = h * (0.64 - 0.14 * float(i))
		var points := PackedVector2Array([
			Vector2(w * 0.5, center_y - h * 0.14),
			Vector2(w * 0.84, center_y),
			Vector2(w * 0.5, center_y + h * 0.14),
			Vector2(w * 0.16, center_y),
		])
		var is_top: bool = i == SHEET_COUNT - 1
		draw_colored_polygon(points, SHEET_ACTIVE_COLOR if active and is_top else SHEET_COLOR)
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, OUTLINE_COLOR, line_width, true)
	if active:
		var dot_radius: float = minf(w, h) * 0.11
		var dot_center := Vector2(w - dot_radius * 1.3, dot_radius * 1.3)
		draw_circle(dot_center, dot_radius, ACTIVE_DOT_COLOR)
		draw_arc(dot_center, dot_radius, 0.0, TAU, 16, OUTLINE_COLOR, line_width * 0.8, true)
