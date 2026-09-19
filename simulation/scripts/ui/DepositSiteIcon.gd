class_name DepositSiteIcon
extends Control

# Icona del Deposit Site per il bottone in BuildBar (2026-09-19, richiesta utente — "rendi l'icona
# un po' più simile al rendering, fai che si veda il bordo"; poi "troppo simile a quella della terra
# battuta, disegna una specie di mucchio di sacchi di iuta"): la STESSA sagoma dell'edificio
# piazzato (DepositSiteShape: angoli smussati, riempimento e bordo scuro) con sopra un piccolo
# mucchio di tre sacchi di iuta — due in basso, uno sopra — che la distingue a colpo d'occhio dalla
# terra battuta (DirtGroundIcon, senza bordo né sacchi). Control minimale, solo _draw(): riempie il
# proprio Rect2 (vedi IconButtonRow.configure_slot, che lo ancora PRESET_FULL_RECT dentro lo slot),
# quindi scala con qualunque dimensione di slot — stesso schema di PebbleCircleIcon. Ridisegnato
# solo quando il Control lo richiede (resize), mai a ogni frame.

const MARGIN_RATIO: float = 0.08
const OUTLINE_WIDTH_RATIO: float = 0.05

const SACK_COLOR := Color(0.74, 0.62, 0.40, 1.0)
const SACK_OUTLINE_COLOR := Color(0.42, 0.32, 0.18, 1.0)
const SACK_WEAVE_COLOR := Color(0.58, 0.46, 0.28, 1.0)
const SACK_ELLIPSE_SEGMENTS: int = 14
# Sacchi: (centro x, centro y) come frazione del lato rispetto al centro dell'icona, semiassi
# frazione del lato. Ordine = ordine di disegno (i due in basso prima, quello in cima sopra).
const SACK_RADIUS_X_RATIO: float = 0.15
const SACK_RADIUS_Y_RATIO: float = 0.12
const SACK_CENTERS: Array[Vector2] = [
	Vector2(-0.16, 0.10),
	Vector2(0.16, 0.10),
	Vector2(0.0, -0.09),
]


func _ready() -> void:
	# IGNORE: puro disegno, i click devono raggiungere il Button sotto (vedi PebbleCircleIcon).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var center: Vector2 = size / 2.0
	var shape := DepositSiteShape.build_polygon(side * (0.5 - MARGIN_RATIO))
	var points := PackedVector2Array()
	for point in shape:
		points.append(center + point)
	draw_colored_polygon(points, DepositSiteShape.FILL_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, DepositSiteShape.OUTLINE_COLOR, maxf(1.0, side * OUTLINE_WIDTH_RATIO), true)

	for sack_center in SACK_CENTERS:
		_draw_sack(center + sack_center * side, side)


# Un sacco: corpo ellittico color iuta con bordo scuro, "collo" legato (piccolo triangolo scuro in
# cima) e due tratti diagonali corti a suggerire la trama del tessuto.
func _draw_sack(sack_center: Vector2, side: float) -> void:
	var radius := Vector2(SACK_RADIUS_X_RATIO, SACK_RADIUS_Y_RATIO) * side
	var body := PackedVector2Array()
	for i in range(SACK_ELLIPSE_SEGMENTS):
		var angle: float = TAU * float(i) / float(SACK_ELLIPSE_SEGMENTS)
		body.append(sack_center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(body, SACK_COLOR)

	var neck := PackedVector2Array([
		sack_center + Vector2(-radius.x * 0.28, -radius.y * 0.85),
		sack_center + Vector2(radius.x * 0.28, -radius.y * 0.85),
		sack_center + Vector2(0.0, -radius.y - side * 0.05),
	])
	draw_colored_polygon(neck, SACK_OUTLINE_COLOR)

	var body_outline := body.duplicate()
	body_outline.append(body[0])
	draw_polyline(body_outline, SACK_OUTLINE_COLOR, maxf(1.0, side * 0.03), true)

	var weave_width: float = maxf(1.0, side * 0.02)
	draw_line(
		sack_center + Vector2(-radius.x * 0.45, -radius.y * 0.1), sack_center + Vector2(-radius.x * 0.05, radius.y * 0.4),
		SACK_WEAVE_COLOR, weave_width
	)
	draw_line(
		sack_center + Vector2(radius.x * 0.05, -radius.y * 0.1), sack_center + Vector2(radius.x * 0.45, radius.y * 0.4),
		SACK_WEAVE_COLOR, weave_width
	)
