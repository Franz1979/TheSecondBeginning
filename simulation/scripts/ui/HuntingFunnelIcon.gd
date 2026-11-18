class_name HuntingFunnelIcon
extends Control

# Icona disegnata "imbuto di caccia" (2026-11-18, animali grossi — cattura viva delle prede grosse): fascio di pali con
# un rotolo di corda, i pali per le braccia dell'imbuto. Solo _draw(), coordinate relative, nessun randf(). draw_into
# (statica) condivisa con DepositStorageIcons.

const STAKE_COLOR := Color(0.55, 0.38, 0.20, 1.0)
const STAKE_DARK_COLOR := Color(0.34, 0.22, 0.11, 1.0)
const CORD_COLOR := Color(0.82, 0.74, 0.52, 1.0)

# Pali paralleli di sbieco (base, cima).
const STAKES := [
	[Vector2(0.12, 0.80), Vector2(0.62, 0.14)],
	[Vector2(0.24, 0.86), Vector2(0.74, 0.20)],
	[Vector2(0.36, 0.92), Vector2(0.86, 0.26)],
]
const COIL_CENTER := Vector2(0.72, 0.74)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna l'imbuto di caccia (pali e corda) dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.05, 1.0)
	for stake in STAKES:
		var bottom: Vector2 = stake[0]
		var top: Vector2 = stake[1]
		canvas.draw_line(p.call(bottom), p.call(top), STAKE_COLOR, width * 2.0, true)
		canvas.draw_line(p.call(bottom + Vector2(0.015, 0.0)), p.call(top + Vector2(0.015, 0.0)), STAKE_DARK_COLOR, width * 0.7, true)
	# Legature dei pali.
	for t in [0.3, 0.7]:
		var a: Vector2 = (STAKES[0][0] as Vector2).lerp(STAKES[0][1], t)
		var b: Vector2 = (STAKES[2][0] as Vector2).lerp(STAKES[2][1], t)
		canvas.draw_line(p.call(a), p.call(b), CORD_COLOR, width * 1.0, true)
	# Rotolo di corda.
	for radius in [0.16, 0.10]:
		canvas.draw_arc(p.call(COIL_CENTER), unit * radius, 0.0, TAU, 16, CORD_COLOR, width * 1.1, true)
