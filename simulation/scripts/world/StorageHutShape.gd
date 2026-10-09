class_name StorageHutShape
extends RefCounted

# Disegno della capanna di stoccaggio (storage_hut, 2026-10-03, richiesta utente), condiviso da mappa
# (MicroCellRenderer._draw_buildings), anteprima di piazzamento (BuildingGhost) e icona della barra di costruzione
# (StorageHutIcon), come TentShapes per le tende. Unità: 1.0 = un pixel sulla mappa (una microcella = 10); `scale` per
# l'icona.
#
# Capanna CHIUSA vista dall'alto, distinguibile dalle due capanne rotonde (abitativa e dell'attrezzista, con recinto e
# porta a V aperta): pianta quadrata senza recinto, tetto a due falde (una più scura) con la linea di colmo dalla porta
# al retro, e una porta di assi chiusa sul lato `direction`, piena e con la traversa.

const HALF_SIZE: float = 2.6
# Ingrandimento sulla mappa e nell'anteprima di piazzamento (2026-10-08, richiesta utente — era troppo piccola): stessa
# forma, scalata finché la porta (il punto più sporgente, HALF_SIZE + DOOR_OUTSIDE = 3.05) arriva a ~4.6 su 5, cioè
# quasi tutta la microcella con un piccolo margine. L'icona della barra non lo usa (ha la sua scala, DRAWING_SPAN).
const MAP_SCALE: float = 1.5
const ROOF_LIGHT := Color(0.74, 0.58, 0.36, 1.0)
const ROOF_DARK := Color(0.60, 0.45, 0.27, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.5
const RIDGE_WIDTH: float = 0.35
const DOOR_COLOR := Color(0.36, 0.24, 0.12, 1.0)
const DOOR_BAR_COLOR := Color(0.62, 0.47, 0.28, 1.0)
const DOOR_HALF_WIDTH: float = 0.85
# La porta sporge un poco oltre il muro e rientra un poco nella pianta.
const DOOR_OUTSIDE: float = 0.45
const DOOR_INSIDE: float = 0.55
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)


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
	var s := HALF_SIZE
	var body := _polygon(to_canvas, [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	canvas.draw_colored_polygon(body, tint.call(ROOF_LIGHT, INVALID_FILL))
	# Falda in ombra: metà della pianta, dal colmo (asse porta-retro) a un fianco.
	canvas.draw_colored_polygon(
		_polygon(to_canvas, [Vector2(-s, -s), Vector2(0.0, -s), Vector2(0.0, s), Vector2(-s, s)]),
		tint.call(ROOF_DARK, INVALID_FILL.darkened(0.2))
	)
	canvas.draw_line(to_canvas.call(Vector2(0.0, -s)), to_canvas.call(Vector2(0.0, s)), tint.call(OUTLINE, INVALID_OUTLINE),
		RIDGE_WIDTH * scale, true)
	var outline := body.duplicate()
	outline.append(body[0])
	canvas.draw_polyline(outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * scale, true)
	# Porta chiusa: un'anta piena di assi con la traversa, sul lato `direction`.
	var door := _polygon(to_canvas, [
		Vector2(-DOOR_HALF_WIDTH, s - DOOR_INSIDE), Vector2(DOOR_HALF_WIDTH, s - DOOR_INSIDE),
		Vector2(DOOR_HALF_WIDTH, s + DOOR_OUTSIDE), Vector2(-DOOR_HALF_WIDTH, s + DOOR_OUTSIDE),
	])
	canvas.draw_colored_polygon(door, tint.call(DOOR_COLOR, INVALID_OUTLINE))
	var door_outline := door.duplicate()
	door_outline.append(door[0])
	canvas.draw_polyline(door_outline, tint.call(OUTLINE, INVALID_OUTLINE), OUTLINE_WIDTH * 0.6 * scale, true)
	var bar_y: float = s + (DOOR_OUTSIDE - DOOR_INSIDE) * 0.5
	canvas.draw_line(to_canvas.call(Vector2(-DOOR_HALF_WIDTH * 0.8, bar_y)), to_canvas.call(Vector2(DOOR_HALF_WIDTH * 0.8, bar_y)),
		tint.call(DOOR_BAR_COLOR, INVALID_FILL), 0.25 * scale, true)


static func _polygon(to_canvas: Callable, points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(to_canvas.call(point))
	return result
