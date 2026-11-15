class_name HaystackShape
extends RefCounted

# Pagliaio (haystack, 2026-11-15, richiesta utente — 1x1, senza porta): quattro trespoli visti dall'alto, in due file da
# due; ognuno una traversa con due gambe incrociate a ogni capo. Un trespolo si disegna coperto di paglia ogni
# FULL_STEP di paglia nel pagliaio (a scalini, non preciso: 200 = l'80% dei 250 di un posto), fino a tutti e quattro.
# Un solo disegno per mappa (MicroCellRenderer), anteprima (BuildingGhost, vuota) e icona (HaystackIcon, piena).
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5).

const TYPE := "haystack"
const RACK_COUNT: int = 4
const FULL_STEP: int = 200

const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const RAIL := Color(0.52, 0.37, 0.20, 1.0)
const LEG := Color(0.38, 0.26, 0.13, 1.0)
const STRAW := Color(0.86, 0.74, 0.40, 1.0)
const STRAW_DARK := Color(0.66, 0.54, 0.26, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Centri dei trespoli (si riempiono in quest'ordine), mezza lunghezza della traversa, apertura delle gambe.
const RACK_CENTERS: Array[Vector2] = [Vector2(-2.4, -2.3), Vector2(2.4, -2.3), Vector2(-2.4, 2.3), Vector2(2.4, 2.3)]
const RAIL_HALF_LENGTH: float = 1.9
const LEG_SPREAD: float = 0.9
const RAIL_WIDTH: float = 0.35
const LEG_WIDTH: float = 0.28
const STRAW_HALF_SIZE := Vector2(2.2, 1.35)


# Trespoli coperti di paglia per il contenuto del pagliaio (tutte le risorse dentro: paglia, poi fieno).
static func racks_full(building: Building) -> int:
	if building == null:
		return 0
	var total := 0
	for resource_name in building.stored_resources.keys():
		total += int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0))
	return clampi(total / FULL_STEP, 0, RACK_COUNT)


# `full` = trespoli coperti; `invalid` = anteprima su una posizione non edificabile; `alpha` per l'anteprima; `scale`
# per l'icona.
static func draw(canvas: CanvasItem, center: Vector2, full: int = 0, invalid: bool = false, alpha: float = 1.0, scale: float = 1.0) -> void:
	var tint := func(color: Color, invalid_color: Color = INVALID_FILL) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	var shown := clampi(full, 0, RACK_COUNT)
	for i in range(RACK_COUNT):
		var c: Vector2 = center + RACK_CENTERS[i] * scale
		# Gambe incrociate ai due capi, poi la traversa.
		for end_sign in [-1.0, 1.0]:
			var foot := c + Vector2(end_sign * RAIL_HALF_LENGTH, 0.0) * scale
			var a := foot + Vector2(-0.35, -LEG_SPREAD) * scale
			var b := foot + Vector2(0.35, LEG_SPREAD) * scale
			var a2 := foot + Vector2(0.35, -LEG_SPREAD) * scale
			var b2 := foot + Vector2(-0.35, LEG_SPREAD) * scale
			canvas.draw_line(a, b, tint.call(LEG, INVALID_OUTLINE), LEG_WIDTH * scale, true)
			canvas.draw_line(a2, b2, tint.call(LEG, INVALID_OUTLINE), LEG_WIDTH * scale, true)
		var left := c + Vector2(-RAIL_HALF_LENGTH, 0.0) * scale
		var right := c + Vector2(RAIL_HALF_LENGTH, 0.0) * scale
		canvas.draw_line(left, right, tint.call(OUTLINE, INVALID_OUTLINE), (RAIL_WIDTH + 0.2) * scale, true)
		canvas.draw_line(left, right, tint.call(RAIL), RAIL_WIDTH * scale, true)
		if i < shown:
			_draw_straw(canvas, c, scale, tint)


# Paglia stesa sopra il trespolo: un cumulo ovale con qualche stelo più scuro di traverso.
static func _draw_straw(canvas: CanvasItem, c: Vector2, scale: float, tint: Callable) -> void:
	var points := PackedVector2Array()
	for k in range(16):
		var angle := TAU * float(k) / 16.0
		var wobble := 1.0 + 0.08 * sin(angle * 3.0 + c.x)
		points.append(c + Vector2(cos(angle) * STRAW_HALF_SIZE.x, sin(angle) * STRAW_HALF_SIZE.y) * wobble * scale)
	canvas.draw_colored_polygon(points, tint.call(STRAW))
	for k in range(5):
		var x := -1.6 + float(k) * 0.8
		canvas.draw_line(c + Vector2(x - 0.25, -1.0) * scale, c + Vector2(x + 0.25, 1.0) * scale,
			tint.call(STRAW_DARK), 0.18 * scale, true)
