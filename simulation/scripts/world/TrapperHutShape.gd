class_name TrapperHutShape
extends RefCounted

# Capanna del trappoliere (trapper_hut, 2026-11-07, richiesta utente — addomesticazione, primo passo): disegno di mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra (TrapperHutIcon), nello
# stile delle altre capanne (colori smorzati, contorni marroni sottili).
#
# Vista dall'alto: riparo basso a spiovente di frasche, aperto sul davanti (striscia d'ombra dell'interno), con due pelli
# essiccate stese sopra; di fianco una rastrelliera (due pali e una traversa) con lacci e matasse di corda appesi; davanti
# due gabbie di bastoni intrecciati e una nassa di vimini appoggiata.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con l'apertura a sud (+y);
# `direction` ruota tutto come la porta.

const TYPE := "trapper_hut"

const BOUGHS := Color(0.47, 0.50, 0.30, 1.0)
const BOUGHS_SHADE := Color(0.38, 0.41, 0.24, 1.0)
const BRANCH := Color(0.40, 0.29, 0.17, 1.0)
const RIDGE := Color(0.33, 0.23, 0.13, 1.0)
const OPENING := Color(0.17, 0.14, 0.11, 1.0)
const HIDE := Color(0.72, 0.60, 0.44, 1.0)
const HIDE_EDGE := Color(0.55, 0.43, 0.29, 1.0)
const POLE := Color(0.42, 0.30, 0.17, 1.0)
const FIBER := Color(0.78, 0.71, 0.50, 1.0)
const ROPE := Color(0.64, 0.55, 0.36, 1.0)
const WICKER := Color(0.66, 0.53, 0.33, 1.0)
const WICKER_DARK := Color(0.45, 0.34, 0.19, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.4
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Riparo a spiovente: il lato alto (colmo) dietro, il lato basso verso l'apertura.
const SHELTER_LEFT: float = -4.6
const SHELTER_RIGHT: float = 2.0
const SHELTER_TOP: float = -4.4
const SHELTER_BOTTOM: float = 0.4
const OPENING_DEPTH: float = 0.7
const BRANCH_STEP: float = 0.8
const BRANCH_WIDTH: float = 0.18
const BRANCH_SLANT: float = 0.5
const RIDGE_WIDTH: float = 0.5
# Pelli stese sul tetto (poligoni irregolari).
const HIDES: Array = [
	[Vector2(-4.0, -3.9), Vector2(-1.9, -4.1), Vector2(-1.6, -2.0), Vector2(-3.8, -1.7)],
	[Vector2(-0.6, -2.6), Vector2(1.4, -2.9), Vector2(1.6, -0.9), Vector2(-0.3, -0.6)],
]
# Rastrelliera sul fianco: traversa tra due pali, lacci (anelli) e matasse (dischi) appesi.
const RACK_X: float = 3.7
const RACK_TOP: float = -4.0
const RACK_BOTTOM: float = 0.4
const POLE_RADIUS: float = 0.45
const RACK_WIDTH: float = 0.35
const SNARES: Array[Vector2] = [Vector2(3.1, -2.9), Vector2(4.3, -1.9), Vector2(3.1, -0.9)]
const SNARE_RADIUS: float = 0.5
const COILS: Array[Vector2] = [Vector2(4.3, -3.2), Vector2(4.3, -0.4)]
const COIL_RADIUS: float = 0.55
# Gabbie di bastoni intrecciati davanti al riparo: x, y, lato.
const CAGES: Array[Vector3] = [Vector3(-4.4, 1.6, 1.9), Vector3(-2.2, 2.0, 1.6)]
const CAGE_BARS: int = 3
# Nassa: bocca rotonda e corpo a cono verso la punta.
const TRAP_MOUTH := Vector2(1.0, 2.9)
const TRAP_MOUTH_RADIUS: float = 0.9
const TRAP_TIP := Vector2(4.2, 3.6)
const TRAP_RIBS: int = 3


# `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima semitrasparente.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0
) -> void:
	var forward := TentShapes.direction_vector(direction)
	var side := Vector2(-forward.y, forward.x)
	var to_canvas := func(local: Vector2) -> Vector2:
		return center + (side * local.x + forward * local.y) * scale
	var tint := func(color: Color, invalid_color: Color) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)

	# Riparo di frasche: la metà verso l'apertura in ombra, rami di traverso, colmo dietro.
	var shelter := _rect(to_canvas, SHELTER_LEFT, SHELTER_TOP, SHELTER_RIGHT, SHELTER_BOTTOM)
	var middle_y := (SHELTER_TOP + SHELTER_BOTTOM) / 2.0
	canvas.draw_colored_polygon(_rect(to_canvas, SHELTER_LEFT, SHELTER_TOP, SHELTER_RIGHT, middle_y), tint.call(BOUGHS, INVALID_FILL))
	canvas.draw_colored_polygon(
		_rect(to_canvas, SHELTER_LEFT, middle_y, SHELTER_RIGHT, SHELTER_BOTTOM), tint.call(BOUGHS_SHADE, INVALID_FILL.darkened(0.2))
	)
	var branch_x := SHELTER_LEFT + BRANCH_STEP * 0.5
	while branch_x < SHELTER_RIGHT - BRANCH_SLANT:
		canvas.draw_line(
			to_canvas.call(Vector2(branch_x, SHELTER_TOP)), to_canvas.call(Vector2(branch_x + BRANCH_SLANT, SHELTER_BOTTOM)),
			tint.call(BRANCH, INVALID_OUTLINE), BRANCH_WIDTH * scale, true
		)
		branch_x += BRANCH_STEP
	for hide in HIDES:
		var points := PackedVector2Array()
		for point: Vector2 in hide:
			points.append(to_canvas.call(point))
		canvas.draw_colored_polygon(points, tint.call(HIDE, INVALID_FILL))
		points.append(points[0])
		canvas.draw_polyline(points, tint.call(HIDE_EDGE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.5 * scale, true)
	canvas.draw_line(
		to_canvas.call(Vector2(SHELTER_LEFT, SHELTER_TOP)), to_canvas.call(Vector2(SHELTER_RIGHT, SHELTER_TOP)),
		tint.call(RIDGE, INVALID_OUTLINE), RIDGE_WIDTH * scale, true
	)
	var outline := shelter.duplicate()
	outline.append(shelter[0])
	canvas.draw_polyline(outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * scale, true)
	# Apertura sul davanti: l'ombra dell'interno sotto il bordo basso del tetto.
	canvas.draw_colored_polygon(
		_rect(to_canvas, SHELTER_LEFT + 0.4, SHELTER_BOTTOM, SHELTER_RIGHT - 0.4, SHELTER_BOTTOM + OPENING_DEPTH),
		tint.call(OPENING, INVALID_OUTLINE)
	)

	# Rastrelliera: traversa, due pali, lacci e matasse appesi.
	var rack_top: Vector2 = to_canvas.call(Vector2(RACK_X, RACK_TOP))
	var rack_bottom: Vector2 = to_canvas.call(Vector2(RACK_X, RACK_BOTTOM))
	canvas.draw_line(rack_top, rack_bottom, tint.call(POLE, INVALID_OUTLINE), RACK_WIDTH * scale, true)
	for snare in SNARES:
		canvas.draw_arc(to_canvas.call(snare), SNARE_RADIUS * scale, 0.0, TAU, 14, tint.call(FIBER, INVALID_FILL), 0.2 * scale, true)
	for coil in COILS:
		var coil_center: Vector2 = to_canvas.call(coil)
		canvas.draw_circle(coil_center, COIL_RADIUS * scale, tint.call(ROPE, INVALID_FILL))
		canvas.draw_arc(coil_center, COIL_RADIUS * 0.55 * scale, 0.0, TAU, 12, tint.call(OUTLINE, INVALID_OUTLINE), 0.15 * scale, true)
	for pole in [rack_top, rack_bottom]:
		canvas.draw_circle(pole, POLE_RADIUS * scale, tint.call(POLE, INVALID_FILL))
		canvas.draw_arc(pole, POLE_RADIUS * scale, 0.0, TAU, 10, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.5 * scale, true)

	# Gabbie di bastoni intrecciati: fondo di vimini, trama a griglia, contorno.
	for cage in CAGES:
		var left := cage.x
		var top := cage.y
		var right := cage.x + cage.z
		var bottom := cage.y + cage.z
		canvas.draw_colored_polygon(_rect(to_canvas, left, top, right, bottom), tint.call(WICKER, INVALID_FILL))
		for i in range(1, CAGE_BARS + 1):
			var t := float(i) / float(CAGE_BARS + 1)
			canvas.draw_line(
				to_canvas.call(Vector2(lerpf(left, right, t), top)), to_canvas.call(Vector2(lerpf(left, right, t), bottom)),
				tint.call(WICKER_DARK, INVALID_OUTLINE), 0.15 * scale, true
			)
			canvas.draw_line(
				to_canvas.call(Vector2(left, lerpf(top, bottom, t))), to_canvas.call(Vector2(right, lerpf(top, bottom, t))),
				tint.call(WICKER_DARK, INVALID_OUTLINE), 0.15 * scale, true
			)
		var cage_outline := _rect(to_canvas, left, top, right, bottom)
		cage_outline.append(cage_outline[0])
		canvas.draw_polyline(cage_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)

	# Nassa: cono dalla bocca alla punta, con le stecche, poi la bocca aperta.
	var axis := (TRAP_TIP - TRAP_MOUTH).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var mouth_a := TRAP_MOUTH + normal * TRAP_MOUTH_RADIUS
	var mouth_b := TRAP_MOUTH - normal * TRAP_MOUTH_RADIUS
	canvas.draw_colored_polygon(
		PackedVector2Array([to_canvas.call(mouth_a), to_canvas.call(TRAP_TIP), to_canvas.call(mouth_b)]), tint.call(WICKER, INVALID_FILL)
	)
	for i in range(TRAP_RIBS):
		var t := (float(i) + 0.5) / float(TRAP_RIBS) * 2.0 - 1.0
		canvas.draw_line(
			to_canvas.call(TRAP_MOUTH + normal * TRAP_MOUTH_RADIUS * t), to_canvas.call(TRAP_TIP),
			tint.call(WICKER_DARK, INVALID_OUTLINE), 0.15 * scale, true
		)
	var trap_outline := PackedVector2Array([to_canvas.call(mouth_a), to_canvas.call(TRAP_TIP), to_canvas.call(mouth_b)])
	canvas.draw_polyline(trap_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)
	var mouth: Vector2 = to_canvas.call(TRAP_MOUTH)
	canvas.draw_circle(mouth, TRAP_MOUTH_RADIUS * scale, tint.call(WICKER, INVALID_FILL))
	canvas.draw_circle(mouth, TRAP_MOUTH_RADIUS * 0.55 * scale, tint.call(OPENING, INVALID_OUTLINE))
	canvas.draw_arc(mouth, TRAP_MOUTH_RADIUS * scale, 0.0, TAU, 16, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)


static func _rect(to_canvas: Callable, left: float, top: float, right: float, bottom: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in [Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]:
		result.append(to_canvas.call(point))
	return result
