class_name DryingRackShape
extends RefCounted

# Essiccatoio (drying_rack, 2026-10-31, richiesta utente — sulla mappa vista dall'alto come gli altri edifici, ruota con la
# direzione scelta al piazzamento; prima segnaposto visto di fronte, uguale in tutte le direzioni): disegno di mappa
# (MicroCellRenderer._draw_buildings) e anteprima di piazzamento (BuildingGhost). L'icona della barra resta la vista di
# fronte di PlaceholderBuildingShapes ("drying_rack", DryingRackIcon).
#
# Vista dall'alto: due pali con la testa chiara, la traversa tra i due e le strisce appese che pendono verso il davanti
# (+y), carne e pelle alternate, ciascuna col suo contorno scuro; sotto, l'ombra delle strisce sul terreno.
#
# Unità: 1.0 = un pixel sulla mappa (una microcella = 10, da −5 a +5). Coordinate locali col davanti a sud (+y);
# `direction` ruota tutto.

const TYPE := "drying_rack"

const POLE := Color(0.36, 0.24, 0.12, 1.0)
const HIDE_STRIP := Color(0.66, 0.52, 0.36, 1.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.18)
const OUTLINE := Color(0.30, 0.22, 0.12, 1.0)
const INVALID_FILL := Color(0.75, 0.15, 0.15, 1.0)
const INVALID_OUTLINE := Color(0.4, 0.05, 0.05, 1.0)

const POLE_X: float = 3.6
const BAR_Y: float = -1.2
const POLE_RADIUS: float = 0.55
const BAR_WIDTH: float = 0.45
# Strisce: x di ciascuna, lunghezza verso il davanti e larghezza; carne e pelle alternate.
const STRIPS: Array[float] = [-2.4, -1.2, 0.0, 1.2, 2.4]
const STRIP_LENGTH: float = 2.6
const STRIP_WIDTH: float = 0.7
const SHADOW_OFFSET := Vector2(0.5, 0.6)


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

	# Ombre delle strisce sul terreno.
	if not invalid:
		for x in STRIPS:
			canvas.draw_line(to_canvas.call(Vector2(x, BAR_Y) + SHADOW_OFFSET), to_canvas.call(Vector2(x, BAR_Y + STRIP_LENGTH) + SHADOW_OFFSET),
				Color(SHADOW.r, SHADOW.g, SHADOW.b, SHADOW.a * alpha), STRIP_WIDTH * scale, true)

	# Traversa col contorno scuro.
	var bar_start: Vector2 = to_canvas.call(Vector2(-POLE_X, BAR_Y))
	var bar_end: Vector2 = to_canvas.call(Vector2(POLE_X, BAR_Y))
	canvas.draw_line(bar_start, bar_end, tint.call(OUTLINE, INVALID_OUTLINE), (BAR_WIDTH + 0.25) * scale, true)
	canvas.draw_line(bar_start, bar_end, tint.call(PlaceholderBuildingShapes.WOOD, INVALID_FILL), BAR_WIDTH * scale, true)

	# Strisce appese verso il davanti, carne e pelle alternate, ciascuna col contorno.
	for i in range(STRIPS.size()):
		var strip_start: Vector2 = to_canvas.call(Vector2(STRIPS[i], BAR_Y))
		var strip_end: Vector2 = to_canvas.call(Vector2(STRIPS[i], BAR_Y + STRIP_LENGTH))
		var strip_color := PlaceholderBuildingShapes.MEAT_STRIP if i % 2 == 0 else HIDE_STRIP
		canvas.draw_line(strip_start, strip_end, tint.call(OUTLINE, INVALID_OUTLINE), (STRIP_WIDTH + 0.25) * scale, true)
		canvas.draw_line(strip_start, strip_end, tint.call(strip_color, INVALID_FILL), STRIP_WIDTH * scale, true)

	# Pali alle estremità, con la testa chiara.
	for x in [-POLE_X, POLE_X]:
		var pole: Vector2 = to_canvas.call(Vector2(x, BAR_Y))
		canvas.draw_circle(pole, POLE_RADIUS * scale, tint.call(POLE, INVALID_OUTLINE))
		canvas.draw_circle(pole, POLE_RADIUS * 0.5 * scale, tint.call(PlaceholderBuildingShapes.LOG_END, INVALID_FILL))
