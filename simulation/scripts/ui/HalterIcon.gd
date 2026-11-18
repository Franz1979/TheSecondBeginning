class_name HalterIcon
extends Control

# Icona disegnata "cavezza" (2026-11-18, animali grossi — condurre a piedi gli animali vivi): anello di corda per il muso
# con il nodo e un capo lungo che pende arricciandosi. Solo _draw(), coordinate relative, nessun randf(). draw_into
# (statica) condivisa con DepositStorageIcons.

const CORD_COLOR := Color(0.82, 0.74, 0.52, 1.0)
const CORD_DARK_COLOR := Color(0.58, 0.50, 0.32, 1.0)

const LOOP_CENTER := Vector2(0.40, 0.36)
const LOOP_RADIUS := 0.22
const KNOT := Vector2(0.58, 0.50)
# Capo lungo: dal nodo verso il basso a destra, con una curva.
const LEAD := [Vector2(0.58, 0.50), Vector2(0.70, 0.62), Vector2(0.74, 0.76), Vector2(0.66, 0.86), Vector2(0.56, 0.84),
	Vector2(0.58, 0.74)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la cavezza dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(v: Vector2) -> Vector2: return origin + Vector2(v.x * area.x, v.y * area.y)
	var unit: float = minf(area.x, area.y)
	var width: float = maxf(unit * 0.06, 1.0)
	# Anello del muso (doppio giro) e la fascia sopra la testa.
	canvas.draw_arc(p.call(LOOP_CENTER), unit * LOOP_RADIUS, 0.0, TAU, 20, CORD_DARK_COLOR, width * 1.6, true)
	canvas.draw_arc(p.call(LOOP_CENTER), unit * LOOP_RADIUS, 0.0, TAU, 20, CORD_COLOR, width, true)
	canvas.draw_arc(p.call(LOOP_CENTER + Vector2(-0.04, -0.04)), unit * LOOP_RADIUS * 0.6, PI * 0.9, PI * 1.9, 12,
		CORD_COLOR, width * 0.8, true)
	# Capo lungo.
	var lead := PackedVector2Array()
	for point in LEAD:
		lead.append(p.call(point))
	canvas.draw_polyline(lead, CORD_DARK_COLOR, width * 1.6, true)
	canvas.draw_polyline(lead, CORD_COLOR, width, true)
	# Nodo.
	canvas.draw_circle(p.call(KNOT), unit * 0.06, CORD_DARK_COLOR)
	canvas.draw_circle(p.call(KNOT), unit * 0.04, CORD_COLOR)
