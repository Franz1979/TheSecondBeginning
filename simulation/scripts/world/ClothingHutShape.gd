class_name ClothingHutShape
extends RefCounted

# Capanna del vestiario (clothing_hut, 2026-10-20, richiesta utente — sulla mappa vista dall'alto come gli altri edifici,
# non più di fronte): disegno di mappa (MicroCellRenderer._draw_buildings) e anteprima di piazzamento (BuildingGhost),
# nello stile di StorageHutShape (colori smorzati, contorni marroni sottili, una metà in ombra). L'icona della barra resta
# la vista di fronte di PlaceholderBuildingShapes ("clothing_hut", ClothingHutIcon).
#
# Vista dall'alto: capanna rotonda coperta di pelli grigio-brune, con le cuciture a raggiera che salgono al foro del fumo
# e le punte dei pali che spuntano al centro; ingresso con il lembo di pelle ripiegato sul lato `direction`; accanto, sul
# fianco, il telaio di due pali con una pelle tesa ad asciugare.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali con la porta a sud (+y);
# `direction` ruota tutto come la porta.

const TYPE := "clothing_hut"

const HIDE := Color(0.52, 0.48, 0.43, 1.0)
const HIDE_SHADE := Color(0.44, 0.41, 0.37, 1.0)
const SEAM := Color(0.36, 0.33, 0.30, 1.0)
const DOOR := Color(0.16, 0.13, 0.11, 1.0)
const FLAP := Color(0.60, 0.56, 0.50, 1.0)
const POLE := Color(0.36, 0.24, 0.12, 1.0)
const FRAME_HIDE := Color(0.66, 0.58, 0.47, 1.0)
const LACING := Color(0.45, 0.36, 0.26, 1.0)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const OUTLINE_WIDTH: float = 0.4
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

# Capanna: centro (spostato verso ovest per lasciare posto al telaio), raggio, vertici del contorno, cuciture.
const HUT_CENTER := Vector2(-0.9, -0.2)
const HUT_RADIUS: float = 3.7
const HUT_VERTICES: int = 20
const SEAM_COUNT: int = 6
const SEAM_WIDTH: float = 0.22
const SMOKE_HOLE_RADIUS: float = 0.55
# Punte dei pali al foro del fumo: direzioni (angoli in radianti) e lunghezza oltre il foro.
const POLE_TIP_ANGLES: Array[float] = [-2.2, -1.0, 0.3]
const POLE_TIP_LENGTH: float = 1.0
const POLE_WIDTH: float = 0.35
# Ingresso: mezza larghezza sul bordo e profondità verso il centro; lembo ripiegato a est dell'ingresso.
const DOOR_HALF_WIDTH: float = 1.0
const DOOR_DEPTH: float = 1.4
# Telaio della pelle: due pali (estremi x, y) e la pelle tesa tra loro.
const FRAME_X: float = 4.0
const FRAME_TOP: float = -3.4
const FRAME_BOTTOM: float = 1.8
const FRAME_HIDE_HALF_WIDTH: float = 0.55
const FRAME_HIDE_INSET: float = 0.6


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
	var fill_invalid := INVALID_FILL
	var line_invalid := INVALID_OUTLINE

	# Telaio (sotto la capanna): pelle tesa, legacci, poi i due pali con le teste.
	var frame_hide := _polygon(to_canvas, [
		Vector2(FRAME_X - FRAME_HIDE_HALF_WIDTH, FRAME_TOP + FRAME_HIDE_INSET),
		Vector2(FRAME_X + FRAME_HIDE_HALF_WIDTH, FRAME_TOP + FRAME_HIDE_INSET),
		Vector2(FRAME_X + FRAME_HIDE_HALF_WIDTH, FRAME_BOTTOM - FRAME_HIDE_INSET),
		Vector2(FRAME_X - FRAME_HIDE_HALF_WIDTH, FRAME_BOTTOM - FRAME_HIDE_INSET),
	])
	canvas.draw_colored_polygon(frame_hide, tint.call(FRAME_HIDE, fill_invalid))
	var frame_outline := frame_hide.duplicate()
	frame_outline.append(frame_hide[0])
	canvas.draw_polyline(frame_outline, tint.call(LACING, line_invalid), OUTLINE_WIDTH * 0.6 * scale, true)
	var lacing_y: float = FRAME_TOP + FRAME_HIDE_INSET + 0.8
	while lacing_y < FRAME_BOTTOM - FRAME_HIDE_INSET - 0.4:
		canvas.draw_line(
			to_canvas.call(Vector2(FRAME_X - FRAME_HIDE_HALF_WIDTH * 0.6, lacing_y)),
			to_canvas.call(Vector2(FRAME_X + FRAME_HIDE_HALF_WIDTH * 0.6, lacing_y)),
			tint.call(LACING, line_invalid), 0.15 * scale, true
		)
		lacing_y += 1.1
	canvas.draw_line(to_canvas.call(Vector2(FRAME_X, FRAME_TOP)), to_canvas.call(Vector2(FRAME_X, FRAME_BOTTOM)),
		tint.call(POLE, line_invalid), POLE_WIDTH * 0.6 * scale, true)
	for y in [FRAME_TOP, FRAME_BOTTOM]:
		canvas.draw_circle(to_canvas.call(Vector2(FRAME_X, y)), 0.45 * scale, tint.call(POLE, line_invalid))

	# Capanna: pelli, metà in ombra (verso ovest), cuciture a raggiera, contorno.
	var hut := PackedVector2Array()
	for i in range(HUT_VERTICES):
		var angle := TAU * float(i) / float(HUT_VERTICES)
		hut.append(to_canvas.call(HUT_CENTER + Vector2(cos(angle), sin(angle)) * HUT_RADIUS))
	canvas.draw_colored_polygon(hut, tint.call(HIDE, fill_invalid))
	var shade := PackedVector2Array()
	for i in range(HUT_VERTICES / 2 + 1):
		var angle := PI / 2.0 + PI * float(i) / float(HUT_VERTICES / 2)
		shade.append(to_canvas.call(HUT_CENTER + Vector2(cos(angle), sin(angle)) * HUT_RADIUS))
	canvas.draw_colored_polygon(shade, tint.call(HIDE_SHADE, fill_invalid.darkened(0.2)))
	for i in range(SEAM_COUNT):
		var angle := TAU * (float(i) + 0.5) / float(SEAM_COUNT) - PI / 2.0
		var dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(
			to_canvas.call(HUT_CENTER + dir * SMOKE_HOLE_RADIUS), to_canvas.call(HUT_CENTER + dir * HUT_RADIUS * 0.96),
			tint.call(SEAM, line_invalid), SEAM_WIDTH * scale, true
		)
	var hut_outline := hut.duplicate()
	hut_outline.append(hut[0])
	canvas.draw_polyline(hut_outline, tint.call(OUTLINE, line_invalid), OUTLINE_WIDTH * scale, true)

	# Ingresso sul lato della porta: apertura scura a cuneo e lembo di pelle ripiegato a est.
	var rim_y: float = HUT_CENTER.y + HUT_RADIUS
	var door := _polygon(to_canvas, [
		Vector2(HUT_CENTER.x - DOOR_HALF_WIDTH, rim_y - 0.25), Vector2(HUT_CENTER.x, rim_y - DOOR_DEPTH),
		Vector2(HUT_CENTER.x + DOOR_HALF_WIDTH, rim_y - 0.25), Vector2(HUT_CENTER.x, rim_y + 0.3),
	])
	canvas.draw_colored_polygon(door, tint.call(DOOR, line_invalid))
	var flap := _polygon(to_canvas, [
		Vector2(HUT_CENTER.x + DOOR_HALF_WIDTH * 0.2, rim_y - DOOR_DEPTH * 0.8), Vector2(HUT_CENTER.x + DOOR_HALF_WIDTH * 1.6, rim_y - 0.7),
		Vector2(HUT_CENTER.x + DOOR_HALF_WIDTH, rim_y - 0.15),
	])
	canvas.draw_colored_polygon(flap, tint.call(FLAP, fill_invalid))
	var flap_outline := flap.duplicate()
	flap_outline.append(flap[0])
	canvas.draw_polyline(flap_outline, tint.call(OUTLINE, line_invalid), OUTLINE_WIDTH * 0.6 * scale, true)

	# Foro del fumo e punte dei pali.
	var hole: Vector2 = to_canvas.call(HUT_CENTER)
	for angle in POLE_TIP_ANGLES:
		var tip_dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(hole, to_canvas.call(HUT_CENTER + tip_dir * (SMOKE_HOLE_RADIUS + POLE_TIP_LENGTH)),
			tint.call(POLE, line_invalid), POLE_WIDTH * scale, true)
	canvas.draw_circle(hole, SMOKE_HOLE_RADIUS * scale, tint.call(DOOR, line_invalid))


static func _polygon(to_canvas: Callable, points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(to_canvas.call(point))
	return result
