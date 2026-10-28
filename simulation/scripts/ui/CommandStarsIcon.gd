class_name CommandStarsIcon
extends Node2D

# Icona della Veglia delle stelle "star_vigil" (2026-10-29, richiesta utente): tre stelle a cinque punte, una grande e due
# piccole, che salgono sopra il cerchio all'inizio della veglia. Stesso stile di CommandMoonIcon — disegnata a codice,
# nitida a ogni zoom. Registrata in IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella
# (10 px = 1 microcella).

const STAR := Color(0.98, 0.92, 0.6, 1.0)
const OUTLINE := Color(0.18, 0.14, 0.12, 1.0)
const OUTLINE_WIDTH_PX: float = 0.3
const INNER_RATIO: float = 0.45
# Centro e raggio esterno di ogni stella.
const STARS := [
	[Vector2(-0.6, 0.6), 2.2],
	[Vector2(2.3, -1.9), 1.1],
	[Vector2(-2.7, -2.4), 0.8],
]


func _draw() -> void:
	for star in STARS:
		var points := star_polygon(star[0], star[1])
		draw_colored_polygon(points, STAR)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, OUTLINE, OUTLINE_WIDTH_PX, true)


# Stella a cinque punte con la punta in alto: 10 vertici alternati tra raggio esterno e interno.
static func star_polygon(center: Vector2, outer_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var radius := outer_radius if i % 2 == 0 else outer_radius * INNER_RATIO
		points.append(center + Vector2.UP.rotated(TAU * float(i) / 10.0) * radius)
	return points
