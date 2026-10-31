class_name FishingLineIcon
extends Control

# Icona disegnata "lenza" (2026-10-31, richiesta utente — pesca): matassina di corda di fibra chiara avvolta, con il capo
# libero che scende e lo stecchino d'osso (gorge, appuntito ai due capi) legato in fondo. Solo _draw(), coordinate
# relative, nessun randf(). draw_into (statica) condivisa con DepositStorageIcons.

const ROPE_COLOR := Color(0.80, 0.70, 0.48, 1.0)
const ROPE_DARK_COLOR := Color(0.52, 0.42, 0.26, 1.0)
const BONE_COLOR := Color(0.93, 0.90, 0.80, 1.0)
const BONE_DARK_COLOR := Color(0.58, 0.54, 0.44, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la lenza dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	var rope_width: float = unit * 0.05

	# Matassina: tre giri di corda sovrapposti in alto a sinistra.
	var coil_center: Vector2 = p.call(0.36, 0.32)
	canvas.draw_circle(coil_center, unit * 0.22, ROPE_DARK_COLOR)
	for i in range(3):
		canvas.draw_arc(coil_center, unit * (0.20 - i * 0.055), 0.0, TAU, 20, ROPE_COLOR, rope_width, true)
	canvas.draw_circle(coil_center, unit * 0.05, ROPE_DARK_COLOR)

	# Capo libero: scende dalla matassina con una curva morbida fino allo stecchino.
	var line_points := PackedVector2Array([
		p.call(0.54, 0.40), p.call(0.64, 0.50), p.call(0.66, 0.60), p.call(0.62, 0.70), p.call(0.60, 0.76),
	])
	canvas.draw_polyline(line_points, ROPE_COLOR, rope_width, true)

	# Stecchino d'osso di traverso, appuntito ai due capi, legato al centro.
	var gorge_left: Vector2 = p.call(0.38, 0.84)
	var gorge_right: Vector2 = p.call(0.86, 0.72)
	var gorge_mid: Vector2 = gorge_left.lerp(gorge_right, 0.5)
	var direction: Vector2 = (gorge_right - gorge_left).normalized()
	var normal := Vector2(-direction.y, direction.x) * unit * 0.045
	var gorge := PackedVector2Array([gorge_left, gorge_mid + normal, gorge_right, gorge_mid - normal])
	canvas.draw_colored_polygon(gorge, BONE_COLOR)
	var closed_gorge := gorge.duplicate()
	closed_gorge.append(gorge[0])
	canvas.draw_polyline(closed_gorge, BONE_DARK_COLOR, unit * 0.02, true)
	# Nodo della corda sullo stecchino.
	canvas.draw_circle(gorge_mid, unit * 0.045, ROPE_DARK_COLOR)
