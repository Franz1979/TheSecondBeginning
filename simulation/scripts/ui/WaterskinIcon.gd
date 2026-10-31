class_name WaterskinIcon
extends Control

# Icona disegnata "otre" (2026-10-30, richiesta utente — sete, ThirstService): pancia di pelle affumicata, collo stretto
# legato con un laccio e tappo di legno, cinghia a tracolla, e una goccia azzurra sulla pancia che la distingue dalle
# sacche (stesso bruno di SmokedHideBagIcon). Solo _draw(), coordinate relative, nessun randf(). draw_into (statica)
# condivisa con DepositStorageIcons.

const BODY_COLOR := Color(0.45, 0.30, 0.17, 1.0)
const DARK_COLOR := Color(0.24, 0.15, 0.08, 1.0)
const LACE_COLOR := Color(0.82, 0.70, 0.50, 1.0)
const STOPPER_COLOR := Color(0.62, 0.48, 0.30, 1.0)
const WATER_COLOR := Color(0.30, 0.62, 0.95, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna l'otre dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var line_width: float = minf(area.x, area.y) * 0.05
	# Cinghia a tracolla dietro la pancia.
	canvas.draw_arc(p.call(0.50, 0.46), minf(area.x, area.y) * 0.36, PI * 1.08, PI * 1.92, 16, DARK_COLOR, line_width * 1.3, true)
	# Pancia.
	var body := PackedVector2Array([
		p.call(0.42, 0.32), p.call(0.58, 0.32), p.call(0.74, 0.42), p.call(0.84, 0.58),
		p.call(0.82, 0.76), p.call(0.70, 0.88), p.call(0.50, 0.92), p.call(0.30, 0.88),
		p.call(0.18, 0.76), p.call(0.16, 0.58), p.call(0.26, 0.42),
	])
	canvas.draw_colored_polygon(body, BODY_COLOR)
	var closed_body := body.duplicate()
	closed_body.append(body[0])
	canvas.draw_polyline(closed_body, DARK_COLOR, line_width, true)
	# Cucitura laterale chiara.
	canvas.draw_polyline(PackedVector2Array([p.call(0.26, 0.50), p.call(0.22, 0.66), p.call(0.28, 0.82)]), LACE_COLOR, line_width * 0.8, true)
	# Collo stretto.
	var neck := PackedVector2Array([p.call(0.44, 0.34), p.call(0.46, 0.18), p.call(0.54, 0.18), p.call(0.56, 0.34)])
	canvas.draw_colored_polygon(neck, BODY_COLOR)
	var closed_neck := neck.duplicate()
	closed_neck.append(neck[0])
	canvas.draw_polyline(closed_neck, DARK_COLOR, line_width, true)
	# Laccio sul collo e tappo.
	canvas.draw_line(p.call(0.42, 0.26), p.call(0.58, 0.26), LACE_COLOR, line_width * 1.4, true)
	canvas.draw_rect(Rect2(p.call(0.45, 0.10), Vector2(0.10 * area.x, 0.09 * area.y)), STOPPER_COLOR)
	# Goccia d'acqua sulla pancia.
	var drop_center: Vector2 = p.call(0.52, 0.64)
	var drop_radius: float = minf(area.x, area.y) * 0.08
	canvas.draw_circle(drop_center, drop_radius, WATER_COLOR)
	canvas.draw_colored_polygon(PackedVector2Array([
		drop_center + Vector2(-drop_radius * 0.9, -drop_radius * 0.3),
		drop_center + Vector2(0.0, -drop_radius * 2.2),
		drop_center + Vector2(drop_radius * 0.9, -drop_radius * 0.3),
	]), WATER_COLOR)
