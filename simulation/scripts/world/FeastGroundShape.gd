class_name FeastGroundShape
extends RefCounted

# Spiazzo delle feste (feast_ground, 2026-10-17, docs/design/feast_ground.md — passo 2a): quadrato di terra battuta 2x2
# con al centro un cerchio di sassi, cenere e due legnetti spenti (il fuoco si accende durante la festa, passo 2b).
# Un solo disegno per mappa (MicroCellRenderer._draw_buildings), anteprima (BuildingGhost) e icona (FeastGroundIcon).
# Nessuna porta e nessuna rotazione: è un quadrato.
#
# draw(canvas, center, rect_px, invalid, alpha): `center` = centro del quadrato nello spazio del canvas, `rect_px` = lato
# in pixel (sulla mappa 2 microcelle = 20 px; tutte le misure sotto scalano col lato); `invalid` = anteprima su una
# posizione non edificabile (tinta rossastra, come le altre sagome di BuildingGhost).

const TYPE := "feast_ground"
# Misure in frazione del lato del quadrato.
const GROUND_INSET: float = 0.03
const RING_RADIUS: float = 0.2
const STONE_RADIUS: float = 0.05
const STONE_COUNT: int = 11
const ASH_RADIUS: float = 0.13
const STICK_HALF_LENGTH: float = 0.1
const STICK_WIDTH: float = 0.025
const SPECK_COUNT: int = 14
const SPECK_RADIUS: float = 0.015

const ASH_COLOR := Color(0.36, 0.34, 0.32, 1.0)
const ASH_LIGHT_COLOR := Color(0.55, 0.53, 0.50, 1.0)
const CHARRED_STICK_COLOR := Color(0.18, 0.13, 0.09, 1.0)
const STONE_COLORS: Array[Color] = [
	Color(0.58, 0.57, 0.54, 1.0), Color(0.66, 0.64, 0.60, 1.0), Color(0.50, 0.49, 0.47, 1.0),
]
const STONE_OUTLINE := Color(0.32, 0.31, 0.30, 1.0)
const INVALID_TINT := Color(1.0, 0.45, 0.4, 1.0)


static func draw(
	canvas: CanvasItem, center: Vector2, rect_px: Vector2, invalid: bool, alpha: float = 1.0, with_ground: bool = true
) -> void:
	var side: float = minf(rect_px.x, rect_px.y)
	var tint := func(color: Color) -> Color:
		var result: Color = color * INVALID_TINT if invalid else color
		result.a = color.a * alpha
		return result

	# Terra battuta, con qualche puntino fisso (stessi colori di DirtGroundPattern). Sulla mappa no (`with_ground` false): lì
	# il fondo sono i tile di terra battuta del renderer, che si fondono con gli edifici vicini; resta per anteprima e icona.
	if with_ground:
		var inset := rect_px * GROUND_INSET
		canvas.draw_rect(Rect2(center - rect_px / 2.0 + inset, rect_px - inset * 2.0), tint.call(DirtGroundPattern.BASE_COLOR), true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in range(SPECK_COUNT):
			var offset := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42)) * side
			var color: Color = DirtGroundPattern.SPECK_COLORS[i % DirtGroundPattern.SPECK_COLORS.size()]
			canvas.draw_circle(center + offset, SPECK_RADIUS * side, tint.call(color))

	# Cenere e legnetti spenti dentro il cerchio.
	canvas.draw_circle(center, ASH_RADIUS * side, tint.call(ASH_COLOR))
	canvas.draw_circle(center + Vector2(0.03, -0.02) * side, ASH_RADIUS * 0.5 * side, tint.call(ASH_LIGHT_COLOR))
	for angle in [0.5, -0.7]:
		var direction := Vector2(cos(angle), sin(angle)) * STICK_HALF_LENGTH * side
		canvas.draw_line(center - direction, center + direction, tint.call(CHARRED_STICK_COLOR), STICK_WIDTH * side, true)

	# Cerchio di sassi.
	for i in range(STONE_COUNT):
		var angle: float = TAU * float(i) / float(STONE_COUNT)
		var stone_center := center + Vector2(cos(angle), sin(angle)) * RING_RADIUS * side
		var polygon := PlaceholderBuildingShapes._blob_polygon(stone_center, STONE_RADIUS * side, 7100 + i, 7)
		canvas.draw_colored_polygon(polygon, tint.call(STONE_COLORS[i % STONE_COLORS.size()]))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		canvas.draw_polyline(outline, tint.call(STONE_OUTLINE), 0.012 * side, true)
