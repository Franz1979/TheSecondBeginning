class_name WaterShelterShape
extends RefCounted

# Tettoia dell'acqua (water_shelter, 2026-11-06, richiesta utente — Vasellame, giare: passo 1, solo l'edificio): 1x1, senza
# porta. Ridisegnata il 2026-11-07 (richiesta utente: la tettoia rotonda era troppo raffinata per frasche e rametti):
# una tettoia QUADRATA rudimentale sul retro della cella e davanti, nella stessa cella, un piccolo spiazzo di terra battuta
# (dove ci si ferma a bere e a posare le giare: WaterJarService.shelter_point). Lo spiazzo segue `direction`, come la porta
# degli altri edifici, quindi la tettoia torna girabile.
# Vista dall'alto: ombra sotto il tetto, le giare (fino a CAPACITY, in file 4 + 3 + 3) una per ogni valore di `jar_waters`
# (l'acqua di ciascuna, WaterJarService.shelter_jar_waters; con acqua ClayJarIcon.draw_full_into, vuota
# ClayJarIcon.draw_into), poi il tetto un po' storto e semitrasparente: due travi sui lati, rami di traverso, ciuffi di
# frasche, quattro pali grezzi agli angoli. Sullo spiazzo un paio di sassi e la macchia scura dell'acqua versata.
# Un solo disegno per mappa (MicroCellRenderer), anteprima (BuildingGhost, vuota) e icona (WaterShelterIcon, piena).
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10). Coordinate locali con lo spiazzo a sud: x da −5 (ovest) a +5
# (est), y da −5 (retro) a +5 (spiazzo); `direction` ruota tutto (asse come WoodshedShape). Le giare restano dritte.

const TYPE := "water_shelter"
const CAPACITY: int = 10

const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const POST := Color(0.36, 0.24, 0.12, 1.0)
const BRANCH := Color(0.42, 0.30, 0.16, 0.95)
const THATCH := Color(0.62, 0.55, 0.30, 0.34)
const FROND := Color(0.42, 0.48, 0.22, 0.75)
const ROOF_SHADOW := Color(0.0, 0.0, 0.0, 0.14)
const DIRT := Color(0.60, 0.50, 0.36, 0.85)
const DIRT_EDGE := Color(0.48, 0.39, 0.27, 0.6)
const WET := Color(0.30, 0.26, 0.20, 0.55)
const STONE := Color(0.55, 0.53, 0.50, 1.0)
const STONE_EDGE := Color(0.35, 0.33, 0.31, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Tetto: quattro angoli un po' storti (retro-ovest, retro-est, davanti-est, davanti-ovest).
# Ridotto il 2026-11-07 (richiesta utente): un bordino di terreno libero ai lati (~1,6) e dietro (~1,4).
const ROOF_CORNERS: Array[Vector2] = [Vector2(-3.4, -3.6), Vector2(3.3, -3.5), Vector2(3.4, 1.2), Vector2(-3.3, 1.1)]
# Rami di traverso sul tetto: (x0, y0, x1, y1).
const BRANCHES: Array[Vector4] = [
	Vector4(-3.8, -2.9, 3.7, -3.1), Vector4(-3.7, -1.7, 3.9, -1.5), Vector4(-3.9, -0.5, 3.6, -0.7), Vector4(-3.6, 0.6, 3.8, 0.8),
]
# Ciuffi di frasche: centro e lunghezza dei tratti.
const FRONDS: Array[Vector3] = [
	Vector3(-2.1, -2.4, 0.9), Vector3(1.3, -2.6, 0.8), Vector3(-0.4, -1.1, 1.0), Vector3(2.3, -0.9, 0.8),
	Vector3(-2.4, 0.1, 0.8), Vector3(0.8, 0.2, 0.9),
]
# Spiazzo: contorno irregolare davanti al tetto.
const YARD_POINTS: Array[Vector2] = [
	Vector2(-3.6, 1.0), Vector2(3.5, 1.0), Vector2(4.2, 2.4), Vector2(3.9, 4.1), Vector2(2.2, 4.6), Vector2(-0.4, 4.4),
	Vector2(-2.9, 4.6), Vector2(-4.1, 3.8), Vector2(-4.2, 2.3),
]
const WET_CENTER := Vector2(1.6, 3.0)
const WET_RADIUS := Vector2(1.5, 0.9)
# Sassi sullo spiazzo: x, y, raggio.
const STONES: Array[Vector3] = [Vector3(-2.9, 3.4, 0.55), Vector3(3.5, 3.7, 0.45)]
const POST_RADIUS: float = 0.42
# Giare: righe (y) e posizioni (x) nelle file 4 + 3 + 3.
const JAR_ROWS: Array = [[-2.6, [-2.4, -0.8, 0.8, 2.4]], [-1.2, [-1.6, 0.0, 1.6]], [0.2, [-1.6, 0.0, 1.6]]]
const JAR_SIZE: float = 1.3


# `direction` = lato dello spiazzo; `jar_waters` = acqua di ogni giara sotto la tettoia; `invalid` = anteprima su una
# posizione non edificabile; `alpha` per l'anteprima; `scale` per l'icona.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, jar_waters: Array = [], invalid: bool = false,
	alpha: float = 1.0, scale: float = 1.0
) -> void:
	var forward := TentShapes.direction_vector(direction)
	var side := Vector2(forward.y, -forward.x)
	var p := func(x: float, y: float) -> Vector2:
		return center + (side * x + forward * y) * scale
	var poly := func(points: Array[Vector2]) -> PackedVector2Array:
		var result := PackedVector2Array()
		for point in points:
			result.append(p.call(point.x, point.y))
		return result
	var tint := func(color: Color, invalid_color: Color = INVALID_FILL) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)

	# Spiazzo di terra battuta, con la macchia dell'acqua versata e due sassi.
	var yard: PackedVector2Array = poly.call(YARD_POINTS)
	canvas.draw_colored_polygon(yard, tint.call(DIRT))
	var yard_outline := yard.duplicate()
	yard_outline.append(yard[0])
	canvas.draw_polyline(yard_outline, tint.call(DIRT_EDGE, INVALID_OUTLINE), 0.2 * scale, true)
	var wet := PackedVector2Array()
	for i in range(14):
		var angle := TAU * float(i) / 14.0
		wet.append(p.call(WET_CENTER.x + cos(angle) * WET_RADIUS.x, WET_CENTER.y + sin(angle) * WET_RADIUS.y))
	canvas.draw_colored_polygon(wet, tint.call(WET))
	for stone in STONES:
		var at: Vector2 = p.call(stone.x, stone.y)
		canvas.draw_circle(at, stone.z * scale, tint.call(STONE_EDGE, INVALID_OUTLINE))
		canvas.draw_circle(at, stone.z * 0.75 * scale, tint.call(STONE))

	# Ombra sotto il tetto, poi le giare.
	var roof: PackedVector2Array = poly.call(ROOF_CORNERS)
	canvas.draw_colored_polygon(roof, tint.call(ROOF_SHADOW))
	var shown := mini(jar_waters.size(), CAPACITY)
	var jar_side := JAR_SIZE * scale
	var index := 0
	for row in JAR_ROWS:
		for x in row[1]:
			if index >= shown:
				break
			var jar_origin: Vector2 = p.call(float(x), float(row[0])) - Vector2(jar_side, jar_side) * 0.5
			if int(jar_waters[index]) > 0:
				ClayJarIcon.draw_full_into(canvas, jar_origin, Vector2(jar_side, jar_side))
			else:
				ClayJarIcon.draw_into(canvas, jar_origin, Vector2(jar_side, jar_side))
			index += 1

	# Tetto rudimentale: falda trasparente, travi sui lati, rami di traverso, ciuffi di frasche, bordo.
	canvas.draw_colored_polygon(roof, tint.call(THATCH))
	canvas.draw_line(p.call(-3.4, -3.9), p.call(-3.3, 1.4), tint.call(BRANCH, INVALID_OUTLINE), 0.4 * scale, true)
	canvas.draw_line(p.call(3.3, -3.8), p.call(3.4, 1.5), tint.call(BRANCH, INVALID_OUTLINE), 0.4 * scale, true)
	for branch in BRANCHES:
		canvas.draw_line(p.call(branch.x, branch.y), p.call(branch.z, branch.w), tint.call(BRANCH, INVALID_OUTLINE), 0.3 * scale, true)
	for frond in FRONDS:
		for k in range(3):
			var tilt := (float(k) - 1.0) * 0.35
			var half := Vector2(cos(tilt), sin(tilt)) * frond.z * 0.5
			canvas.draw_line(p.call(frond.x - half.x, frond.y - half.y), p.call(frond.x + half.x, frond.y + half.y), tint.call(FROND), 0.22 * scale, true)
	var roof_outline := roof.duplicate()
	roof_outline.append(roof[0])
	canvas.draw_polyline(roof_outline, tint.call(OUTLINE, INVALID_OUTLINE), 0.25 * scale, true)
	# Pali grezzi agli angoli.
	for corner in ROOF_CORNERS:
		canvas.draw_circle(p.call(corner.x, corner.y), POST_RADIUS * scale, tint.call(POST, INVALID_OUTLINE))
