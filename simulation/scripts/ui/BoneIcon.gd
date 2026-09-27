class_name BoneIcon
extends Control

# Icona provvisoria "ossa" (2026-09-26, richiesta utente — macellazione, step 1): un osso lungo in diagonale
# con le due estremità a doppio nodo, color osso. Stesso schema di WoodenSpearIcon: draw_into (statica)
# condivisa con DepositStorageIcons.

const BONE_COLOR := Color(0.92, 0.89, 0.80, 1.0)
const BONE_SHADE_COLOR := Color(0.66, 0.62, 0.52, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna l'osso dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var width: float = minf(area.x, area.y)
	var a: Vector2 = p.call(0.26, 0.74)
	var b: Vector2 = p.call(0.74, 0.26)
	var normal: Vector2 = Vector2(-(b - a).y, (b - a).x).normalized() * width * 0.08
	for end_point in [a, b]:
		canvas.draw_circle(end_point + normal, width * 0.11, BONE_SHADE_COLOR)
		canvas.draw_circle(end_point - normal, width * 0.11, BONE_SHADE_COLOR)
	canvas.draw_line(a, b, BONE_SHADE_COLOR, width * 0.16, true)
	canvas.draw_line(a, b, BONE_COLOR, width * 0.11, true)
	for end_point in [a, b]:
		canvas.draw_circle(end_point + normal, width * 0.08, BONE_COLOR)
		canvas.draw_circle(end_point - normal, width * 0.08, BONE_COLOR)
