class_name SmokehouseShape
extends RefCounted

# Affumicatoio (smokehouse, 2026-10-23, richiesta utente — sulla mappa vista dall'alto come gli altri edifici, con porta e
# rotazione; prima segnaposto visto di fronte): disegno di mappa (MicroCellRenderer._draw_buildings) e anteprima di
# piazzamento (BuildingGhost), nello stile degli altri edifici (colori smorzati, contorni marroni sottili). L'icona della
# barra resta la vista di fronte di PlaceholderBuildingShapes ("smokehouse", SmokehouseIcon).
#
# Vista dall'alto (ridisegnato lo stesso giorno, richiesta utente: la prima versione era la Capanna del vestiario con un
# altro colore): telaio RETTANGOLARE con un palo per angolo; dietro, una copertura di corteccia a strisce sovrapposte;
# davanti, aperto verso la porta, il focolare in un cerchio di pietre e una traversa con strisce di carne e pelle appese;
# sul fianco, una catasta di legna. Mentre produce (`smoking`) le braci sono accese e il fumo sale da sotto la copertura,
# sempre verso l'alto dello schermo qualunque sia la direzione.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con la porta a sud (+y);
# `direction` ruota tutto come la porta (tranne il fumo).

const TYPE := "smokehouse"

const FLOOR := Color(0.50, 0.41, 0.30, 1.0)
const BARK_LIGHT := Color(0.43, 0.32, 0.23, 1.0)
const BARK_DARK := Color(0.36, 0.27, 0.19, 1.0)
const BARK_EDGE := Color(0.27, 0.19, 0.12, 1.0)
const POLE := Color(0.36, 0.24, 0.12, 1.0)
const HEARTH := Color(0.22, 0.16, 0.12, 1.0)
const EMBER := Color(0.92, 0.45, 0.15, 1.0)
const EMBER_CORE := Color(1.0, 0.75, 0.30, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.35
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Telaio: rettangolo (spostato verso ovest per lasciare posto alla catasta); la copertura arriva fino a COVER_BOTTOM.
const FRAME := Rect2(-3.8, -3.8, 6.8, 7.2)
const COVER_BOTTOM: float = 0.4
const COVER_MARGIN: float = 0.2
const COVER_STRIP_COUNT: int = 4
const POLE_RADIUS: float = 0.42
# Focolare: centro, raggi dell'ovale delle pietre, raggio delle pietre e del fondo; braci accese solo con `smoking`.
const HEARTH_CENTER := Vector2(-0.4, 1.6)
const HEARTH_STONE_RING := Vector2(1.25, 0.95)
const HEARTH_STONE_COUNT: int = 7
const HEARTH_STONE_RADIUS: float = 0.4
const HEARTH_PIT_RADIUS: float = 0.85
# Traversa davanti con le strisce appese (x di ciascuna; carne e pelle alternate), lontane dal focolare.
const RACK_Y: float = 3.0
const RACK_STRIPS: Array[float] = [-3.0, -2.1, 1.3, 2.2]
const STRIP_HALF_LENGTH: float = 0.3
const STRIP_WIDTH: float = 0.5
# Catasta di legna sul fianco est: ceppi lungo y (x, y iniziale, y finale) con la testa verso la porta.
const WOODPILE_LOGS: Array[Vector3] = [Vector3(4.1, -3.4, 0.4), Vector3(4.75, -3.0, 0.8)]
const LOG_WIDTH: float = 0.62
# Fumo (solo con `smoking`): sbuffi in coordinate dello schermo dal bordo della copertura sopra il focolare, sempre verso
# l'alto (come il fumo della casa riscaldata, MicroCellRenderer.HOUSE_SMOKE_PUFFS): x, y, raggio.
const SMOKE_PUFFS: Array[Vector3] = [Vector3(0.1, -0.6, 0.85), Vector3(0.6, -1.8, 0.7), Vector3(1.0, -2.9, 0.5)]


# `invalid` = anteprima su una posizione non edificabile (tutto rossastro); `alpha` per l'anteprima semitrasparente;
# `smoking` = l'affumicatoio sta producendo (braci e fumo).
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
	var fill_invalid := INVALID_FILL
	var line_invalid := INVALID_OUTLINE
	var lit := smoking and not invalid

	# Catasta: ogni ceppo col contorno scuro, la corteccia e la testa chiara con un anello.
	for log_data in WOODPILE_LOGS:
		var log_start: Vector2 = to_canvas.call(Vector2(log_data.x, log_data.y))
		var log_end: Vector2 = to_canvas.call(Vector2(log_data.x, log_data.z))
		canvas.draw_line(log_start, log_end, tint.call(OUTLINE, line_invalid), (LOG_WIDTH + 0.25) * scale, true)
		canvas.draw_line(log_start, log_end, tint.call(PlaceholderBuildingShapes.LOG_BARK, fill_invalid), LOG_WIDTH * scale, true)
		canvas.draw_circle(log_end, LOG_WIDTH * 0.5 * scale, tint.call(PlaceholderBuildingShapes.LOG_END, fill_invalid))
		canvas.draw_circle(log_end, LOG_WIDTH * 0.22 * scale, tint.call(PlaceholderBuildingShapes.LOG_RING, line_invalid))

	# Fondo di terra battuta sotto il telaio.
	canvas.draw_colored_polygon(_rect_polygon(to_canvas, FRAME), tint.call(FLOOR, fill_invalid.darkened(0.3)))

	# Focolare: pietre in ovale, fondo scuro, braci se lavora.
	for i in range(HEARTH_STONE_COUNT):
		var angle := TAU * float(i) / float(HEARTH_STONE_COUNT)
		var stone_pos := HEARTH_CENTER + Vector2(cos(angle) * HEARTH_STONE_RING.x, sin(angle) * HEARTH_STONE_RING.y)
		canvas.draw_circle(to_canvas.call(stone_pos), HEARTH_STONE_RADIUS * scale, tint.call(PlaceholderBuildingShapes.STONE, fill_invalid))
	var hearth: Vector2 = to_canvas.call(HEARTH_CENTER)
	canvas.draw_circle(hearth, HEARTH_PIT_RADIUS * scale, tint.call(HEARTH, line_invalid))
	if lit:
		canvas.draw_circle(hearth, HEARTH_PIT_RADIUS * 0.6 * scale, Color(EMBER.r, EMBER.g, EMBER.b, alpha))
		canvas.draw_circle(hearth, HEARTH_PIT_RADIUS * 0.3 * scale, Color(EMBER_CORE.r, EMBER_CORE.g, EMBER_CORE.b, alpha))

	# Traversa davanti con le strisce appese, carne e pelle alternate.
	canvas.draw_line(to_canvas.call(Vector2(FRAME.position.x + 0.2, RACK_Y)), to_canvas.call(Vector2(FRAME.end.x - 0.2, RACK_Y)),
		tint.call(POLE, line_invalid), 0.3 * scale, true)
	for i in range(RACK_STRIPS.size()):
		var strip_color := PlaceholderBuildingShapes.MEAT_STRIP if i % 2 == 0 else PlaceholderBuildingShapes.WOOD
		canvas.draw_line(
			to_canvas.call(Vector2(RACK_STRIPS[i], RACK_Y - STRIP_HALF_LENGTH)), to_canvas.call(Vector2(RACK_STRIPS[i], RACK_Y + STRIP_HALF_LENGTH)),
			tint.call(strip_color, fill_invalid), STRIP_WIDTH * scale, true
		)

	# Copertura di corteccia sulla parte di dietro: strisce sovrapposte parallele alla porta, ciascuna col bordo scuro
	# sotto, poi il contorno.
	var cover := Rect2(
		FRAME.position.x - COVER_MARGIN, FRAME.position.y - COVER_MARGIN,
		FRAME.size.x + COVER_MARGIN * 2.0, COVER_BOTTOM - FRAME.position.y + COVER_MARGIN
	)
	var strip_height := cover.size.y / float(COVER_STRIP_COUNT)
	for i in range(COVER_STRIP_COUNT):
		var strip := Rect2(cover.position.x, cover.position.y + strip_height * float(i), cover.size.x, strip_height)
		canvas.draw_colored_polygon(_rect_polygon(to_canvas, strip), tint.call(BARK_LIGHT if i % 2 == 0 else BARK_DARK, fill_invalid))
		canvas.draw_line(to_canvas.call(Vector2(strip.position.x, strip.end.y)), to_canvas.call(Vector2(strip.end.x, strip.end.y)),
			tint.call(BARK_EDGE, line_invalid), 0.15 * scale, true)
	var cover_outline := _rect_polygon(to_canvas, cover)
	cover_outline.append(cover_outline[0])
	canvas.draw_polyline(cover_outline, tint.call(OUTLINE, line_invalid), OUTLINE_WIDTH * scale, true)

	# Pali agli angoli, con la testa chiara.
	for corner in [FRAME.position, Vector2(FRAME.end.x, FRAME.position.y), Vector2(FRAME.position.x, FRAME.end.y), FRAME.end]:
		var pole: Vector2 = to_canvas.call(corner)
		canvas.draw_circle(pole, POLE_RADIUS * scale, tint.call(POLE, line_invalid))
		canvas.draw_circle(pole, POLE_RADIUS * 0.5 * scale, tint.call(PlaceholderBuildingShapes.LOG_END, fill_invalid))

	# Fumo dal bordo della copertura sopra il focolare: in coordinate dello schermo, verso l'alto.
	if lit:
		var smoke_origin: Vector2 = to_canvas.call(Vector2(HEARTH_CENTER.x, COVER_BOTTOM))
		var smoke := PlaceholderBuildingShapes.SMOKE
		for puff in SMOKE_PUFFS:
			canvas.draw_circle(smoke_origin + Vector2(puff.x, puff.y) * scale, puff.z * scale, Color(smoke.r, smoke.g, smoke.b, smoke.a * alpha))


# I quattro angoli di `rect` (coordinate locali) sul canvas, in ordine.
static func _rect_polygon(to_canvas: Callable, rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		to_canvas.call(rect.position), to_canvas.call(Vector2(rect.end.x, rect.position.y)),
		to_canvas.call(rect.end), to_canvas.call(Vector2(rect.position.x, rect.end.y)),
	])
