class_name CommandPickaxeIcon
extends Node2D

# Icona del comando "demolish" (2026-09-27, richiesta utente — Demolish Task): piccone inclinato, manico di legno e
# testa di metallo ricurva a due punte, stesso stile di CommandHammerIcon. Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella).

const WOOD := Color(0.62, 0.42, 0.22, 1.0)
const METAL := Color(0.62, 0.64, 0.68, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const HEAD_THICKNESS_PX: float = 0.8
const HEAD_SEGMENTS: int = 8


func _draw() -> void:
	# Manico: dal basso a sinistra verso l'alto a destra, come il martello.
	var handle_axis := Vector2(1.0, -1.0).normalized()
	var handle_start: Vector2 = -handle_axis * 3.0
	var handle_end: Vector2 = handle_axis * 1.9
	draw_line(handle_start, handle_end, OUTLINE, 0.7 + OUTLINE_WIDTH_PX * 2.0, true)
	draw_line(handle_start, handle_end, WOOD, 0.7, true)
	# Testa: arco perpendicolare al manico, centrato sulla sua estremità, con le punte piegate verso il basso
	# (verso l'impugnatura).
	var head_axis := handle_axis.orthogonal()
	var head_center: Vector2 = handle_axis * 1.9
	var half_length := 2.6
	var bend := 1.0
	var points := PackedVector2Array()
	for i in range(HEAD_SEGMENTS + 1):
		var t: float = lerpf(-1.0, 1.0, float(i) / float(HEAD_SEGMENTS))
		points.append(head_center + head_axis * (t * half_length) - handle_axis * (bend * t * t))
	draw_polyline(points, OUTLINE, HEAD_THICKNESS_PX + OUTLINE_WIDTH_PX * 2.0, true)
	draw_polyline(points, METAL, HEAD_THICKNESS_PX, true)
