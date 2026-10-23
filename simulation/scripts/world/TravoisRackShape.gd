class_name TravoisRackShape
extends RefCounted

# Appoggio per travois (travois_rack, 2026-10-23, richiesta utente — 1x1, senza porta, ruotabile): una staccionata al
# centro della microcella (pali e traversa) e, appoggiati da una parte e dall'altra, fino a 4 travois per lato — ognuno una
# V di due pali con la punta sulla traversa e una pelle tesa tra i due. Se ne disegnano tanti quanti sono appoggiati
# (`count`, 0-8: prima un lato, poi l'altro), così si vede quanti ce ne sono. Un solo disegno per mappa (MicroCellRenderer),
# anteprima (BuildingGhost, vuota) e icona (TravoisRackIcon, piena). Stile smorzato come WoodshedShape.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con la staccionata orizzontale
# (direzione SUD); `direction` (tasto di rotazione) la gira di 90° per passo.

const TYPE := "travois_rack"
const CAPACITY: int = 8

const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const RAIL := Color(0.50, 0.36, 0.20, 1.0)
const POST := Color(0.36, 0.24, 0.12, 1.0)
const POLE := Color(0.58, 0.42, 0.24, 1.0)
const HIDE := Color(0.66, 0.56, 0.42, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Larghezza (2026-10-23, richiesta utente): il 60% della microcella (6 unità su 10), non più quasi tutta.
const RAIL_HALF_LENGTH: float = 3.0
const RAIL_WIDTH: float = 0.45
const POST_RADIUS: float = 0.45
const POSTS_X: Array[float] = [-2.8, 0.0, 2.8]
# Travois appoggiati: centri lungo la staccionata, mezza larghezza delle due gambe a terra, distanza della base dalla
# traversa, spessore dei pali.
const TRAVOIS_X: Array[float] = [-2.25, -0.75, 0.75, 2.25]
const TRAVOIS_HALF_SPREAD: float = 0.6
const TRAVOIS_REACH: float = 3.6
const POLE_WIDTH: float = 0.3


# `count` = travois appoggiati; `invalid` = anteprima su una posizione non edificabile; `alpha` per l'anteprima;
# `scale` per l'icona.
static func draw(
	canvas: CanvasItem, center: Vector2, direction: GameTypes.Direction, count: int = 0, invalid: bool = false,
	alpha: float = 1.0, scale: float = 1.0
) -> void:
	var forward := TentShapes.direction_vector(direction)
	var side := Vector2(forward.y, -forward.x)
	var p := func(x: float, y: float) -> Vector2:
		return center + (side * x + forward * y) * scale
	var w := func(width: float) -> float:
		return width * scale
	var tint := func(color: Color, invalid_color: Color = INVALID_FILL) -> Color:
		var base: Color = invalid_color if invalid else color
		return Color(base.r, base.g, base.b, base.a * alpha)

	# Travois: prima un lato (+y), poi l'altro (−y), sotto la staccionata.
	var shown := clampi(count, 0, CAPACITY)
	for i in range(shown):
		var outward_sign: float = 1.0 if i < CAPACITY / 2 else -1.0
		_draw_travois(canvas, p, w, tint, TRAVOIS_X[i % (CAPACITY / 2)], outward_sign)
	# Staccionata: traversa e pali.
	canvas.draw_line(p.call(-RAIL_HALF_LENGTH, 0.0), p.call(RAIL_HALF_LENGTH, 0.0), tint.call(OUTLINE, INVALID_OUTLINE), w.call(RAIL_WIDTH + 0.25), true)
	canvas.draw_line(p.call(-RAIL_HALF_LENGTH, 0.0), p.call(RAIL_HALF_LENGTH, 0.0), tint.call(RAIL), w.call(RAIL_WIDTH), true)
	for post_x in POSTS_X:
		canvas.draw_circle(p.call(post_x, 0.0), w.call(POST_RADIUS), tint.call(POST, INVALID_OUTLINE))


# Un travois appoggiato: punta sulla traversa, due pali che scendono verso `outward_sign` e la pelle tesa tra i due.
static func _draw_travois(canvas: CanvasItem, p: Callable, w: Callable, tint: Callable, x: float, outward_sign: float) -> void:
	var apex: Vector2 = p.call(x, 0.0)
	var left: Vector2 = p.call(x - TRAVOIS_HALF_SPREAD, outward_sign * TRAVOIS_REACH)
	var right: Vector2 = p.call(x + TRAVOIS_HALF_SPREAD, outward_sign * TRAVOIS_REACH)
	canvas.draw_colored_polygon(PackedVector2Array([
		p.call(x - TRAVOIS_HALF_SPREAD * 0.3, outward_sign * TRAVOIS_REACH * 0.3),
		p.call(x + TRAVOIS_HALF_SPREAD * 0.3, outward_sign * TRAVOIS_REACH * 0.3),
		p.call(x + TRAVOIS_HALF_SPREAD * 0.8, outward_sign * TRAVOIS_REACH * 0.85),
		p.call(x - TRAVOIS_HALF_SPREAD * 0.8, outward_sign * TRAVOIS_REACH * 0.85),
	]), tint.call(HIDE))
	for leg in [left, right]:
		canvas.draw_line(apex, leg, tint.call(OUTLINE, INVALID_OUTLINE), w.call(POLE_WIDTH + 0.2), true)
		canvas.draw_line(apex, leg, tint.call(POLE), w.call(POLE_WIDTH), true)
