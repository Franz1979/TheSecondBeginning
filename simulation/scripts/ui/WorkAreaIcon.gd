class_name WorkAreaIcon
extends Control

# Icona disegnata del bottone "Zone di lavoro" della barra in basso (2026-09-27, richiesta utente — work areas): un
# rettangolo tratteggiato con i quattro angoli marcati e un riempimento leggero, come una zona tracciata a terra.
# Solo _draw(), coordinate relative al proprio rettangolo (lo slot di IconButtonRow lo ancora a tutto riquadro), stesso
# schema di LayersIcon/PebbleCircleIcon.

const FILL_COLOR := Color(0.98, 0.80, 0.20, 0.28)
const LINE_COLOR := Color(0.98, 0.80, 0.20, 1.0)
const CORNER_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const DASH_COUNT: int = 4


func _ready() -> void:
	# Solo disegno: i click devono arrivare al bottone sotto.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var line_width: float = minf(w, h) * 0.05
	var rect := Rect2(Vector2(w * 0.2, h * 0.24), Vector2(w * 0.6, h * 0.52))
	draw_rect(rect, FILL_COLOR)
	# Lati tratteggiati.
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for d in range(DASH_COUNT):
			var t0: float = (float(d) + 0.2) / float(DASH_COUNT)
			var t1: float = (float(d) + 0.8) / float(DASH_COUNT)
			draw_line(a.lerp(b, t0), a.lerp(b, t1), LINE_COLOR, line_width, true)
	# Angoli marcati.
	var corner_len: float = minf(w, h) * 0.1
	var directions := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in range(4):
		var c: Vector2 = corners[i]
		var dir: Vector2 = directions[i]
		draw_line(c, c + Vector2(dir.x * corner_len, 0.0), CORNER_COLOR, line_width * 1.4, true)
		draw_line(c, c + Vector2(0.0, dir.y * corner_len), CORNER_COLOR, line_width * 1.4, true)
