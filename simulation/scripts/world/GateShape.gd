class_name GateShape
extends RefCounted

# Cancello (gate, 2026-10-23, richiesta utente): varco della cinta difensiva, pezzo lineare dello stesso gruppo di vallo e
# palizzata (BuildingRules.linear_link_group "defensive_wall"). Visto dall'alto: un tratto d'argine ai due capi (si salda ai
# pezzi vicini), due pali grossi ai lati del varco e due ante di legno chiaro. Asse dai vicini: est/ovest → orizzontale,
# nord/sud → verticale, altrimenti orizzontale. Aperto: le ante girate verso `outward` (il lato scelto col tasto di
# rotazione, PalisadeShape.side_vector, stessa regola del lato parallelo della palizzata), varco libero; chiuso: le ante
# allineate che chiudono il varco. L'anteprima di piazzamento lo mostra sempre aperto. Condiviso da mappa, anteprima e
# icona (GateIcon) tramite LinearShapes.

const HALF_CELL: float = 5.0
const POST_OFFSET: float = 3.8
const POST_RADIUS: float = 1.0
const POST_CORE_RADIUS: float = 0.7
const LEAF_LENGTH: float = 3.4
const LEAF_WIDTH: float = 0.75
const LEAF_OUTLINE_WIDTH: float = 1.1
# Ante aperte: quasi perpendicolari al varco (10° di scarto verso il centro).
const OPEN_ANGLE_FROM_SIDE: float = deg_to_rad(10.0)
const BANK_WIDTH: float = 4.0
const EARTH := Color(0.47, 0.36, 0.24, 1.0)
const WOOD := Color(0.52, 0.37, 0.21, 1.0)
const WOOD_DARK := Color(0.28, 0.19, 0.10, 1.0)
const LEAF_WOOD := Color(0.70, 0.54, 0.33, 1.0)
const INVALID_TINT := Color(0.9, 0.25, 0.25, 0.55)


static func draw(
	canvas: CanvasItem, center: Vector2, neighbor_mask: int, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0, outward: Vector2 = Vector2.ZERO, gate_open: bool = true
) -> void:
	var tint := func(color: Color) -> Color:
		var base: Color = INVALID_TINT if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)
	var axis := _axis(neighbor_mask)
	var across := Vector2(-axis.y, axis.x)
	var side := across
	if outward != Vector2.ZERO:
		var dot := across.dot(outward)
		if absf(dot) < 0.001:
			dot = across.dot(Vector2(-outward.y, outward.x))
		side = across if dot > 0.0 else -across
	for sign in [-1.0, 1.0]:
		var post: Vector2 = center + axis * sign * POST_OFFSET * scale
		# Tratto d'argine dal palo al bordo: si salda ai pezzi vicini.
		canvas.draw_line(post, center + axis * sign * HALF_CELL * scale, tint.call(EARTH), BANK_WIDTH * scale)
		# Anta: dal palo verso il centro (chiusa) o girata verso il lato scelto (aperta).
		var toward_center: Vector2 = -axis * sign
		var leaf_dir: Vector2 = toward_center
		if gate_open:
			leaf_dir = (side * cos(OPEN_ANGLE_FROM_SIDE) + toward_center * sin(OPEN_ANGLE_FROM_SIDE)).normalized()
		var leaf_end: Vector2 = post + leaf_dir * LEAF_LENGTH * scale
		canvas.draw_line(post, leaf_end, tint.call(WOOD_DARK), LEAF_OUTLINE_WIDTH * scale, true)
		canvas.draw_line(post, leaf_end, tint.call(LEAF_WOOD), LEAF_WIDTH * scale, true)
		canvas.draw_circle(post, POST_RADIUS * scale, tint.call(WOOD_DARK))
		canvas.draw_circle(post, POST_CORE_RADIUS * scale, tint.call(WOOD))


static func draw_ground(canvas: CanvasItem, center: Vector2, neighbor_mask: int, clip_mask: int, fill_mask: int, color: Color) -> void:
	LinearShape.draw_ground(canvas, center, neighbor_mask, clip_mask, fill_mask, PalisadeShape.STYLE, color)


# Asse del varco: verticale se i vicini sono solo a nord/sud, altrimenti orizzontale.
static func _axis(neighbor_mask: int) -> Vector2:
	var north_south := (neighbor_mask & ((1 << 0) | (1 << 2))) != 0
	var east_west := (neighbor_mask & ((1 << 1) | (1 << 3))) != 0
	return Vector2.DOWN if north_south and not east_west else Vector2.RIGHT
