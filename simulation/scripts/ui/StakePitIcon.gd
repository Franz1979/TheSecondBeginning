class_name StakePitIcon
extends Control

# Icona disegnata "pali per fossa" (2026-11-11, fossa con pali — trappola per le prede grosse): tre pali appuntiti
# appoggiati di sbieco, legati al centro da una corda. Solo _draw(), coordinate relative, nessun randf(). draw_into
# (statica) condivisa con DepositStorageIcons.

const STAKE_COLOR := Color(0.55, 0.38, 0.20, 1.0)
const STAKE_DARK_COLOR := Color(0.34, 0.22, 0.11, 1.0)
const TIP_COLOR := Color(0.82, 0.68, 0.44, 1.0)
const CORD_COLOR := Color(0.82, 0.74, 0.52, 1.0)

# Pali: base in basso, punta in alto.
const STAKES := [
	[Vector2(0.20, 0.88), Vector2(0.62, 0.12)],
	[Vector2(0.44, 0.90), Vector2(0.50, 0.10)],
	[Vector2(0.80, 0.88), Vector2(0.38, 0.12)],
]
const TIP_LENGTH := 0.14
const CORD_CENTER := Vector2(0.50, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna i pali per fossa dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.05, 1.0)
	for stake in STAKES:
		var bottom: Vector2 = stake[0]
		var top: Vector2 = stake[1]
		var tip_start: Vector2 = top + (bottom - top).normalized() * TIP_LENGTH
		canvas.draw_line(p.call(bottom), p.call(tip_start), STAKE_COLOR, width * 2.0, true)
		canvas.draw_line(p.call(bottom + Vector2(0.015, 0.0)), p.call(tip_start + Vector2(0.015, 0.0)), STAKE_DARK_COLOR, width * 0.7, true)
		# Punta scortecciata, più chiara e sottile.
		canvas.draw_line(p.call(tip_start), p.call(top), TIP_COLOR, width * 1.1, true)
	# Legatura al centro.
	canvas.draw_line(p.call(CORD_CENTER + Vector2(-0.16, -0.02)), p.call(CORD_CENTER + Vector2(0.16, 0.02)), CORD_COLOR, width * 1.2, true)
	canvas.draw_line(p.call(CORD_CENTER + Vector2(-0.15, 0.05)), p.call(CORD_CENTER + Vector2(0.15, 0.08)), CORD_COLOR, width * 1.0, true)
