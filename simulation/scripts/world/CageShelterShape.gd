class_name CageShelterShape
extends RefCounted

# Tettoia delle gabbie (cage_shelter, 2026-11-12, richiesta utente — addomesticazione per cattura viva, primo edificio): 1x1.
# Sul retro della cella una tettoia QUADRATA di frasche (stesso stile rudimentale della tettoia dell'acqua, WaterShelterShape)
# con sotto 20 gabbiette di bastoni legate con la corda, in 4 file da 5; davanti, nella stessa cella, una striscia di terra
# battuta da cui si entra. Lo spiazzo segue `direction`, come la porta degli altri edifici.
# Per ora le gabbie sono sempre vuote: gli animali arriveranno con la cattura viva.
# Un solo disegno per mappa (MicroCellRenderer), anteprima (BuildingGhost) e icona (CageShelterIcon).
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10). Coordinate locali con lo spiazzo a sud: x da −5 (ovest) a +5
# (est), y da −5 (retro) a +5 (spiazzo); `direction` ruota tutto. Le gabbie restano allineate al tetto.

const TYPE := "cage_shelter"
const CAPACITY: int = 20

const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const POST := Color(0.36, 0.24, 0.12, 1.0)
const BRANCH := Color(0.42, 0.30, 0.16, 0.95)
const THATCH := Color(0.62, 0.55, 0.30, 0.30)
const FROND := Color(0.42, 0.48, 0.22, 0.75)
const ROOF_SHADOW := Color(0.0, 0.0, 0.0, 0.16)
const DIRT := Color(0.60, 0.50, 0.36, 0.85)
const DIRT_EDGE := Color(0.48, 0.39, 0.27, 0.6)
const CAGE_FLOOR := Color(0.50, 0.42, 0.28, 0.55)
const CAGE_BAR := Color(0.55, 0.40, 0.20, 1.0)
const ROPE := Color(0.78, 0.70, 0.50, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Tetto: quattro angoli un po' storti (retro-ovest, retro-est, davanti-est, davanti-ovest).
const ROOF_CORNERS: Array[Vector2] = [Vector2(-4.2, -4.3), Vector2(4.1, -4.2), Vector2(4.2, 2.0), Vector2(-4.1, 1.9)]
# Rami di traverso sul tetto: (x0, y0, x1, y1).
const BRANCHES: Array[Vector4] = [
	Vector4(-4.5, -3.4, 4.4, -3.6), Vector4(-4.4, -1.8, 4.6, -1.6), Vector4(-4.6, -0.1, 4.3, -0.3), Vector4(-4.3, 1.3, 4.5, 1.5),
]
# Ciuffi di frasche: centro e lunghezza dei tratti.
const FRONDS: Array[Vector3] = [
	Vector3(-2.8, -2.7, 0.9), Vector3(1.6, -2.9, 0.8), Vector3(-0.5, -1.0, 1.0), Vector3(2.9, -0.9, 0.8),
	Vector3(-3.0, 0.6, 0.8), Vector3(0.9, 0.7, 0.9),
]
# Spiazzo: contorno irregolare davanti al tetto.
const YARD_POINTS: Array[Vector2] = [
	Vector2(-4.0, 1.9), Vector2(4.0, 1.9), Vector2(4.4, 3.2), Vector2(3.6, 4.5), Vector2(1.2, 4.7), Vector2(-1.4, 4.5),
	Vector2(-3.7, 4.6), Vector2(-4.4, 3.3),
]
const POST_RADIUS: float = 0.42
# Gabbie: 4 file (y) da 5 (x), lato CAGE_SIZE.
const CAGE_COLUMNS: Array[float] = [-3.0, -1.5, 0.0, 1.5, 3.0]
const CAGE_ROWS: Array[float] = [-3.3, -1.85, -0.4, 1.05]
const CAGE_SIZE: float = 1.25


# `direction` = lato dello spiazzo; `invalid` = anteprima su una posizione non edificabile; `alpha` per l'anteprima;
# `scale` per l'icona.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0
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

	# Spiazzo di terra battuta davanti.
	var yard: PackedVector2Array = poly.call(YARD_POINTS)
	canvas.draw_colored_polygon(yard, tint.call(DIRT))
	var yard_outline := yard.duplicate()
	yard_outline.append(yard[0])
	canvas.draw_polyline(yard_outline, tint.call(DIRT_EDGE, INVALID_OUTLINE), 0.2 * scale, true)

	# Ombra sotto il tetto, poi le gabbie: fondo, bordo di bastoni, due sbarre e un nodo di corda all'angolo.
	var roof: PackedVector2Array = poly.call(ROOF_CORNERS)
	canvas.draw_colored_polygon(roof, tint.call(ROOF_SHADOW))
	var half := CAGE_SIZE * 0.5
	for y in CAGE_ROWS:
		for x in CAGE_COLUMNS:
			var cage: PackedVector2Array = poly.call([
				Vector2(x - half, y - half), Vector2(x + half, y - half), Vector2(x + half, y + half), Vector2(x - half, y + half),
			] as Array[Vector2])
			canvas.draw_colored_polygon(cage, tint.call(CAGE_FLOOR))
			var cage_outline := cage.duplicate()
			cage_outline.append(cage[0])
			canvas.draw_polyline(cage_outline, tint.call(CAGE_BAR, INVALID_OUTLINE), 0.18 * scale, true)
			for k in [-1.0, 1.0]:
				var bar_x: float = x + k * half / 3.0
				canvas.draw_line(p.call(bar_x, y - half), p.call(bar_x, y + half), tint.call(CAGE_BAR, INVALID_OUTLINE), 0.12 * scale, true)
			canvas.draw_circle(p.call(x - half, y - half), 0.16 * scale, tint.call(ROPE))

	# Tetto rudimentale: falda trasparente, travi sui lati, rami di traverso, ciuffi di frasche, bordo.
	canvas.draw_colored_polygon(roof, tint.call(THATCH))
	canvas.draw_line(p.call(-4.2, -4.6), p.call(-4.1, 2.3), tint.call(BRANCH, INVALID_OUTLINE), 0.4 * scale, true)
	canvas.draw_line(p.call(4.1, -4.5), p.call(4.2, 2.4), tint.call(BRANCH, INVALID_OUTLINE), 0.4 * scale, true)
	for branch in BRANCHES:
		canvas.draw_line(p.call(branch.x, branch.y), p.call(branch.z, branch.w), tint.call(BRANCH, INVALID_OUTLINE), 0.3 * scale, true)
	for frond in FRONDS:
		for k in range(3):
			var tilt := (float(k) - 1.0) * 0.35
			var stroke := Vector2(cos(tilt), sin(tilt)) * frond.z * 0.5
			canvas.draw_line(p.call(frond.x - stroke.x, frond.y - stroke.y), p.call(frond.x + stroke.x, frond.y + stroke.y), tint.call(FROND), 0.22 * scale, true)
	var roof_outline := roof.duplicate()
	roof_outline.append(roof[0])
	canvas.draw_polyline(roof_outline, tint.call(OUTLINE, INVALID_OUTLINE), 0.25 * scale, true)
	# Pali grezzi agli angoli.
	for corner in ROOF_CORNERS:
		canvas.draw_circle(p.call(corner.x, corner.y), POST_RADIUS * scale, tint.call(POST, INVALID_OUTLINE))
