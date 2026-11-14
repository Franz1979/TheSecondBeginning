class_name CommandSproutIcon
extends Node2D

# Icona del lavoro "sow" (2026-11-15, Semina della lista dei lavori): germoglio con due foglioline su una zolla di terra,
# stesso stile di CommandAxeIcon. Registrata in IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali
# della cella (10 px = 1 microcella).

const SOIL := Color(0.45, 0.31, 0.18, 1.0)
const STEM := Color(0.36, 0.62, 0.24, 1.0)
const LEAF := Color(0.46, 0.76, 0.3, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3

# Fattore applicato a coordinate e spessori, come CommandAxeIcon.
var icon_scale: float = 1.0


func _draw() -> void:
	var s := icon_scale
	# Zolla: mezza ellisse schiacciata in basso.
	var soil := PackedVector2Array()
	for i in range(9):
		var angle := PI * float(i) / 8.0
		soil.append(Vector2(cos(angle) * 2.6, 2.6 - sin(angle) * 1.1) * s)
	draw_colored_polygon(soil, SOIL)
	var soil_closed := soil.duplicate()
	soil_closed.append(soil[0])
	draw_polyline(soil_closed, OUTLINE, OUTLINE_WIDTH_PX * 1.5 * s, true)
	# Stelo.
	var stem_base := Vector2(0.0, 1.6) * s
	var stem_top := Vector2(0.0, -1.2) * s
	draw_line(stem_base, stem_top, OUTLINE, (0.5 + OUTLINE_WIDTH_PX * 2.0) * s, true)
	draw_line(stem_base, stem_top, STEM, 0.5 * s, true)
	# Due foglioline a goccia, una per lato.
	for side in [-1.0, 1.0]:
		var leaf := _leaf(stem_top, Vector2(side * 2.4, -1.6) * s, 0.75 * s)
		draw_colored_polygon(leaf, LEAF)
		var leaf_closed := leaf.duplicate()
		leaf_closed.append(leaf[0])
		draw_polyline(leaf_closed, OUTLINE, OUTLINE_WIDTH_PX * 1.5 * s, true)


# Foglia a mandorla da `from` (attacco) a `from + reach`, larga `width` a metà.
static func _leaf(from: Vector2, reach: Vector2, width: float) -> PackedVector2Array:
	var normal := reach.normalized().orthogonal()
	var points := PackedVector2Array()
	for i in range(7):
		var t := float(i) / 6.0
		points.append(from + reach * t + normal * sin(t * PI) * width)
	for i in range(5, 0, -1):
		var t := float(i) / 6.0
		points.append(from + reach * t - normal * sin(t * PI) * width)
	return points
