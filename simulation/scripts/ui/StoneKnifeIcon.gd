class_name StoneKnifeIcon
extends Control

# Icona disegnata "coltello di pietra" (2026-09-24, richiesta utente — 🔪 sembrava un coltello
# moderno, e anche la variante con impugnatura fasciata non convinceva). Una SCHEGGIA di selce
# senza manico: sagoma a foglia irregolare in diagonale, con una base larga e arrotondata (dove la si
# impugna) e una punta affusolata. Il bordo tagliente è una linea chiara lungo un lato, le
# "cicatrici" della scheggiatura sono alcune linee scure corte sulla faccia. Stesso schema di
# StickIcon/PebbleIcon: solo _draw(), coordinate relative, nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con MicroCellRenderer (icona nel magazzino
# sulla mappa) — un solo disegno per entrambi i punti.

const FLINT_COLOR := Color(0.52, 0.49, 0.45, 1.0)
const FLINT_OUTLINE_COLOR := Color(0.27, 0.25, 0.22, 1.0)
const FLAKE_SCAR_COLOR := Color(0.38, 0.35, 0.32, 1.0)
const EDGE_HIGHLIGHT_COLOR := Color(0.80, 0.78, 0.74, 1.0)

# Contorno della scheggia in coordinate relative (0..1), in senso orario dalla punta. Lati
# volutamente spezzati: una scheggia scheggiata, non una lama liscia.
const OUTLINE_POINTS := [
	Vector2(0.90, 0.10),
	Vector2(0.80, 0.26),
	Vector2(0.70, 0.36),
	Vector2(0.60, 0.50),
	Vector2(0.46, 0.64),
	Vector2(0.34, 0.80),
	Vector2(0.22, 0.90),
	Vector2(0.11, 0.86),
	Vector2(0.10, 0.72),
	Vector2(0.20, 0.58),
	Vector2(0.34, 0.46),
	Vector2(0.48, 0.34),
	Vector2(0.62, 0.24),
	Vector2(0.76, 0.16),
]

# Cicatrici di scheggiatura: coppie di punti (inizio, fine) sulla faccia.
const SCAR_SEGMENTS := [
	[Vector2(0.26, 0.60), Vector2(0.36, 0.70)],
	[Vector2(0.40, 0.48), Vector2(0.48, 0.58)],
	[Vector2(0.54, 0.36), Vector2(0.60, 0.44)],
	[Vector2(0.18, 0.74), Vector2(0.26, 0.82)],
]

# Bordo tagliente (lato superiore-sinistro della scheggia), dalla base verso la punta.
const EDGE_POINTS := [
	Vector2(0.20, 0.58),
	Vector2(0.34, 0.46),
	Vector2(0.48, 0.34),
	Vector2(0.62, 0.24),
	Vector2(0.76, 0.16),
	Vector2(0.90, 0.10),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna la scheggia dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var line_width: float = minf(area.x, area.y) * 0.04
	var outline := PackedVector2Array()
	for point in OUTLINE_POINTS:
		outline.append(origin + Vector2(point.x * area.x, point.y * area.y))
	canvas.draw_colored_polygon(outline, FLINT_COLOR)

	for segment in SCAR_SEGMENTS:
		canvas.draw_line(
			origin + Vector2(segment[0].x * area.x, segment[0].y * area.y),
			origin + Vector2(segment[1].x * area.x, segment[1].y * area.y),
			FLAKE_SCAR_COLOR, line_width, true
		)

	var edge := PackedVector2Array()
	for point in EDGE_POINTS:
		edge.append(origin + Vector2(point.x * area.x, point.y * area.y))
	canvas.draw_polyline(edge, EDGE_HIGHLIGHT_COLOR, line_width * 1.2, true)

	var closed_outline := outline.duplicate()
	closed_outline.append(outline[0])
	canvas.draw_polyline(closed_outline, FLINT_OUTLINE_COLOR, line_width, true)
