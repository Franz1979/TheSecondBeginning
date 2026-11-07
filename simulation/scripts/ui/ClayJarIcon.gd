class_name ClayJarIcon
extends Control

# Icona "giara" (2026-11-04, richiesta utente — al posto dell'emoji, che sembrava un'anfora raffinata): un vasone grezzo e
# tozzo, largo quasi come è alto, senza manici e senza collo: si restringe appena verso la bocca larga. Sagoma un po' storta,
# fatta a mano, con segni orizzontali del colombino. Stesso schema di BoneIcon: draw_into condivisa con DepositStorageIcons.

const BODY_COLOR := Color(0.65, 0.36, 0.22, 1.0)
const SHADE_COLOR := Color(0.49, 0.26, 0.16, 1.0)
const RIM_COLOR := Color(0.74, 0.45, 0.29, 1.0)
const MOUTH_COLOR := Color(0.20, 0.11, 0.08, 1.0)
const COIL_COLOR := Color(0.54, 0.29, 0.18, 1.0)

# Sagoma, in frazioni dell'area: un lato leggermente diverso dall'altro.
const BODY_POINTS: Array[Vector2] = [
	Vector2(0.23, 0.20), Vector2(0.19, 0.38), Vector2(0.15, 0.56), Vector2(0.20, 0.76), Vector2(0.33, 0.88),
	Vector2(0.67, 0.89), Vector2(0.81, 0.75), Vector2(0.86, 0.55), Vector2(0.80, 0.37), Vector2(0.77, 0.20),
]
# Lato in ombra, a destra.
const SHADE_POINTS: Array[Vector2] = [
	Vector2(0.64, 0.20), Vector2(0.77, 0.20), Vector2(0.80, 0.37), Vector2(0.86, 0.55), Vector2(0.81, 0.75),
	Vector2(0.67, 0.89), Vector2(0.56, 0.89), Vector2(0.69, 0.72), Vector2(0.72, 0.52), Vector2(0.68, 0.34),
]
# Segni del colombino: y, x iniziale, x finale.
const COILS: Array[Vector3] = [Vector3(0.40, 0.23, 0.70), Vector3(0.56, 0.20, 0.74), Vector3(0.72, 0.24, 0.70)]
const MOUTH_CENTER := Vector2(0.50, 0.19)
const MOUTH_RADIUS := Vector2(0.29, 0.10)
const MOUTH_SEGMENTS: int = 18


# Giara con dell'acqua (2026-11-06): disegnata con l'acqua nella bocca (WaterJarService.decorate_jar_box).
var full: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if full:
		draw_full_into(self, Vector2.ZERO, size)
	else:
		draw_into(self, Vector2.ZERO, size)


# Disegna la giara dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var width: float = minf(area.x, area.y)
	var p := func(point: Vector2) -> Vector2: return origin + Vector2(point.x * area.x, point.y * area.y)
	var to_canvas := func(points: Array[Vector2]) -> PackedVector2Array:
		var result := PackedVector2Array()
		for point in points:
			result.append(p.call(point))
		return result
	canvas.draw_colored_polygon(to_canvas.call(BODY_POINTS), BODY_COLOR)
	canvas.draw_colored_polygon(to_canvas.call(SHADE_POINTS), SHADE_COLOR)
	for coil in COILS:
		canvas.draw_line(p.call(Vector2(coil.y, coil.x)), p.call(Vector2(coil.z, coil.x)), COIL_COLOR, width * 0.025, true)
	# Bocca larga: orlo chiaro, interno scuro.
	_draw_ellipse(canvas, p.call(MOUTH_CENTER), Vector2(MOUTH_RADIUS.x * area.x, MOUTH_RADIUS.y * area.y), RIM_COLOR)
	_draw_ellipse(canvas, p.call(MOUTH_CENTER), Vector2(MOUTH_RADIUS.x * area.x, MOUTH_RADIUS.y * area.y) * 0.72, MOUTH_COLOR)


# Giara con dell'acqua (2026-11-06, ToolInstance.KEY_WATER): la stessa giara con l'acqua nella bocca.
const WATER_COLOR := Color(0.30, 0.55, 0.80, 1.0)


static func draw_full_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	draw_into(canvas, origin, area)
	var center := origin + Vector2(MOUTH_CENTER.x * area.x, MOUTH_CENTER.y * area.y)
	_draw_ellipse(canvas, center, Vector2(MOUTH_RADIUS.x * area.x, MOUTH_RADIUS.y * area.y) * 0.62, WATER_COLOR)


static func _draw_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(MOUTH_SEGMENTS):
		var angle := TAU * float(i) / float(MOUTH_SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	canvas.draw_colored_polygon(points, color)
