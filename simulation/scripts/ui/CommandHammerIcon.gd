class_name CommandHammerIcon
extends Node2D

# Icona del comando "build" (2026-09-26, richiesta utente — icone di comando disegnate, stesso stile
# del mirino CrosshairIcon): martello inclinato, manico di legno e testa di metallo. Registrata in
# IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px =
# 1 microcella). La stessa sagoma è riusata da CommandProduceIcon (draw_hammer, statica).

const WOOD := Color(0.62, 0.42, 0.22, 1.0)
const METAL := Color(0.62, 0.64, 0.68, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3


func _draw() -> void:
	draw_hammer(self, 0.0)


# Martello su `canvas`, ruotato di `angle` (0 = manico inclinato da in basso a sinistra verso l'alto
# a destra, testa in alto a destra). Statica: la usa anche CommandProduceIcon per i due attrezzi incrociati.
static func draw_hammer(canvas: CanvasItem, angle: float) -> void:
	var handle_axis := Vector2(1.0, -1.0).normalized().rotated(angle)
	var handle_start: Vector2 = -handle_axis * 3.0
	var handle_end: Vector2 = handle_axis * 1.6
	canvas.draw_line(handle_start, handle_end, OUTLINE, 0.7 + OUTLINE_WIDTH_PX * 2.0, true)
	canvas.draw_line(handle_start, handle_end, WOOD, 0.7, true)
	# Testa: rettangolo perpendicolare al manico, centrato sulla sua estremità.
	var head_axis := handle_axis.orthogonal()
	var head_center: Vector2 = handle_axis * 1.9
	var half_length := 1.7
	var half_width := 0.65
	var corners := PackedVector2Array([
		head_center + head_axis * half_length + handle_axis * half_width,
		head_center - head_axis * half_length + handle_axis * half_width,
		head_center - head_axis * half_length - handle_axis * half_width,
		head_center + head_axis * half_length - handle_axis * half_width,
	])
	canvas.draw_colored_polygon(corners, METAL)
	var outline := corners.duplicate()
	outline.append(corners[0])
	canvas.draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)
