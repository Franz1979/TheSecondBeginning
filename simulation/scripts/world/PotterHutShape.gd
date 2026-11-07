class_name PotterHutShape
extends RefCounted

# Capanna del vasellaio (potter_hut, 2026-11-03, richiesta utente — Vasellame, passo 4): disegno di mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra (PotterHutIcon), nello
# stile di ClothingHutShape (colori smorzati, contorni marroni sottili, una metà in ombra).
#
# Vista dall'alto (2026-11-04, richiesta utente — distinguerla dalla capanna del vestiario): pianta rettangolare, muri di
# argilla CRUDA spalmata a mano su un intreccio di rami (ocra spento a chiazze, mai color terracotta: sembrerebbero mattoni),
# con un tratto di intonaco caduto che lascia vedere i rami. Tetto di paglia a due falde con la trave di colmo. Porta sul lato
# lungo `direction`; accanto alla porta una fila di tre vasi: sono già cotti, l'unica macchia rosso-bruna del disegno. Dietro,
# in un angolo, la piccola fossa di cottura.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con la porta a sud (+y);
# `direction` ruota tutto come la porta.

const TYPE := "potter_hut"

const WALL := Color(0.66, 0.56, 0.40, 1.0)
const WALL_LIGHT := Color(0.74, 0.64, 0.47, 1.0)
const WALL_DARK := Color(0.57, 0.47, 0.33, 1.0)
const WATTLE := Color(0.36, 0.25, 0.14, 1.0)
const THATCH := Color(0.74, 0.64, 0.32, 1.0)
const THATCH_SHADE := Color(0.60, 0.51, 0.25, 1.0)
const THATCH_LINE := Color(0.48, 0.40, 0.20, 1.0)
const RIDGE := Color(0.36, 0.25, 0.14, 1.0)
const DOOR := Color(0.16, 0.13, 0.11, 1.0)
const PIT_STONE := Color(0.56, 0.55, 0.52, 1.0)
const PIT_ASH := Color(0.27, 0.24, 0.22, 1.0)
const EMBER := Color(0.88, 0.45, 0.15, 1.0)
const POT := Color(0.68, 0.35, 0.21, 1.0)
const POT_MOUTH := Color(0.28, 0.15, 0.10, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.4
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Muri: rettangolo esterno. Tetto: rientrato di WALL_THICKNESS, la trave di colmo a metà profondità.
const WALL_LEFT: float = -4.6
const WALL_RIGHT: float = 2.4
const WALL_TOP: float = -4.0
const WALL_BOTTOM: float = 1.2
const WALL_THICKNESS: float = 0.8
const THATCH_LINE_STEP: float = 0.9
const THATCH_LINE_WIDTH: float = 0.16
const RIDGE_WIDTH: float = 0.4
# Chiazze dell'intonaco, sui muri: x, y, lato; z pari = chiara, dispari = scura.
const WALL_PATCHES: Array[Vector3] = [
	Vector3(-4.4, -3.1, 0.6), Vector3(-4.4, -0.7, 0.6), Vector3(-2.9, -3.9, 0.6), Vector3(0.3, -3.9, 0.6),
	Vector3(1.7, -2.4, 0.6), Vector3(1.7, 0.1, 0.6), Vector3(0.6, 0.5, 0.6),
]
# Intonaco caduto: tratto del muro di fondo dove si vedono i rami.
const WATTLE_LEFT: float = -1.4
const WATTLE_RIGHT: float = -0.3
const WATTLE_WIDTH: float = 0.16
# Porta sul lato lungo, a sinistra della fila di vasi.
const DOOR_CENTER_X: float = -1.6
const DOOR_HALF_WIDTH: float = 0.95
# Fila di vasi accanto alla porta: x, y, raggio.
const POTS: Array[Vector3] = [Vector3(0.7, 2.8, 1.0), Vector3(2.4, 2.9, 0.8), Vector3(3.8, 3.0, 0.6)]
const POT_MOUTH_RATIO: float = 0.5
# Fossa di cottura, dietro la capanna, in un angolo.
const PIT_CENTER := Vector2(3.7, -2.7)
const PIT_RADIUS: float = 1.0
const PIT_STONE_COUNT: int = 6
const PIT_STONE_RADIUS: float = 0.3


# `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima semitrasparente.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, smoking: bool = false
) -> void:
	var forward := TentShapes.direction_vector(direction)
	var side := Vector2(-forward.y, forward.x)
	var to_canvas := func(local: Vector2) -> Vector2:
		return center + (side * local.x + forward * local.y) * scale
	var tint := func(color: Color, invalid_color: Color) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)

	# Fossa di cottura: cenere, brace, cerchio di pietre.
	var pit: Vector2 = to_canvas.call(PIT_CENTER)
	canvas.draw_circle(pit, PIT_RADIUS * scale, tint.call(PIT_ASH, INVALID_OUTLINE))
	canvas.draw_circle(pit, PIT_RADIUS * 0.5 * scale, tint.call(EMBER, INVALID_FILL))
	for i in range(PIT_STONE_COUNT):
		var angle := TAU * float(i) / float(PIT_STONE_COUNT)
		canvas.draw_circle(
			to_canvas.call(PIT_CENTER + Vector2(cos(angle), sin(angle)) * PIT_RADIUS),
			PIT_STONE_RADIUS * scale, tint.call(PIT_STONE, INVALID_FILL)
		)

	# Muri d'argilla cruda: fondo, chiazze a mano, tratto caduto con i rami.
	var walls := _rect(to_canvas, WALL_LEFT, WALL_TOP, WALL_RIGHT, WALL_BOTTOM)
	canvas.draw_colored_polygon(walls, tint.call(WALL, INVALID_FILL))
	for i in range(WALL_PATCHES.size()):
		var patch: Vector3 = WALL_PATCHES[i]
		canvas.draw_colored_polygon(
			_rect(to_canvas, patch.x, patch.y, patch.x + patch.z, patch.y + patch.z),
			tint.call(WALL_LIGHT if i % 2 == 0 else WALL_DARK, INVALID_FILL)
		)
	var wattle_x := WATTLE_LEFT
	while wattle_x <= WATTLE_RIGHT:
		canvas.draw_line(
			to_canvas.call(Vector2(wattle_x, WALL_TOP)), to_canvas.call(Vector2(wattle_x, WALL_TOP + WALL_THICKNESS)),
			tint.call(WATTLE, INVALID_OUTLINE), WATTLE_WIDTH * scale, true
		)
		wattle_x += 0.35

	# Tetto a due falde: la falda verso la porta in ombra, la paglia di traverso alla trave di colmo.
	var roof_left := WALL_LEFT + WALL_THICKNESS
	var roof_right := WALL_RIGHT - WALL_THICKNESS
	var roof_top := WALL_TOP + WALL_THICKNESS
	var roof_bottom := WALL_BOTTOM - WALL_THICKNESS
	var ridge_y := (roof_top + roof_bottom) / 2.0
	canvas.draw_colored_polygon(_rect(to_canvas, roof_left, roof_top, roof_right, ridge_y), tint.call(THATCH, INVALID_FILL))
	canvas.draw_colored_polygon(
		_rect(to_canvas, roof_left, ridge_y, roof_right, roof_bottom), tint.call(THATCH_SHADE, INVALID_FILL.darkened(0.2))
	)
	var thatch_x := roof_left + THATCH_LINE_STEP
	while thatch_x < roof_right:
		canvas.draw_line(
			to_canvas.call(Vector2(thatch_x, roof_top)), to_canvas.call(Vector2(thatch_x, roof_bottom)),
			tint.call(THATCH_LINE, INVALID_OUTLINE), THATCH_LINE_WIDTH * scale, true
		)
		thatch_x += THATCH_LINE_STEP
	canvas.draw_line(
		to_canvas.call(Vector2(roof_left, ridge_y)), to_canvas.call(Vector2(roof_right, ridge_y)),
		tint.call(RIDGE, INVALID_OUTLINE), RIDGE_WIDTH * scale, true
	)

	# Contorni e porta, che taglia il muro sul lato lungo.
	var wall_outline := walls.duplicate()
	wall_outline.append(walls[0])
	canvas.draw_polyline(wall_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * scale, true)
	var roof_outline := _rect(to_canvas, roof_left, roof_top, roof_right, roof_bottom)
	roof_outline.append(roof_outline[0])
	canvas.draw_polyline(roof_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)
	canvas.draw_colored_polygon(
		_rect(to_canvas, DOOR_CENTER_X - DOOR_HALF_WIDTH, WALL_BOTTOM - WALL_THICKNESS, DOOR_CENTER_X + DOOR_HALF_WIDTH, WALL_BOTTOM + 0.2),
		tint.call(DOOR, INVALID_OUTLINE)
	)

	# Fila di vasi già cotti accanto alla porta.
	for pot in POTS:
		var pot_center: Vector2 = to_canvas.call(Vector2(pot.x, pot.y))
		canvas.draw_circle(pot_center, pot.z * scale, tint.call(POT, INVALID_FILL))
		canvas.draw_arc(pot_center, pot.z * scale, 0.0, TAU, 16, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)
		canvas.draw_circle(pot_center, pot.z * POT_MOUTH_RATIO * scale, tint.call(POT_MOUTH, INVALID_OUTLINE))

	# Fumo dalla fossa di cottura mentre cuoce (2026-11-07, richiesta utente): stessi sbuffi e colore dell'affumicatoio, in
	# coordinate dello schermo, verso l'alto.
	if smoking:
		var smoke := PlaceholderBuildingShapes.SMOKE
		for puff in SmokehouseShape.SMOKE_PUFFS:
			canvas.draw_circle(pit + Vector2(puff.x, puff.y) * scale, puff.z * scale, Color(smoke.r, smoke.g, smoke.b, smoke.a * alpha))


static func _rect(to_canvas: Callable, left: float, top: float, right: float, bottom: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in [Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]:
		result.append(to_canvas.call(point))
	return result
