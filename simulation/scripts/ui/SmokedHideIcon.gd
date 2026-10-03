class_name SmokedHideIcon
extends Control

# Icona provvisoria "pelle affumicata" (2026-10-03, richiesta utente — ricette dell'affumicatoio): la sagoma della pelle
# (HideIcon) in un bruno scuro e caldo, con macchie più scure di affumicatura e un filo di fumo grigio. Stesso schema di
# HideIcon: draw_into (statica) condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const SMOKED_HIDE_COLOR := Color(0.45, 0.30, 0.17, 1.0)
const SMOKED_HIDE_DARK_COLOR := Color(0.24, 0.15, 0.08, 1.0)
const SMOKE_COLOR := Color(0.70, 0.70, 0.68, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la pelle affumicata dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	var outline := PackedVector2Array([
		p.call(0.50, 0.20), p.call(0.62, 0.30), p.call(0.84, 0.26), p.call(0.74, 0.46),
		p.call(0.80, 0.66), p.call(0.86, 0.86), p.call(0.64, 0.78), p.call(0.50, 0.92),
		p.call(0.36, 0.78), p.call(0.14, 0.86), p.call(0.20, 0.66), p.call(0.26, 0.46),
		p.call(0.16, 0.26), p.call(0.38, 0.30),
	])
	canvas.draw_colored_polygon(outline, SMOKED_HIDE_COLOR)
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, SMOKED_HIDE_DARK_COLOR, unit * 0.05, true)
	canvas.draw_circle(p.call(0.42, 0.56), unit * 0.07, SMOKED_HIDE_DARK_COLOR)
	canvas.draw_circle(p.call(0.60, 0.66), unit * 0.05, SMOKED_HIDE_DARK_COLOR)
	# Filo di fumo sopra la pelle.
	canvas.draw_polyline(PackedVector2Array([
		p.call(0.50, 0.16), p.call(0.45, 0.10), p.call(0.52, 0.05),
	]), SMOKE_COLOR, unit * 0.05, true)
