class_name TentShapes
extends RefCounted

# Disegni delle due tende (2026-10-03, richiesta utente — scambio di aspetto), condivisi da mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icone della barra di costruzione
# (HideTentIcon/StickTentIcon), invece di copie separate. Unità: 1.0 = un pixel sulla mappa (una microcella = 10);
# `scale` per le icone. Entrambe hanno la porta (has_door): il triangolino sul bordo segue `direction`.
#
#   - hide_tent (tenda di pelli): il disegno che fino al 2026-10-03 avevano entrambe le tende, invariato — disco liscio
#     color cuoio con contorno scuro e segno della porta.
#   - stick_tent (tenda di rami): copertura chiusa e fitta di rami a raggiera verso il centro, come una capanna conica
#     vista dall'alto: un fondo pieno (il terreno non si vede), rami di lunghezza, spessore e tono irregolari con le punte
#     oltre il bordo, un nodo più scuro al centro. Niente contorno. Colori dei rametti di StickIcon. Stessa impronta.
#     Variazioni deterministiche (funzione dell'indice del ramo, mai randf()): identica a ogni ridisegno.

const RADIUS: float = 2.0
const DOOR_MARKER_COLOR := Color(0.25, 0.15, 0.06, 1.0)
const DOOR_MARKER_HALF_WIDTH: float = 0.7
const DOOR_MARKER_HEIGHT: float = 1.1

# Tenda di pelli (i valori di prima della tenda di rami).
const HIDE_TENT_COLOR := Color(0.78, 0.62, 0.32, 1.0)
const HIDE_TENT_OUTLINE_COLOR := Color(0.45, 0.32, 0.15, 1.0)
const HIDE_TENT_OUTLINE_WIDTH: float = 0.4
const HIDE_TENT_SEGMENTS: int = 24

# Tenda di rami.
const STICK_BRANCH_COUNT: int = 22
const STICK_BRANCH_INNER: float = 0.15
const STICK_BRANCH_OUTER_MIN: float = 1.02
const STICK_BRANCH_OUTER_EXTRA: float = 0.24
const STICK_BRANCH_WIDTH_MIN: float = 0.26
const STICK_BRANCH_WIDTH_EXTRA: float = 0.24
const STICK_BRANCH_ANGLE_JITTER: float = 0.22
const STICK_BRANCH_BEND: float = 0.18
const STICK_BRANCH_TONE_JITTER: float = 0.16
const STICK_KNOT_RADIUS: float = 0.42
const STICK_INVALID_COLOR := Color(0.75, 0.15, 0.15, 1.0)


# Tenda di pelli: disco pieno `fill`, contorno `outline`, segno della porta. I colori li passa il chiamante (la mappa i
# suoi, l'anteprima i propri semitrasparenti o rossi), come prima.
static func draw_hide_tent(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, fill: Color = HIDE_TENT_COLOR,
	outline: Color = HIDE_TENT_OUTLINE_COLOR, scale: float = 1.0
) -> void:
	canvas.draw_circle(center, RADIUS * scale, fill)
	canvas.draw_arc(center, RADIUS * scale, 0.0, TAU, HIDE_TENT_SEGMENTS, outline, HIDE_TENT_OUTLINE_WIDTH * scale, true)
	_draw_door_marker(canvas, center, direction, scale, 1.0)


# Tenda di rami. `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima.
static func draw_stick_tent(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0
) -> void:
	var colors: Array[Color] = [StickIcon.STICK_COLOR_MAIN, StickIcon.STICK_COLOR_LIGHT, StickIcon.STICK_COLOR_DARK]
	var tone := func(color: Color) -> Color:
		var base: Color = STICK_INVALID_COLOR.lerp(color, 0.25) if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	# Fondo pieno: la copertura è chiusa, il terreno non si vede tra un ramo e l'altro.
	canvas.draw_circle(center, RADIUS * scale, tone.call(StickIcon.STICK_COLOR_DARK))
	for i in range(STICK_BRANCH_COUNT):
		var angle: float = TAU * float(i) / float(STICK_BRANCH_COUNT) + (_hash(i, 1) - 0.5) * STICK_BRANCH_ANGLE_JITTER
		var direction_out := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction_out.y, direction_out.x)
		var outer: float = RADIUS * (STICK_BRANCH_OUTER_MIN + STICK_BRANCH_OUTER_EXTRA * _hash(i, 2))
		var width: float = STICK_BRANCH_WIDTH_MIN + STICK_BRANCH_WIDTH_EXTRA * _hash(i, 3)
		var color: Color = colors[int(_hash(i, 4) * float(colors.size())) % colors.size()]
		var shift: float = (_hash(i, 5) - 0.5) * STICK_BRANCH_TONE_JITTER
		color = Color(clampf(color.r + shift, 0.0, 1.0), clampf(color.g + shift, 0.0, 1.0), clampf(color.b + shift * 0.6, 0.0, 1.0), 1.0)
		# Leggera piega a metà: un ramo, non una riga dritta (stesso principio di StickIcon).
		var start: Vector2 = center + direction_out * STICK_BRANCH_INNER * scale
		var mid: Vector2 = center + (direction_out * outer * 0.55 + side * (_hash(i, 6) - 0.5) * STICK_BRANCH_BEND) * scale
		var end: Vector2 = center + direction_out * outer * scale
		canvas.draw_line(start, mid, tone.call(color), width * scale, true)
		canvas.draw_line(mid, end, tone.call(color), width * 0.85 * scale, true)
	# Nodo al centro, dove i rami si incrociano.
	canvas.draw_circle(center, STICK_KNOT_RADIUS * scale, tone.call(StickIcon.STICK_COLOR_DARK.darkened(0.35)))
	# Porta sempre opaca, anche nell'anteprima: deve restare leggibile (come per la tenda di pelli).
	_draw_door_marker(canvas, center, direction, scale, 1.0)


static func _draw_door_marker(canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, scale: float, alpha: float) -> void:
	var dir_vector := direction_vector(direction)
	var perpendicular := Vector2(-dir_vector.y, dir_vector.x)
	var base_center: Vector2 = center + dir_vector * RADIUS * scale
	var apex: Vector2 = center + dir_vector * (RADIUS + DOOR_MARKER_HEIGHT) * scale
	var color := Color(DOOR_MARKER_COLOR.r, DOOR_MARKER_COLOR.g, DOOR_MARKER_COLOR.b, DOOR_MARKER_COLOR.a * alpha)
	canvas.draw_colored_polygon(
		PackedVector2Array([
			base_center + perpendicular * DOOR_MARKER_HALF_WIDTH * scale,
			base_center - perpendicular * DOOR_MARKER_HALF_WIDTH * scale,
			apex,
		]),
		color
	)


static func direction_vector(direction: GameTypes.Direction) -> Vector2:
	match direction:
		GameTypes.Direction.NORTH:
			return Vector2(0, -1)
		GameTypes.Direction.EAST:
			return Vector2(1, 0)
		GameTypes.Direction.WEST:
			return Vector2(-1, 0)
		_: # SOUTH, anche default
			return Vector2(0, 1)


# Valore stabile in [0, 1) per il ramo `index` e la proprietà `salt`.
static func _hash(index: int, salt: int) -> float:
	var value: float = sin(float(index) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return value - floor(value)
