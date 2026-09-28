class_name AutoZoneIcon
extends Control

# Icona disegnata del bottone a interruttore "Scegli zona in automatico" della barra in basso (2026-09-28, richiesta
# utente — work areas): una zona tratteggiata (come WorkAreaIcon) con una freccia circolare al centro, il segno di
# "automatico". Acceso: zona gialla e freccia verde; spento: tutto grigio e una barra rossa di traverso, così lo stato
# si legge a colpo d'occhio anche senza il colore del bottone premuto. Solo _draw() nel proprio rettangolo (lo slot lo
# ancora a tutto riquadro), alla dimensione reale del bottone.

const ZONE_ON := Color(0.98, 0.80, 0.20, 1.0)
const ZONE_FILL_ON := Color(0.98, 0.80, 0.20, 0.22)
const ARROW_ON := Color(0.45, 0.92, 0.45, 1.0)
const OFF_COLOR := Color(0.62, 0.62, 0.62, 1.0)
const OFF_FILL := Color(0.62, 0.62, 0.62, 0.12)
const SLASH_COLOR := Color(0.92, 0.28, 0.24, 1.0)
const DASH_COUNT: int = 4

var active: bool = true:
	set(value):
		active = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var unit: float = minf(w, h)
	var line_width: float = maxf(1.0, unit * 0.05)
	var zone_color := ZONE_ON if active else OFF_COLOR
	var rect := Rect2(Vector2(w * 0.16, h * 0.2), Vector2(w * 0.68, h * 0.6))
	draw_rect(rect, ZONE_FILL_ON if active else OFF_FILL)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for d in range(DASH_COUNT):
			var t0: float = (float(d) + 0.2) / float(DASH_COUNT)
			var t1: float = (float(d) + 0.8) / float(DASH_COUNT)
			draw_line(a.lerp(b, t0), a.lerp(b, t1), zone_color, line_width, true)
	# Freccia circolare: arco di tre quarti con la punta a triangolo.
	var center := rect.get_center()
	var radius: float = unit * 0.17
	var arrow_color := ARROW_ON if active else OFF_COLOR
	var start_angle: float = -PI * 0.35
	var end_angle: float = PI * 1.15
	draw_arc(center, radius, start_angle, end_angle, 24, arrow_color, line_width * 1.3, true)
	var tip := center + Vector2.from_angle(end_angle) * radius
	var tangent := Vector2.from_angle(end_angle + PI / 2.0)
	var normal := Vector2.from_angle(end_angle)
	var head: float = unit * 0.1
	draw_colored_polygon(PackedVector2Array([
		tip + tangent * head, tip - normal * head * 0.8, tip + normal * head * 0.8,
	]), arrow_color)
	if not active:
		draw_line(Vector2(w * 0.2, h * 0.8), Vector2(w * 0.8, h * 0.2), SLASH_COLOR, line_width * 1.5, true)
