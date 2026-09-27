class_name CookedMeatIcon
extends Control

# Icona provvisoria "carne cotta" (2026-09-26, richiesta utente): lo stesso taglio della carne cruda
# (MeatIcon), più piccolo perché cuocendo si ritira, color bruno arrostito con due segni di cottura scuri e il
# bordo di grasso dorato. Stesso schema di WoodenSpearIcon: draw_into (statica) condivisa con
# DepositStorageIcons (magazzini e mucchi a terra).

const CRUST_COLOR := Color(0.55, 0.30, 0.14, 1.0)
const SEAR_COLOR := Color(0.28, 0.14, 0.06, 1.0)
const FAT_COLOR := Color(0.86, 0.66, 0.36, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la carne cotta dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var outline := PackedVector2Array([
		p.call(0.20, 0.54), p.call(0.28, 0.34), p.call(0.48, 0.26), p.call(0.70, 0.30),
		p.call(0.82, 0.46), p.call(0.78, 0.66), p.call(0.60, 0.76), p.call(0.36, 0.74), p.call(0.22, 0.66),
	])
	canvas.draw_colored_polygon(outline, CRUST_COLOR)
	canvas.draw_polyline(PackedVector2Array([
		p.call(0.24, 0.48), p.call(0.30, 0.35), p.call(0.48, 0.28), p.call(0.69, 0.32), p.call(0.79, 0.45),
	]), FAT_COLOR, minf(area.x, area.y) * 0.07, true)
	# Segni di cottura.
	var mark_width: float = minf(area.x, area.y) * 0.06
	canvas.draw_line(p.call(0.34, 0.62), p.call(0.52, 0.42), SEAR_COLOR, mark_width, true)
	canvas.draw_line(p.call(0.50, 0.68), p.call(0.68, 0.48), SEAR_COLOR, mark_width, true)
