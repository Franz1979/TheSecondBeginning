class_name HideIcon
extends Control

# Icona provvisoria "pelle" (2026-09-26, richiesta utente — macellazione, step 1): una pelle distesa con le
# quattro zampe, color cuoio, con un bordo più scuro. Stesso schema di WoodenSpearIcon: draw_into (statica)
# condivisa con DepositStorageIcons.

const HIDE_COLOR := Color(0.66, 0.48, 0.30, 1.0)
const HIDE_DARK_COLOR := Color(0.42, 0.29, 0.17, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la pelle dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var outline := PackedVector2Array([
		p.call(0.50, 0.12), p.call(0.62, 0.24), p.call(0.86, 0.18), p.call(0.74, 0.40),
		p.call(0.80, 0.62), p.call(0.88, 0.84), p.call(0.64, 0.74), p.call(0.50, 0.90),
		p.call(0.36, 0.74), p.call(0.12, 0.84), p.call(0.20, 0.62), p.call(0.26, 0.40),
		p.call(0.14, 0.18), p.call(0.38, 0.24),
	])
	canvas.draw_colored_polygon(outline, HIDE_COLOR)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, HIDE_DARK_COLOR, minf(area.x, area.y) * 0.05, true)
