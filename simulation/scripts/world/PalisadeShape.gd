class_name PalisadeShape
extends RefCounted

# Palizzata (palisade, 2026-10-23, richiesta utente — evoluzione del vallo di terra), a pezzi uniti come il vallo. Vista
# dall'alto: un argine di terra più basso e stretto del vallo (stesso disegno comune di LinearShape, colori di terra) e
# sopra una fila di pali lungo ogni braccio, inclinati di lato: ogni palo è un trattino di legno che parte dalla cresta e
# sporge, con la punta chiara (legno appuntito). I pali si inclinano verso `outward`, la direzione dell'edificio
# (Building.rotation, scelta col tasto di rotazione al piazzamento o al miglioramento dal vallo — side_vector): su un braccio
# parallelo a quella direzione si usa la direzione ruotata di 90° in senso orario (sud → ovest, est → sud…), così ognuna
# delle quattro direzioni dà un lato a ogni tratto. `outward` nullo = alternati a zig-zag. Condiviso da mappa, anteprima e icona (PalisadeIcon) tramite LinearShapes. Si collega ai
# pezzi di vallo (BuildingRules.linear_link_group "defensive_wall").

const BANK_RADIUS: float = 2.0
const BANK_CREST_WIDTH: float = 0.5
const BANK_CREST_DOT_RADIUS: float = 0.6
const EARTH := Color(0.47, 0.36, 0.24, 1.0)
const EARTH_DARK := Color(0.33, 0.25, 0.16, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)
# Striscia di fondo chiaro sotto l'argine, come per il vallo.
const GROUND_HALF_WIDTH: float = 3.6

# Pali: posizioni lungo un braccio (dal centro verso il bordo, in unità di disegno), lunghezza del trattino visto dall'alto,
# spessore, contorno e punta.
const STAKE_POSITIONS: Array[float] = [1.25, 2.5, 3.75, 5.0]
const STAKE_LENGTH: float = 2.2
const STAKE_WIDTH: float = 0.45
const STAKE_OUTLINE_WIDTH: float = 0.7
const STAKE_TIP_RADIUS: float = 0.28
const WOOD := Color(0.52, 0.37, 0.21, 1.0)
const WOOD_DARK := Color(0.28, 0.19, 0.10, 1.0)
const TIP := Color(0.86, 0.74, 0.55, 1.0)

static var STYLE := LinearShapeStyle.new(
	BANK_RADIUS, EARTH, EARTH_DARK, BANK_CREST_WIDTH, BANK_CREST_DOT_RADIUS, INVALID_TINT, GROUND_HALF_WIDTH
)


static func draw(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, clip_mask: int = 0, outward: Vector2 = Vector2.ZERO
) -> void:
	LinearShape.draw(canvas, center, neighbor_mask, STYLE, invalid, alpha, scale, clip_mask)
	_draw_stakes(canvas, center, neighbor_mask, outward, invalid, alpha, scale)


static func draw_ground(canvas: CanvasItem, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, color: Color) -> void:
	LinearShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, STYLE, color)


# Fila di pali: su ogni braccio presente, a STAKE_POSITIONS dal centro, più uno al centro; pezzo isolato: tre pali attorno
# al centro. Ogni palo sporge perpendicolare al braccio, dalla parte di `outward` (zig-zag se nullo).
static func _draw_stakes(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, outward: Vector2, invalid: bool, alpha: float, scale: float
) -> void:
	var tint := func(color: Color) -> Color:
		var base: Color = INVALID_TINT if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	var stakes: Array = []  # [base (Vector2, unità), direzione di inclinazione (Vector2)]
	var index := 0
	var first_lean := Vector2.ZERO
	# Angolo (2026-10-27, richiesta utente): l'argine è un tratto diagonale tra i punti medi dei due lati (LinearShape), quindi
	# i pali seguono quella diagonale, dalla stessa parte, invece dei due bracci a L.
	if LinearShape.is_corner_mask(neighbor_mask):
		var ends := _corner_ends(neighbor_mask)
		var lean := _lean(_corner_across(neighbor_mask), outward, 0)
		var count := roundi(ends[0].distance_to(ends[1]) / STAKE_POSITIONS[0])
		for i in range(count + 1):
			if outward == Vector2.ZERO:
				lean = _lean(_corner_across(neighbor_mask), outward, i)
			stakes.append([ends[0].lerp(ends[1], float(i) / float(count)), lean])
	for side in range(4):
		if LinearShape.is_corner_mask(neighbor_mask):
			break
		if (neighbor_mask & (1 << side)) == 0:
			continue
		var direction: Vector2 = LinearShape.SIDE_DIRECTIONS[side]
		var across := Vector2(-direction.y, direction.x)
		for distance in STAKE_POSITIONS:
			var lean := _lean(across, outward, index)
			if first_lean == Vector2.ZERO:
				first_lean = lean
			stakes.append([direction * distance, lean])
			index += 1
	if stakes.is_empty():
		for i in range(3):
			var direction := Vector2.RIGHT.rotated(TAU * float(i) / 3.0 + PI / 2.0)
			stakes.append([direction * 1.2, direction if outward == Vector2.ZERO else outward.normalized()])
	elif first_lean != Vector2.ZERO:
		stakes.append([Vector2.ZERO, first_lean])
	for stake in stakes:
		var base: Vector2 = center + (stake[0] as Vector2) * scale
		var tip: Vector2 = base + (stake[1] as Vector2) * STAKE_LENGTH * scale
		canvas.draw_line(base, tip, tint.call(WOOD_DARK), STAKE_OUTLINE_WIDTH * scale, true)
		canvas.draw_line(base, tip, tint.call(WOOD), STAKE_WIDTH * scale, true)
		canvas.draw_circle(tip, STAKE_TIP_RADIUS * scale, tint.call(TIP))


# Lato dei pali per ogni braccio presente (pezzo isolato: `outward` stesso): due direzioni con lo stesso risultato si
# disegnano uguali (LinearShapes.side_signature).
static func lean_signature(neighbor_mask: int, outward: Vector2) -> Array[Vector2]:
	var leans: Array[Vector2] = []
	if LinearShape.is_corner_mask(neighbor_mask):
		leans.append(_lean(_corner_across(neighbor_mask), outward, 0))
		return leans
	for side in range(4):
		if (neighbor_mask & (1 << side)) == 0:
			continue
		var direction: Vector2 = LinearShape.SIDE_DIRECTIONS[side]
		leans.append(_lean(Vector2(-direction.y, direction.x), outward, 0))
	if leans.is_empty():
		leans.append(outward)
	return leans


# Pezzo ad angolo: i punti medi dei due lati collegati (estremi del tratto diagonale, in unità di disegno).
static func _corner_ends(neighbor_mask: int) -> Array[Vector2]:
	var ends: Array[Vector2] = []
	for side in range(4):
		if (neighbor_mask & (1 << side)) != 0:
			ends.append(LinearShape.SIDE_DIRECTIONS[side] * LinearShape.HALF_CELL)
	return ends


# Pezzo ad angolo: perpendicolare al tratto diagonale.
static func _corner_across(neighbor_mask: int) -> Vector2:
	var ends := _corner_ends(neighbor_mask)
	var direction := (ends[1] - ends[0]).normalized()
	return Vector2(-direction.y, direction.x)


# Direzione verso cui sporgono i pali per la direzione dell'edificio `direction` (Building.rotation).
static func side_vector(direction: GameTypes.Direction) -> Vector2:
	return TentShapes.direction_vector(direction)


# Verso del palo: il lato di `across` che guarda verso `outward`; braccio parallelo a `outward`: verso `outward` ruotato di
# 90° in senso orario; senza `outward`, alternato (zig-zag).
static func _lean(across: Vector2, outward: Vector2, index: int) -> Vector2:
	if outward == Vector2.ZERO:
		return across if index % 2 == 0 else -across
	var side := across.dot(outward)
	if absf(side) < 0.001:
		side = across.dot(Vector2(-outward.y, outward.x))
	return across if side > 0.0 else -across
