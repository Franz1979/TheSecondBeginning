class_name WoodshedShape
extends RefCounted

# Legnaia (woodshed, 2026-10-18, richiesta utente — 2x1, nello stile di StorageHutShape: colori smorzati, contorni marroni
# sottili, una falda in ombra). Vista dall'alto, porta sul lato lungo (BuildingRules.door_offset = 1, davanti alla metà
# della produzione). Metà MAGAZZINO (a sinistra con la porta a sud): tettoia di assi a falda unica sul retro e, davanti,
# la catasta di tronchi vista di testa. Metà PRODUZIONE: spiazzo di terra con un recinto basso aperto sulla porta, il
# ceppo per spaccare con l'ascia piantata e qualche ciocco spaccato. Un solo disegno per mappa (MicroCellRenderer
# ._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona (WoodshedIcon).
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10). Coordinate locali con la porta a sud: x da −10 (ovest) a +10
# (est), y da −5 (retro) a +5 (lato della porta); `direction` ruota tutto come la porta (BuildingFootprint).

const TYPE := "woodshed"
const HALF_WIDTH: float = 10.0
const HALF_DEPTH: float = 5.0

const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.4
const ROOF_LIGHT := Color(0.74, 0.58, 0.36, 1.0)
const ROOF_DARK := Color(0.60, 0.45, 0.27, 1.0)
const PLANK_LINE := Color(0.52, 0.38, 0.22, 1.0)
const YARD := Color(0.55, 0.46, 0.34, 1.0)
const FENCE := Color(0.50, 0.36, 0.20, 1.0)
const FENCE_WIDTH: float = 0.45
const LOG_BARK := Color(0.40, 0.28, 0.16, 1.0)
const LOG_END := Color(0.78, 0.63, 0.42, 1.0)
const LOG_RING := Color(0.60, 0.46, 0.29, 1.0)
const AXE_HANDLE := Color(0.66, 0.50, 0.30, 1.0)
const AXE_HEAD := Color(0.62, 0.62, 0.60, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Catasta: centri dei tronchi visti di testa (due file, davanti alla tettoia) e raggio.
const LOGS: Array[Vector2] = [
	Vector2(-8.2, 3.3), Vector2(-6.2, 3.3), Vector2(-4.2, 3.3), Vector2(-2.2, 3.3),
	Vector2(-7.2, 1.6), Vector2(-5.2, 1.6), Vector2(-3.2, 1.6),
]
const LOG_RADIUS: float = 0.95
# Tettoia sul retro della metà magazzino.
const ROOF_FRONT_Y: float = 0.6
# Ceppo per spaccare (centro, raggio) e ciocchi spaccati (centro, raggio, angolo).
const BLOCK_CENTER := Vector2(5.2, -0.6)
const BLOCK_RADIUS: float = 1.5
const SPLITS: Array[Vector3] = [Vector3(2.6, 1.6, 0.4), Vector3(7.6, 1.4, 2.1), Vector3(3.2, -3.0, 1.2), Vector3(8.0, -2.8, 3.6)]
const SPLIT_SIZE: float = 0.75
# Varco della porta nel recinto (lato y = +5, metà produzione).
const DOOR_GAP := Vector2(2.6, 7.4)
# Porta più leggibile (2026-10-18, richiesta utente): stipiti grossi e scuri, un'anta di assi aperta verso l'esterno e una
# soglia di terra calpestata che sporge oltre il lato della porta.
const DOOR_POST := Color(0.36, 0.24, 0.12, 1.0)
const DOOR_POST_RADIUS: float = 0.7
const DOOR_LEAF := Color(0.66, 0.50, 0.30, 1.0)
const DOOR_LEAF_WIDTH: float = 0.7
const THRESHOLD := Color(0.64, 0.54, 0.40, 1.0)
const THRESHOLD_OUTSIDE: float = 1.3


# `invalid` = anteprima su una posizione non edificabile; `alpha` per l'anteprima semitrasparente; `scale` per l'icona.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, invalid: bool = false, alpha: float = 1.0,
	scale: float = 1.0
) -> void:
	var forward := TentShapes.direction_vector(direction)
	# Asse della larghezza: est con la porta a sud, ruotato come BuildingFootprint.door_front_local (S -> W -> N -> E).
	var side := Vector2(forward.y, -forward.x)
	var p := func(x: float, y: float) -> Vector2:
		return center + (side * x + forward * y) * scale
	var w := func(width: float) -> float:
		return width * scale
	var tint := func(color: Color, invalid_color: Color = INVALID_FILL) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)

	# Metà produzione: spiazzo di terra, con la soglia calpestata della porta che esce dal lato lungo.
	canvas.draw_colored_polygon(_rect(p, 0.0, -HALF_DEPTH, HALF_WIDTH, HALF_DEPTH), tint.call(YARD))
	canvas.draw_colored_polygon(_rect(p, DOOR_GAP.x, HALF_DEPTH - 1.2, DOOR_GAP.y, HALF_DEPTH + THRESHOLD_OUTSIDE), tint.call(THRESHOLD))
	# Catasta davanti alla tettoia (prima la fila dietro), poi la tettoia sopra la parte posteriore.
	for log_center in LOGS:
		_draw_log_end(canvas, p.call(log_center.x, log_center.y), w.call(LOG_RADIUS), tint, w)
	var roof := _rect(p, -HALF_WIDTH, -HALF_DEPTH, 0.0, ROOF_FRONT_Y)
	canvas.draw_colored_polygon(roof, tint.call(ROOF_LIGHT))
	canvas.draw_colored_polygon(_rect(p, -HALF_WIDTH, -HALF_DEPTH, 0.0, -2.6), tint.call(ROOF_DARK, INVALID_FILL.darkened(0.2)))
	for plank_x in [-7.5, -5.0, -2.5]:
		canvas.draw_line(p.call(plank_x, -HALF_DEPTH), p.call(plank_x, ROOF_FRONT_Y), tint.call(PLANK_LINE, INVALID_OUTLINE), w.call(0.2), true)
	_outline(canvas, roof, tint.call(OUTLINE, INVALID_OUTLINE), w.call(OUTLINE_WIDTH))
	# Metà produzione: ciocchi spaccati, ceppo con gli anelli, ascia piantata.
	for split in SPLITS:
		var wedge := PackedVector2Array()
		for corner in [Vector2(-1.0, -0.6), Vector2(1.0, -0.6), Vector2(0.0, 0.8)]:
			var rotated: Vector2 = (corner * SPLIT_SIZE).rotated(split.z)
			wedge.append(p.call(split.x + rotated.x, split.y + rotated.y))
		canvas.draw_colored_polygon(wedge, tint.call(LOG_END))
		_outline(canvas, wedge, tint.call(OUTLINE, INVALID_OUTLINE), w.call(0.2))
	_draw_log_end(canvas, p.call(BLOCK_CENTER.x, BLOCK_CENTER.y), w.call(BLOCK_RADIUS), tint, w)
	canvas.draw_line(p.call(BLOCK_CENTER.x + 0.3, BLOCK_CENTER.y - 0.2), p.call(BLOCK_CENTER.x + 2.6, BLOCK_CENTER.y - 2.4),
		tint.call(AXE_HANDLE), w.call(0.35), true)
	canvas.draw_colored_polygon(PackedVector2Array([
		p.call(BLOCK_CENTER.x - 0.5, BLOCK_CENTER.y + 0.1), p.call(BLOCK_CENTER.x + 0.6, BLOCK_CENTER.y - 0.6),
		p.call(BLOCK_CENTER.x + 0.9, BLOCK_CENTER.y - 0.1), p.call(BLOCK_CENTER.x - 0.2, BLOCK_CENTER.y + 0.6),
	]), tint.call(AXE_HEAD))
	# Recinto basso della metà produzione, aperto sulla porta.
	var fence_color: Color = tint.call(FENCE, INVALID_OUTLINE)
	var fence_width: float = w.call(FENCE_WIDTH)
	canvas.draw_line(p.call(0.0, -HALF_DEPTH), p.call(HALF_WIDTH, -HALF_DEPTH), fence_color, fence_width, true)
	canvas.draw_line(p.call(HALF_WIDTH, -HALF_DEPTH), p.call(HALF_WIDTH, HALF_DEPTH), fence_color, fence_width, true)
	canvas.draw_line(p.call(0.0, HALF_DEPTH), p.call(DOOR_GAP.x, HALF_DEPTH), fence_color, fence_width, true)
	canvas.draw_line(p.call(DOOR_GAP.y, HALF_DEPTH), p.call(HALF_WIDTH, HALF_DEPTH), fence_color, fence_width, true)
	for post_x in [0.0, HALF_WIDTH]:
		canvas.draw_circle(p.call(post_x, HALF_DEPTH), w.call(0.4), fence_color)
	# Porta: anta di assi aperta verso l'esterno (incernierata allo stipite destro), poi gli stipiti sopra.
	var hinge: Vector2 = p.call(DOOR_GAP.y, HALF_DEPTH)
	var leaf_end: Vector2 = p.call(DOOR_GAP.y - 2.6, HALF_DEPTH + 2.6)
	canvas.draw_line(hinge, leaf_end, tint.call(OUTLINE, INVALID_OUTLINE), w.call(DOOR_LEAF_WIDTH + 0.3), true)
	canvas.draw_line(hinge, leaf_end, tint.call(DOOR_LEAF), w.call(DOOR_LEAF_WIDTH), true)
	for post_x in [DOOR_GAP.x, DOOR_GAP.y]:
		canvas.draw_circle(p.call(post_x, HALF_DEPTH), w.call(DOOR_POST_RADIUS), tint.call(DOOR_POST, INVALID_OUTLINE))


# Tronco visto di testa: corteccia, sezione chiara, un anello.
static func _draw_log_end(canvas: CanvasItem, at: Vector2, radius: float, tint: Callable, w: Callable) -> void:
	canvas.draw_circle(at, radius, tint.call(LOG_BARK, INVALID_OUTLINE))
	canvas.draw_circle(at, radius * 0.78, tint.call(LOG_END))
	canvas.draw_arc(at, radius * 0.4, 0.0, TAU, 14, tint.call(LOG_RING, INVALID_OUTLINE), w.call(0.15), true)


static func _rect(p: Callable, x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([p.call(x0, y0), p.call(x1, y0), p.call(x1, y1), p.call(x0, y1)])


static func _outline(canvas: CanvasItem, polygon: PackedVector2Array, color: Color, width: float) -> void:
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	canvas.draw_polyline(closed, color, width, true)
