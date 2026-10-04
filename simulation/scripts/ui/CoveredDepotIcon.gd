class_name CoveredDepotIcon
extends Control

# Icona del deposito coperto nella barra di costruzione (2026-10-04, richiesta utente): lo spiazzo del sito di deposito
# (DepositSiteShape, stessi colori di DepositSiteIcon) con la tettoia della mappa sopra (CoveredDepotShape), scalati al
# rettangolo. Registrata in IconRegistry.BUILDING_ICON_NODES.

const MARGIN_RATIO: float = 0.08
const OUTLINE_WIDTH_RATIO: float = 0.05
# Semilato dello spiazzo sulla mappa (MicroCellRenderer.DEPOSIT_SITE_HALF_SIDE): la tettoia si scala sullo stesso rapporto.
const MAP_HALF_SIDE: float = 4.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var center: Vector2 = size / 2.0
	var half_side: float = side * (0.5 - MARGIN_RATIO)
	var points := PackedVector2Array()
	for point in DepositSiteShape.build_polygon(half_side):
		points.append(center + point)
	draw_colored_polygon(points, DepositSiteShape.FILL_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, DepositSiteShape.OUTLINE_COLOR, maxf(1.0, side * OUTLINE_WIDTH_RATIO), true)
	CoveredDepotShape.draw_cover(self, center, false, 1.0, half_side / MAP_HALF_SIDE)
