class_name SmokedMeatIcon
extends Control

# Icona provvisoria "carne affumicata" (2026-10-03, richiesta utente — ricette dell'affumicatoio): un pezzo di carne
# scuro, bruno-rossastro con la crosta quasi nera e due venature chiare di grasso, e un filo di fumo grigio che sale.
# Stesso schema di CookedMeatIcon: draw_into (statica) condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const CRUST_COLOR := Color(0.34, 0.15, 0.09, 1.0)
const CRUST_DARK_COLOR := Color(0.18, 0.08, 0.05, 1.0)
const FAT_COLOR := Color(0.78, 0.60, 0.38, 1.0)
const SMOKE_COLOR := Color(0.70, 0.70, 0.68, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la carne affumicata dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	var outline := PackedVector2Array([
		p.call(0.18, 0.62), p.call(0.26, 0.44), p.call(0.46, 0.36), p.call(0.68, 0.40),
		p.call(0.82, 0.56), p.call(0.78, 0.76), p.call(0.58, 0.86), p.call(0.34, 0.84), p.call(0.20, 0.76),
	])
	canvas.draw_colored_polygon(outline, CRUST_COLOR)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, CRUST_DARK_COLOR, unit * 0.05, true)
	canvas.draw_line(p.call(0.32, 0.70), p.call(0.50, 0.52), FAT_COLOR, unit * 0.04, true)
	canvas.draw_line(p.call(0.48, 0.76), p.call(0.66, 0.58), FAT_COLOR, unit * 0.04, true)
	# Filo di fumo sopra il pezzo.
	canvas.draw_polyline(PackedVector2Array([
		p.call(0.50, 0.32), p.call(0.44, 0.24), p.call(0.52, 0.16), p.call(0.46, 0.08),
	]), SMOKE_COLOR, unit * 0.05, true)
