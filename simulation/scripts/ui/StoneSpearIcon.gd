class_name StoneSpearIcon
extends Control

# Icona disegnata "lancia con punta di pietra" (2026-10-04, richiesta utente — modello migliore di wooden_spear):
# stessa asta diagonale color corteccia di WoodenSpearIcon (con i due nodi del ramo), ma in cima una punta di pietra
# scheggiata, grigia e più larga dell'asta, legata con un giro di tendine chiaro. Solo _draw(), coordinate relative,
# nessun randf(). draw_into (statica) condivisa con DepositStorageIcons (magazzino sulla mappa, arma a terra).

const BARK_COLOR := Color(0.42, 0.30, 0.16, 1.0)
const BARK_DARK_COLOR := Color(0.30, 0.20, 0.10, 1.0)
const STONE_COLOR := Color(0.62, 0.61, 0.58, 1.0)
const STONE_DARK_COLOR := Color(0.36, 0.35, 0.33, 1.0)
const BINDING_COLOR := Color(0.88, 0.80, 0.62, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la lancia dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var shaft_width: float = minf(area.x, area.y) * 0.10
	var butt: Vector2 = p.call(0.12, 0.88)
	var head_start: Vector2 = p.call(0.60, 0.40)
	var tip: Vector2 = p.call(0.92, 0.08)

	# Asta con la corteccia, fino all'attacco della punta.
	canvas.draw_line(butt, head_start, BARK_COLOR, shaft_width, true)
	canvas.draw_circle(butt, shaft_width * 0.5, BARK_DARK_COLOR)
	canvas.draw_circle(butt.lerp(head_start, 0.30), shaft_width * 0.32, BARK_DARK_COLOR)
	canvas.draw_circle(butt.lerp(head_start, 0.68), shaft_width * 0.26, BARK_DARK_COLOR)

	# Punta di pietra a foglia, più larga dell'asta: grigia con il contorno scuro e una scheggiatura al centro.
	var direction: Vector2 = (tip - head_start).normalized()
	var normal := Vector2(-direction.y, direction.x) * shaft_width
	var widest: Vector2 = head_start.lerp(tip, 0.35)
	var blade := PackedVector2Array([head_start, widest + normal * 1.1, tip, widest - normal * 1.1])
	canvas.draw_colored_polygon(blade, STONE_COLOR)
	var closed_blade := blade.duplicate()
	closed_blade.append(blade[0])
	canvas.draw_polyline(closed_blade, STONE_DARK_COLOR, shaft_width * 0.22, true)
	canvas.draw_line(widest, head_start.lerp(tip, 0.75), STONE_DARK_COLOR, shaft_width * 0.18, true)
	# Legatura di tendine dove la punta si innesta sull'asta.
	var binding: Vector2 = head_start.lerp(butt, 0.06)
	var binding_normal := normal * 0.75
	canvas.draw_line(binding + binding_normal, binding - binding_normal, BINDING_COLOR, shaft_width * 0.45, true)
