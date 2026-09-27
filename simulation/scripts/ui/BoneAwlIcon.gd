class_name BoneAwlIcon
extends Control

# Icona disegnata "punteruolo d'osso" (2026-09-27, richiesta utente): una scheggia d'osso lunga e sottile in
# diagonale, con la testa arrotondata (l'epifisi, dove la si impugna) in basso a sinistra e una punta acuminata in
# alto a destra. Color osso con un bordo più scuro e una linea chiara lungo il fusto. Stesso schema di
# StoneKnifeIcon/BoneIcon: solo _draw(), coordinate relative, nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (icona nel magazzino sulla mappa).

const BONE_COLOR := Color(0.92, 0.89, 0.80, 1.0)
const BONE_OUTLINE_COLOR := Color(0.50, 0.46, 0.37, 1.0)
const BONE_HIGHLIGHT_COLOR := Color(1.0, 0.98, 0.92, 1.0)

# Contorno del punteruolo in coordinate relative (0..1): testa arrotondata in basso a sinistra, fusto che si
# assottiglia, punta in alto a destra.
const OUTLINE_POINTS := [
	Vector2(0.90, 0.10),
	Vector2(0.62, 0.46),
	Vector2(0.40, 0.70),
	Vector2(0.34, 0.80),
	Vector2(0.26, 0.88),
	Vector2(0.16, 0.89),
	Vector2(0.11, 0.84),
	Vector2(0.12, 0.74),
	Vector2(0.20, 0.66),
	Vector2(0.30, 0.60),
	Vector2(0.54, 0.38),
]

# Linea chiara lungo il fusto, dalla testa verso la punta.
const HIGHLIGHT_POINTS := [
	Vector2(0.20, 0.72),
	Vector2(0.36, 0.62),
	Vector2(0.58, 0.40),
	Vector2(0.82, 0.16),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


# Disegna il punteruolo dentro il rettangolo (origin, area) di `canvas`.
static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var line_width: float = minf(area.x, area.y) * 0.04
	var outline := PackedVector2Array()
	for point in OUTLINE_POINTS:
		outline.append(origin + Vector2(point.x * area.x, point.y * area.y))
	canvas.draw_colored_polygon(outline, BONE_COLOR)

	var highlight := PackedVector2Array()
	for point in HIGHLIGHT_POINTS:
		highlight.append(origin + Vector2(point.x * area.x, point.y * area.y))
	canvas.draw_polyline(highlight, BONE_HIGHLIGHT_COLOR, line_width, true)

	var closed_outline := outline.duplicate()
	closed_outline.append(outline[0])
	canvas.draw_polyline(closed_outline, BONE_OUTLINE_COLOR, line_width, true)
