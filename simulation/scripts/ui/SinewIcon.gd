class_name SinewIcon
extends Control

# Icona provvisoria "tendini" (2026-09-26, richiesta utente — macellazione, step 1): tre fili chiari e
# ondulati, color avorio-rosato, raccolti in un fascio. Stesso schema di WoodenSpearIcon: draw_into (statica)
# condivisa con DepositStorageIcons.

const SINEW_COLOR := Color(0.93, 0.84, 0.74, 1.0)
const SINEW_SHADE_COLOR := Color(0.74, 0.58, 0.50, 1.0)
const WAVE_SEGMENTS: int = 10


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna i tendini dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var width: float = minf(area.x, area.y)
	for strand in range(3):
		var offset: float = (float(strand) - 1.0) * 0.12
		var points := PackedVector2Array()
		for i in range(WAVE_SEGMENTS + 1):
			var t: float = float(i) / float(WAVE_SEGMENTS)
			var x: float = 0.14 + 0.72 * t
			var y: float = 0.50 + offset + sin(t * TAU * 1.5 + float(strand)) * 0.05
			points.append(origin + Vector2(x * area.x, y * area.y))
		canvas.draw_polyline(points, SINEW_SHADE_COLOR, width * 0.09, true)
		canvas.draw_polyline(points, SINEW_COLOR, width * 0.05, true)
