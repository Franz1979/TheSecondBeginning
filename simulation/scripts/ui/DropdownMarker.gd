class_name DropdownMarker
extends Control

# Triangolino ▾ disegnato a codice nell'angolo in basso a destra di un pulsante che apre una scelta (2026-10-03,
# richiesta utente — barra dei comandi: distingue le opzioni a scelta dai comandi). Da aggiungere come figlio del
# pulsante a tutto rettangolo; ignora il mouse.

const MARKER_SIZE: float = 6.0
const MARGIN: float = 3.0
const FILL_COLOR := Color(0.95, 0.95, 0.95, 1.0)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.7)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var right: float = size.x - MARGIN
	var bottom: float = size.y - MARGIN
	var points := PackedVector2Array([
		Vector2(right - MARKER_SIZE, bottom - MARKER_SIZE * 0.6),
		Vector2(right, bottom - MARKER_SIZE * 0.6),
		Vector2(right - MARKER_SIZE * 0.5, bottom),
	])
	draw_colored_polygon(points, FILL_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.0, true)
