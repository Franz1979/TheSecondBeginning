class_name WoodenSpearIcon
extends Control

# Icona disegnata "lancia di legno" (2026-09-24, richiesta utente — 🔱 leggeva come un forcone:
# "è semplicemente uno stick appuntito"). Un solo bastone dritto in diagonale, color corteccia, con
# l'estremità superiore SCORTECCIATA e affilata a punta (legno chiaro, a triangolo) e la punta
# annerita dal fuoco (la ricetta è indurita al focolare, recipe_fuel_required). Due nodi scuri sulla
# corteccia per leggerlo come un ramo, non un'asta lavorata. Stesso schema di StickIcon: solo
# _draw(), coordinate relative al proprio Rect2, nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con MicroCellRenderer (icona nel magazzino
# sulla mappa) — un solo disegno per entrambi i punti.

const BARK_COLOR := Color(0.42, 0.30, 0.16, 1.0)
const BARK_DARK_COLOR := Color(0.30, 0.20, 0.10, 1.0)
const CARVED_COLOR := Color(0.82, 0.68, 0.46, 1.0)
const HARDENED_TIP_COLOR := Color(0.22, 0.15, 0.09, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la lancia dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var shaft_width: float = minf(area.x, area.y) * 0.10
	var butt: Vector2 = p.call(0.12, 0.88)
	var carve_start: Vector2 = p.call(0.62, 0.38)
	var tip: Vector2 = p.call(0.90, 0.10)

	# Asta con la corteccia, dal fondo all'inizio della parte scortecciata.
	canvas.draw_line(butt, carve_start, BARK_COLOR, shaft_width, true)
	# Estremità inferiore tagliata netta, leggermente più scura.
	canvas.draw_circle(butt, shaft_width * 0.5, BARK_DARK_COLOR)
	# Due nodi del ramo.
	canvas.draw_circle(butt.lerp(carve_start, 0.30), shaft_width * 0.32, BARK_DARK_COLOR)
	canvas.draw_circle(butt.lerp(carve_start, 0.68), shaft_width * 0.26, BARK_DARK_COLOR)

	# Parte scortecciata e appuntita: triangolo di legno chiaro dalla larghezza piena dell'asta fino
	# alla punta.
	var direction: Vector2 = (tip - carve_start).normalized()
	var normal := Vector2(-direction.y, direction.x) * shaft_width * 0.55
	canvas.draw_colored_polygon(PackedVector2Array([carve_start + normal, tip, carve_start - normal]), CARVED_COLOR)
	# Punta indurita al fuoco: l'ultimo tratto del triangolo, annerito.
	var hardened_start: Vector2 = carve_start.lerp(tip, 0.62)
	var hardened_normal: Vector2 = normal * 0.38
	canvas.draw_colored_polygon(PackedVector2Array([hardened_start + hardened_normal, tip, hardened_start - hardened_normal]), HARDENED_TIP_COLOR)
	# Bordo sottile dove finisce la corteccia.
	canvas.draw_line(carve_start + normal, carve_start - normal, BARK_DARK_COLOR, shaft_width * 0.25, true)
