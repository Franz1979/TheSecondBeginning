class_name CommandHandIcon
extends Node2D

# Icona del comando "pickup" (2026-09-26, richiesta utente — icone di comando disegnate, stesso stile
# del mirino CrosshairIcon): mano alzata vista di palmo, ricalcata sull'emoji ✋ — quattro dita unite e
# arrotondate in cima (il medio più lungo), pollice aperto di lato, palmo arrotondato, pelle gialla
# "emoji" con contorno ambrato e sottili righe tra le dita. (Una prima versione, più schematica, non
# convinceva.) Registrata in IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali
# della cella (10 px = 1 microcella).

const SKIN := Color(1.0, 0.8, 0.24, 1.0)
const OUTLINE := Color(0.78, 0.5, 0.1, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const FINGER_SEPARATION := Color(0.78, 0.5, 0.1, 0.8)
const FINGER_SEPARATION_WIDTH_PX: float = 0.15

const FINGER_WIDTH_PX: float = 0.72
const FINGER_BASE_Y: float = 0.2
# Indice, medio, anulare, mignolo: posizione orizzontale e punta.
const FINGER_X := [-1.05, -0.35, 0.35, 1.05]
const FINGER_TOP_Y := [-2.3, -2.75, -2.6, -2.0]
const THUMB_BASE := Vector2(-1.1, 1.3)
const THUMB_TIP := Vector2(-2.45, -0.1)
const THUMB_WIDTH_PX: float = 0.8
const PALM := Rect2(Vector2(-1.45, -0.2), Vector2(2.9, 2.9))
const PALM_CORNER_PX: float = 0.8


func _draw() -> void:
	# Prima tutti i contorni (forme ingrandite del bordo), poi tutti i riempimenti sopra: così le forme
	# si fondono in un'unica sagoma, come nell'emoji, e il bordo resta solo all'esterno.
	_draw_shapes(OUTLINE, OUTLINE_WIDTH_PX)
	_draw_shapes(SKIN, 0.0)
	# Righe sottili tra le dita, dalla base del palmo fino alla punta del dito più corto dei due vicini.
	for i in range(FINGER_X.size() - 1):
		var x: float = (FINGER_X[i] + FINGER_X[i + 1]) / 2.0
		var top: float = maxf(FINGER_TOP_Y[i], FINGER_TOP_Y[i + 1]) + FINGER_WIDTH_PX * 0.5
		draw_line(Vector2(x, 0.6), Vector2(x, top), FINGER_SEPARATION, FINGER_SEPARATION_WIDTH_PX, true)


# Sagoma completa (dita, pollice, palmo) in `color`, allargata di `grow` pixel su ogni lato.
func _draw_shapes(color: Color, grow: float) -> void:
	for i in range(FINGER_X.size()):
		_draw_capsule(Vector2(FINGER_X[i], FINGER_BASE_Y), Vector2(FINGER_X[i], FINGER_TOP_Y[i]), FINGER_WIDTH_PX + grow * 2.0, color)
	_draw_capsule(THUMB_BASE, THUMB_TIP, THUMB_WIDTH_PX + grow * 2.0, color)
	draw_colored_polygon(_rounded_rect_points(PALM.grow(grow), PALM_CORNER_PX + grow), color)


# Segmento dalle estremità arrotondate (dito): linea spessa più un cerchio a ciascun capo.
func _draw_capsule(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)


# Contorno di un rettangolo dagli angoli arrotondati, come poligono.
func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 6
	var corners := [
		[rect.position + Vector2(rect.size.x - radius, radius), -PI / 2.0],
		[rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), 0.0],
		[rect.position + Vector2(radius, rect.size.y - radius), PI / 2.0],
		[rect.position + Vector2(radius, radius), PI],
	]
	for corner in corners:
		var center: Vector2 = corner[0]
		var start_angle: float = corner[1]
		for s in range(steps + 1):
			points.append(center + Vector2.from_angle(start_angle + (PI / 2.0) * float(s) / float(steps)) * radius)
	return points
