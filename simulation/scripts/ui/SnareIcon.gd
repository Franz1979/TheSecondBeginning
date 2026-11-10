class_name SnareIcon
extends Control

# Icona disegnata "mazzo di lacci" (2026-11-09, capanna del trappoliere): due paletti piantati, la cordicella tesa tra
# loro e un cappio di corda che pende al centro. Solo _draw(), coordinate relative, nessun randf(). draw_into (statica)
# condivisa con DepositStorageIcons.

const STAKE_COLOR := Color(0.55, 0.38, 0.20, 1.0)
const STAKE_DARK_COLOR := Color(0.34, 0.22, 0.11, 1.0)
const CORD_COLOR := Color(0.82, 0.74, 0.52, 1.0)
const GROUND_COLOR := Color(0.36, 0.30, 0.20, 1.0)

# Paletti: punta in alto e base a terra, un po' inclinati verso l'esterno.
const STAKES := [[Vector2(0.22, 0.20), Vector2(0.28, 0.86)], [Vector2(0.80, 0.22), Vector2(0.73, 0.86)]]
const GROUND_Y := 0.86
# Cordicella tesa tra i paletti, e punto da cui pende il cappio.
const CORD_LEFT := Vector2(0.245, 0.34)
const CORD_RIGHT := Vector2(0.775, 0.35)
const NOOSE_TOP := Vector2(0.51, 0.345)
const NOOSE_CENTER := Vector2(0.51, 0.58)
const NOOSE_RADIUS := Vector2(0.12, 0.15)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il mazzo di lacci dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.04, 1.0)

	# Terra sotto i paletti.
	canvas.draw_line(p.call(Vector2(0.12, GROUND_Y)), p.call(Vector2(0.88, GROUND_Y)), GROUND_COLOR, width * 1.4, true)

	# Paletti: corpo e ombra su un lato, punta appuntita.
	for stake in STAKES:
		var top: Vector2 = stake[0]
		var bottom: Vector2 = stake[1]
		canvas.draw_line(p.call(top), p.call(bottom), STAKE_COLOR, width * 2.2, true)
		canvas.draw_line(p.call(top + Vector2(0.015, 0.04)), p.call(bottom + Vector2(0.015, 0.0)), STAKE_DARK_COLOR, width * 0.8, true)

	# Cordicella tesa, con una leggera curva verso il centro.
	canvas.draw_polyline(PackedVector2Array([p.call(CORD_LEFT), p.call(NOOSE_TOP), p.call(CORD_RIGHT)]), CORD_COLOR, width, true)

	# Cappio: tratto che scende e anello aperto in basso al nodo.
	var knot: Vector2 = NOOSE_CENTER - Vector2(0.0, NOOSE_RADIUS.y)
	canvas.draw_line(p.call(NOOSE_TOP), p.call(knot), CORD_COLOR, width, true)
	var loop := PackedVector2Array()
	for step in range(25):
		var radians := deg_to_rad(-90.0 + 15.0 * float(step))
		loop.append(p.call(NOOSE_CENTER + Vector2(cos(radians) * NOOSE_RADIUS.x, sin(radians) * NOOSE_RADIUS.y)))
	canvas.draw_polyline(loop, CORD_COLOR, width * 1.2, true)
	# Nodo scorsoio: un piccolo ingrossamento in cima all'anello.
	canvas.draw_circle(p.call(knot), width * 1.3, CORD_COLOR)
