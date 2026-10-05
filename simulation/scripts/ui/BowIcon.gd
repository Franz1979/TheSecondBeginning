class_name BowIcon
extends Control

# Icona disegnata "arco" (2026-10-04, richiesta utente): un arco di legno curvo in verticale, più spesso al centro
# (l'impugnatura), con la corda tesa chiara tra le due estremità. Solo _draw(), coordinate relative, nessun randf().
# draw_into (statica) condivisa con DepositStorageIcons.

const WOOD_COLOR := Color(0.50, 0.34, 0.18, 1.0)
const GRIP_COLOR := Color(0.32, 0.21, 0.11, 1.0)
const STRING_COLOR := Color(0.90, 0.85, 0.72, 1.0)
const ARC_SEGMENTS: int = 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	var top: Vector2 = p.call(0.40, 0.10)
	var bottom: Vector2 = p.call(0.40, 0.90)
	# Corda tesa tra le estremità.
	canvas.draw_line(top, bottom, STRING_COLOR, unit * 0.03, true)
	# Legno: arco di parabola che sporge a destra, più spesso al centro.
	var points := PackedVector2Array()
	for i in range(ARC_SEGMENTS + 1):
		var t := float(i) / float(ARC_SEGMENTS)
		var bulge: float = 0.38 * (1.0 - pow(2.0 * t - 1.0, 2.0))
		points.append(p.call(0.40 + bulge, 0.10 + 0.80 * t))
	for i in range(ARC_SEGMENTS):
		var t := (float(i) + 0.5) / float(ARC_SEGMENTS)
		var width: float = unit * (0.05 + 0.05 * (1.0 - absf(2.0 * t - 1.0)))
		canvas.draw_line(points[i], points[i + 1], WOOD_COLOR, width, true)
	# Impugnatura al centro e puntali alle estremità.
	canvas.draw_line(p.call(0.78, 0.44), p.call(0.78, 0.56), GRIP_COLOR, unit * 0.12, true)
	canvas.draw_circle(top, unit * 0.035, GRIP_COLOR)
	canvas.draw_circle(bottom, unit * 0.035, GRIP_COLOR)
