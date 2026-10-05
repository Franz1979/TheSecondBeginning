class_name StoneAxeIcon
extends Control

# Icona disegnata "accetta rudimentale" (2026-10-04, richiesta utente): manico di legno dritto in diagonale (dal basso a
# sinistra verso l'alto a destra) e, in cima, una testa di pietra grigia a cuneo, con il taglio verso sinistra, legata al
# manico da una fascia di corda. Poche forme grandi con il contorno scuro, leggibili a 32 px. Solo _draw(), coordinate
# relative, nessun randf(). draw_into (statica) condivisa con DepositStorageIcons.

const HANDLE_COLOR := Color(0.55, 0.38, 0.20, 1.0)
const STONE_COLOR := Color(0.64, 0.63, 0.60, 1.0)
const STONE_EDGE_COLOR := Color(0.80, 0.79, 0.76, 1.0)
const BINDING_COLOR := Color(0.86, 0.76, 0.52, 1.0)
const OUTLINE_COLOR := Color(0.16, 0.12, 0.08, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x * area.x, y * area.y)
	var unit: float = minf(area.x, area.y)
	var outline: float = unit * 0.03
	var handle_width: float = unit * 0.11
	# Manico: dal basso a sinistra fino a sotto la testa, contorno scuro e legno sopra.
	var handle_bottom: Vector2 = p.call(0.20, 0.92)
	var handle_top: Vector2 = p.call(0.66, 0.20)
	canvas.draw_line(handle_bottom, handle_top, OUTLINE_COLOR, handle_width + outline * 2.0)
	canvas.draw_line(handle_bottom, handle_top, HANDLE_COLOR, handle_width)
	# Testa di pietra a cuneo in cima, con il filo verso sinistra: largo sul filo, stretto verso il manico.
	var head := PackedVector2Array([
		p.call(0.58, 0.14), p.call(0.80, 0.22), p.call(0.80, 0.40), p.call(0.58, 0.48),
		p.call(0.24, 0.42), p.call(0.16, 0.30), p.call(0.24, 0.16),
	])
	canvas.draw_colored_polygon(head, STONE_COLOR)
	var closed_head := head.duplicate()
	closed_head.append(head[0])
	canvas.draw_polyline(closed_head, OUTLINE_COLOR, outline * 1.4)
	# Filo della lama, più chiaro, sul lato sinistro.
	canvas.draw_line(p.call(0.23, 0.19), p.call(0.22, 0.40), STONE_EDGE_COLOR, unit * 0.05)
	# Legatura di corda: fascia sul punto in cui il manico entra nella testa.
	var binding_center: Vector2 = p.call(0.66, 0.31)
	var binding := Rect2(binding_center - Vector2(unit * 0.11, unit * 0.09), Vector2(unit * 0.22, unit * 0.18))
	canvas.draw_rect(binding.grow(outline), OUTLINE_COLOR)
	canvas.draw_rect(binding, BINDING_COLOR)
	canvas.draw_line(binding.position + Vector2(0.0, binding.size.y * 0.5), binding.end - Vector2(0.0, binding.size.y * 0.5), OUTLINE_COLOR, outline)
