class_name CommandAxeIcon
extends Node2D

# Icona del comando "cut" (2026-10-04, richiesta utente — task Cut): accetta inclinata, manico di legno e testa di pietra
# a cuneo col filo verso l'esterno, stesso stile di CommandPickaxeIcon. Registrata in IconRegistry.COMMAND_ICON_NODES;
# origine = centro dell'icona, pixel locali della cella (10 px = 1 microcella).

const WOOD := Color(0.62, 0.42, 0.22, 1.0)
const STONE := Color(0.64, 0.63, 0.60, 1.0)
const STONE_EDGE := Color(0.82, 0.81, 0.78, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3

# Fattore applicato a coordinate e spessori (2026-10-06, come CrosshairIcon/CommandHandIcon): 1 sulla mappa (pixel di
# cella, come sempre); nel bottone della barra dei comandi (CommandButtonIcon) il disegno avviene direttamente alla
# dimensione reale invece di ingrandire il nodo con `scale`, che sfocava i bordi antialiasati.
var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	# Manico: dal basso a sinistra verso l'alto a destra, come il piccone.
	var handle_axis := Vector2(1.0, -1.0).normalized()
	var handle_start: Vector2 = -handle_axis * 3.0 * s
	var handle_end: Vector2 = handle_axis * 2.2 * s
	draw_line(handle_start, handle_end, OUTLINE, (0.7 + OUTLINE_WIDTH_PX * 2.0) * s, true)
	draw_line(handle_start, handle_end, WOOD, 0.7 * s, true)
	# Testa a cuneo su un solo lato del manico, vicino alla cima: stretta sul manico, larga sul filo.
	var side := handle_axis.orthogonal()
	var head_base: Vector2 = handle_axis * 1.3 * s
	var head := PackedVector2Array([
		head_base + handle_axis * 0.6 * s,
		head_base - handle_axis * 0.6 * s,
		head_base + (-handle_axis * 1.2 + side * 2.4) * s,
		head_base + (handle_axis * 1.2 + side * 2.4) * s,
	])
	draw_colored_polygon(head, STONE)
	var closed := head.duplicate()
	closed.append(head[0])
	draw_polyline(closed, OUTLINE, OUTLINE_WIDTH_PX * 1.5 * s, true)
	# Filo della lama più chiaro.
	draw_line(head[2], head[3], STONE_EDGE, 0.45 * s, true)
