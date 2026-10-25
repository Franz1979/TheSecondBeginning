class_name HealerHutShape
extends RefCounted

# Capanna del guaritore (healer_hut, 2026-10-25, richiesta utente — laboratorio dei rimedi): disegno di mappa
# (MicroCellRenderer._draw_buildings) e anteprima di piazzamento (BuildingGhost), nello stile di ClothingHutShape (colori
# smorzati, contorni marroni sottili, una metà in ombra). L'icona della barra è la vista di fronte (HealerHutIcon).
#
# Vista dall'alto (2026-10-25, richiesta utente — distinguerla dalla capanna del vestiario): tettoia semiaperta, un
# arco di frasche verde-brune a ferro di cavallo aperto sul lato `direction`, con i fasci di frasche di traverso sulla
# corona. Dentro si vede il pavimento di terra battuta: contro la parete di fondo il giaciglio di paglia con una pelle
# per il malato, verso l'apertura il focolare cerchiato di pietre con la pentola degli infusi (il fumo esce da lì).
# Davanti una ciotola di pietra con le erbe pestate; sul fianco una rastrelliera di due pali con i mazzetti di erbe
# appesi ad asciugare (verdi, qualcuno fiorito di giallo o viola).
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con la porta a sud (+y);
# `direction` ruota tutto come la porta.

const TYPE := "healer_hut"

const THATCH := Color(0.42, 0.45, 0.30, 1.0)
const THATCH_SHADE := Color(0.34, 0.37, 0.25, 1.0)
const BUNDLE := Color(0.30, 0.33, 0.21, 1.0)
const BARK := Color(0.40, 0.30, 0.20, 1.0)
const DOOR := Color(0.16, 0.13, 0.11, 1.0)
const FLOOR := Color(0.47, 0.37, 0.26, 1.0)
const STRAW := Color(0.78, 0.68, 0.40, 1.0)
const STRAW_DARK := Color(0.62, 0.52, 0.30, 1.0)
const BED_HIDE := Color(0.72, 0.64, 0.52, 1.0)
const HEARTH_STONE := Color(0.56, 0.55, 0.52, 1.0)
const EMBER := Color(0.88, 0.45, 0.15, 1.0)
const POT := Color(0.32, 0.27, 0.22, 1.0)
const POLE := Color(0.36, 0.24, 0.12, 1.0)
const HERB := Color(0.35, 0.58, 0.28, 1.0)
const HERB_DARK := Color(0.24, 0.42, 0.20, 1.0)
const FLOWER_YELLOW := Color(0.95, 0.82, 0.30, 1.0)
const FLOWER_VIOLET := Color(0.66, 0.48, 0.82, 1.0)
const BOWL := Color(0.58, 0.57, 0.54, 1.0)
const BOWL_RIM := Color(0.40, 0.39, 0.37, 1.0)
const BOWL_HERBS := Color(0.30, 0.48, 0.22, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.4
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Tettoia: centro (spostato verso ovest per lasciare posto alla rastrelliera), raggio esterno e interno della corona di
# frasche, mezza ampiezza dell'apertura verso la porta (radianti), vertici dell'arco, fasci di frasche sulla corona.
const HUT_CENTER := Vector2(-0.9, -0.4)
const HUT_RADIUS: float = 3.5
const HUT_INNER_RADIUS: float = 2.2
const OPENING_HALF_ANGLE: float = 0.95
const ARC_VERTICES: int = 18
const BUNDLE_COUNT: int = 9
const BUNDLE_WIDTH: float = 0.28
# Giaciglio contro la parete di fondo: centro (rispetto a HUT_CENTER) e mezze misure; la pelle ne copre la metà est.
const BED_OFFSET := Vector2(-0.2, -1.05)
const BED_HALF_SIZE := Vector2(1.15, 0.5)
# Focolare verso l'apertura: centro (rispetto a HUT_CENTER), raggio del cerchio di pietre e numero di pietre.
const HEARTH_OFFSET := Vector2(0.45, 0.75)
const HEARTH_RADIUS: float = 0.62
const HEARTH_STONES: int = 7
# Ciotola davanti all'ingresso, spostata a est (rispetto al punto dell'apertura sul bordo esterno).
const BOWL_OFFSET := Vector2(1.6, 0.9)
const BOWL_RADIUS: float = 0.75
# Rastrelliera: palo a x fisso tra due estremi, mazzetti appesi lungo il palo (y) con il loro fiore (0 nessuno, 1
# giallo, 2 viola).
const RACK_X: float = 3.9
const RACK_TOP: float = -3.6
const RACK_BOTTOM: float = 2.0
const RACK_BUNDLES: Array[Vector2] = [Vector2(-2.8, 1), Vector2(-1.5, 0), Vector2(-0.2, 2), Vector2(1.1, 0)]
const HERB_BUNDLE_LENGTH: float = 1.0
const HERB_BUNDLE_HALF_WIDTH: float = 0.42
# Fumo (solo con `smoking`): un filo sottile dal focolare, in coordinate dello schermo e sempre verso l'alto (come
# SmokehouseShape.SMOKE_PUFFS, ma più piccolo: è un fuoco da infusi): x, y, raggio.
const SMOKE_PUFFS: Array[Vector3] = [Vector3(0.0, -0.5, 0.55), Vector3(0.35, -1.4, 0.45), Vector3(0.7, -2.2, 0.32)]


# `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima semitrasparente;
# `smoking` = sta preparando una ricetta col fuoco (ProductionService.refresh_smoking).
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

	# Rastrelliera (sotto la capanna): palo, poi i mazzetti appesi che sporgono verso est, con il fiore in punta.
	canvas.draw_line(to_canvas.call(Vector2(RACK_X, RACK_TOP)), to_canvas.call(Vector2(RACK_X, RACK_BOTTOM)),
		tint.call(POLE, INVALID_OUTLINE), 0.3 * scale, true)
	for y in [RACK_TOP, RACK_BOTTOM]:
		canvas.draw_circle(to_canvas.call(Vector2(RACK_X, y)), 0.42 * scale, tint.call(POLE, INVALID_OUTLINE))
	for bundle in RACK_BUNDLES:
		var top := Vector2(RACK_X, bundle.x)
		var tip := top + Vector2(HERB_BUNDLE_LENGTH, 0.15)
		var herb := _polygon(to_canvas, [
			top + Vector2(0.0, -0.12), tip + Vector2(0.0, -HERB_BUNDLE_HALF_WIDTH), tip + Vector2(0.15, 0.0),
			tip + Vector2(0.0, HERB_BUNDLE_HALF_WIDTH), top + Vector2(0.0, 0.12),
		])
		canvas.draw_colored_polygon(herb, tint.call(HERB, INVALID_FILL))
		canvas.draw_line(to_canvas.call(top), to_canvas.call(tip), tint.call(HERB_DARK, INVALID_OUTLINE), 0.12 * scale, true)
		canvas.draw_circle(to_canvas.call(top), 0.16 * scale, tint.call(BARK, INVALID_OUTLINE))
		if int(bundle.y) != 0:
			canvas.draw_circle(to_canvas.call(tip + Vector2(0.05, 0.0)), 0.2 * scale,
				tint.call(FLOWER_YELLOW if int(bundle.y) == 1 else FLOWER_VIOLET, INVALID_FILL))

	# Pavimento di terra battuta: un disco appena più largo dell'interno, che dall'apertura sporge sulla soglia.
	canvas.draw_circle(to_canvas.call(HUT_CENTER), (HUT_INNER_RADIUS + 0.3) * scale, tint.call(FLOOR, INVALID_FILL.darkened(0.35)))

	# Giaciglio di paglia contro la parete di fondo, con qualche filo di paglia e la pelle sulla metà est.
	var bed_center := HUT_CENTER + BED_OFFSET
	var bed := _polygon(to_canvas, [
		bed_center + Vector2(-BED_HALF_SIZE.x, -BED_HALF_SIZE.y), bed_center + Vector2(BED_HALF_SIZE.x, -BED_HALF_SIZE.y),
		bed_center + Vector2(BED_HALF_SIZE.x, BED_HALF_SIZE.y), bed_center + Vector2(-BED_HALF_SIZE.x, BED_HALF_SIZE.y),
	])
	canvas.draw_colored_polygon(bed, tint.call(STRAW, INVALID_FILL))
	for straw_x in [-0.8, -0.35]:
		canvas.draw_line(to_canvas.call(bed_center + Vector2(straw_x, -BED_HALF_SIZE.y * 0.6)),
			to_canvas.call(bed_center + Vector2(straw_x + 0.25, BED_HALF_SIZE.y * 0.6)), tint.call(STRAW_DARK, INVALID_OUTLINE), 0.12 * scale, true)
	var bed_hide := _polygon(to_canvas, [
		bed_center + Vector2(0.0, -BED_HALF_SIZE.y - 0.05), bed_center + Vector2(BED_HALF_SIZE.x + 0.1, -BED_HALF_SIZE.y + 0.05),
		bed_center + Vector2(BED_HALF_SIZE.x, BED_HALF_SIZE.y + 0.05), bed_center + Vector2(0.15, BED_HALF_SIZE.y),
	])
	canvas.draw_colored_polygon(bed_hide, tint.call(BED_HIDE, INVALID_FILL))
	var bed_outline := bed.duplicate()
	bed_outline.append(bed[0])
	canvas.draw_polyline(bed_outline, tint.call(STRAW_DARK, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)

	# Focolare: cerchio di pietre, braci e la pentola degli infusi nel mezzo.
	var hearth_center: Vector2 = to_canvas.call(HUT_CENTER + HEARTH_OFFSET)
	canvas.draw_circle(hearth_center, (HEARTH_RADIUS - 0.1) * scale, tint.call(EMBER, INVALID_FILL))
	for i in range(HEARTH_STONES):
		var angle := TAU * float(i) / float(HEARTH_STONES)
		canvas.draw_circle(to_canvas.call(HUT_CENTER + HEARTH_OFFSET + Vector2(cos(angle), sin(angle)) * HEARTH_RADIUS),
			0.2 * scale, tint.call(HEARTH_STONE, INVALID_OUTLINE))
	canvas.draw_circle(hearth_center, 0.36 * scale, tint.call(POT, INVALID_OUTLINE))
	canvas.draw_circle(hearth_center, 0.24 * scale, tint.call(HERB_DARK, INVALID_FILL))

	# Tettoia: corona di frasche a ferro di cavallo aperta verso la porta (+y), metà in ombra (verso ovest), fasci di
	# frasche di traverso sulla corona, contorno su entrambi i bordi e sulle testate.
	var arc_from: float = PI / 2.0 + OPENING_HALF_ANGLE
	var arc_to: float = PI / 2.0 + TAU - OPENING_HALF_ANGLE
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var shade_outer := PackedVector2Array()
	var shade_inner := PackedVector2Array()
	for i in range(ARC_VERTICES + 1):
		var angle: float = lerpf(arc_from, arc_to, float(i) / float(ARC_VERTICES))
		var dir := Vector2(cos(angle), sin(angle))
		# Bordo esterno appena irregolare, come un tetto di frasche.
		var wobble := 1.0 + 0.04 * sin(float(i) * 2.7)
		outer.append(to_canvas.call(HUT_CENTER + dir * HUT_RADIUS * wobble))
		inner.append(to_canvas.call(HUT_CENTER + dir * HUT_INNER_RADIUS))
		if angle <= 1.5 * PI + 0.001:
			shade_outer.append(outer[i])
			shade_inner.append(inner[i])
	var roof := outer.duplicate()
	for i in range(inner.size() - 1, -1, -1):
		roof.append(inner[i])
	canvas.draw_colored_polygon(roof, tint.call(THATCH, INVALID_FILL))
	var shade := shade_outer.duplicate()
	for i in range(shade_inner.size() - 1, -1, -1):
		shade.append(shade_inner[i])
	canvas.draw_colored_polygon(shade, tint.call(THATCH_SHADE, INVALID_FILL.darkened(0.2)))
	for i in range(BUNDLE_COUNT):
		var angle: float = lerpf(arc_from, arc_to, (float(i) + 0.5) / float(BUNDLE_COUNT))
		var dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(
			to_canvas.call(HUT_CENTER + dir * (HUT_INNER_RADIUS + 0.2)), to_canvas.call(HUT_CENTER + dir * HUT_RADIUS * 0.93),
			tint.call(BUNDLE, INVALID_OUTLINE), BUNDLE_WIDTH * scale, true
		)
	var roof_outline := roof.duplicate()
	roof_outline.append(roof[0])
	canvas.draw_polyline(roof_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * scale, true)

	if smoking:
		var smoke := PlaceholderBuildingShapes.SMOKE
		for puff in SMOKE_PUFFS:
			canvas.draw_circle(hearth_center + Vector2(puff.x, puff.y) * scale, puff.z * scale, Color(smoke.r, smoke.g, smoke.b, smoke.a * alpha))

	# Ciotola di pietra con le erbe pestate, davanti all'apertura.
	var rim_y: float = HUT_CENTER.y + HUT_RADIUS
	var bowl_center: Vector2 = to_canvas.call(Vector2(HUT_CENTER.x, rim_y) + BOWL_OFFSET)
	canvas.draw_circle(bowl_center, (BOWL_RADIUS + 0.12) * scale, tint.call(BOWL_RIM, INVALID_OUTLINE))
	canvas.draw_circle(bowl_center, BOWL_RADIUS * scale, tint.call(BOWL, INVALID_FILL))
	canvas.draw_circle(bowl_center, BOWL_RADIUS * 0.6 * scale, tint.call(BOWL_HERBS, INVALID_FILL))


static func _polygon(to_canvas: Callable, points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(to_canvas.call(point))
	return result
