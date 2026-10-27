class_name CommandCouncilIcon
extends Node2D

# Icona del comando "council" (2026-10-26, riunioni politiche al Cerchio del consiglio): anello di sei pietre con al
# centro tre teste viste dall'alto, stesso stile delle altre icone di comando disegnate a codice. Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella).

const STONE := Color(0.72, 0.70, 0.66, 1.0)
const HEAD := Color(0.62, 0.42, 0.28, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const RING_RADIUS: float = 2.4
const STONE_RADIUS: float = 0.6
const HEAD_RING_RADIUS: float = 0.9
const HEAD_RADIUS: float = 0.5
const OUTLINE_WIDTH_PX: float = 0.3


func _draw() -> void:
	draw_council(self)


# Disegno condiviso con le icone di esito (CommandCouncilSuccessIcon, CommandCouncilQuarrelIcon): `head_ring_radius` più
# largo scosta le teste (lite).
static func draw_council(canvas: CanvasItem, head_ring_radius: float = HEAD_RING_RADIUS) -> void:
	for i in range(6):
		_dot(canvas, Vector2.from_angle(TAU * float(i) / 6.0) * RING_RADIUS, STONE_RADIUS, STONE)
	for i in range(3):
		_dot(canvas, Vector2.from_angle(TAU * float(i) / 3.0 - PI / 2.0) * head_ring_radius, HEAD_RADIUS, HEAD)


static func _dot(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(center, radius, color)
	canvas.draw_arc(center, radius, 0.0, TAU, 12, OUTLINE, OUTLINE_WIDTH_PX, true)
