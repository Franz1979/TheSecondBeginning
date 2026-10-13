class_name WorkedHideDressIcon
extends Control

# Icona disegnata del "vestito di pelli lavorate" (worked_hide_dress, 2026-10-11, richiesta utente — secondo livello,
# segnaposto: il disegno più "sartoriale" scartato per la pelliccia di base). Veste lunga svasata, maniche corte,
# scollo a V, orli chiari a zigzag su collo e fondo, qualche cucitura scura, cintura con due capi pendenti. Toni grigi
# come le altre icone del vestiario. Stesso schema di FurDressIcon: spazio di disegno DESIGN_SIZE, nessun randf().
#
# draw_into (statica) è la geometria vera, condivisa con DepositStorageIcons (magazzini e mucchi a terra).

const DESIGN_SIZE := Vector2(108.0, 204.0)
const HIDE_COLOR := Color(0.52, 0.48, 0.43, 1.0)
const OUTLINE_COLOR := Color(0.25, 0.23, 0.21, 1.0)
const TRIM_COLOR := Color(0.74, 0.70, 0.63, 1.0)
const STITCH_COLOR := Color(0.38, 0.35, 0.32, 1.0)
const BELT_COLOR := Color(0.66, 0.61, 0.50, 1.0)

const OUTLINE_POINTS := [
	Vector2(36, 12), Vector2(54, 27), Vector2(72, 12), Vector2(90, 21), Vector2(99, 45), Vector2(87, 51),
	Vector2(84, 39), Vector2(87, 99), Vector2(99, 183), Vector2(9, 183), Vector2(21, 99), Vector2(24, 39),
	Vector2(21, 51), Vector2(9, 45), Vector2(18, 21),
]
const STITCHES := [
	[Vector2(30, 70), Vector2(36, 70)], [Vector2(60, 60), Vector2(66, 60)], [Vector2(42, 120), Vector2(48, 120)],
	[Vector2(66, 135), Vector2(72, 135)], [Vector2(30, 150), Vector2(36, 150)], [Vector2(54, 160), Vector2(60, 160)],
	[Vector2(48, 80), Vector2(54, 80)],
]
const BELT_RECT := Rect2(21, 92, 66, 7)
const BELT_ENDS := [[Vector2(50, 99), Vector2(47, 115)], [Vector2(58, 99), Vector2(61, 115)]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_into(self, Vector2.ZERO, size)


static func draw_into(canvas: CanvasItem, origin: Vector2, area: Vector2) -> void:
	var rect := ApparelIcon.fit_aspect(origin, area, DESIGN_SIZE.x / DESIGN_SIZE.y)
	var unit: float = rect.size.x / DESIGN_SIZE.x
	var outline := PackedVector2Array()
	for point in OUTLINE_POINTS:
		outline.append(ApparelIcon.map_point(point, DESIGN_SIZE, rect))
	# Piccola (magazzini, mucchi): sagoma, contorno netto e la cintura (ApparelIcon.is_small).
	if ApparelIcon.is_small(rect):
		ApparelIcon.draw_silhouette(canvas, outline, HIDE_COLOR, OUTLINE_COLOR)
		var belt_y := BELT_RECT.position.y + BELT_RECT.size.y * 0.5
		canvas.draw_line(ApparelIcon.map_point(Vector2(BELT_RECT.position.x, belt_y), DESIGN_SIZE, rect), ApparelIcon.map_point(Vector2(BELT_RECT.end.x, belt_y), DESIGN_SIZE, rect), BELT_COLOR, 1.0, false)
		return
	canvas.draw_colored_polygon(outline, HIDE_COLOR)
	ApparelIcon.draw_strokes(canvas, STITCHES, DESIGN_SIZE, rect, STITCH_COLOR, maxf(2.0 * unit, 1.0))
	var closed := outline.duplicate()
	closed.append(outline[0])
	canvas.draw_polyline(closed, OUTLINE_COLOR, maxf(2.0 * unit, 1.0), true)
	# Orli a zigzag: fondo (da sinistra a destra) e collo.
	canvas.draw_polyline(_zigzag(Vector2(9, 183), 15, 6.0, -8.0, DESIGN_SIZE, rect), TRIM_COLOR, maxf(3.0 * unit, 1.0), true)
	canvas.draw_polyline(_zigzag(Vector2(36, 12), 12, 3.0, 5.0, DESIGN_SIZE, rect), TRIM_COLOR, maxf(3.0 * unit, 1.0), true)
	var belt := Rect2(ApparelIcon.map_point(BELT_RECT.position, DESIGN_SIZE, rect), BELT_RECT.size * unit)
	canvas.draw_rect(belt, BELT_COLOR)
	ApparelIcon.draw_strokes(canvas, BELT_ENDS, DESIGN_SIZE, rect, BELT_COLOR, maxf(3.0 * unit, 1.0))


# Linea a zigzag di `count` denti larghi `step`, alti `depth` (alternati), dal punto `start`.
static func _zigzag(start: Vector2, count: int, step: float, depth: float, design_size: Vector2, rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(count + 1):
		var offset := Vector2(float(i) * step, depth if i % 2 == 1 else 0.0)
		points.append(ApparelIcon.map_point(start + offset, design_size, rect))
	return points
