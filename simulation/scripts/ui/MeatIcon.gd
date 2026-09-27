class_name MeatIcon
extends Control

# Icona provvisoria "carne cruda" (2026-09-26, richiesta utente — macellazione, step 1): un taglio di carne
# rosso con una fascia di grasso chiaro sul bordo superiore. Stesso schema di WoodenSpearIcon: draw_into
# (statica) è la geometria vera, condivisa con DepositStorageIcons (icona nel magazzino e nei mucchi a terra).

const FLESH_COLOR := Color(0.72, 0.16, 0.16, 1.0)
const FLESH_DARK_COLOR := Color(0.50, 0.09, 0.10, 1.0)
const FAT_COLOR := Color(0.95, 0.86, 0.76, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la carne dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var outline := PackedVector2Array([
		p.call(0.14, 0.52), p.call(0.24, 0.30), p.call(0.48, 0.20), p.call(0.74, 0.24),
		p.call(0.88, 0.44), p.call(0.84, 0.68), p.call(0.62, 0.82), p.call(0.34, 0.80), p.call(0.18, 0.68),
	])
	canvas.draw_colored_polygon(outline, FLESH_COLOR)
	# Fascia di grasso lungo il bordo superiore.
	canvas.draw_polyline(PackedVector2Array([
		p.call(0.18, 0.46), p.call(0.26, 0.31), p.call(0.48, 0.22), p.call(0.73, 0.26), p.call(0.85, 0.43),
	]), FAT_COLOR, minf(area.x, area.y) * 0.08, true)
	# Venatura scura.
	canvas.draw_polyline(PackedVector2Array([p.call(0.32, 0.62), p.call(0.50, 0.52), p.call(0.70, 0.58)]),
		FLESH_DARK_COLOR, minf(area.x, area.y) * 0.05, true)
